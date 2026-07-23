package com.noop.analytics

import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/*
 * SleepRegularity.kt — sleep-TIMING regularity over a trailing window of nights.
 *
 * Byte-for-byte twin of StrandAnalytics/SleepRegularity.swift. Keep the thresholds, the
 * circular-statistics math, the score curve, and the sign-aware rounding identical to Swift
 * — the two clients must report the same score, SD, R and label for the same nights.
 *
 * PURELY ADDITIVE: introduces NO change to any Charge / Effort / Rest / sleep output. It is a
 * brand-new descriptive estimator the UI can surface later.
 *
 * WHAT IT MEASURES: how CONSISTENT the TIMING of sleep is from night to night — an independent,
 * well-validated axis of sleep health (irregular timing tracks with worse cardiometabolic and
 * mood outcomes even at fixed total duration). Distinct from SleepDebt (how much), Rest (how
 * restorative) and RhythmScreener (beat-to-beat regularity within a night).
 *
 * WHY CIRCULAR STATISTICS: a clock time lives on a 24 h CIRCLE. A midpoint of 23:50 and 00:10
 * are 20 min apart, not 23 h 40 m. A naive linear SD of "minutes past midnight" would report a
 * huge spurious variance for a steady near-midnight sleeper and rank them maximally irregular —
 * the opposite of the truth. So every timing statistic is computed with directional statistics:
 * each clock time is an angle, we average the unit vectors, and the spread is read from the mean
 * resultant length R (1 = identical every night; → 0 = spread around the circle). circular SD =
 * sqrt(−2·ln R), converted to minutes for a legible read.
 *
 * HONEST by construction: descriptive only (no clinical verdict); implausible-duration nights are
 * SKIPPED (not zero-filled); below minNights the read is withheld. Every SURFACED number is
 * rounded and the label is derived from the ROUNDED SD, so cross-platform libm ULP differences in
 * cos/ln/exp can never diverge the reported value or label between clients.
 */

/**
 * One night's sleep-timing inputs: day key plus the local minute-of-day of sleep onset and of
 * final wake (0…1439). A window that crosses midnight is handled by the circular math, so
 * [wakeMinOfDay] may be numerically smaller than [onsetMinOfDay]. Mirrors Swift `SleepTimingNight`.
 */
data class SleepTimingNight(
    /** "yyyy-MM-dd" day key for the night. */
    val day: String,
    /** Local minute-of-day of sleep onset (0…1439). */
    val onsetMinOfDay: Int,
    /** Local minute-of-day of final wake (0…1439). */
    val wakeMinOfDay: Int,
) {
    /** Sleep duration (minutes) as the forward arc onset → wake on the 24 h circle. */
    val durationMin: Double
        get() = (((wakeMinOfDay - onsetMinOfDay) % 1440 + 1440) % 1440).toDouble()

    /** Sleep midpoint as a minute-of-day (0…1440) = onset + duration/2 wrapped onto the circle. */
    val midpointMinOfDay: Double
        get() {
            val mid = (onsetMinOfDay.toDouble() + durationMin / 2.0) % 1440.0
            return if (mid < 0) mid + 1440.0 else mid
        }
}

/**
 * Neutral, non-clinical timing-regularity category. Mirrors Swift `SleepRegularityLabel`.
 */
enum class SleepRegularityLabel(val raw: String) {
    VERY_REGULAR("veryRegular"),
    REGULAR("regular"),
    VARIABLE("variable"),
    IRREGULAR("irregular"),
    UNREADABLE("unreadable"),
}

/**
 * Result of a timing-regularity assessment over the trailing window. Every surfaced number is
 * pre-rounded for cross-platform parity. Optional fields are null when unreadable. Mirrors Swift
 * `SleepRegularityResult`.
 */
data class SleepRegularityResult(
    /** 0–100 regularity score (100 = perfectly consistent timing). null when unreadable. */
    val score: Int?,
    /** Neutral descriptive category. */
    val label: SleepRegularityLabel,
    /** Read certainty from the usable-night count. */
    val confidence: ScoreConfidence,
    /** Circular SD of the sleep MIDPOINT (minutes, 1 dp) — the headline "±X min" spread. */
    val midpointSDMinutes: Double?,
    /** Circular SD of sleep ONSET (minutes, 1 dp) — bedtime consistency. */
    val onsetSDMinutes: Double?,
    /** Circular SD of final WAKE (minutes, 1 dp) — wake consistency. */
    val wakeSDMinutes: Double?,
    /** Circular MEAN sleep midpoint as a minute-of-day (0…1439). */
    val meanMidpointMinOfDay: Int?,
    /** Mean resultant length R of the midpoint (0…1, 3 dp): 1 = identical timing every night. */
    val resultantLength: Double?,
    /** Number of usable nights that fed the read. */
    val nightCount: Int,
) {
    /** True when the read is a real assessment rather than a withheld one. */
    val isReadable: Boolean get() = label != SleepRegularityLabel.UNREADABLE

    companion object {
        /** The withheld read: too few usable nights to say anything honestly. */
        fun unreadable(nightCount: Int) = SleepRegularityResult(
            score = null, label = SleepRegularityLabel.UNREADABLE,
            confidence = ScoreConfidence.CALIBRATING,
            midpointSDMinutes = null, onsetSDMinutes = null, wakeSDMinutes = null,
            meanMidpointMinOfDay = null, resultantLength = null, nightCount = nightCount,
        )
    }
}

object SleepRegularity {

    /** Trailing window of nights to assess — a fortnight, matching SleepDebt. */
    const val DEFAULT_WINDOW_NIGHTS: Int = 14

    /** Minimum usable nights before a read is attempted at all. */
    const val MIN_NIGHTS: Int = 3

    /** Usable-night count at/above which the read is SOLID — a full week of timings. */
    const val SOLID_NIGHTS: Int = 7

    /** Plausible sleep-duration band (minutes); a night outside is a nap/glitch and is SKIPPED. */
    const val MIN_DURATION_MIN: Double = 180.0   // 3 h
    const val MAX_DURATION_MIN: Double = 960.0   // 16 h

    /** Score scale (minutes): score = 100·exp(−midpointSD / SCORE_SCALE_MIN). */
    const val SCORE_SCALE_MIN: Double = 135.0

    /** Midpoint circular-SD band edges (minutes) for the descriptive label. */
    const val TAU_VERY_REGULAR_MIN: Double = 30.0
    const val TAU_REGULAR_MIN: Double = 60.0
    const val TAU_VARIABLE_MIN: Double = 120.0

    /** Floor on R before ln, so a fully-dispersed set yields a finite, capped SD. */
    const val R_FLOOR: Double = 1e-9

    /**
     * Assess sleep-timing regularity over the most-recent usable nights.
     *
     * @param nights per-night timings in CHRONOLOGICAL order (oldest → newest); implausible-duration
     *   nights are skipped.
     * @param window how many of the most-recent USABLE nights to include (default 14, ≥ 1).
     */
    /**
     * The nights an assessment actually uses: implausible-duration nights dropped, chronological
     * order preserved, capped to the most-recent [window]. Exposed so a dial can plot exactly the
     * nights the score was built from (one source of truth for the windowing).
     */
    fun windowedNights(
        nights: List<SleepTimingNight>,
        window: Int = DEFAULT_WINDOW_NIGHTS,
    ): List<SleepTimingNight> {
        val cap = window.coerceAtLeast(1)
        val usable = nights.filter {
            val d = it.durationMin
            d >= MIN_DURATION_MIN && d <= MAX_DURATION_MIN
        }
        return usable.takeLast(cap)
    }

    fun assess(
        nights: List<SleepTimingNight>,
        window: Int = DEFAULT_WINDOW_NIGHTS,
    ): SleepRegularityResult {
        val windowed = windowedNights(nights, window)

        if (windowed.size < MIN_NIGHTS) {
            return SleepRegularityResult.unreadable(windowed.size)
        }

        val midStats = circularStats(windowed.map { it.midpointMinOfDay })
        val onsetStats = circularStats(windowed.map { it.onsetMinOfDay.toDouble() })
        val wakeStats = circularStats(windowed.map { it.wakeMinOfDay.toDouble() })

        // Round the headline SD FIRST, then derive score and label from that same rounded value.
        val midSD = round1(midStats.sdMin)
        val score = round0(100.0 * exp(-midSD / SCORE_SCALE_MIN))
        val label = classify(midSD)

        val meanMid = midStats.meanMinOfDay.roundToInt() % 1440

        return SleepRegularityResult(
            score = score,
            label = label,
            confidence = confidence(windowed.size),
            midpointSDMinutes = midSD,
            onsetSDMinutes = round1(onsetStats.sdMin),
            wakeSDMinutes = round1(wakeStats.sdMin),
            meanMidpointMinOfDay = meanMid,
            resultantLength = round3(midStats.r),
            nightCount = windowed.size,
        )
    }

    /** Circular statistics over clock times expressed as minutes-of-day. Mirrors Swift. */
    data class CircularStats(val sdMin: Double, val r: Double, val meanMinOfDay: Double)

    internal fun circularStats(minutes: List<Double>): CircularStats {
        val n = minutes.size.toDouble()
        if (n <= 0.0) return CircularStats(0.0, 1.0, 0.0)
        val twoPi = 2.0 * PI
        var sumCos = 0.0
        var sumSin = 0.0
        for (m in minutes) {
            val ang = (m / 1440.0) * twoPi
            sumCos += cos(ang)
            sumSin += sin(ang)
        }
        val c = sumCos / n
        val s = sumSin / n
        // Clamp R into (0, 1]: ≤ 1 keeps the sqrt real; ≥ R_FLOOR keeps ln finite.
        val r = sqrt(c * c + s * s).coerceIn(R_FLOOR, 1.0)
        val sdRad = sqrt(-2.0 * ln(r))
        val sdMin = sdRad * (1440.0 / twoPi)
        var meanAng = atan2(s, c)
        if (meanAng < 0) meanAng += twoPi
        val meanMin = (meanAng / twoPi) * 1440.0
        return CircularStats(sdMin, r, meanMin)
    }

    /** Map the (rounded) midpoint circular SD to a neutral descriptive label. */
    internal fun classify(midpointSD: Double): SleepRegularityLabel = when {
        midpointSD <= TAU_VERY_REGULAR_MIN -> SleepRegularityLabel.VERY_REGULAR
        midpointSD <= TAU_REGULAR_MIN -> SleepRegularityLabel.REGULAR
        midpointSD <= TAU_VARIABLE_MIN -> SleepRegularityLabel.VARIABLE
        else -> SleepRegularityLabel.IRREGULAR
    }

    /** Read certainty from the usable-night count, mirroring ScoreConfidence's tiers. */
    internal fun confidence(nights: Int): ScoreConfidence = when {
        nights < MIN_NIGHTS -> ScoreConfidence.CALIBRATING
        nights >= SOLID_NIGHTS -> ScoreConfidence.SOLID
        else -> ScoreConfidence.BUILDING
    }

    // Rounding — sign-aware, half-away-from-zero, matching Swift's `Double.rounded()` and
    // SleepDebt.round1 (Kotlin's roundToInt rounds half toward +∞, which would diverge on a
    // negative half-tie; SDs and scores here are non-negative, but the helper stays sign-aware
    // for exact parity with Swift).
    internal fun round1(v: Double): Double = roundAway(v * 10.0) / 10.0
    internal fun round3(v: Double): Double = roundAway(v * 1000.0) / 1000.0
    internal fun round0(v: Double): Int = roundAway(v).toInt()

    private fun roundAway(scaled: Double): Double =
        if (scaled < 0.0) ceil(scaled - 0.5) else floor(scaled + 0.5)
}
