package com.noop.analytics

import com.noop.data.HrSample
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.roundToLong

/*
 * StrainScorer.kt — cardiovascular load (NOOP "Effort") on a 0–100 logarithmic scale.
 *
 * Faithful Kotlin port of StrandAnalytics/StrainScorer.swift (verified on macOS),
 * itself ported from server/ingest/app/analysis/strain.py. INDEPENDENT implementation
 * of published exercise-physiology methods (WHOOP-*like*, not a reproduction of the
 * proprietary algorithm; not medical advice).
 *
 * SCALE: the internal metric key stays `strain`, but the published axis is now 0–100
 * ("Effort"). This is a pure RESCALE — `maxStrain` went 21.0 → 100.0 while the
 * denominator D = 7201 is UNCHANGED, so the log curve and its saturation point
 * (TRIMP 7200 ≈ max) are preserved: a max-Effort day stays exactly as rare as a 21.0
 * day was. trimpToStrain now returns 0–100.
 *
 * Pipeline:
 *   1. Heart-Rate Reserve (Karvonen): HRR = HRmax − RHR.
 *   2. Per-sample intensity as %HRR = (HR − RHR) / HRR × 100, clamped 0..100.
 *   3. TRIMP accumulated over the window:
 *        a. Edwards 5-zone summation (default): sample contributes its zone weight
 *           (1..5 at 50/60/70/80/90 %HRR cut-offs) × duration.
 *        b. Banister exponential: sample contributes duration × x × 0.64 × e^(b·x).
 *   4. Logarithmic compression onto [0, 100]:
 *        effort = 100 × ln(TRIMP + 1) / ln(D),  D = STRAIN_DENOMINATOR.
 *
 * References: Karvonen 1957 (%HRR); Edwards 1993 (5-zone TRIMP); Banister 1991
 * (exponential TRIMP, b = 1.92 men / 1.67 women); Tanaka 2001 (HRmax = 208 − 0.7×age).
 *
 * Operates on the Room [HrSample] (ts:Long unix seconds, bpm:Int). The HRR-based
 * zone math here is INDEPENDENT of the %HRmax display zones in [HrZones]; this port
 * uses [HrZones] only where the Swift used HRZones (none in this file — strain has
 * its own Edwards %HRR thresholds).
 */
object StrainScorer {

    // ---- Constants (strain.py) ----

    /** Minimum HR readings before computing strain on a DENSE stream (≈10 min at 1 Hz). */
    const val minReadings: Int = 600
    /**
     * Sparse-stream acceptance (#482/#480): a low-cadence strap — the WHOOP 5/MG sends live
     * standard HR only ~every 30 s — would need ~5 h of continuous wear to reach [minReadings], so
     * Effort sat un-scored (null → a stale prior-day value on the gauge) for most of the day. Also
     * accept once the HR series SPANS at least [minSpanSeconds] of wall-clock with a small sample
     * floor. This never fabricates load: TRIMP still integrates honestly, so a genuine low-HR day
     * scores 0 either way — it just lets the live gauge reflect TODAY. A dense 1 Hz stream is
     * unaffected (it clears [minReadings] first).
     */
    const val minSparseReadings: Int = 20
    /** Wall-clock coverage (seconds) qualifying a sparse stream. 600 s = 10 min, matching the dense
     *  gate's ≈10 min of 600 × 1 Hz samples, so both cadences trust the number at the same age. */
    const val minSpanSeconds: Int = 600

    /** Top of the Effort scale (was 21.0 — rescaled to 0–100 for "Effort"). */
    const val maxStrain: Double = 100.0

    /**
     * Logarithmic-map denominator D. Chosen so the Edwards daily ceiling
     * (top zone weight 5 sustained 24 h = 7200) maps to exactly maxStrain:
     * D = 7200 + 1 = 7201 makes ln(7201)/ln(7201) = 1, so the curve shape and
     * its saturation point are independent of maxStrain (the 21→100 rescale is a
     * pure linear scaling of the whole curve).
     */
    const val strainDenominator: Double = 7201.0
    val lnStrainDenominator: Double get() = ln(strainDenominator)

    /** Fallback per-sample duration (minutes) — 1 s at 1 Hz. */
    const val fallbackSampleMin: Double = 1.0 / 60.0

    const val defaultAge: Int = 30
    const val defaultRestingHR: Double = 60.0

    /** Minimum HR samples before the observed high-percentile HRmax is trusted. */
    const val hrmaxMinSamples: Int = 600

    /** Upper percentile for the observed-HRmax estimate. */
    const val hrmaxPercentile: Double = 99.5

    /** Banister coefficients. */
    const val banisterScale: Double = 0.64
    const val banisterBMen: Double = 1.92
    const val banisterBWomen: Double = 1.67

    /** Edwards zone cut-offs as (%HRR threshold, weight), highest-first. */
    val edwardsZones: List<Pair<Double, Int>> = listOf(
        90.0 to 5, 80.0 to 4, 70.0 to 3, 60.0 to 2, 50.0 to 1,
    )

    /** TRIMP accumulation method. */
    enum class Method { EDWARDS, BANISTER }

    /** Strain calibration / fit errors. Mirrors Swift `StrainError`. */
    enum class StrainError { TOO_FEW_PAIRS, DEGENERATE }

    /** Thrown by [fitStrainDenominator] when the fit is impossible. */
    class StrainException(val error: StrainError) : Exception("Strain fit failed: $error")

    // ---- HRmax helpers ----

    /** Tanaka (2001): HRmax = 208 − 0.7 × age (gender-independent). */
    fun tanakaHRmax(age: Double): Double = 208.0 - 0.7 * age

    /** Classic 220 − age. Last-resort fallback only. */
    fun defaultMaxHR(age: Int = defaultAge): Int = 220 - age

    /** Linear-interpolated percentile of an already-sorted sequence (numpy-style). */
    fun percentile(sortedValues: List<Double>, pct: Double): Double {
        val n = sortedValues.size
        if (n == 0) return 0.0
        if (n == 1) return sortedValues[0]
        val position = (pct / 100.0) * (n - 1).toDouble()
        val lower = position.toInt()
        val upper = minOf(lower + 1, n - 1)
        val frac = position - lower.toDouble()
        return sortedValues[lower] + frac * (sortedValues[upper] - sortedValues[lower])
    }

    /**
     * Estimate a personalized HRmax from a trailing HR series.
     * Returns (hrmax bpm, source) where source ∈ {"observed", "tanaka", "unknown"}.
     */
    fun estimateHRmax(hrHistory: List<Double>, age: Double?): Pair<Double, String> {
        val n = hrHistory.size
        val tanaka = age?.let { tanakaHRmax(it) }

        if (n >= hrmaxMinSamples) {
            val observed = percentile(hrHistory.sorted(), hrmaxPercentile)
            if (tanaka == null) return observed to "observed"
            return if (observed >= tanaka) observed to "observed" else tanaka to "tanaka"
        }
        if (tanaka != null) return tanaka to "tanaka"
        return 0.0 to "unknown"
    }

    // ---- Karvonen %HRR and Edwards zone weight ----

    /** Karvonen %HRR, clamped [0, 100]. */
    fun pctHRR(bpm: Double, restingHR: Double, hrReserve: Double): Double {
        val pct = (bpm - restingHR) / hrReserve * 100.0
        if (pct < 0) return 0.0
        if (pct > 100) return 100.0
        return pct
    }

    /**
     * Edwards 5-zone weight (0–5) from %HRR (unclamped; extremes agree with
     * the clamped path at both ends).
     */
    fun zoneWeight(bpm: Double, restingHR: Double, hrReserve: Double): Int {
        val pct = (bpm - restingHR) / hrReserve * 100.0
        for ((threshold, weight) in edwardsZones) {
            if (pct >= threshold) return weight
        }
        return 0
    }

    // ---- TRIMP accumulation ----

    /**
     * Infer per-sample duration (minutes) from the first two timestamps. Falls
     * back to 1 s when fewer than two samples or coincident timestamps.
     *
     * ONLY valid for a UNIFORMLY sampled stream. Kept for the testable surface, but the TRIMP
     * integrators no longer use it — see [sampleDurationsMinutes].
     */
    fun sampleDurationMinutes(hr: List<HrSample>): Double {
        if (hr.size < 2) return fallbackSampleMin
        val deltaS = abs((hr[1].ts - hr[0].ts).toDouble())
        return if (deltaS > 0) deltaS / 60.0 else fallbackSampleMin
    }

    /**
     * Longest gap (seconds) a single sample may be credited with. A WHOOP 4.0 streams ~1 Hz and a
     * 5/MG drops to ~30 s at rest, so 120 s covers every legitimate cadence while stopping a real
     * GAP — strap removed, BLE dropout, an overnight sparse stretch — from being integrated as if
     * the wearer held that heart rate continuously through it.
     *
     * Swift twin: `StrainScorer.maxSampleGapSeconds`.
     */
    const val maxSampleGapSeconds: Double = 120.0

    /**
     * Per-sample durations in minutes, from each sample's ACTUAL gap to the next.
     *
     * Fixes "strain starts the day unrealistically high": the integrators previously derived ONE
     * duration from `hr[1].ts - hr[0].ts` and multiplied every sample by it, so a single
     * unrepresentative first gap rescaled the whole day. Early morning — when the stream is sparse
     * and irregular — that inferred a huge per-sample duration and credited every later reading
     * with it, inflating TRIMP and therefore strain; as the stream densified the number "settled".
     *
     * A uniformly sampled stream yields the same value for every element, so a healthy 1 Hz day
     * scores identically to before. The last sample has no successor and inherits the MEDIAN of the
     * observed gaps (one outlier can't skew it).
     *
     * Byte-identical twin of Swift `StrainScorer.sampleDurationsMinutes`.
     */
    fun sampleDurationsMinutes(hr: List<HrSample>): List<Double> {
        if (hr.size < 2) return List(hr.size) { fallbackSampleMin }
        val gaps = ArrayList<Double>(hr.size - 1)
        for (i in 0 until hr.size - 1) {
            val raw = abs((hr[i + 1].ts - hr[i].ts).toDouble())
            val capped = if (raw <= 0) fallbackSampleMin * 60.0 else minOf(raw, maxSampleGapSeconds)
            gaps.add(capped / 60.0)
        }
        val sorted = gaps.sorted()
        val median = if (sorted.isEmpty()) fallbackSampleMin else sorted[sorted.size / 2]
        return gaps + median
    }

    fun edwardsTRIMP(
        hr: List<HrSample>,
        restingHR: Double,
        hrReserve: Double,
        sampleDurationMin: Double,
    ): Double {
        var weighted = 0
        for (s in hr) {
            weighted += zoneWeight(s.bpm.toDouble(), restingHR, hrReserve)
        }
        return weighted.toDouble() * sampleDurationMin
    }

    /**
     * Edwards TRIMP integrated with PER-SAMPLE durations. Byte-identical twin of the Swift
     * `edwardsTRIMP(_:restingHR:hrReserve:durations:)` overload.
     */
    fun edwardsTRIMP(
        hr: List<HrSample>,
        restingHR: Double,
        hrReserve: Double,
        durations: List<Double>,
    ): Double {
        var acc = 0.0
        for ((i, s) in hr.withIndex()) {
            if (i >= durations.size) break
            val w = zoneWeight(s.bpm.toDouble(), restingHR, hrReserve)
            if (w > 0) acc += w.toDouble() * durations[i]
        }
        return acc
    }

    fun banisterTRIMP(
        hr: List<HrSample>,
        restingHR: Double,
        hrReserve: Double,
        sampleDurationMin: Double,
        b: Double,
    ): Double {
        var acc = 0.0
        for (s in hr) {
            val x = pctHRR(s.bpm.toDouble(), restingHR, hrReserve) / 100.0
            if (x > 0) acc += sampleDurationMin * x * banisterScale * exp(b * x)
        }
        return acc
    }

    /**
     * Banister TRIMP with PER-SAMPLE durations. Byte-identical twin of the Swift
     * `banisterTRIMP(_:restingHR:hrReserve:durations:b:)` overload.
     */
    fun banisterTRIMP(
        hr: List<HrSample>,
        restingHR: Double,
        hrReserve: Double,
        durations: List<Double>,
        b: Double,
    ): Double {
        var acc = 0.0
        for ((i, s) in hr.withIndex()) {
            if (i >= durations.size) break
            val x = pctHRR(s.bpm.toDouble(), restingHR, hrReserve) / 100.0
            if (x > 0) acc += durations[i] * x * banisterScale * exp(b * x)
        }
        return acc
    }

    // ---- Logarithmic map ----

    /**
     * Map accumulated TRIMP onto [0, 100] via 100 × ln(TRIMP+1) / ln(D), 2 dp.
     * TRIMP ≤ 0 → 0.
     */
    fun trimpToStrain(trimp: Double, denominator: Double = strainDenominator): Double {
        if (trimp <= 0) return 0.0
        val value = maxStrain * ln(trimp + 1.0) / ln(denominator)
        return (value * 100).roundToLong() / 100.0
    }

    // ---- Denominator calibration ----

    /**
     * Calibrate D from (TRIMP, reference_strain) pairs via the through-origin
     * least-squares line: ln(D) = maxStrain × Σ(x²) / Σ(xy), x = ln(TRIMP+1).
     * Reference strains are on the maxStrain (0–100) scale. Throws [StrainException]
     * when fewer than 2 usable pairs (TRIMP>0, strain>0) or degenerate.
     */
    fun fitStrainDenominator(pairs: List<Pair<Double, Double>>): Double {
        val usable = pairs.filter { it.first > 0 && it.second > 0 }
        if (usable.size < 2) throw StrainException(StrainError.TOO_FEW_PAIRS)
        var sumXX = 0.0
        var sumXY = 0.0
        for ((trimp, strain) in usable) {
            val x = ln(trimp + 1.0)
            sumXX += x * x
            sumXY += x * strain
        }
        if (!(sumXY > 0 && sumXX > 0)) throw StrainException(StrainError.DEGENERATE)
        return exp(maxStrain * sumXX / sumXY)
    }

    // ---- Public API ----

    /**
     * Cardiovascular Effort (0–100) from an HR series. APPROXIMATE.
     *
     * Returns null when there isn't yet enough data to trust the number — fewer than [minReadings]
     * samples AND less than [minSpanSeconds] of HR coverage (the sparse-strap path, #482) — or when
     * maxHR ≤ restingHR (invalid HRR).
     *
     * @param hr time-ordered [HrSample] list.
     * @param maxHR HRmax (bpm). Defaults to 220 − defaultAge when null.
     * @param restingHR resting HR (bpm) for the HRR denominator (default 60).
     * @param method [Method.EDWARDS] (default) or [Method.BANISTER].
     * @param sex "male"/"female" — selects the Banister coefficient (ignored by Edwards).
     * @param denominator log-map D (default [strainDenominator]).
     */
    fun strain(
        hr: List<HrSample>,
        maxHR: Double? = null,
        restingHR: Double = defaultRestingHR,
        method: Method = Method.EDWARDS,
        sex: String = "male",
        denominator: Double = strainDenominator,
    ): Double? {
        val effMax = maxHR ?: defaultMaxHR().toDouble()
        // Enough data to trust the score: a dense stream (≥ minReadings) OR a sparse-but-sustained
        // one spanning ≥ minSpanSeconds with a sample floor (#482 — the 5/MG's ~30 s HR cadence).
        val enoughData = when {
            hr.size >= minReadings -> true
            hr.size >= minSparseReadings -> {
                val tss = hr.map { it.ts }
                (tss.maxOrNull() ?: 0L) - (tss.minOrNull() ?: 0L) >= minSpanSeconds
            }
            else -> false
        }
        if (!enoughData || effMax <= restingHR) return null

        // Per-sample durations, NOT one duration inferred from the first two timestamps — see
        // sampleDurationsMinutes for why that inflated early-day strain.
        val durations = sampleDurationsMinutes(hr)
        val hrReserve = effMax - restingHR

        val trimp: Double = when (method) {
            Method.BANISTER -> {
                val b = if (sex.lowercase().startsWith("f")) banisterBWomen else banisterBMen
                banisterTRIMP(hr, restingHR, hrReserve, durations, b)
            }
            Method.EDWARDS -> {
                edwardsTRIMP(hr, restingHR, hrReserve, durations)
            }
        }
        return trimpToStrain(trimp, denominator)
    }
}
