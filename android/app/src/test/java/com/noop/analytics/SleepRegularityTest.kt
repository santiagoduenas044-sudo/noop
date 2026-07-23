package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Kotlin parity for StrandAnalytics/SleepRegularityTests.swift — same vectors, same results.
 *  The decisive case is [wrapAroundNearMidnight_readsRegular]: it proves the statistics are
 *  CIRCULAR (a steady near-midnight sleeper reads very regular, where a linear SD would not). */
class SleepRegularityTest {

    /** A night from an onset minute-of-day with a fixed 8 h duration → midpoint = onset + 240. */
    private fun night(day: String, onset: Int, durMin: Int = 480) =
        SleepTimingNight(day = day, onsetMinOfDay = onset, wakeMinOfDay = (onset + durMin) % 1440)

    private fun nights(onsets: List<Int>, durMin: Int = 480) =
        onsets.mapIndexed { i, o -> night("2026-06-%02d".format(i + 1), o, durMin) }

    @Test
    fun identicalNights_scorePerfect() {
        val r = SleepRegularity.assess(nights(List(7) { 1380 }))
        assertEquals(100, r.score)
        assertEquals(SleepRegularityLabel.VERY_REGULAR, r.label)
        assertEquals(ScoreConfidence.SOLID, r.confidence)
        assertEquals(0.0, r.midpointSDMinutes!!, 1e-9)
        assertEquals(0.0, r.onsetSDMinutes!!, 1e-9)
        assertEquals(0.0, r.wakeSDMinutes!!, 1e-9)
        assertEquals(1.0, r.resultantLength!!, 1e-9)
        assertEquals(180, r.meanMidpointMinOfDay)   // 03:00
        assertEquals(7, r.nightCount)
        assertTrue(r.isReadable)
    }

    /** Onsets straddle midnight (23:40…00:20) but cluster within ~20 min. Circular onset SD is
     *  tiny (≤ 30); a linear SD would be ~700+ and mislabel a rock-steady sleeper as irregular. */
    @Test
    fun wrapAroundNearMidnight_readsRegular() {
        val r = SleepRegularity.assess(nights(listOf(1425, 15, 1435, 5, 1420, 20, 0)))
        assertEquals(SleepRegularityLabel.VERY_REGULAR, r.label)
        assertNotNull(r.score)
        assertTrue(r.score!! >= 80)
        assertNotNull(r.onsetSDMinutes)
        assertTrue(r.onsetSDMinutes!! <= 30.0)
        assertTrue(r.midpointSDMinutes!! <= 30.0)
    }

    /** A tight schedule scores strictly higher, with a strictly smaller spread, than a loose one. */
    @Test
    fun tighterSchedule_scoresHigherThanLooser() {
        val tight = SleepRegularity.assess(nights(listOf(1380, 1370, 1390, 1380, 1360, 1400, 1380)))
        val loose = SleepRegularity.assess(nights(listOf(720, 600, 840, 720, 590, 850, 720)))

        assertNotNull(tight.score); assertNotNull(loose.score)
        assertTrue(tight.score!! > loose.score!!)
        assertTrue(tight.midpointSDMinutes!! < loose.midpointSDMinutes!!)
        assertEquals(SleepRegularityLabel.VERY_REGULAR, tight.label)
        assertFalse(loose.label == SleepRegularityLabel.VERY_REGULAR)
        assertTrue(tight.resultantLength!! > loose.resultantLength!!)
    }

    /** Balanced midpoints at base ± 50 min (three each): R = cos(2π·50/1440) ≈ 0.976, circular
     *  midpoint SD ≈ 50.2 min, `.regular` label. Pins the formula with libm-ULP margin. */
    @Test
    fun balancedSpread_matchesCircularFormula() {
        val r = SleepRegularity.assess(nights(listOf(50, 1390, 50, 1390, 50, 1390)))
        assertEquals(SleepRegularityLabel.REGULAR, r.label)
        assertNotNull(r.midpointSDMinutes)
        assertEquals(50.2, r.midpointSDMinutes!!, 1.5)
        assertEquals(0.976, r.resultantLength!!, 0.01)
        assertNotNull(r.score)
        assertEquals(69.0, r.score!!.toDouble(), 3.0)
    }

    @Test
    fun tooFewNights_isUnreadable() {
        val r = SleepRegularity.assess(nights(listOf(1380, 1380)))
        assertEquals(SleepRegularityLabel.UNREADABLE, r.label)
        assertNull(r.score)
        assertNull(r.midpointSDMinutes)
        assertEquals(ScoreConfidence.CALIBRATING, r.confidence)
        assertFalse(r.isReadable)
        assertEquals(2, r.nightCount)
    }

    @Test
    fun implausibleDuration_skipped() {
        val ns = nights(listOf(1380, 1380, 1380)).toMutableList()
        ns.add(SleepTimingNight(day = "2026-06-09", onsetMinOfDay = 600, wakeMinOfDay = 630)) // 30 min
        val r = SleepRegularity.assess(ns)
        assertEquals(3, r.nightCount)
        assertTrue(r.isReadable)
    }

    @Test
    fun confidenceTiers() {
        assertEquals(ScoreConfidence.BUILDING, SleepRegularity.assess(nights(List(4) { 1380 })).confidence)
        assertEquals(ScoreConfidence.SOLID, SleepRegularity.assess(nights(List(7) { 1380 })).confidence)
    }

    @Test
    fun windowCap_keepsMostRecent() {
        val r = SleepRegularity.assess(nights(List(20) { 1380 }), window = 14)
        assertEquals(14, r.nightCount)
    }

    @Test
    fun durationWrapsAcrossMidnight() {
        val n = SleepTimingNight(day = "d", onsetMinOfDay = 1380, wakeMinOfDay = 420) // 23:00 → 07:00
        assertEquals(480.0, n.durationMin, 1e-9)
        assertEquals(180.0, n.midpointMinOfDay, 1e-9)   // 03:00
    }

    @Test
    fun windowedNights_filtersAndCaps() {
        val ns = nights(List(20) { 1380 }).toMutableList()
        ns.add(SleepTimingNight(day = "nap", onsetMinOfDay = 600, wakeMinOfDay = 630)) // 30 min → dropped
        val w = SleepRegularity.windowedNights(ns, window = 14)
        assertEquals(14, w.size)
        assertTrue(w.all { it.durationMin >= SleepRegularity.MIN_DURATION_MIN })
    }
}
