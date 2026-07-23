package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Kotlin parity for StrandAnalytics/SleepConsistencyPresentationTests.swift. */
class SleepConsistencyPresentationTest {

    private fun result(
        label: SleepRegularityLabel,
        confidence: ScoreConfidence,
        score: Int? = 80,
        midSD: Double? = 18.0,
        onsetSD: Double? = 22.0,
        wakeSD: Double? = 15.0,
        meanMid: Int? = 192,
    ) = SleepRegularityResult(
        score = score, label = label, confidence = confidence,
        midpointSDMinutes = midSD, onsetSDMinutes = onsetSD, wakeSDMinutes = wakeSD,
        meanMidpointMinOfDay = meanMid, resultantLength = 0.98, nightCount = 12,
    )

    @Test
    fun solidVeryRegular_showsBars() {
        val p = SleepConsistencyPresentation.from(result(SleepRegularityLabel.VERY_REGULAR, ScoreConfidence.SOLID))
        assertEquals(SleepConsistencyPresentation.Tone.POSITIVE, p.tone)
        assertTrue(p.showChannelBars)
        assertEquals(3, p.midpointClockHour)    // 192 min = 03:12
        assertEquals(12, p.midpointClockMinute)
        assertNotNull(p.midpointBarFraction)
        assertNotNull(p.onsetBarFraction)
        assertNotNull(p.wakeBarFraction)
        assertEquals(18.0 / 180.0, p.midpointBarFraction!!, 1e-9)
    }

    @Test
    fun variable_isCautionNotCritical() {
        assertEquals(
            SleepConsistencyPresentation.Tone.CAUTION,
            SleepConsistencyPresentation.from(result(SleepRegularityLabel.VARIABLE, ScoreConfidence.SOLID)).tone,
        )
        assertEquals(
            SleepConsistencyPresentation.Tone.CAUTION,
            SleepConsistencyPresentation.from(result(SleepRegularityLabel.IRREGULAR, ScoreConfidence.SOLID)).tone,
        )
    }

    @Test
    fun regular_isPositive() {
        assertEquals(
            SleepConsistencyPresentation.Tone.POSITIVE,
            SleepConsistencyPresentation.from(result(SleepRegularityLabel.REGULAR, ScoreConfidence.SOLID)).tone,
        )
    }

    @Test
    fun buildingConfidence_hidesBars() {
        val p = SleepConsistencyPresentation.from(result(SleepRegularityLabel.VERY_REGULAR, ScoreConfidence.BUILDING))
        assertFalse(p.showChannelBars)
        assertNull(p.onsetBarFraction)
        assertNull(p.wakeBarFraction)
        assertNotNull(p.midpointBarFraction)
    }

    @Test
    fun missingChannel_hidesBars() {
        val p = SleepConsistencyPresentation.from(
            result(SleepRegularityLabel.VERY_REGULAR, ScoreConfidence.SOLID, wakeSD = null),
        )
        assertFalse(p.showChannelBars)
        assertNull(p.onsetBarFraction)
    }

    @Test
    fun unreadable_isNeutralAndBlank() {
        val p = SleepConsistencyPresentation.from(SleepRegularityResult.unreadable(2))
        assertEquals(SleepConsistencyPresentation.Tone.NEUTRAL, p.tone)
        assertFalse(p.showChannelBars)
        assertNull(p.midpointClockHour)
        assertNull(p.midpointBarFraction)
        assertNull(p.onsetBarFraction)
    }

    @Test
    fun barFraction_clamps() {
        assertEquals(1.0, SleepConsistencyPresentation.barFraction(360.0), 1e-9)
        assertEquals(0.0, SleepConsistencyPresentation.barFraction(0.0), 1e-9)
        assertEquals(0.5, SleepConsistencyPresentation.barFraction(90.0), 1e-9)
    }

    @Test
    fun clockDerivation() {
        val late = SleepConsistencyPresentation.from(result(SleepRegularityLabel.REGULAR, ScoreConfidence.SOLID, meanMid = 1439))
        assertEquals(23, late.midpointClockHour)
        assertEquals(59, late.midpointClockMinute)
        val mid = SleepConsistencyPresentation.from(result(SleepRegularityLabel.REGULAR, ScoreConfidence.SOLID, meanMid = 0))
        assertEquals(0, mid.midpointClockHour)
        assertEquals(0, mid.midpointClockMinute)
    }
}
