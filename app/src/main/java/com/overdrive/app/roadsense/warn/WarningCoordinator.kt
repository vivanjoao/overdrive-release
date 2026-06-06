package com.overdrive.app.roadsense.warn

import android.media.AudioManager
import android.media.ToneGenerator
import android.util.Log
import com.overdrive.app.roadsense.config.RoadSenseConfig
import com.overdrive.app.roadsense.detect.Pose
import com.overdrive.app.roadsense.detect.Severity
import com.overdrive.app.roadsense.store.ApproachEngine
import com.overdrive.app.roadsense.store.RoadSenseStore

/**
 * Decides WHEN to warn the driver about an upcoming hazard and HOW (audio chime /
 * visual cue / both), honoring every gate (D-010 distance, D-015 confidence,
 * R-SET-4 per-severity, R-EXT-4 direction).
 *
 * ## Where it sits
 * Driven by the daemon controller's periodic tick (NOT the 100 Hz IMU path). On
 * each tick the controller hands it the live [Pose] + the current config snapshot;
 * this queries the store for hazards ahead (via [ApproachEngine]), picks the most
 * imminent one that passes the gates, and fires at most one warning per hazard.
 *
 * ## The gates (all must pass)
 *  1. feature + warnings enabled, and severity/confidence pass [RoadSenseConfig.Snapshot.warnsFor]
 *  2. hazard is AHEAD within the forward cone (ApproachEngine already filtered this)
 *  3. range ≤ dynamic alert distance `d = max(v·t_w, floor)` (D-010)
 *  4. we haven't already warned for THIS hazard id on this approach (dedupe)
 *
 * ## Audio
 * Uses [ToneGenerator] on STREAM_MUSIC — the same mechanism the project's
 * AudioTestApiHandler uses for beeps. Severity picks the tone so the driver can
 * tell a minor bump from a severe pothole without looking. Visual cues are
 * delegated to a [VisualSink] the overlay implements, keeping this class
 * overlay-agnostic + unit-testable.
 *
 * Not thread-safe; called from the single controller tick thread.
 */
class WarningCoordinator(
    private val store: RoadSenseStore,
    private val approach: ApproachEngine = ApproachEngine(),
    private val visualSink: VisualSink? = null,
    private val audio: AudioCue = ToneAudioCue(),
    private val clock: () -> Long = { System.currentTimeMillis() },
) {

    /** Overlay-implemented visual cue. Kept minimal so the overlay owns rendering. */
    interface VisualSink {
        /** Show/refresh the approach cue for the zone led by [hazardId] at [rangeM]
         *  with the given [relativeBearingDeg] (−180..+180, 0=ahead) and [severity]
         *  (the zone's WORST). [typeOrdinal] is the lead hazard's type (for the
         *  icon). [zoneCount]/[zoneLengthM]/[zoneRough] describe the cluster (D-032):
         *  count=1 length=0 for a singleton; count>1 / rough=true for a cluster the
         *  overlay renders as "N bumps ahead" / "rough section, N m". */
        fun showApproach(
            hazardId: String,
            rangeM: Double,
            relativeBearingDeg: Double,
            severity: Severity,
            typeOrdinal: Int,
            zoneCount: Int,
            zoneLengthM: Int,
            zoneRough: Boolean,
        )
        /** Clear any visible approach cue (no hazard ahead). */
        fun clearApproach()
    }

    /** Pluggable audio so tests don't need a real ToneGenerator. */
    interface AudioCue {
        fun chime(severity: Severity)
        fun release()
    }

    // Dedupe: the id we last warned for, and when, so we warn once per approach
    // and re-arm only after the hazard leaves range / a cooldown passes.
    private var lastWarnedId: String? = null
    private var lastWarnedMs = 0L

    /**
     * Evaluate one tick. [pose] is the live (or back-projected current) vehicle
     * pose; [cfg] the current config snapshot; [headingReliable] false at crawl /
     * no-fix (ApproachEngine then skips the cone filter).
     */
    fun onTick(pose: Pose, cfg: RoadSenseConfig.Snapshot, headingReliable: Boolean) {
        if (!cfg.enabled || !cfg.warnEnabled) {
            visualSink?.clearApproach()
            return
        }

        // Pull nearby hazards (tile-scoped); ApproachEngine consumes StoredHazard
        // directly (queryAhead's return type) — no adapter needed.
        val nearby = store.queryAhead(pose.lat, pose.lng, pose.bearingDeg.toDouble(), MAX_CANDIDATES)
        if (nearby.isEmpty()) { visualSink?.clearApproach(); return }

        // Dynamic alert distance from speed + configured lead time (D-010).
        val vMps = pose.speedMps
        val alertDist = maxOf(vMps * cfg.warnLeadSeconds, cfg.warnFloorMeters).toDouble()

        // Group ahead into zones (D-032), then pick the nearest zone that passes ALL
        // gates. A zone is gated on its LEAD distance (reached at its first member)
        // and its WORST member's severity/confidence — so a cluster with one severe
        // bump warns at "severe", and a single chime covers the whole stretch.
        val zones = approach.zonesAhead(pose, nearby, headingReliable)
        val target = zones.firstOrNull { z ->
            z.lead.rangeM <= alertDist &&
                z.members.any { cfg.warnsFor(it.stored.hazard.severity.level, it.stored.hazard.confidence) }
        }

        if (target == null) {
            visualSink?.clearApproach()
            // Leaving range re-arms the dedupe once the zone's lead is no longer ahead.
            if (lastWarnedId != null && zones.none { it.lead.stored.id == lastWarnedId }) {
                lastWarnedId = null
            }
            return
        }

        val lead = target.lead
        // The zone chimes/colours at its WORST member, not its nearest (D-032).
        val sev = severityFromLevel(target.maxSeverityLevel)
        // Always refresh the visual cue while in range (cheap, shows live distance +
        // zone count/length); only fire AUDIO once per zone (a repeating chime would
        // be maddening). The dedupe key is the zone's lead hazard id.
        if (cfg.warnMode != RoadSenseConfig.WarnMode.AUDIO) {
            visualSink?.showApproach(
                lead.stored.id, lead.rangeM, lead.relativeBearingDeg, sev,
                lead.stored.hazard.type.ordinal,
                target.count, target.lengthM.toInt(), target.isRoughSection,
            )
        }

        val now = clock()
        val alreadyWarned = lead.stored.id == lastWarnedId &&
            (now - lastWarnedMs) < REWARN_COOLDOWN_MS
        if (!alreadyWarned) {
            lastWarnedId = lead.stored.id
            lastWarnedMs = now
            if (cfg.warnMode != RoadSenseConfig.WarnMode.VISUAL) {
                audio.chime(sev)
            }
            Log.i(TAG, "warn $sev zone lead=${lead.stored.id} n=${target.count} " +
                "len=${"%.0f".format(target.lengthM)}m rough=${target.isRoughSection} " +
                "@${"%.0f".format(lead.rangeM)}m (alertDist=${"%.0f".format(alertDist)}m, mode=${cfg.warnMode})")
        }
    }

    /** Map a stored severity level (1..3) back to [Severity], clamped. */
    private fun severityFromLevel(level: Int): Severity = when {
        level >= Severity.SEVERE.level -> Severity.SEVERE
        level == Severity.MODERATE.level -> Severity.MODERATE
        else -> Severity.MINOR
    }

    fun release() = audio.release()

    companion object {
        private const val TAG = "RoadSense/Warn"
        private const val MAX_CANDIDATES = 16
        /** Don't re-chime for the same hazard within this window (one chime/approach). */
        private const val REWARN_COOLDOWN_MS = 20_000L
    }
}

/**
 * Default [WarningCoordinator.AudioCue] backed by [ToneGenerator] on STREAM_MUSIC
 * — same approach as the project's AudioTestApiHandler. Severity → distinct tone
 * so the chime itself conveys urgency. The generator is created lazily and reused;
 * [release] frees it when the feature stops.
 */
class ToneAudioCue : WarningCoordinator.AudioCue {
    private var tg: ToneGenerator? = null

    private fun gen(): ToneGenerator? {
        if (tg == null) {
            tg = try { ToneGenerator(AudioManager.STREAM_MUSIC, VOLUME) } catch (_: Throwable) { null }
        }
        return tg
    }

    override fun chime(severity: Severity) {
        val tone = when (severity) {
            Severity.MINOR -> ToneGenerator.TONE_PROP_BEEP          // single soft beep
            Severity.MODERATE -> ToneGenerator.TONE_PROP_BEEP2      // double beep
            Severity.SEVERE -> ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD // urgent
        }
        val ms = if (severity == Severity.SEVERE) 600 else 300
        try { gen()?.startTone(tone, ms) } catch (_: Throwable) { /* never crash on a chime */ }
    }

    override fun release() {
        try { tg?.release() } catch (_: Throwable) {}
        tg = null
    }

    companion object { private const val VOLUME = 90 }
}
