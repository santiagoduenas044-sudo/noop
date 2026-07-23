package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Kotlin parity for StrandAnalytics/SleepStageInsightsTests.swift. */
class SleepStageInsightsTest {

    private fun m(awake: Double, light: Double, deep: Double, rem: Double) =
        SleepStageTotals.Minutes(awake = awake, light = light, deep = deep, rem = rem)

    private fun kinds(r: SleepStageInsights.Report) = r.insights.map { it.kind }

    private fun steadyBaseline(deep: Double, rem: Double, count: Int = 6) =
        (0 until count).map { m(25.0, 245.0, deep, rem) }

    @Test
    fun compositionFractionsAndShares() {
        val c = SleepStageInsights.composition(m(20.0, 240.0, 110.0, 110.0))
        assertEquals(480.0, c.inBedMin, 1e-9)
        assertEquals(0.958, c.efficiency, 1e-3)
        assertEquals(0.478, c.restorativeShare, 1e-3)
        assertEquals(1.0, c.awakeFrac + c.lightFrac + c.deepFrac + c.remFrac, 2e-3)
    }

    @Test
    fun efficientAndRestorativeStrong() {
        val r = SleepStageInsights.analyze(m(20.0, 240.0, 110.0, 110.0), emptyList())
        assertTrue(kinds(r).contains(SleepStageInsights.Kind.EFFICIENT_NIGHT))
        assertTrue(kinds(r).contains(SleepStageInsights.Kind.RESTORATIVE_STRONG))
    }

    @Test
    fun fragmentedNight() {
        val r = SleepStageInsights.analyze(m(100.0, 240.0, 80.0, 60.0), emptyList())
        assertTrue(kinds(r).contains(SleepStageInsights.Kind.FRAGMENTED))
        assertEquals(SleepStageInsights.Tone.CAUTION, r.insights.first().tone)
    }

    @Test
    fun deepBelowUsualEmitsNegativeDelta() {
        val r = SleepStageInsights.analyze(m(25.0, 300.0, 60.0, 95.0), steadyBaseline(100.0, 95.0))
        val deep = r.insights.firstOrNull { it.kind == SleepStageInsights.Kind.DEEP_BELOW_USUAL }
        assertNotNull(deep)
        assertEquals(SleepStageInsights.Tone.CAUTION, deep!!.tone)
        assertEquals(-40, deep.deltaMin)
        assertTrue(r.hasBaseline)
    }

    @Test
    fun smallDeltaIsNotNotable() {
        val r = SleepStageInsights.analyze(m(25.0, 245.0, 108.0, 95.0), steadyBaseline(100.0, 95.0))
        assertFalse(kinds(r).contains(SleepStageInsights.Kind.DEEP_ABOVE_USUAL))
        assertFalse(kinds(r).contains(SleepStageInsights.Kind.DEEP_BELOW_USUAL))
    }

    @Test
    fun withheldUntilBaseline() {
        val r = SleepStageInsights.analyze(m(25.0, 245.0, 60.0, 95.0), steadyBaseline(100.0, 95.0, count = 3))
        assertFalse(r.hasBaseline)
        assertFalse(kinds(r).contains(SleepStageInsights.Kind.DEEP_BELOW_USUAL))
        assertTrue(kinds(r).contains(SleepStageInsights.Kind.BUILDING_BASELINE))
    }

    @Test
    fun balancedNightWhenNothingStandsOut() {
        val r = SleepStageInsights.analyze(m(60.0, 250.0, 95.0, 85.0), steadyBaseline(95.0, 85.0))
        assertEquals(listOf(SleepStageInsights.Kind.BALANCED_NIGHT), kinds(r))
    }

    @Test
    fun insightsCappedAndCautionFirst() {
        val r = SleepStageInsights.analyze(m(120.0, 250.0, 50.0, 40.0), steadyBaseline(100.0, 95.0))
        assertTrue(r.insights.size <= SleepStageInsights.MAX_INSIGHTS)
        assertEquals(SleepStageInsights.Tone.CAUTION, r.insights.first().tone)
    }

    @Test
    fun emptyNightBuildsBaseline() {
        val r = SleepStageInsights.analyze(m(0.0, 0.0, 0.0, 0.0), emptyList())
        assertEquals(listOf(SleepStageInsights.Kind.BUILDING_BASELINE), kinds(r))
    }

    @Test
    fun medianIsRobust() {
        assertEquals(100.0, SleepStageInsights.median(listOf(90.0, 100.0, 100.0, 100.0, 100.0, 110.0)), 1e-9)
        assertEquals(20.0, SleepStageInsights.median(listOf(10.0, 20.0, 30.0)), 1e-9)
        assertEquals(0.0, SleepStageInsights.median(emptyList()), 1e-9)
    }
}
