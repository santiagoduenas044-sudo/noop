package com.noop.analytics

/*
 * SleepConsistencyPresentation.kt — framework-free presentation model for the "Sleep
 * Consistency" surface.
 *
 * Byte-for-byte twin of StrandAnalytics/SleepConsistencyPresentation.swift. Keep the tone
 * mapping, the SOLID-only bar gate, the clock derivation, and the bar-fraction clamp identical
 * to Swift — both clients must present the same read for the same engine result.
 *
 * PURELY ADDITIVE and UI-FRAMEWORK-FREE: takes a SleepRegularityResult and returns plain values.
 * Colours and copy belong to the Compose layer; every DECISION lives here so it is covered by
 * JVM unit tests and stays parallel with Swift.
 *
 * PRODUCT NOTE (tone): sleep-timing is a wellness read, not a clinical one, so there is NO
 * critical/alarm tone — an irregular week reads as CAUTION, never a failure. The four bands are
 * distinguished by the view's headline wording; tone only separates steady / worth-noticing /
 * building, keeping the surface encouraging.
 */

data class SleepConsistencyPresentation(
    /** The engine's descriptive band, for the view's copy switch. */
    val band: SleepRegularityLabel,
    /** Emphasis bucket the view maps to a token (not a colour). */
    val tone: Tone,
    /** Whether per-channel bedtime/wake bars are trustworthy enough to show (SOLID + both spreads). */
    val showChannelBars: Boolean,
    /** Typical mid-sleep hour (0…23), null when withheld. */
    val midpointClockHour: Int?,
    /** Typical mid-sleep minute (0…59), null when withheld. */
    val midpointClockMinute: Int?,
    /** Mid-sleep spread as a 0…1 bar fill; null when withheld. */
    val midpointBarFraction: Double?,
    /** Bedtime spread as a 0…1 bar fill; null unless [showChannelBars]. */
    val onsetBarFraction: Double?,
    /** Wake spread as a 0…1 bar fill; null unless [showChannelBars]. */
    val wakeBarFraction: Double?,
) {
    /** Semantic emphasis — NOT a colour. Mirrors Swift `Tone`. */
    enum class Tone(val raw: String) {
        POSITIVE("positive"),
        CAUTION("caution"),
        NEUTRAL("neutral"),
    }

    companion object {
        /** Spread (minutes) that fills a per-channel bar completely. */
        const val BAR_FULL_SCALE_MIN: Double = 180.0

        /** Derive the presentation from an engine result. Pure and total. */
        fun from(r: SleepRegularityResult): SleepConsistencyPresentation {
            val tone = when (r.label) {
                SleepRegularityLabel.VERY_REGULAR, SleepRegularityLabel.REGULAR -> Tone.POSITIVE
                SleepRegularityLabel.VARIABLE, SleepRegularityLabel.IRREGULAR -> Tone.CAUTION
                SleepRegularityLabel.UNREADABLE -> Tone.NEUTRAL
            }

            if (!r.isReadable) {
                return SleepConsistencyPresentation(
                    band = r.label, tone = tone, showChannelBars = false,
                    midpointClockHour = null, midpointClockMinute = null,
                    midpointBarFraction = null, onsetBarFraction = null, wakeBarFraction = null,
                )
            }

            var hour: Int? = null
            var minute: Int? = null
            r.meanMidpointMinOfDay?.let { mid ->
                val m = ((mid % 1440) + 1440) % 1440
                hour = m / 60
                minute = m % 60
            }

            val midFrac = r.midpointSDMinutes?.let { barFraction(it) }

            val bothChannels = r.onsetSDMinutes != null && r.wakeSDMinutes != null
            val showBars = r.confidence == ScoreConfidence.SOLID && bothChannels
            val onsetFrac = if (showBars) r.onsetSDMinutes?.let { barFraction(it) } else null
            val wakeFrac = if (showBars) r.wakeSDMinutes?.let { barFraction(it) } else null

            return SleepConsistencyPresentation(
                band = r.label, tone = tone, showChannelBars = showBars,
                midpointClockHour = hour, midpointClockMinute = minute,
                midpointBarFraction = midFrac, onsetBarFraction = onsetFrac, wakeBarFraction = wakeFrac,
            )
        }

        /** Map a spread in minutes to a clamped 0…1 bar fill. */
        internal fun barFraction(sdMin: Double): Double =
            (sdMin / BAR_FULL_SCALE_MIN).coerceIn(0.0, 1.0)
    }
}
