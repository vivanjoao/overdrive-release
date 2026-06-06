package com.overdrive.app.roadsense

import android.content.Context
import android.util.Log
import com.overdrive.app.roadsense.detect.Assessment
import com.overdrive.app.roadsense.detect.DaemonImuStream
import com.overdrive.app.roadsense.detect.DetectionCandidate
import com.overdrive.app.roadsense.detect.EventDetector
import com.overdrive.app.roadsense.detect.GravityFrame
import com.overdrive.app.roadsense.detect.GpsRingBuffer
import com.overdrive.app.roadsense.detect.GyroStats
import com.overdrive.app.roadsense.detect.HazardType
import com.overdrive.app.roadsense.detect.ImuAccelSample
import com.overdrive.app.roadsense.detect.ImuGyroSample
import com.overdrive.app.roadsense.detect.ImuStream
import com.overdrive.app.roadsense.detect.RejectionFilter
import com.overdrive.app.roadsense.detect.RoadSenseHazard
import com.overdrive.app.roadsense.detect.SeverityClassifier
import com.overdrive.app.roadsense.detect.VehicleCalibrator
import com.overdrive.app.roadsense.detect.VehicleDynamics
import com.overdrive.app.roadsense.detect.VerticalSample
import com.overdrive.app.roadsense.detect.ImuFrameCodec
import com.overdrive.app.roadsense.config.RoadSenseConfig
import com.overdrive.app.roadsense.label.GroundTruthStore
import com.overdrive.app.roadsense.sidecar.RoadSenseImuSidecarService
import com.overdrive.app.roadsense.source.LocationSource
import com.overdrive.app.roadsense.source.VehicleDataSource
import com.overdrive.app.roadsense.source.VehicleStateGate
import com.overdrive.app.roadsense.store.RoadSenseStore
import com.overdrive.app.roadsense.store.SpatialIndex
import com.overdrive.app.roadsense.sync.CloudflareEdgeSyncProvider
import com.overdrive.app.roadsense.sync.DeviceId
import com.overdrive.app.roadsense.sync.RoadSenseSyncProvider
import com.overdrive.app.roadsense.sync.TileCursor
import com.overdrive.app.roadsense.warn.OverlayState
import kotlin.math.abs

/**
 * Daemon-side brain of RoadSense (D-019/D-023). Wires the whole pipeline and owns
 * the vehicle-state lifecycle. Self-contained: nothing in CameraDaemon /
 * SurveillanceIpcServer references this yet — those two integration points are
 * DEFERRED tiny patches (see dev/roadsense/06-DAEMON-PATCHES.md) because another
 * session is editing those files. To go live, the daemon calls:
 *   - [start] once at boot (after BydDataCollector/GpsMonitor are up),
 *   - [onImuBatch] from the IPC server's `IMU_BATCH` case,
 *   - [onVehicleStatePoll] periodically (or it self-polls — see [start]),
 *   - [stop] at shutdown.
 *
 * ## Data flow (all on the IPC reader thread, single-threaded per the engine
 *    contract — see DaemonImuStream):
 *
 *   IMU_BATCH ─► DaemonImuStream.feed ─► [onAccel]/[onGyro]
 *     onAccel: GravityFrame.update → a_vert → VehicleCalibrator.onSample
 *                                          └► EventDetector.onSample → candidate?
 *       candidate → RejectionFilter.evaluate(dynamics, gyroStats, eventRate)
 *         not rejected → SeverityClassifier.classify(vehicleScale, maturity, gpsAcc)
 *           → back-project pose (GpsRingBuffer) → RoadSenseStore.upsertDetection
 *     onGyro: fold into rolling GyroStats (peak yaw/roll over the event window)
 *
 * ## Vehicle-state gating (D-021)
 * [onVehicleStatePoll] reads gear (BydDataCollector via VehicleDataSource) + ACC
 * (AccMonitor) through [VehicleStateGate] and drives the app IMU sidecar:
 *   DRIVING → start sidecar FAST + run detector
 *   RELAXED → sidecar SLOW + pause detector (keep state warm)
 *   OFF     → stop sidecar + release detector state (silent, ~zero cost)
 *
 * Not a singleton on purpose — the daemon owns exactly one instance and its
 * lifecycle. Clock injected for testability.
 */
class RoadSenseController @JvmOverloads constructor(
    private val appContext: Context,
    private val clock: () -> Long = { System.currentTimeMillis() },
    private val vehicleSource: VehicleDataSource = VehicleDataSource(),
    private val locationSource: LocationSource = LocationSource(),
    private val store: RoadSenseStore = RoadSenseStore.getInstance(),
) : ImuStream.Listener {

    // Persistent diagnostics: RoadSense runs in the daemon, but most of its logs go
    // via android.util.Log (logcat) which is VOLATILE — gone after a no-ADB drive.
    // For the few breadcrumbs we actually need to verify a drive post-hoc (regime
    // transitions, IMU-flow heartbeat, detections), ALSO write to DaemonLogger, which
    // persists to /data/local/tmp/cam_daemon.log and survives park→reconnect.
    private val plog = com.overdrive.app.logging.DaemonLogger.getInstance("RoadSense")

    // ── Pipeline stages (single-threaded; one feeder per DaemonImuStream) ──────
    private val gravity = GravityFrame()
    private val detector = EventDetector()
    private val rejection = RejectionFilter()
    private val classifier = SeverityClassifier()
    private val calibrator = VehicleCalibrator()
    private val gpsBuffer = GpsRingBuffer()
    private val imuStream = DaemonImuStream()
    // Route coverage: which tiles we've driven (distinct from vehicle calibration).
    // Updated from the live pose; supplies the overlay's "new road vs mapped" signal.
    private val coverage = com.overdrive.app.roadsense.store.RouteCoverage()
    // Last pose we published a coverage level for (overlay supplier reads this so the
    // level reflects WHERE WE ARE, not a stale tile). @Volatile: written on the warn
    // tick, read by the visualSink supplier lambda on the same tick — kept simple.
    @Volatile private var lastCoverageLevel = 0
    // Daemon-side visual sink publishes overlay state to UCM (D-024); calibration
    // level for the green/orange/red dot comes from the calibrator's maturity, and
    // route coverage (new/seen/mapped) from RouteCoverage.
    private val visualSink = com.overdrive.app.roadsense.warn.UcmVisualSink(
        calibrationLevelSupplier = { calibrator.maturity },
        coverageSupplier = { lastCoverageLevel },
        clock = clock,
    )
    private val warnings = com.overdrive.app.roadsense.warn.WarningCoordinator(
        store, visualSink = visualSink, clock = clock,
        audio = com.overdrive.app.roadsense.warn.RoadSenseAudioCue(appContext),
    )

    // Rolling gyro peaks over the current event window, reset when an event closes.
    // Each peak carries the sensor tMs of the sample that set it so it can be AGED
    // OUT once it falls outside ~one EventDetector window (audit detection #1): the
    // since-last-candidate max held a turn made seconds/minutes before a later
    // straight-line bump, making RejectionFilter wrongly reject it as cornering.
    // Only rotation concurrent with the jolt should vote "cornering".
    private var peakYaw = 0f
    private var peakYawTMs = 0L
    private var peakRoll = 0f
    private var peakRollTMs = 0L

    // Persistent IMU-flow heartbeat state (diagnostics; IPC thread only).
    private var imuBatchCount = 0L
    private var lastImuHeartbeatMs = 0L
    private var lastSeenSpeedKmh = 0f

    // Calibration-persistence throttle (daemon tick thread only).
    private var lastCalPersistMs = 0L
    private var lastPersistedQuietCount = 0L
    // Candidate-disposition tallies (diagnostics; IPC thread). Surfaced in the
    // imu-flow heartbeat so a no-ADB drive shows WHY candidates didn't store.
    private var dropNoDyn = 0
    private var dropNoPose = 0
    private var dropStored = 0
    private val dropRejects = HashMap<String, Int>()
    // Coverage-persistence throttle (daemon tick thread only).
    private var lastCoveragePersistMs = 0L

    // Rolling candidate rate for washboard rejection (events in the last window).
    private val recentCandidateMs = ArrayDeque<Long>()
    // D-032: throttle for mapping a sustained washboard stretch as ONE rough_section
    // row rather than spamming a row per cobble. Last rough-section map time (event
    // tMs) on the single IPC/sensor thread.
    private var lastRoughSectionMs = 0L

    @Volatile private var regime = VehicleStateGate.Regime.OFF
    @Volatile private var started = false
    private var ticker: java.util.concurrent.ScheduledExecutorService? = null
    // Set by onVehicleStatePoll (daemon housekeeping thread) when leaving DRIVING;
    // the actual pipeline-state reset is performed on the IPC/sensor thread at the
    // top of the next batch, so ALL detector/gravity/gps state is mutated by ONE
    // thread only. Avoids a data race without locking the 100 Hz hot path.
    @Volatile private var resetRequested = false
    private var lastGpsPollMs = 0L
    // Cached vehicle snapshot, refreshed on a throttle (the source only updates
    // every ~5 s; re-fetching at 100 Hz would allocate needlessly). Read on the
    // single IPC/sensor thread only.
    private var lastVehiclePollMs = 0L
    private var cachedDynamics: VehicleDynamics? = null
    // Master feature toggle (UCM roadSense.enabled). @Volatile: WRITTEN by both the
    // tick thread (onVehicleStatePoll) and the IPC thread (onAccel throttle), READ
    // on the IPC thread (handleCandidate). Without volatile the IPC thread could
    // cache a stale value and never observe a master-disable (review blocker #2).
    @Volatile private var featureEnabled = false
    // @Volatile: WRITTEN by the tick thread (onWarningTick), READ by the IPC thread
    // (handleCandidate). A stale read would silently never start surfacing confirm
    // cards after the user enables Calibration Mode (review blocker #2).
    @Volatile private var calibrationMode = false

    // Calibration-Mode ground-truth (D-025, R-DET-7) + the pending confirm awaiting
    // the user's verdict. @Volatile: WRITTEN by the IPC thread (handleCandidate sets
    // it) AND the tick thread (consumePendingConfirmResult clears it); single-ref
    // assignment, one clearer — volatile gives the needed visibility without a lock
    // on the 100 Hz path (review blocker #1).
    private val groundTruth = GroundTruthStore.getInstance()
    @Volatile private var pendingConfirm: PendingLabel? = null
    private var lastConfirmResultTs = 0L

    // Crowdsource sync (Phase 8, D-009). Worker URL comes from config; both
    // directions are opt-in (default OFF, R-CRD-6). Sync runs on a slow tick.
    private val syncProvider: RoadSenseSyncProvider = CloudflareEdgeSyncProvider(
        workerUrlSupplier = { RoadSenseConfig.snapshot().syncWorkerUrl }
    )
    private val tileCursor = TileCursor()
    // Last successful sync wall-clock, PERSISTED in UCM (roadSense.lastSyncMs) so a
    // daemon restart / new ACC session doesn't force an immediate re-sync — the
    // 2.5 h cadence survives reboots. -1 = not yet loaded.
    private var lastSyncMs = -1L
    // Last uploaded row's updated_ms, PERSISTED in UCM (roadSense.lastUploadCursor)
    // so a daemon restart / ACC cycle doesn't re-scan and re-upload every eligible
    // local row from 0 (wasted bandwidth) and — worse — re-contribute this device's
    // own backlog under a NEW rotating deviceId after the 30-day id rotation,
    // self-inflating distinct-device consensus (audit network #5). -1 = not loaded.
    private var lastUploadCursor = -1L

    private data class PendingLabel(
        val hazardId: String,
        val candidate: DetectionCandidate,
        val assessment: Assessment,
        val lat: Double,
        val lng: Double,
        /** Wall-clock ms the confirm was surfaced — drives the G-7 auto-accept
         *  timeout so the card never demands interaction while driving. */
        val shownMs: Long,
    )

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    fun start() {
        if (started) return
        started = true
        store.init()
        store.start()
        groundTruth.init()
        // Restore persisted per-vehicle calibration so maturity ACCUMULATES across
        // daemon restarts / reboots / app updates instead of resetting to 0 every
        // trip (a head unit power-cycles with the car, so without this the overlay
        // would sit at "Calibrating" forever and never reach the mature state).
        restoreCalibration()
        imuStream.setListener(this)
        // Self-driven housekeeping tick (kept out of CameraDaemon per D-023 notes):
        // ~2 Hz drives both the regime poll (gear/ACC → sidecar start/stop) and the
        // approach-warning eval. Both are cheap no-ops unless DRIVING. A single-
        // thread scheduler; the warning eval reads the store + GPS off the IMU path.
        ticker = java.util.concurrent.Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "roadsense-tick").apply { isDaemon = true }
        }
        ticker?.scheduleWithFixedDelay({
            try { onVehicleStatePoll(); onWarningTick() }
            catch (t: Throwable) { Log.w(TAG, "tick error: ${t.message}") }
        }, 0L, TICK_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
        Log.i(TAG, "RoadSenseController started")
    }

    fun stop() {
        if (!started) return
        started = false
        ticker?.shutdownNow()
        ticker = null
        imuStream.stop()
        // Stop the scoped fast-dynamics poll if it was running (DRIVING at shutdown).
        try { vehicleSource.collectorOrNull()?.stopFastDynamicsPoll() } catch (_: Throwable) {}
        RoadSenseImuSidecarService.stop(appContext)
        warnings.release()
        // Flush learned state on a clean shutdown so the last minute isn't lost (the
        // throttled persists may not have fired right before stop). Best-effort.
        try {
            val (qc, ms) = calibrator.snapshot()
            persistCalibration(qc, ms)
            coverage.persistIfDirty()
        } catch (_: Throwable) {}
        groundTruth.stop()
        store.stop()
        Log.i(TAG, "RoadSenseController stopped")
    }

    /** Wipe route coverage (called from delete-local, R-SET-5). */
    fun clearCoverage() = coverage.clear()

    /**
     * Entry point for the IPC server's `IMU_BATCH` case (DEFERRED patch). Decodes
     * the wire line and feeds the pipeline. Returns samples processed (for the
     * IPC ack), 0 if not an IMU_BATCH line or detector is paused.
     */
    fun onImuBatch(line: String): Int {
        if (!started || regime != VehicleStateGate.Regime.DRIVING) return 0
        // Perform any pending reset HERE (on this single IPC/sensor thread) so all
        // pipeline-state mutation is serialized — onVehicleStatePoll only flags it.
        if (resetRequested) {
            resetRequested = false
            resetTransient()
        }
        val decoded = ImuFrameCodec.decode(line) ?: return 0
        val n = imuStream.feed(decoded, clock())
        // Persistent IMU-flow heartbeat (survives a no-ADB drive). Throttled to
        // ~30 s so it's cheap on the IPC path. A drive with ZERO detected hazards
        // still leaves proof here that IMU actually flowed + how calibration climbed,
        // distinguishing "pipeline ran, road was smooth" from "pipeline never ran".
        imuBatchCount += n
        val nowWall = clock()
        if (nowWall - lastImuHeartbeatMs > IMU_HEARTBEAT_MS) {
            lastImuHeartbeatMs = nowWall
            val rejects = if (dropRejects.isEmpty()) "" else
                " rejects=" + dropRejects.entries.joinToString(",") { "${it.key}:${it.value}" }
            plog.info("imu-flow: batches~${imuBatchCount} samples, cal=${"%.3f".format(calibrator.maturity)} " +
                "events=${detector.totalCandidates} stored=$dropStored noDyn=$dropNoDyn noPose=$dropNoPose" +
                rejects + " speed=${"%.0f".format(lastSeenSpeedKmh)}km/h")
        }
        return n
    }

    /**
     * Re-evaluate the operating regime from current gear + ACC and act on the
     * transition (D-021). Safe to call on any cadence; the daemon can self-poll
     * (e.g. every ~1 s) or call on vehicle-data ticks.
     */
    fun onVehicleStatePoll() {
        if (!started) return
        val now = clock()
        // Refresh the master-enabled flag here too (not only on the IMU throttle)
        // so toggling RoadSense off promptly tears the sidecar down even while the
        // car keeps driving — a disabled feature must cost ~zero (R-EXT-6 / D-021).
        featureEnabled = RoadSenseConfig.snapshot().enabled
        val dyn = vehicleSource.latest(now)
        val accOn = com.overdrive.app.monitor.AccMonitor.isAccOn()
        val accAuth = com.overdrive.app.monitor.AccMonitor.isAccStateAuthoritative()
        // Gear for the regime gate: prefer the AUTHORITATIVE GearMonitor (200 ms poll)
        // ONLY while it's actually running, else fall back to the collector snapshot.
        // CRITICAL (audit): GearMonitor.currentGear defaults to GEAR_P(1) and is never
        // 0/UNAVAILABLE, so a `g > 0` guard never falls back — and since GearMonitor
        // starts AFTER RoadSense at boot and STOPS on ACC-off, reading it unconditionally
        // would return a stale P during the boot/first-arming window and pin us in
        // RELAXED forever (the exact "Calibrating forever" bug). So we gate on
        // isRunning(): only trust GearMonitor when its poll thread is live; otherwise
        // use the collector's gearMode (which reads the same HAL getter and is correctly
        // UNAVAILABLE→non-forward before it has a real reading).
        val gm = com.overdrive.app.monitor.GearMonitor.getInstance()
        val gear = try {
            if (gm.isRunning) gm.currentGear else (dyn?.gearMode ?: 0)
        } catch (_: Throwable) { dyn?.gearMode ?: 0 }

        // Feature disabled ⇒ treat as OFF regime regardless of gear/ACC: no sidecar,
        // no IMU, no pipeline. This is the master switch's teeth.
        val newRegime = if (!featureEnabled) VehicleStateGate.Regime.OFF
        else VehicleStateGate.evaluate(accOn, accAuth, gear)
        if (newRegime == regime) return
        val action = VehicleStateGate.transition(regime, newRegime)
        Log.i(TAG, "regime $regime → $newRegime")
        // Persist regime transitions (survives a no-ADB drive). gear + acc context so
        // a post-drive read explains WHY it did/didn't reach DRIVING.
        plog.info("regime $regime → $newRegime (acc=$accOn auth=$accAuth gear=$gear feature=$featureEnabled)")
        regime = newRegime

        when {
            action.startImu -> RoadSenseImuSidecarService.start(
                appContext, RoadSenseImuSidecarService.ImuRate.FAST
            )
            action.slowImu -> RoadSenseImuSidecarService.start(
                appContext, RoadSenseImuSidecarService.ImuRate.SLOW
            )
            action.stopImu -> RoadSenseImuSidecarService.stop(appContext)
        }
        if (action.persistState && newRegime != VehicleStateGate.Regime.DRIVING) {
            // Hazards are already persisted per-detection (map from drive one);
            // nothing buffered to flush. Request a transient-state reset so a stale
            // half-event can't fire on resume — but DON'T mutate detector state
            // here (we're on the housekeeping thread, not the IPC/sensor thread).
            // The reset runs on the IPC thread at the next batch (thread safety).
            resetRequested = true
        }

        // Fast vehicle-dynamics poll (R-PERF-4): brake/accel/gear event-aligned to
        // ~200 ms jolts. Run it ONLY while DRIVING (when detection + rejection are
        // active) — and since !featureEnabled forces regime=OFF above, this is
        // implicitly gated on RoadSense being enabled too. Any non-DRIVING regime
        // (RELAXED/OFF) stops it, so it costs nothing when parked or feature-off.
        if (newRegime == VehicleStateGate.Regime.DRIVING) {
            try { vehicleSource.collectorOrNull()?.startFastDynamicsPoll() }
            catch (t: Throwable) { Log.w(TAG, "startFastDynamicsPoll: ${t.message}") }
        } else {
            try { vehicleSource.collectorOrNull()?.stopFastDynamicsPoll() }
            catch (t: Throwable) { Log.w(TAG, "stopFastDynamicsPoll: ${t.message}") }
        }

        if (newRegime == VehicleStateGate.Regime.DRIVING) imuStream.start(ImuStream.Rate.FULL)
    }

    /**
     * Restore persisted per-vehicle calibration from UCM. Cross-UID safe via
     * forceReload (daemon may have just (re)started). VEHICLE-IDENTITY GUARD (audit
     * accuracy S2): the persisted baseline is only restored if the stored VIN matches
     * the current car's VIN — a car/head-unit swap (different VIN) discards the old
     * baseline and re-learns, rather than silently mis-scaling severity with another
     * vehicle's suspension model. If either VIN is unknown/empty we can't prove a
     * mismatch, so we trust the persisted value (no regression vs no-guard). Any parse
     * failure simply starts calibration fresh.
     */
    private fun restoreCalibration() {
        try {
            val rs = com.overdrive.app.config.UnifiedConfigManager.forceReload()
                .optJSONObject("roadSense") ?: return
            val qc = rs.optLong("calQuietCount", 0L)
            val ms = rs.optDouble("calMeanSq", -1.0)
            if (qc <= 0L || ms < 0.0) return
            val savedKey = rs.optString("calVehicleKey", "")
            val curKey = vehicleKey()
            if (savedKey.isNotEmpty() && curKey.isNotEmpty() && savedKey != curKey) {
                plog.info("calibration NOT restored: vehicle changed (saved=$savedKey cur=$curKey) → re-learning")
                return
            }
            calibrator.restore(qc, ms.toFloat())
            plog.info("calibration restored: quietCount=$qc meanSq=${"%.5f".format(ms)} maturity=${"%.3f".format(calibrator.maturity)}")
        } catch (_: Throwable) { /* start fresh */ }
    }

    /**
     * Persist calibration state to UCM on a throttle ([CAL_PERSIST_MS]). Only writes
     * when quietCount has meaningfully advanced since the last persist, so a parked /
     * smooth-road tick doesn't rewrite the config file needlessly (updateSection is a
     * full-file rewrite). Daemon tick thread only.
     */
    private fun maybePersistCalibration(now: Long) {
        if (now - lastCalPersistMs < CAL_PERSIST_MS) return
        val (qc, ms) = calibrator.snapshot()   // atomic pair (audit concurrency B)
        if (qc <= lastPersistedQuietCount) return   // no new learning → skip the rewrite
        lastCalPersistMs = now
        lastPersistedQuietCount = qc
        persistCalibration(qc, ms)
    }

    /**
     * Write calibration to UCM. forceReload FIRST (audit concurrency D): these are
     * daemon-owned keys, but updateSection rewrites the whole roadSense section by
     * merging onto the daemon's cached config — and ext4's 1 s mtime granularity can
     * hide a just-written app key (warnMode / pendingConfirmResult), so without a
     * fresh reload the daemon's write could drop the user's toggle. The vehicle
     * fingerprint is stored alongside so a car/head-unit swap is detected on restore
     * (audit accuracy S2).
     */
    private fun persistCalibration(quietCount: Long, meanSq: Float) {
        try {
            com.overdrive.app.config.UnifiedConfigManager.forceReload()
            com.overdrive.app.config.UnifiedConfigManager.updateSection(
                "roadSense",
                org.json.JSONObject()
                    .put("calQuietCount", quietCount)
                    .put("calMeanSq", meanSq.toDouble())
                    .put("calVehicleKey", vehicleKey()),
            )
        } catch (_: Throwable) { /* best-effort; lost write just re-learns a little */ }
    }

    /**
     * Vehicle identity to tie calibration to the car that learned it (audit accuracy
     * S2): the BYD VIN from the bus snapshot. On a car/head-unit swap the VIN changes,
     * so restoreCalibration() discards a mismatched baseline rather than mis-scaling
     * severity with another vehicle's suspension model. Empty string when the VIN
     * isn't available yet — restore then skips the identity check (can't prove a
     * mismatch, so it trusts the persisted value, same as before this guard).
     */
    private fun vehicleKey(): String =
        try { com.overdrive.app.byd.BydDataCollector.getInstance().getData()?.vin ?: "" }
        catch (_: Throwable) { "" }

    /** Persist route coverage on a throttle ([COVERAGE_PERSIST_MS]). Called only when
     *  a NEW tile was entered, then further throttled so a fast road through many
     *  tiles doesn't rewrite the config file per tile. Daemon tick thread. */
    private fun maybePersistCoverage(now: Long) {
        if (now - lastCoveragePersistMs < COVERAGE_PERSIST_MS) return
        lastCoveragePersistMs = now
        coverage.persistIfDirty()
    }

    private fun resetTransient() {
        gravity.reset()
        detector.reset()
        gpsBuffer.reset()
        peakYaw = 0f; peakYawTMs = 0L; peakRoll = 0f; peakRollTMs = 0L
        recentCandidateMs.clear()
        lastRoughSectionMs = 0L
        cachedDynamics = null
        lastVehiclePollMs = 0L
        lastGpsPollMs = 0L
    }

    /**
     * Delete this device's uploaded rows from the shared backend (R-SET-5
     * delete-cloud), called by RoadSenseApiHandler. Uses the current rotating
     * device id; also clears local tile cursors so a re-sync repopulates cleanly.
     * Returns true on success.
     */
    fun deleteCloudUploads(): Boolean {
        val ok = syncProvider.deleteOwnUploads(DeviceId.current(clock()))
        if (ok) tileCursor.clear()
        return ok
    }

    /**
     * Approach-warning tick. Called by the daemon on a modest cadence (~2–4 Hz) —
     * NOT the 100 Hz IMU path. Reads the live pose + config and lets the
     * WarningCoordinator decide whether to chime/flash for an upcoming hazard.
     * Only meaningful while DRIVING; cheap no-op otherwise.
     */
    fun onWarningTick() {
        if (!started) return
        val now = clock()

        // Refresh the Calibration-Mode flag BEFORE the regime gate so a card opened
        // while driving still reacts to the user toggling Calibration Mode off after
        // they've stopped (regime → RELAXED/OFF). Cheap mtime-gated read.
        calibrationMode = RoadSenseConfig.snapshot(forceReload = false).calibrationMode

        // Consume any Calibration-Mode verdict / fire the G-7 auto-accept timeout
        // BEFORE the regime gate (and regardless of regime): a confirm card stays up
        // when you slow to a stop or park (regime → RELAXED/OFF), and it MUST still
        // auto-dismiss after CONFIRM_TIMEOUT_MS so it never lingers demanding a tap.
        // Previously this sat after the DRIVING early-return, so stopping with a card
        // open froze it forever. Only runs when actually awaiting a verdict.
        if (pendingConfirm != null) {
            // If the user turned Calibration Mode OFF while a card is open, dismiss it
            // immediately instead of waiting out the 8 s timeout (audit LOW). The
            // detection is already stored; we just don't surface/await a label.
            if (!calibrationMode) {
                pendingConfirm = null
                visualSink.setPendingConfirm(null)
            } else {
                consumePendingConfirmResult(now)
            }
        }

        // The rest (approach warnings, coverage, sync) is only meaningful while DRIVING.
        if (regime != VehicleStateGate.Regime.DRIVING) return

        val cfg = RoadSenseConfig.snapshot(forceReload = false)

        val pose = locationSource.latest(now)
        if (pose == null) {
            // No fix: still heartbeat idle so the app overlay knows we're alive.
            visualSink.publishIdle()
            return
        }
        // Heading is reliable only when actually moving (GPS bearing is noise at
        // crawl); ApproachEngine falls back to range-only when this is false.
        val headingReliable = pose.speedMps > HEADING_RELIABLE_MPS

        // Route coverage: record this tile (only while genuinely MOVING, so a parked
        // car with GPS jitter doesn't fabricate "passes") and publish its level so the
        // overlay's idle caption distinguishes a mapped road from a new one. The
        // supplier (lastCoverageLevel) is read by visualSink inside warnings.onTick.
        if (pose.speedMps > HEADING_RELIABLE_MPS) {
            if (coverage.record(pose.lat, pose.lng, now)) maybePersistCoverage(now)
        }
        lastCoverageLevel = coverage.levelAt(pose.lat, pose.lng).ordinal

        warnings.onTick(pose, cfg, headingReliable)
        // onTick already wrote overlay state when there was a hazard; when nothing
        // is ahead WarningCoordinator calls clearApproach() (which writes idle), so
        // the heartbeat is covered either way.

        // Crowdsource sync runs on a much slower cadence than the warn tick.
        maybeSync(cfg, pose, now)

        // Persist the per-vehicle calibration on a slow throttle so it survives a
        // restart (off the 100 Hz path — this is the ~2 Hz warn tick).
        maybePersistCalibration(now)
    }

    /**
     * Opt-in crowdsource sync (Phase 8, D-009). Throttled to [SYNC_MS]. Download
     * pulls confirmed hazards in the tiles around the current pose (delta-by-tile,
     * R-CRD-5); upload pushes this device's high-confidence local hazards (D-016).
     * Both directions independently gated by config (default OFF, R-CRD-6). All
     * network is blocking but we're on the slow daemon tick, off the IMU path.
     */
    private fun maybeSync(cfg: RoadSenseConfig.Snapshot, pose: com.overdrive.app.roadsense.detect.Pose, now: Long) {
        if (!cfg.crowdDownload && !cfg.crowdUpload) return
        // Lazy-load the persisted last-sync time on first use so a reboot doesn't
        // re-sync. (cfg is fresh this tick; read the raw section for the long.)
        if (lastSyncMs < 0L) {
            lastSyncMs = try {
                com.overdrive.app.config.UnifiedConfigManager.loadConfig()
                    .optJSONObject("roadSense")?.optLong("lastSyncMs", 0L) ?: 0L
            } catch (_: Throwable) { 0L }
        }
        if (now - lastSyncMs < SYNC_MS) return
        // Don't advance/persist the cadence cursor until at least one enabled
        // direction actually succeeded (audit network #5b): download()/upload() are
        // designed to return ok=false (network down, worker unreachable, proxy mid-
        // transition) rather than throw, so advancing here would burn the full 2.5 h
        // window on a transient blip and defer the next retry for hours. A failed
        // tick instead retries on the next housekeeping tick.
        var anyOk = false
        // Set when the server capped the response and more rows match (cold/dense
        // first sync): schedule the NEXT sync SOON to drain the remaining pages
        // rather than waiting the full 2.5 h cadence (audit network LOW paging).
        var morePending = false

        if (cfg.crowdDownload) {
            val tiles = SpatialIndex.neighborTiles(pose.lat, pose.lng).toList()
            val sinceMap = tileCursor.sinceMap(tiles)
            val result = syncProvider.download(tiles, sinceMap)
            if (result.ok) {
                anyOk = true
                if (result.more) morePending = true
                // Persist downloaded confirmed hazards as CLOUD-sourced rows so they
                // show up in approach queries but are NEVER re-uploaded (audit network
                // #7): upsertDetection only ever writes source=LOCAL, so a plain
                // upsert here tagged downloaded rows LOCAL and made them eligible for
                // re-upload under this device's id — fabricating distinct-device
                // consensus. upsertCloudHazard tags them SOURCE_CLOUD; queryForUpload
                // filters those out.
                for (h in result.hazards) store.upsertCloudHazard(h, now)
                // Advance each tile to ITS OWN observed high-water, NEVER to a busy
                // neighbour's max (audit network #9): a quiet tile that returned
                // nothing is caught up only to its own query floor (the `since` we
                // sent for it), so a row whose updated_ms later lands between that
                // floor and an unrelated busy tile's max is still returned next sync
                // — not skipped forever. Tiles that DID return rows advance to their
                // own tileHighWater. This still avoids the min-cursor re-pull cost
                // (audit network #2) because each empty tile keeps its own floor
                // rather than being dragged back to the global minimum.
                tileCursor.advance(sinceMap, result.tileHighWater)
            }
        }
        if (cfg.crowdUpload) {
            val deviceId = DeviceId.current(now)
            // Lazy-load the persisted upload cursor on first use (same pattern as
            // lastSyncMs) so a reboot / id-rotation doesn't re-upload the backlog
            // (audit network #5).
            if (lastUploadCursor < 0L) {
                lastUploadCursor = try {
                    com.overdrive.app.config.UnifiedConfigManager.loadConfig()
                        .optJSONObject("roadSense")?.optLong("lastUploadCursor", 0L) ?: 0L
                } catch (_: Throwable) { 0L }
            }
            // Cap the batch HERE to the same size the provider sends (256), so the
            // cursor advance and the actually-uploaded slice agree. Advancing over a
            // larger query result than was sent would silently drop rows past 256
            // forever (audit network #1). Remaining rows go on the next tick.
            var batch = store.queryForUpload(cfg.uploadConfidenceThreshold.toDouble(), lastUploadCursor)
                .take(MAX_UPLOAD_BATCH)
            // Batch-boundary tie guard (audit network #6): queryForUpload filters
            // `updated_ms > since` STRICTLY, so once we advance the cursor to the
            // batch's max updated_ms, any eligible row sharing that exact ms but cut
            // off by the 256 cap is skipped FOREVER. Ties are realistic (inserts +
            // merges stamp updated_ms = nowMs; a backlog or washboard burst can write
            // several rows in the same ms). When the batch is full AND its trailing
            // rows all share the max updated_ms, drop that equal-ms tail and don't
            // advance past it, so the whole tied group is re-queried next tick instead
            // of partially uploaded-and-skipped.
            if (batch.size == MAX_UPLOAD_BATCH) {
                val maxMs = batch.last().updatedMs
                val trimmed = batch.filter { it.updatedMs < maxMs }
                // Only trim if doing so still leaves something to send; if the ENTIRE
                // capped batch shares one updated_ms we can't make progress by trimming
                // (we'd send nothing forever), so send it as-is and accept that any
                // same-ms rows beyond the cap are an extreme edge we can't page past.
                if (trimmed.isNotEmpty()) batch = trimmed
            }
            if (batch.isNotEmpty()) {
                val r = syncProvider.upload(batch, deviceId)
                if (r.ok) {
                    anyOk = true
                    lastUploadCursor = batch.maxOf { it.updatedMs }
                    try {
                        com.overdrive.app.config.UnifiedConfigManager.updateSection(
                            "roadSense",
                            org.json.JSONObject().put("lastUploadCursor", lastUploadCursor),
                        )
                    } catch (_: Throwable) {}
                }
            } else {
                // Upload enabled but nothing eligible to send — that's a successful
                // no-op for cadence purposes (don't keep retrying every tick).
                anyOk = true
            }
        }

        // Only now that at least one direction succeeded (or had nothing to do) do we
        // advance + persist the 2.5 h cadence cursor (audit network #5b). If the
        // server signalled more pages pending, back-date the cursor so the NEXT
        // housekeeping tick re-syncs within ~SYNC_PAGE_DRAIN_MS to drain the rest,
        // instead of waiting the full cadence (cold/dense first sync only).
        if (anyOk) {
            lastSyncMs = if (morePending) now - SYNC_MS + SYNC_PAGE_DRAIN_MS else now
            try {
                com.overdrive.app.config.UnifiedConfigManager.updateSection(
                    "roadSense", org.json.JSONObject().put("lastSyncMs", lastSyncMs))
            } catch (_: Throwable) {}
        }
    }

    /**
     * Read the overlay's confirm verdict (roadSense.pendingConfirmResult), and if
     * it's new + matches our pending detection, record the ground-truth label
     * (R-DET-7) and mark the stored hazard human-verified (D-012/D-025).
     */
    private fun consumePendingConfirmResult(now: Long) {
        val pending = pendingConfirm ?: return
        // forceReload ONCE here (only reached when a confirm is pending): the verdict
        // is written by the APP UID, so the daemon needs a fresh cross-UID read to
        // see it. This is the only forceReload on the tick, and only while awaiting.
        val result = try {
            com.overdrive.app.config.UnifiedConfigManager.forceReload()
                .optJSONObject("roadSense")?.optJSONObject("pendingConfirmResult")
        } catch (_: Throwable) { null }

        // Find a fresh verdict for THIS pending detection, if any.
        val verdict = result?.takeIf {
            it.optLong("ts", 0L) > lastConfirmResultTs && it.optString("id") == pending.hazardId
        }

        if (verdict == null) {
            // G-7 auto-accept: the confirm card must never demand interaction while
            // driving. If no verdict arrived within CONFIRM_TIMEOUT_MS, record the
            // ALGORITHM's own assessment as the (auto-)confirmed label and clear the
            // card — exactly "accept algorithm assessment after N seconds". This is a
            // weaker label than an explicit human tap, so we mark it auto (no user
            // corrections) and still local-confirm the hazard.
            if (now - pending.shownMs >= CONFIRM_TIMEOUT_MS) {
                groundTruth.record(
                    hazardId = pending.hazardId,
                    candidate = pending.candidate,
                    algoType = pending.assessment.type,
                    algoSeverity = pending.assessment.severity,
                    algoConfidence = pending.assessment.confidence,
                    confirmed = true,        // auto-accept = trust the algorithm
                    userSeverity = null,
                    userType = null,
                    nowMs = now,
                    lat = pending.lat,
                    lng = pending.lng,
                )
                store.markHumanVerified(pending.hazardId, true, null, null, now)
                pendingConfirm = null
                visualSink.setPendingConfirm(null)
                Log.i(TAG, "calibration auto-accept (timeout) id=${pending.hazardId} → algo label recorded")
                plog.info("calibration auto-accept (timeout) id=${pending.hazardId}")
            }
            return
        }

        lastConfirmResultTs = verdict.optLong("ts", 0L)
        val id = verdict.optString("id")
        val confirmed = verdict.optBoolean("confirmed", true)
        // Optional user corrections (R-OVL-6): severity bucket 1..3 and/or type
        // ordinal. Absent keys (or <0 sentinels) mean "no correction — accept algo".
        val userSeverity = verdict.optInt("severity", -1).takeIf { it in 1..3 }
        val userType = verdict.optInt("type", -1).takeIf { it >= 0 }
        val userSeverityEnum = userSeverity?.let {
            com.overdrive.app.roadsense.detect.Severity.values().firstOrNull { s -> s.level == it }
        }
        val userTypeEnum = userType?.let {
            com.overdrive.app.roadsense.detect.HazardType.values().getOrNull(it)
        }

        // Persist the ground-truth label (raw features + algo assessment + verdict +
        // any user corrections).
        groundTruth.record(
            hazardId = pending.hazardId,
            candidate = pending.candidate,
            algoType = pending.assessment.type,
            algoSeverity = pending.assessment.severity,
            algoConfidence = pending.assessment.confidence,
            confirmed = confirmed,
            userSeverity = userSeverityEnum,
            userType = userTypeEnum,
            lat = pending.lat,
            lng = pending.lng,
            nowMs = now,
        )
        // Reflect the verdict in the hazard store (instant local-confirm or remove),
        // applying any severity/type correction on confirm.
        store.markHumanVerified(
            pending.hazardId, confirmed,
            if (confirmed) userSeverity else null,
            if (confirmed) userType else null,
            now,
        )
        pendingConfirm = null
        visualSink.setPendingConfirm(null)
        Log.i(TAG, "calibration verdict id=$id confirmed=$confirmed sevΔ=$userSeverity typeΔ=$userType → label recorded")
    }

    // ── ImuStream.Listener (pipeline hot path, IPC reader thread) ──────────────

    override fun onAccel(sample: ImuAccelSample) {
        // HOT PATH — runs at ~100 Hz. Keep allocations + syscalls minimal (R-PERF-1).
        // One clock() read per sample; the cached snapshots below avoid re-fetching
        // (and re-allocating) vehicle/GPS data that only refreshes every few seconds.
        val nowWall = clock()

        // 1) gravity removal → vertical residual
        val aVert = gravity.update(sample.ax, sample.ay, sample.az)

        // 2) refresh the cached vehicle-dynamics snapshot on a throttle. The
        //    underlying BydDataCollector only polls ~5 s (F-011), so fetching it
        //    every 100 Hz sample would allocate a VehicleDynamics 100×/s for no new
        //    data. Cache it; refresh ~2 Hz. Same for GPS.
        if (nowWall - lastVehiclePollMs > VEHICLE_POLL_MS) {
            lastVehiclePollMs = nowWall
            cachedDynamics = vehicleSource.latest(nowWall)
            // Refresh the master-enabled flag on the same throttle (config is
            // file-backed; reading it per-100Hz-sample would be wasteful I/O).
            featureEnabled = RoadSenseConfig.snapshot().enabled
        }
        if (nowWall - lastGpsPollMs > GPS_POLL_MS) {
            lastGpsPollMs = nowWall
            locationSource.latest(nowWall)?.let { gpsBuffer.add(it) }
        }
        val dyn = cachedDynamics

        // 3) speed (from the reused snapshot; fall back to GPS speed if vehicle
        //    data isn't ready). Feeds detector threshold + calibration gating.
        val speedKmh = dyn?.speedKmh ?: (gpsBuffer.latest()?.speedMps?.times(3.6f) ?: 0f)
        val speedMps = speedKmh / 3.6f
        lastSeenSpeedKmh = speedKmh   // for the persistent IMU-flow heartbeat

        // 4) feed the silent vehicle calibrator (quiet samples only — it self-gates)
        calibrator.onSample(aVert, speedKmh, detector.inEvent, eventsPerSec())

        // 5) detection (uses the sensor sample's own tMs, not wall-clock). Pass
        //    the gravity-free LATERAL + LONGITUDINAL residuals from the SAME
        //    projection so the detector can derive lateral asymmetry (one-sided vs
        //    full-width) while gating out fore-aft brake/launch energy (audit #6).
        val candidate = detector.onSample(
            VerticalSample(
                sample.tMs, aVert, speedMps,
                gravity.lateralResidual, gravity.longitudinalResidual,
            )
        ) ?: return
        handleCandidate(candidate, dyn, nowWall)
    }

    override fun onGyro(sample: ImuGyroSample) {
        // Track peak yaw/roll over the (current) event window for rejection. Yaw
        // ≈ rotation about vertical (turn); roll ≈ about the travel axis. We don't
        // know the device's exact axis mapping, so use the two largest-magnitude
        // components as a robust proxy — RejectionFilter only needs "is the body
        // rotating hard" (F-006), not precise axis attribution.
        val ax = abs(sample.gx); val ay = abs(sample.gy); val az = abs(sample.gz)
        val maxC = maxOf(ax, ay, az)
        val midC = (ax + ay + az) - maxC - minOf(ax, ay, az)
        // Age out a peak older than ~one event window so a turn made before the
        // current jolt no longer dominates (audit detection #1). Uses the sensor
        // sample's own tMs (same clock the detector/rate window use), not wall-clock.
        val tMs = sample.tMs
        if (tMs - peakYawTMs > GYRO_PEAK_WINDOW_MS) peakYaw = 0f
        if (tMs - peakRollTMs > GYRO_PEAK_WINDOW_MS) peakRoll = 0f
        if (maxC >= peakYaw) { peakYaw = maxC; peakYawTMs = tMs }
        if (midC >= peakRoll) { peakRoll = midC; peakRollTMs = tMs }
    }

    override fun onStreamState(state: ImuStream.State) {
        Log.d(TAG, "IMU stream state=$state")
    }

    // ── Candidate → assessment → store ─────────────────────────────────────────

    private fun handleCandidate(candidate: DetectionCandidate, dyn: VehicleDynamics?, now: Long) {
        trackCandidateRate(candidate.tMs)
        // Master toggle: if the feature is disabled we still let the detector +
        // calibrator run (cheap, keeps calibration warm) but we map nothing.
        if (!featureEnabled) { resetEventGyro(); return }

        // Rejection needs vehicle dynamics; if unavailable we can't safely confirm
        // it wasn't a brake/turn artefact, so be conservative and skip mapping.
        if (dyn == null) {
            dropNoDyn++
            resetEventGyro(); return
        }
        val gyroStats = GyroStats(peakYawRateRps = peakYaw, peakRollRateRps = peakRoll)
        val verdict = rejection.evaluate(candidate, dyn, gyroStats, eventsPerSec())
        resetEventGyro()
        if (verdict.rejected) {
            // D-032: a SUSTAINED washboard/cobble stretch isn't noise to discard —
            // it's a rough-section hazard worth ONE warning. Convert it (throttled
            // so we map ~one row per stretch, not per cobble); every OTHER reject
            // (brake/turn/curb/gear) is still dropped.
            if (verdict.reason == "washboard") {
                maybeMapRoughSection(candidate, now)
            } else {
                Log.d(TAG, "rejected: ${verdict.reason}")
            }
            // Tally reject reasons so the imu-flow heartbeat can report WHY candidates
            // didn't become hazards (logcat Log.d is volatile across a no-ADB drive).
            dropRejects[verdict.reason ?: "?"] = (dropRejects[verdict.reason ?: "?"] ?: 0) + 1
            return
        }

        // Classify (speed-normalized + vehicle-cal + confidence).
        val pose = gpsBuffer.backProject(candidate.tMs, GpsRingBuffer.DEFAULT_FIX_LATENCY_MS)
        val gpsAcc = pose?.accuracyM ?: 999f
        val assessment: Assessment = classifier.classify(
            candidate = candidate,
            vehicleScale = calibrator.vehicleScale,
            calibrationMaturity = calibrator.maturity,
            gpsAccuracyM = gpsAcc,
        )

        // Map from drive one (D-015): store regardless of confidence. No pose ⇒
        // we can't localize, so skip (a hazard with no position is useless).
        if (pose == null) {
            Log.d(TAG, "no pose to localize hazard; skipping store")
            dropNoPose++
            return
        }
        dropStored++
        val hazard = RoadSenseHazard(
            lat = pose.lat,
            lng = pose.lng,
            type = assessment.type,
            severity = assessment.severity,
            headingDeg = validHeading(pose.bearingDeg, candidate.speedMps),
            confidence = assessment.confidence,
            speedKmh = candidate.speedMps * 3.6f,
            aVertPeak = assessment.normalizedPeak,
            tMs = candidate.tMs,
        )
        val id = store.upsertDetection(hazard, now)
        val hazardMsg = "hazard ${assessment.type}/${assessment.severity} " +
            "conf=${"%.2f".format(assessment.confidence)} @${pose.lat},${pose.lng} id=$id"
        Log.i(TAG, hazardMsg)
        plog.info(hazardMsg)   // persist (logcat is volatile across a no-ADB drive)

        // Calibration Mode (R-OVL-6/D-025): surface this detection for the user to
        // confirm/correct in the overlay. We stash the raw candidate + assessment
        // so onWarningTick can write the ground-truth label once the verdict
        // round-trips. Only one pending confirm at a time — a newer detection
        // replaces an unanswered one (the older just never gets a human label).
        if (calibrationMode) {
            pendingConfirm = PendingLabel(id, candidate, assessment, pose.lat, pose.lng, now)
            visualSink.setPendingConfirm(
                OverlayState.PendingConfirm(
                    hazardId = id,
                    algoType = assessment.type.ordinal,
                    algoSeverity = assessment.severity.level,
                    algoConfidence = assessment.confidence,
                )
            )
        }
    }

    private fun resetEventGyro() { peakYaw = 0f; peakYawTMs = 0L; peakRoll = 0f; peakRollTMs = 0L }

    /**
     * Heading to STORE for a hazard, or a sentinel when it's untrustworthy (audit
     * accuracy S1). GPS bearing is only meaningful while moving; below the heading-
     * reliable floor Location.getBearing() defaults to 0° (due north), which would
     * be stored as a real heading and then mis-drive the ApproachEngine road-match
     * gate (suppressing real hazards on E-W roads, admitting wrong-road ones on N-S).
     * Store [HEADING_UNKNOWN] instead so the gate treats it as "road identity
     * unknown" and falls back to the cone-only test rather than a bogus 0°. */
    private fun validHeading(bearingDeg: Float, speedMps: Float): Float =
        if (speedMps > HEADING_RELIABLE_MPS) bearingDeg else HEADING_UNKNOWN

    /**
     * D-032: map a SUSTAINED washboard/cobble stretch as a single ROUGH_SECTION
     * hazard (one warning for the stretch), rather than discarding it or chiming on
     * every cobble. Throttled by [ROUGH_SECTION_MIN_GAP_MS] so a long rough run maps
     * ~one row at its start; the store's same-spot/zone logic groups repeats. Severity
     * is MINOR by default (washboard is annoyance, not a wheel-breaker) and bumped to
     * MODERATE only if the individual jolt was itself large. Confidence is modest —
     * it's a texture call, not a clean biphasic pulse. Runs on the IPC/sensor thread.
     */
    private fun maybeMapRoughSection(candidate: DetectionCandidate, now: Long) {
        // Use the event tMs for the throttle (same clock the rate window uses).
        if (candidate.tMs - lastRoughSectionMs < ROUGH_SECTION_MIN_GAP_MS) return
        if (!featureEnabled) return
        val pose = gpsBuffer.backProject(candidate.tMs, GpsRingBuffer.DEFAULT_FIX_LATENCY_MS) ?: return
        lastRoughSectionMs = candidate.tMs
        val rawJolt = maxOf(abs(candidate.peakUp), abs(candidate.peakDown))
        // Speed- + vehicle-normalize the jolt the SAME way SeverityClassifier does
        // (audit detection #8): a_vert_peak must be a road property comparable across
        // rows. Storing the RAW device-frame jolt here while every other row stores
        // the normalized peak made the column incomparable (mergeInto takes max
        // across rows) and made ROUGH_SECTION_MODERATE_JOLT speed-dependent — the
        // same washboard reading MINOR at low speed, MODERATE at high speed.
        val v = candidate.speedMps.coerceIn(
            SeverityClassifier.MIN_NORM_SPEED_MPS, SeverityClassifier.MAX_NORM_SPEED_MPS
        )
        val speedFactor = kotlin.math.sqrt(SeverityClassifier.REFERENCE_SPEED_MPS / v)
        val safeVehicleScale = calibrator.vehicleScale.let { if (it > 1e-3f) it else 1f }
        val jolt = rawJolt * speedFactor / safeVehicleScale
        val severity = if (jolt >= ROUGH_SECTION_MODERATE_JOLT)
            com.overdrive.app.roadsense.detect.Severity.MODERATE
        else com.overdrive.app.roadsense.detect.Severity.MINOR
        val hazard = RoadSenseHazard(
            lat = pose.lat,
            lng = pose.lng,
            type = HazardType.ROUGH_SECTION,
            severity = severity,
            headingDeg = validHeading(pose.bearingDeg, candidate.speedMps),
            confidence = ROUGH_SECTION_CONFIDENCE,
            speedKmh = candidate.speedMps * 3.6f,
            aVertPeak = jolt,
            tMs = candidate.tMs,
        )
        val id = store.upsertDetection(hazard, now)
        Log.i(TAG, "rough_section sev=$severity @${pose.lat},${pose.lng} id=$id")
    }

    // Rolling candidate-rate window for washboard rejection (R-DET-5).
    private fun trackCandidateRate(tMs: Long) {
        recentCandidateMs.addLast(tMs)
        val cutoff = tMs - WASHBOARD_WINDOW_MS
        while (recentCandidateMs.isNotEmpty() && recentCandidateMs.first() < cutoff) {
            recentCandidateMs.removeFirst()
        }
    }

    private fun eventsPerSec(): Float =
        recentCandidateMs.size.toFloat() / (WASHBOARD_WINDOW_MS / 1000f)

    companion object {
        private const val TAG = "RoadSense/Controller"
        private const val GPS_POLL_MS = 500L
        /** Vehicle-dynamics cache refresh (~2 Hz). Source only updates ~5 s (F-011),
         *  so this is generous; keeps brakeAgeMs fresh enough for rejection. */
        private const val VEHICLE_POLL_MS = 500L
        /** GPS bearing is noise below ~walking pace; above this we trust heading
         *  for the ApproachEngine forward-cone (else it falls back to range-only). */
        private const val HEADING_RELIABLE_MPS = 2.5f
        /** Sentinel stored heading meaning "heading was unreliable at detection" — the
         *  ApproachEngine road-match gate skips the heading test for these (audit S1). */
        const val HEADING_UNKNOWN = -1f
        /** Self-driven housekeeping tick: ~2 Hz (regime poll + warning eval). */
        private const val TICK_MS = 500L
        /** Persistent IMU-flow heartbeat cadence (diagnostics). 30 s keeps the daemon
         *  log small over a long drive while still proving the pipeline ran. */
        private const val IMU_HEARTBEAT_MS = 30_000L
        /** How often to persist calibration to UCM (per-vehicle, slow-changing). 60 s
         *  is plenty — a lost minute of learning is trivial, and it keeps the full-file
         *  config rewrite rare. */
        private const val CAL_PERSIST_MS = 60_000L
        /** How often to persist route coverage (only when a new tile was entered). */
        private const val COVERAGE_PERSIST_MS = 30_000L
        /** G-7 auto-accept timeout for the Calibration-Mode confirm card: if the
         *  driver hasn't tapped confirm/reject within this window, the card auto-
         *  dismisses and the algorithm's own assessment is recorded as the label, so
         *  it never demands interaction while driving. 8 s ≈ glanceable without
         *  nagging; checked on the ~2 Hz warn tick (so effective resolution ~0.5 s). */
        private const val CONFIRM_TIMEOUT_MS = 8_000L
        /** Crowdsource sync cadence — road hazards don't change minute-to-minute,
         *  so syncing every ~2.5 h (plus once shortly after the first DRIVING tick
         *  of an ACC session) is plenty and keeps the free-tier cost trivial (G-6).
         *  Persisted across daemon restarts so a reboot doesn't force a re-sync. */
        private const val SYNC_MS = 150 * 60 * 1000L  // 2.5 hours
        /** When the server signals more download pages pending, re-sync this soon
         *  instead of waiting the full cadence — drains a cold/dense first sync over
         *  a few quick ticks, then settles back to SYNC_MS. */
        private const val SYNC_PAGE_DRAIN_MS = 15_000L
        /** Upload batch cap — MUST match the provider/server cap (256) so the cursor
         *  advance and the sent slice agree (audit network #1). */
        private const val MAX_UPLOAD_BATCH = 256
        /** Window for the washboard candidate-rate metric (matches RejectionFilter). */
        private const val WASHBOARD_WINDOW_MS = 2_000L
        /** Age-out horizon for the rolling gyro peak (audit detection #1). Beyond
         *  this a peak no longer reflects rotation concurrent with a jolt, so it must
         *  not vote "cornering". ~EventDetector.DEFAULT_WINDOW_MS (400) so only yaw/
         *  roll near the event window contributes. */
        private const val GYRO_PEAK_WINDOW_MS = 500L
        /** D-032: min gap between mapping rough_section rows so a sustained stretch
         *  maps ~one row at a time (then the store/zone logic groups them) rather
         *  than one per cobble. ~5 s ≈ tens of metres at urban speed. */
        private const val ROUGH_SECTION_MIN_GAP_MS = 5_000L
        /** Jolt (m/s²) at/above which a rough-section sample is mapped MODERATE
         *  rather than MINOR — a washboard with real wheel-slamming bumps in it. */
        private const val ROUGH_SECTION_MODERATE_JOLT = 4.0f
        /** Confidence for a rough_section row — modest; it's a texture/rate call,
         *  not a clean isolated biphasic pulse. Above the default warn floor (0). */
        private const val ROUGH_SECTION_CONFIDENCE = 0.5f
    }
}
