package com.overdrive.app.roadsense.detect

import kotlin.math.sqrt

/**
 * Converts raw `-iner` accelerometer samples into a **vertical residual**
 * `a_vert` — the signal the detector actually keys on.
 *
 * Why this exists (F-005, F-008): the head-unit IMU is mounted ~9.2° off true
 * vertical, so raw `aZ` is not "up" — it mixes gravity with cornering/braking
 * horizontal g. We can't use TYPE_GRAVITY/LINEAR_ACCELERATION (fusion sensors
 * built on the stub accel, F-004), so we estimate gravity ourselves:
 *
 *   ĝ  = low-pass(accel)                      (the gravity unit vector, device frame)
 *   a_vert = dot(accel, ĝ) − |g|              (pure vertical residual, tilt-corrected)
 *
 * `a_vert` ≈ 0 on flat road, swings ±several m/s² on a bump/pothole. The 9.2°
 * tilt is corrected automatically because ĝ is *measured*, not assumed to be Z.
 *
 * Production note (vs the probe's whole-drive mean): ĝ is a SLOW exponential
 * moving average so it tracks slow attitude changes (hills, remount) but does
 * NOT absorb fast bump transients. Time constant ≈ several seconds.
 *
 * Pure math, no Android deps — unit-testable. Not thread-safe; the owning
 * service feeds it from a single sensor thread.
 */
class GravityFrame(
    /**
     * Low-pass smoothing factor per sample for the gravity estimate.
     * alpha is the weight given to the NEW sample. At 100 Hz, alpha=0.02 gives
     * a time constant of ~0.5 s; we want gravity to settle in a second or two
     * but ignore ~150 ms bumps, so a small alpha is correct. Lower = slower =
     * more bump-rejection in the gravity track but slower attitude tracking.
     */
    private val alpha: Float = DEFAULT_ALPHA,
) {
    // Running gravity estimate in device frame (m/s²). Lazily seeded on first sample.
    private var gx = 0f
    private var gy = 0f
    private var gz = 0f
    private var seeded = false

    /** Samples folded in so far — used to report warm-up readiness. */
    private var count = 0L

    /**
     * Horizontal-residual magnitude (m/s²) of the most recent [update] sample —
     * the component of acceleration ORTHOGONAL to gravity. Gravity lives entirely
     * along ĝ, so this is gravity-free by construction. ~0 on flat cruise; spikes
     * on a body-roll/lateral kick (a one-sided pothole loads one wheel and rolls
     * the body) AND on longitudinal brake/accel. The longitudinal part is split out
     * into [longitudinalResidual] below so the asymmetry stage uses only the lateral
     * part — a stale-poll hard-brake-and-bump (F-011: pedal polls ~5 s old) can
     * otherwise slip past the rejection filter and inflate asymmetry (audit
     * detection #6). The asymmetry stage in [EventDetector] pairs [lateralResidual]
     * against the vertical peak.
     */
    var horizontalResidual: Float = 0f
        private set

    // Slow EMA of the gravity-free horizontal acceleration VECTOR (device frame).
    // Braking dive / launch squat push the body along a FIXED device-frame axis
    // (forward/back) for ~seconds, so this persistent average approximates the
    // longitudinal (travel) axis without needing GPS heading or gyro integration.
    // A fast one-sided bump is a brief transient that barely moves this average, so
    // its kick lands mostly in the lateral (orthogonal) remainder. Same time
    // constant family as the gravity track.
    private var hax = 0f
    private var hay = 0f
    private var haz = 0f

    /**
     * Longitudinal (brake/accel, fore-aft) component of the most recent sample's
     * horizontal residual (m/s², ≥0): the projection of the gravity-free horizontal
     * acceleration onto the slow longitudinal-axis estimate. Large during a
     * brake/launch transient. The asymmetry stage gates on this so a driver-caused
     * fore-aft jolt cannot read as road one-sidedness.
     */
    var longitudinalResidual: Float = 0f
        private set

    /**
     * Lateral (cross-track, body-roll) component of the most recent sample's
     * horizontal residual (m/s², ≥0): the part orthogonal to the longitudinal-axis
     * estimate. This is the intended one-sidedness signal for asymmetry.
     */
    var lateralResidual: Float = 0f
        private set

    /** Latest gravity magnitude (≈ 9.8 once seeded). Exposed for diagnostics. */
    val gravityMagnitude: Float
        get() = sqrt(gx * gx + gy * gy + gz * gz)

    /**
     * True once the gravity estimate has settled enough that `a_vert` is
     * meaningful. Before this, the detector should map/observe but treat
     * confidence as low (consistent with "map from drive one", D-015).
     */
    val isWarm: Boolean
        get() = count >= WARMUP_SAMPLES

    /**
     * Fold one accelerometer sample in and return the vertical residual.
     *
     * @return a_vert in m/s²: positive = pushed up (bump crest), negative =
     *         dropped (pothole / dip). Near 0 on flat road.
     */
    fun update(ax: Float, ay: Float, az: Float): Float {
        if (!seeded) {
            // Seed directly with the first sample so we don't spend the first
            // second ramping up from zero (which would emit a huge bogus a_vert).
            gx = ax; gy = ay; gz = az
            seeded = true
            count = 1
            return 0f
        }
        gx += alpha * (ax - gx)
        gy += alpha * (ay - gy)
        gz += alpha * (az - gz)
        count++

        val mag = sqrt(gx * gx + gy * gy + gz * gz)
        if (mag < 1e-3f) {
            horizontalResidual = 0f; longitudinalResidual = 0f; lateralResidual = 0f
            return 0f
        } // degenerate; avoid div-by-zero
        // Project the raw sample onto the gravity unit vector, subtract gravity
        // magnitude → the component of acceleration along "up", gravity removed.
        val dot = (ax * gx + ay * gy + az * gz) / mag
        // Horizontal residual = the part of accel orthogonal to ĝ. By Pythagoras
        // on the orthogonal decomposition: |a|² = a_along² + a_perp², where
        // a_along = dot (the full projection onto ĝ, INCLUDING gravity). So
        // a_perp = sqrt(max(0, |a|² − dot²)). This is gravity-free (gravity is
        // entirely along ĝ) and needs no extra state — it reuses `dot`/`mag`.
        val aSq = ax * ax + ay * ay + az * az
        val perpSq = aSq - dot * dot
        horizontalResidual = if (perpSq > 0f) sqrt(perpSq) else 0f

        // ---- Longitudinal / lateral split (audit detection #6) ----------------
        // Build the gravity-free horizontal acceleration VECTOR by subtracting the
        // along-gravity component from the raw sample: a_h = a − (a·ĝ)ĝ.
        val ux = gx / mag; val uy = gy / mag; val uz = gz / mag
        val hx = ax - dot * ux
        val hy = ay - dot * uy
        val hz = az - dot * uz
        // Slow EMA of that horizontal vector → the persistent longitudinal axis.
        hax += LONG_AXIS_ALPHA * (hx - hax)
        hay += LONG_AXIS_ALPHA * (hy - hay)
        haz += LONG_AXIS_ALPHA * (hz - haz)
        val laMag = sqrt(hax * hax + hay * hay + haz * haz)
        if (laMag < 1e-3f) {
            // No established fore-aft bias yet → treat the whole kick as lateral.
            longitudinalResidual = 0f
            lateralResidual = horizontalResidual
        } else {
            val lx = hax / laMag; val ly = hay / laMag; val lz = haz / laMag
            val longComp = hx * lx + hy * ly + hz * lz   // signed projection onto the axis
            longitudinalResidual = if (longComp < 0f) -longComp else longComp
            val latSq = horizontalResidual * horizontalResidual - longComp * longComp
            lateralResidual = if (latSq > 0f) sqrt(latSq) else 0f
        }
        return dot - mag
    }

    /** Current gravity unit vector (device frame). For diagnostics / direction work. */
    fun gravityUnit(): FloatArray {
        val mag = gravityMagnitude
        return if (mag < 1e-3f) floatArrayOf(0f, 0f, 1f)
        else floatArrayOf(gx / mag, gy / mag, gz / mag)
    }

    /** Tilt of the device's Z axis off true vertical, in degrees (diagnostics). */
    fun tiltDegrees(): Float {
        val mag = gravityMagnitude
        if (mag < 1e-3f) return 0f
        val cos = (gz / mag).coerceIn(-1f, 1f)
        return Math.toDegrees(kotlin.math.acos(cos).toDouble()).toFloat()
    }

    fun reset() {
        gx = 0f; gy = 0f; gz = 0f; seeded = false; count = 0; horizontalResidual = 0f
        hax = 0f; hay = 0f; haz = 0f
        longitudinalResidual = 0f; lateralResidual = 0f
    }

    companion object {
        /** ~0.5 s time constant at 100 Hz — settles fast, ignores ~150 ms bumps. */
        // ~0.004 ⇒ ~250-sample (~2.5 s at 100 Hz) time constant. The old 0.02
        // (~0.5 s) let a 2-3 s sustained brake/accel get absorbed into the gravity
        // estimate, leaking longitudinal g into a_vert during exactly the
        // braking/launch transients the rejection filter cares about (audit
        // detection #2). Slow enough to reject sustained maneuvers, still fast
        // enough to track hills/remount, and far slower than a ~150 ms bump.
        const val DEFAULT_ALPHA = 0.004f

        /** EMA weight for the longitudinal-axis estimate (the slow horizontal
         *  acceleration vector). ~0.01 ⇒ ~1 s time constant at 100 Hz: fast enough
         *  to settle onto the fore-aft brake/accel direction within a maneuver, slow
         *  enough that a ~180 ms bump transient barely perturbs the axis (so the
         *  bump's kick lands in the lateral remainder, not the longitudinal one). */
        const val LONG_AXIS_ALPHA = 0.01f

        /** ~2 s at 100 Hz before we call the gravity estimate "warm". */
        const val WARMUP_SAMPLES = 200L
    }
}
