package com.noop.analytics

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt

/*
 * SleepStageInsights.kt — composition + neutral, actionable sleep-stage insights.
 *
 * Byte-for-byte twin of StrandAnalytics/SleepStageInsights.swift. Keep the thresholds, the median
 * baseline, the both-gates "notable" rule, and the ranking identical to Swift — both clients must
 * produce the same insights for the same nights.
 *
 * PURELY ADDITIVE, pure/DB-free: takes SleepStageTotals.Minutes (tonight) + a trailing baseline and
 * returns framework-free values. Colours + copy belong to the UI. HONEST: comparative insights are
 * withheld until [MIN_BASELINE_NIGHTS] nights exist; a stage reads notable only when it clears BOTH a
 * relative and an absolute gate; baselines use the MEDIAN; nothing here is clinical.
 */
object SleepStageInsights {

    const val MIN_BASELINE_NIGHTS: Int = 5
    const val NOTABLE_RATIO: Double = 0.20
    const val NOTABLE_MINUTES: Double = 15.0
    const val RESTORATIVE_STRONG_SHARE: Double = 0.45
    const val RESTORATIVE_LOW_SHARE: Double = 0.28
    const val EFFICIENT_THRESHOLD: Double = 0.90
    const val FRAGMENTED_THRESHOLD: Double = 0.82
    const val MAX_INSIGHTS: Int = 3

    data class Composition(
        val awakeMin: Double, val lightMin: Double, val deepMin: Double, val remMin: Double,
        val asleepMin: Double, val inBedMin: Double,
        val awakeFrac: Double, val lightFrac: Double, val deepFrac: Double, val remFrac: Double,
        val restorativeShare: Double, val efficiency: Double,
    )

    enum class Kind(val raw: String) {
        BUILDING_BASELINE("buildingBaseline"),
        BALANCED_NIGHT("balancedNight"),
        EFFICIENT_NIGHT("efficientNight"),
        FRAGMENTED("fragmented"),
        RESTORATIVE_STRONG("restorativeStrong"),
        RESTORATIVE_LIGHT("restorativeLight"),
        DEEP_ABOVE_USUAL("deepAboveUsual"),
        DEEP_BELOW_USUAL("deepBelowUsual"),
        REM_ABOVE_USUAL("remAboveUsual"),
        REM_BELOW_USUAL("remBelowUsual"),
    }

    enum class Tone(val raw: String) { POSITIVE("positive"), CAUTION("caution"), NEUTRAL("neutral") }

    data class Insight(val kind: Kind, val tone: Tone, val deltaMin: Int? = null)

    data class Report(val composition: Composition, val insights: List<Insight>, val hasBaseline: Boolean)

    fun composition(m: SleepStageTotals.Minutes): Composition {
        val inBed = m.inBed
        val asleep = m.asleep
        fun frac(x: Double) = if (inBed > 0) round3(x / inBed) else 0.0
        return Composition(
            awakeMin = round1(m.awake), lightMin = round1(m.light), deepMin = round1(m.deep), remMin = round1(m.rem),
            asleepMin = round1(asleep), inBedMin = round1(inBed),
            awakeFrac = frac(m.awake), lightFrac = frac(m.light), deepFrac = frac(m.deep), remFrac = frac(m.rem),
            restorativeShare = if (asleep > 0) round3((m.deep + m.rem) / asleep) else 0.0,
            efficiency = if (inBed > 0) round3(asleep / inBed) else 0.0,
        )
    }

    fun analyze(tonight: SleepStageTotals.Minutes, baseline: List<SleepStageTotals.Minutes>): Report {
        val comp = composition(tonight)
        val insights = ArrayList<Insight>()

        if (tonight.inBed > 0) {
            if (comp.efficiency >= EFFICIENT_THRESHOLD) {
                insights.add(Insight(Kind.EFFICIENT_NIGHT, Tone.POSITIVE))
            } else if (comp.efficiency < FRAGMENTED_THRESHOLD) {
                insights.add(Insight(Kind.FRAGMENTED, Tone.CAUTION))
            }
            if (comp.restorativeShare >= RESTORATIVE_STRONG_SHARE) {
                insights.add(Insight(Kind.RESTORATIVE_STRONG, Tone.POSITIVE))
            } else if (comp.asleepMin > 0 && comp.restorativeShare < RESTORATIVE_LOW_SHARE) {
                insights.add(Insight(Kind.RESTORATIVE_LIGHT, Tone.CAUTION))
            }
        }

        val usable = baseline.filter { it.inBed > 0 }
        val hasBaseline = usable.size >= MIN_BASELINE_NIGHTS
        if (hasBaseline) {
            val deepBase = median(usable.map { it.deep })
            val remBase = median(usable.map { it.rem })
            notableDelta(tonight.deep, deepBase)?.let { d ->
                insights.add(Insight(if (d > 0) Kind.DEEP_ABOVE_USUAL else Kind.DEEP_BELOW_USUAL,
                    if (d > 0) Tone.POSITIVE else Tone.CAUTION, d.roundToInt()))
            }
            notableDelta(tonight.rem, remBase)?.let { d ->
                insights.add(Insight(if (d > 0) Kind.REM_ABOVE_USUAL else Kind.REM_BELOW_USUAL,
                    if (d > 0) Tone.POSITIVE else Tone.CAUTION, d.roundToInt()))
            }
        }

        insights.sortWith(Comparator { a, b ->
            if (toneRank(a.tone) != toneRank(b.tone)) toneRank(a.tone) - toneRank(b.tone)
            else abs(b.deltaMin ?: 0) - abs(a.deltaMin ?: 0)
        })
        val capped = ArrayList(insights.take(MAX_INSIGHTS))

        if (capped.isEmpty()) {
            capped.add(
                if (tonight.inBed <= 0 || !hasBaseline) Insight(Kind.BUILDING_BASELINE, Tone.NEUTRAL)
                else Insight(Kind.BALANCED_NIGHT, Tone.POSITIVE),
            )
        } else if (!hasBaseline && tonight.inBed > 0 && capped.size < MAX_INSIGHTS) {
            capped.add(Insight(Kind.BUILDING_BASELINE, Tone.NEUTRAL))
        }

        return Report(comp, capped, hasBaseline)
    }

    internal fun notableDelta(value: Double, base: Double): Double? {
        if (base <= 0) return null
        val delta = value - base
        if (abs(delta) < NOTABLE_MINUTES || abs(delta) / base < NOTABLE_RATIO) return null
        return delta
    }

    internal fun median(xs: List<Double>): Double {
        if (xs.isEmpty()) return 0.0
        val s = xs.sorted()
        val n = s.size
        return if (n % 2 == 1) s[n / 2] else (s[n / 2 - 1] + s[n / 2]) / 2.0
    }

    private fun toneRank(t: Tone): Int = if (t == Tone.CAUTION) 0 else if (t == Tone.POSITIVE) 1 else 2

    internal fun round1(v: Double): Double = roundAway(v * 10.0) / 10.0
    internal fun round3(v: Double): Double = roundAway(v * 1000.0) / 1000.0
    private fun roundAway(x: Double): Double = if (x < 0.0) ceil(x - 0.5) else floor(x + 0.5)
}
