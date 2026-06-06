package com.overdrive.app.roadsense.detect

import kotlin.math.abs

/**
 * Streaming, sliding-window biphasic-pulse detector — the stage that turns the
 * `a_vert` residual stream from [GravityFrame] into raw [DetectionCandidate]s.
 *
 * ## What it keys on (the hardware truth — see dev/roadsense/05-FINDINGS.md)
 *
 * A real road feature at speed shows up on the vertical channel as a **biphasic
 * pulse**: the suspension loads one way then rebounds the other. F-007 measured a
 * textbook speed bump at ~30 km/h as `−2.0 m/s² (load) → +3.5 m/s² (crest) →
 * rebound`, total ≈ 180 ms, ≈ 18 samples at 100 Hz, peak 3.5 vs a driving noise
 * floor of ±0.18 m/s² stdev (F-005) ⇒ ~19× SNR. So the signal is clean and the
 * morphology is what we extract:
 *
 *   - **peakUp / peakDown** — the two excursions of the biphasic pulse.
 *   - **dipLeading** — down-first (pothole-ish) vs up-first/crest-first
 *     (breaker-ish). F-007 + 03-ARCHITECTURE §Severity: potholes are dip-leading
 *     with a sharper rise (<40 ms); breakers are crest-leading / symmetric.
 *   - **riseTimeMs** — zero-cross → first peak. Pothole ≪ breaker (the sharp-edge
 *     vs ramped-profile distinction the classifier downstream reasons on).
 *   - **durationMs** — total span; a real event is ~150–200 ms (~15–20 samples).
 *   - **axlePairGapMs** — if a second same-shape pulse arrives one wheelbase-time
 *     later (`Δt = wheelbase / v`), it's almost certainly a real transverse road
 *     feature (front axle then rear axle hit the same bump). High-confidence cue.
 *
 * ## Why streaming, not batch
 *
 * This runs inside the app-process foreground service at the sensor rate
 * (99.9 Hz, F-005). R-PERF-1/3: compute and memory are constrained. So:
 *   - one sample in via [onSample], at most one candidate out;
 *   - a **fixed-size primitive ring buffer** (FloatArray + parallel LongArray for
 *     timestamps), NOT a growing collection — no per-sample allocation, no boxing;
 *   - the ONLY allocation on the hot path is the returned [DetectionCandidate]
 *     when an event actually completes (rare — a handful per drive).
 *
 * ## Threading
 *
 * NOT thread-safe — by design. The owning [RoadSenseService] feeds it from a
 * single sensor-callback thread (same contract as [GravityFrame]). Do not call
 * [onSample] concurrently.
 *
 * ## What this stage does NOT do
 *
 * It does not reject (turns/braking/washboard — that's [RejectionFilter]), does
 * not classify severity/type, and does not localize. It is the dumb morphology
 * extractor. It DOES derive [DetectionCandidate.lateralAsymmetry] from the
 * gravity-free horizontal residual ([VerticalSample.aHoriz], supplied by
 * [GravityFrame.horizontalResidual]) paired with the vertical peak — a one-wheel
 * pothole rolls the body (horizontal-dominant) where a full-width breaker stays
 * vertical (R-DET-3). When the vertical peak is too weak to trust the ratio,
 * `asymmetryValid` is left false so downstream gates ignore it.
 */
class EventDetector(
    /**
     * Sliding-window length in milliseconds. Must comfortably contain the
     * longest event we want to characterize. F-007's bump was ~180 ms; we want
     * headroom to capture both lobes of the biphasic pulse plus a little lead-in,
     * so the default is ~400 ms. At 100 Hz that's 40 samples — tiny.
     */
    windowMs: Int = DEFAULT_WINDOW_MS,
    /**
     * Nominal sample rate (Hz) used only to size the ring buffer. The detector's
     * timing math uses real sample timestamps ([VerticalSample.tMs]), so a small
     * error here only affects buffer capacity, never measured durations. F-005:
     * real rate is 99.9 Hz; 100 is the right nominal.
     */
    sampleRateHz: Int = NOMINAL_SAMPLE_RATE_HZ,
    /**
     * Speed-aware threshold base (m/s²). The detection threshold on |a_vert| is
     * `thresholdBase + thresholdSpeedSlope * speedKmh`. Base is set well above
     * the ±0.18 m/s² noise floor (F-005) so road texture never trips us; the
     * slope accounts for the same bump hitting harder at speed (F-007 was a
     * single-speed capture — point 4 of the findings' detector implications).
     * Provisional per the spec: 1.0 + 0.05·speedKmh.
     */
    private val thresholdBase: Float = DEFAULT_THRESHOLD_BASE,
    private val thresholdSpeedSlope: Float = DEFAULT_THRESHOLD_SPEED_SLOPE,
    /**
     * Minimum speed (km/h) to arm detection at all. Below this we gate OFF and
     * return null: at walking pace the vertical channel is dominated by
     * parking-lot manoeuvring, door slams, people getting in — not road hazards —
     * and a bump that slow carries no useful severity signal anyway.
     */
    private val minSpeedKmh: Float = DEFAULT_MIN_SPEED_KMH,
    /**
     * Assumed wheelbase (m) for the axle-pair check. BYD Seal ≈ 2.9 m; we use a
     * conservative ~2.7 m so the acceptance window straddles typical sedans. The
     * front and rear axle hit the same transverse feature `Δt = wheelbase / v`
     * apart; seeing that second matched pulse is a strong "real road feature" cue.
     */
    private val wheelbaseM: Float = DEFAULT_WHEELBASE_M,
    /**
     * Fractional tolerance on the axle-pair gap. We accept a second pulse whose
     * arrival gap is within ±this fraction of the predicted `wheelbase / v`.
     * ±30% absorbs wheelbase uncertainty, speed change across the feature, and
     * timing jitter without matching unrelated bumps.
     */
    private val axlePairTolerance: Float = DEFAULT_AXLE_PAIR_TOLERANCE,
) {
    // ---- Ring buffer (fixed-size, no allocation after construction) ----------
    // Parallel arrays: aVert[i] is the residual, tMs[i] its timestamp. We keep
    // raw samples so a completed event can report exact peaks and timings; the
    // window is small (tens of samples) so this is cheap.
    private val capacity: Int = maxOf(8, (windowMs.toLong() * sampleRateHz / 1000L).toInt())
    private val aVertBuf = FloatArray(capacity)
    private val tMsBuf = LongArray(capacity)
    private var head = 0          // index where the NEXT sample will be written
    private var filled = 0        // number of valid samples (<= capacity)

    // ---- Event-accumulation state (the "in an event" sliding window) ---------
    // We are "active" from the moment |a_vert| first crosses the threshold until
    // the signal settles back into the noise band for QUIET_SAMPLES in a row.
    private var active = false
    private var evtStartMs = 0L          // timestamp of the first supra-threshold sample
    private var evtPeakUp = 0f           // max a_vert seen during the event
    private var evtPeakDown = 0f         // min a_vert seen during the event
    private var evtPeakUpMs = 0L         // when peakUp occurred
    private var evtPeakDownMs = 0L       // when peakDown occurred
    private var evtFirstSign = 0         // +1 if the event opened upward, -1 if downward, 0 unset
    private var evtZeroCrossMs = 0L      // timestamp of the threshold crossing that started the event
    private var quietRun = 0             // consecutive in-noise-band samples while active
    private var evtSpeedMps = 0f         // speed at the defining peak (carried into the candidate)
    private var evtPeakHoriz = 0f        // peak gravity-free LATERAL residual over the event (m/s²)
    private var evtPeakLong = 0f         // peak gravity-free LONGITUDINAL residual over the event (m/s²)

    // ---- Debounce / axle-pair memory -----------------------------------------
    // After emitting we must not re-emit the same physical event. We require the
    // signal to fall back below the noise floor and stay quiet for a gap before
    // arming again (R-DET: "MUST NOT emit two candidates for the same event").
    private var rearmQuietRun = 0
    private var armed = true

    // Memory of the just-emitted pulse so we can recognise the SECOND axle's
    // matching pulse and tag axlePairGapMs on it. Null when there's nothing to
    // pair against (or it has aged out of the plausible window).
    private var lastEmitPeakMs = 0L
    private var lastEmitDipLeading = false
    private var lastEmitValid = false

    // ---- Diagnostics ----------------------------------------------------------
    private var samplesSeen = 0L
    // Last sample timestamp seen, for the monotonic / gap guard. NOT cleared by the
    // in-stream guard (it sets the new baseline); cleared by full reset().
    private var lastTMs = 0L
    private var candidatesEmitted = 0L

    /** Total samples fed in. Diagnostics only. */
    val totalSamples: Long get() = samplesSeen

    /** Total candidates emitted. Diagnostics only. */
    val totalCandidates: Long get() = candidatesEmitted

    /** True while accumulating a (not-yet-completed) event. Diagnostics only. */
    val inEvent: Boolean get() = active

    /** Current speed-aware threshold for the most recent speed. Diagnostics only. */
    var lastThreshold: Float = thresholdBase
        private set

    /**
     * Feed one vertical sample. Returns a [DetectionCandidate] at the instant an
     * event completes (signal has settled after a supra-threshold excursion),
     * otherwise null.
     *
     * Hot path: no allocation except the returned candidate on a completing event.
     */
    fun onSample(s: VerticalSample): DetectionCandidate? {
        samplesSeen++

        // Time-jump / sensor-gap guard (audit detection #3): a non-monotonic or
        // large-gap timestamp makes durations go negative (MAX_EVENT_MS never trips,
        // event hangs) and produces garbage candidate timings. On a backward jump or
        // a gap, abandon the in-flight event/window so this sample starts clean.
        if (lastTMs != 0L && (s.tMs < lastTMs || s.tMs - lastTMs > GAP_MS)) {
            resetEvent()
            armed = true
            rearmQuietRun = 0
            lastEmitValid = false
            head = 0; filled = 0
        }
        lastTMs = s.tMs

        // Always keep the ring buffer current so timings/peaks are exact, even
        // for samples we end up gating out — cheap, and keeps the buffer coherent.
        aVertBuf[head] = s.aVert
        tMsBuf[head] = s.tMs
        head = (head + 1) % capacity
        if (filled < capacity) filled++

        val speedKmh = s.speedMps * MPS_TO_KMH

        // Speed gate (parking-lot noise). Below the floor we never detect; also
        // abandon any half-built event — if we've slowed to a crawl mid-window
        // it isn't a road-hazard signature worth completing.
        if (speedKmh < minSpeedKmh) {
            if (active) resetEvent()
            // Let the re-arm / pair memory keep ageing so we don't get stuck
            // disarmed; treat a slow stretch as quiet.
            ageRearmAndPairMemory(s.tMs, settled = true)
            return null
        }

        val threshold = thresholdBase + thresholdSpeedSlope * speedKmh
        lastThreshold = threshold

        val mag = abs(s.aVert)
        val settled = mag < (NOISE_FLOOR + NOISE_BAND_MARGIN)

        // ---- Re-arm logic ----------------------------------------------------
        // After an emit we sit disarmed until the signal returns to the noise
        // band for REARM_QUIET_SAMPLES consecutive samples. This is the debounce
        // that stops one physical bump (which rings/rebounds) emitting twice.
        if (!armed) {
            if (settled) {
                rearmQuietRun++
                if (rearmQuietRun >= REARM_QUIET_SAMPLES) {
                    armed = true
                    rearmQuietRun = 0
                }
            } else {
                rearmQuietRun = 0
            }
            // While disarmed we don't open new events, but we DO keep the
            // pair-memory alive so a genuine rear-axle pulse can still be matched
            // even though we suppress re-emitting. (We simply don't emit it; the
            // first-axle candidate already carries axlePairGapMs once we see it.)
            ageRearmAndPairMemory(s.tMs, settled)
            return null
        }

        ageRearmAndPairMemory(s.tMs, settled)

        if (!active) {
            // ---- Idle: look for the opening threshold crossing ----------------
            if (mag >= threshold) {
                active = true
                evtStartMs = s.tMs
                evtZeroCrossMs = s.tMs
                evtPeakUp = s.aVert
                evtPeakDown = s.aVert
                evtPeakUpMs = s.tMs
                evtPeakDownMs = s.tMs
                evtFirstSign = if (s.aVert >= 0f) +1 else -1
                evtSpeedMps = s.speedMps
                evtPeakHoriz = s.aHoriz
                evtPeakLong = s.aLong
                quietRun = 0
            }
            return null
        }

        // ---- Active: accumulate morphology until the event settles -----------
        if (s.aVert > evtPeakUp) { evtPeakUp = s.aVert; evtPeakUpMs = s.tMs }
        if (s.aVert < evtPeakDown) { evtPeakDown = s.aVert; evtPeakDownMs = s.tMs }
        if (s.aHoriz > evtPeakHoriz) evtPeakHoriz = s.aHoriz
        if (s.aLong > evtPeakLong) evtPeakLong = s.aLong

        if (settled) {
            quietRun++
            if (quietRun >= QUIET_SAMPLES) {
                // Event complete. Build the candidate, reset, possibly emit.
                return finishEvent(s.tMs)
            }
        } else {
            quietRun = 0
            // Guard against a pathological never-settling stretch (rough road /
            // washboard): cap the event span. Rejection handles washboard later,
            // but we must not accumulate unboundedly.
            if (s.tMs - evtStartMs > MAX_EVENT_MS) {
                return finishEvent(s.tMs)
            }
        }
        return null
    }

    /**
     * Close out the active event, compute the candidate, update debounce/pair
     * state, and return the candidate (or null if it degenerates to nothing).
     */
    private fun finishEvent(nowMs: Long): DetectionCandidate? {
        // The "defining peak" is the larger-magnitude excursion of the biphasic
        // pulse — that's the timestamp we localize on and the durationMs anchor.
        val upMag = abs(evtPeakUp)
        val downMag = abs(evtPeakDown)
        val peakMs: Long
        val definingPeakMs: Long
        if (downMag >= upMag) {
            peakMs = evtPeakDownMs
            definingPeakMs = evtPeakDownMs
        } else {
            peakMs = evtPeakUpMs
            definingPeakMs = evtPeakUpMs
        }

        // dipLeading: did the pulse open downward? Prefer the temporal order of
        // the two lobes (which excursion happened FIRST), falling back to the
        // sign of the opening sample. Down-first ⇒ pothole-ish (sharper rise).
        val dipLeading: Boolean = when {
            evtPeakDownMs < evtPeakUpMs -> true
            evtPeakUpMs < evtPeakDownMs -> false
            else -> evtFirstSign < 0
        }

        // riseTimeMs: zero-cross (event open) → the FIRST (leading) lobe's peak —
        // NOT the larger/defining lobe (audit detection #9). For a dip-leading
        // pothole the rebound crest is often the larger lobe, so measuring to the
        // defining peak times to the SECOND lobe (a long interval) and votes the
        // event as a slow-rise BREAKER, contradicting the dipLeading vote it should
        // corroborate. Leading-edge sharpness is the time to the first lobe. The
        // larger (defining) peak still anchors localization/durationMs above.
        val firstLobeMs = if (evtPeakDownMs <= evtPeakUpMs) evtPeakDownMs else evtPeakUpMs
        val riseTimeMs = (firstLobeMs - evtZeroCrossMs).toInt().coerceAtLeast(0)

        // durationMs: open → settle. Real events ~150–200 ms (F-007).
        val durationMs = (nowMs - evtStartMs).toInt().coerceAtLeast(0)

        // Sanity: a real biphasic pulse must clear the noise band on BOTH lobes
        // meaningfully, or at least have a strong single excursion. If neither
        // peak is appreciable the "event" was a borderline blip — drop it.
        val strongest = maxOf(upMag, downMag)
        if (strongest < NOISE_FLOOR + NOISE_BAND_MARGIN) {
            resetEvent()
            return null
        }

        // ---- Axle-pair check -------------------------------------------------
        // If the previous emitted pulse was the same shape (same dipLeading) and
        // arrived a plausible wheelbase-time ago, tag the gap. v from this event's
        // speed; Δt_expected = wheelbase / v. Accept within ±axlePairTolerance.
        var axlePairGapMs: Int? = null
        if (lastEmitValid && evtSpeedMps > 0.1f && lastEmitDipLeading == dipLeading) {
            val gapMs = peakMs - lastEmitPeakMs
            if (gapMs > 0) {
                val expectedMs = (wheelbaseM / evtSpeedMps) * 1000f
                val low = expectedMs * (1f - axlePairTolerance)
                val high = expectedMs * (1f + axlePairTolerance)
                if (gapMs >= low && gapMs <= high) {
                    axlePairGapMs = gapMs.toInt()
                }
            }
        }

        // ---- Lateral asymmetry from the horizontal channel -------------------
        // A one-sided hit (single-wheel pothole, curb scuff) loads one corner of
        // the car and rolls the body → a large LATERAL kick relative to the
        // vertical jolt. A full-width breaker hits both wheels symmetrically →
        // energy stays mostly vertical, little lateral. So the ratio
        // latPeak / (latPeak + vertPeak) is a 0..1 "one-sidedness" (evtPeakHoriz now
        // carries only the LATERAL residual; the longitudinal part is split out):
        //   ~0  = vertical-dominant → symmetric / full-width (breaker)
        //   ~1  = lateral-dominant  → one-sided (pothole / curb)
        // We only mark it VALID when the vertical peak clears the noise band, so a
        // borderline blip doesn't produce a garbage ratio (consumers gate on
        // asymmetryValid — see RejectionFilter Rule 6 / SeverityClassifier).
        val vertPeakMag = maxOf(abs(evtPeakUp), abs(evtPeakDown))
        val denom = vertPeakMag + evtPeakHoriz
        // Longitudinal-dominance gate (audit detection #6): evtPeakHoriz is now the
        // LATERAL residual only, but a brake/launch transient that slipped past the
        // rejection filter (stale ~5 s pedal poll, F-011) still leaks some fore-aft
        // energy into the lateral remainder. If the LONGITUDINAL peak dominates the
        // horizontal kick, the one-sidedness reading is driver-caused, not road —
        // so we refuse to validate the asymmetry rather than feed a fake one-sided
        // vote / curb reject.
        val longDominates = evtPeakLong > evtPeakHoriz * LONG_DOMINANCE_RATIO
        val asymmetry: Float
        val asymmetryValid: Boolean
        if (vertPeakMag >= NOISE_FLOOR + NOISE_BAND_MARGIN && denom > 1e-3f && !longDominates) {
            asymmetry = (evtPeakHoriz / denom).coerceIn(0f, 1f)
            asymmetryValid = true
        } else {
            asymmetry = 0f
            asymmetryValid = false
        }

        val candidate = DetectionCandidate(
            tMs = peakMs,
            peakUp = evtPeakUp,
            peakDown = evtPeakDown,
            riseTimeMs = riseTimeMs,
            durationMs = durationMs,
            dipLeading = dipLeading,
            speedMps = evtSpeedMps,
            axlePairGapMs = axlePairGapMs,
            lateralAsymmetry = asymmetry,
            asymmetryValid = asymmetryValid,
        )

        // Remember this pulse so the NEXT event (the rear axle) can pair against
        // it. Then disarm for debounce: require the signal to go quiet before we
        // open another event, so this physical bump's ringing doesn't re-fire.
        lastEmitPeakMs = peakMs
        lastEmitDipLeading = dipLeading
        lastEmitValid = true

        resetEvent()
        armed = false
        rearmQuietRun = 0
        candidatesEmitted++
        return candidate
    }

    /** Clear the in-event accumulator (does NOT touch debounce/pair memory). */
    private fun resetEvent() {
        active = false
        evtPeakUp = 0f
        evtPeakDown = 0f
        evtPeakHoriz = 0f
        evtPeakLong = 0f
        evtFirstSign = 0
        quietRun = 0
    }

    /**
     * Age out the axle-pair memory once it's too old to plausibly be the same
     * road feature's other axle (slowest credible speed ⇒ longest gap). Keeps the
     * pair check from matching an unrelated bump much later. `settled` is unused
     * for memory ageing today but kept for symmetry / future hysteresis tuning.
     */
    private fun ageRearmAndPairMemory(nowMs: Long, @Suppress("UNUSED_PARAMETER") settled: Boolean) {
        if (lastEmitValid && nowMs - lastEmitPeakMs > MAX_AXLE_PAIR_GAP_MS) {
            lastEmitValid = false
        }
    }

    /** Drop all state — call on a sensor restart / large time gap. */
    fun reset() {
        head = 0; filled = 0
        resetEvent()
        armed = true
        rearmQuietRun = 0
        lastEmitValid = false
        lastEmitPeakMs = 0L
        lastEmitDipLeading = false
        samplesSeen = 0L
        candidatesEmitted = 0L
        lastThreshold = thresholdBase
        lastTMs = 0L
    }

    companion object {
        /** m/s → km/h. */
        const val MPS_TO_KMH = 3.6f

        /** ~400 ms sliding window: comfortably contains the ~180 ms biphasic pulse (F-007) with lead-in. */
        const val DEFAULT_WINDOW_MS = 400

        /** F-005: real `-iner` accel runs at 99.9 Hz; 100 is the right nominal for buffer sizing. */
        const val NOMINAL_SAMPLE_RATE_HZ = 100

        /**
         * Speed-aware threshold: `base + slope·speedKmh` (m/s²). Provisional per
         * spec. Base 1.0 sits ~5.5× above the ±0.18 m/s² noise floor (F-005);
         * slope 0.05 raises the bar at speed where the same bump reads harder.
         */
        const val DEFAULT_THRESHOLD_BASE = 1.0f
        const val DEFAULT_THRESHOLD_SPEED_SLOPE = 0.05f

        /** Parking-lot gate: below ~10 km/h the vertical channel is manoeuvring noise, not hazards. */
        const val DEFAULT_MIN_SPEED_KMH = 10.0f

        /** Assumed wheelbase (m) for the axle-pair check. Conservative ~2.7 m so
         *  the gap window straddles typical sedans (BYD Seal ≈ 2.9 m). */
        const val DEFAULT_WHEELBASE_M = 2.7f

        /** ±fraction tolerance on the predicted axle-pair gap (wheelbase / v). */
        const val DEFAULT_AXLE_PAIR_TOLERANCE = 0.30f

        /** Driving vertical-residual noise floor, stdev (F-005). */
        const val NOISE_FLOOR = 0.18f

        /**
         * Extra margin above the noise floor that defines the "settled" band. The
         * signal must drop below `NOISE_FLOOR + margin` to count as quiet. A
         * couple of sigma keeps texture jitter from looking like an ongoing event.
         */
        const val NOISE_BAND_MARGIN = 0.22f // → settle band ≈ 0.40 m/s² (~2.2σ)

        /**
         * Consecutive in-band samples that close an active event. 6 @ 100 Hz ≈
         * 60 ms of quiet — long enough that the biphasic pulse has truly ended,
         * short enough not to swallow a fast-following second axle into one event.
         */
        const val QUIET_SAMPLES = 6

        /**
         * Consecutive in-band samples required to RE-ARM after an emit (debounce).
         * 8 @ 100 Hz ≈ 80 ms. Must be ≥ QUIET_SAMPLES; the post-bump rebound ring
         * has to fully die before we'll open a new event for a new feature.
         */
        const val REARM_QUIET_SAMPLES = 8

        /**
         * Hard cap on a single event's span. A real bump is ~180 ms; if |a_vert|
         * never settles for MAX_EVENT_MS we force-close (rough road / washboard).
         * RejectionFilter handles washboard properly downstream; this just bounds
         * the accumulator so it can't run forever.
         */
        const val MAX_EVENT_MS = 600

        /**
         * Oldest axle-pair gap we'll still match. `Δt = wheelbase / v`; at the
         * min detection speed (~10 km/h ≈ 2.78 m/s) and ~2.7 m wheelbase that's
         * ~970 ms, so ~1.2 s gives margin. Beyond this the "second axle" is far
         * more likely an unrelated feature, so we forget the first pulse.
         */
        const val MAX_AXLE_PAIR_GAP_MS = 1200L

        /**
         * Longitudinal-vs-lateral dominance ratio for the asymmetry validity gate
         * (audit detection #6). If the peak longitudinal (fore-aft brake/accel)
         * residual exceeds the peak lateral residual by more than this factor, the
         * horizontal energy is driver-caused fore-aft, not road one-sidedness, so we
         * mark asymmetry invalid. 1.5 keeps a genuinely lateral kick (lateral ≥
         * longitudinal, or only modestly below) valid while vetoing a clear
         * brake/launch transient. PROVISIONAL — tune on the labeled set.
         */
        const val LONG_DOMINANCE_RATIO = 1.5f

        /** A sample gap longer than this means the sensor stalled / we paused; treat
         *  the next sample as a fresh start rather than spanning the gap. ~300 ms =
         *  30 missed samples at 100 Hz, well beyond normal jitter. */
        const val GAP_MS = 300L
    }
}
