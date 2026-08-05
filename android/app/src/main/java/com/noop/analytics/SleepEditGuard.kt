package com.noop.analytics

import java.time.Instant
import java.time.ZoneId

/**
 * Pure guards for the hand-edit sleep-time pickers (#940). The reporter corrected a late-tracked
 * night's bed time from 01:06 back to 23:00; the picker kept the calendar DATE, so the "corrected"
 * bed landed on the COMING evening: a future-dated night whose staged window came back all-awake,
 * and the Sleep tab then hid the intact history behind it. Three layered rules, the byte-for-byte
 * twin of Swift StrandAnalytics.SleepEditGuard, all pure and unit-tested:
 *   1. [autoCorrectedBed]: a time-only roll that lands the bed in the future, or at/after the
 *      night's wake, almost always means the PREVIOUS evening; auto-decrement the date.
 *   2. [isDisjoint]: a corrected window with no overlap of the night's recorded coverage needs an
 *      explicit confirm ("this moves the night to a time with no recorded data"), never silent
 *      acceptance.
 *   3. [clampedEditWindow]: the repository belt-and-braces; no code path may persist a future or
 *      inverted window even if a client UI misbehaves.
 */
object SleepEditGuard {

    /**
     * The longest night span (seconds) the at/after-wake auto-correct will manufacture. A genuine
     * evening-bed correction (bed 23:00, wake 05:00 next day) yields a ~6h span; a user moving a
     * session LATER past its wake (nap 14:00-15:00 -> bed 16:00 same day) would yield a ~23h span if
     * decremented, which is not a plausible night, so those candidates are left verbatim.
     */
    const val MAX_AUTO_CORRECT_NIGHT_SEC: Long = 16L * 3600L

    /**
     * Rule 1: the cross-midnight bed auto-correct. [candidateBedTs] is what the picker just
     * produced, [previousBedTs] the value it held before this change (a DELIBERATE date change,
     * where the two sit on different calendar days, is always respected verbatim; the Android
     * picker is time-only, so this always holds there). When the change was time-only (same
     * calendar day) and the candidate is impossible for a bed time, the user almost always meant the
     * previous evening: return the candidate moved one day back, provided that lands in the past.
     * Two impossibility cases:
     *   - the candidate is in the FUTURE ([candidateBedTs] > [nowTs]) - always corrected (this is the
     *     [originalWakeTs] == null "Add a nap" case too, whose anchor sits after the night's wake);
     *   - the candidate is at/after [originalWakeTs] AND decrementing it forms a PLAUSIBLE night, i.e.
     *     the decremented bed lands before the wake and within [MAX_AUTO_CORRECT_NIGHT_SEC] of it. This
     *     guards a legitimate MOVE-LATER edit (a past bed rolled to just after its own wake on the same
     *     day) from being silently shoved back a full day into a ~23h wrong-day window.
     * All timestamps unix seconds.
     */
    fun autoCorrectedBed(
        previousBedTs: Long,
        candidateBedTs: Long,
        originalWakeTs: Long?,
        nowTs: Long,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Long {
        val prevDay = Instant.ofEpochSecond(previousBedTs).atZone(zone).toLocalDate()
        val candZoned = Instant.ofEpochSecond(candidateBedTs).atZone(zone)
        if (candZoned.toLocalDate() != prevDay) return candidateBedTs
        // minusDays is DST-correct: "the same wall-clock time one calendar day earlier".
        val decremented = candZoned.minusDays(1).toEpochSecond()
        if (decremented > nowTs) return candidateBedTs
        val futureViolation = candidateBedTs > nowTs
        val wakeViolation = originalWakeTs != null && candidateBedTs >= originalWakeTs &&
            decremented < originalWakeTs &&
            (originalWakeTs - decremented) <= MAX_AUTO_CORRECT_NIGHT_SEC
        if (!futureViolation && !wakeViolation) return candidateBedTs
        return decremented
    }

    /**
     * Rule 2: true when the corrected window `[newStart, newEnd)` shares NOTHING with the night's
     * recorded coverage `[coverageStart, coverageEnd)` (unix seconds). A disjoint window has no
     * data to stage from, so accepting it silently fabricates an all-awake phantom night; the UI
     * must confirm the move instead.
     */
    fun isDisjoint(newStart: Long, newEnd: Long, coverageStart: Long, coverageEnd: Long): Boolean =
        newEnd <= coverageStart || newStart >= coverageEnd

    /**
     * Rule 3: the persistence belt-and-braces. Caps the corrected wake at `nowTs + slackSec` (a
     * sleep cannot END in the future; the slack absorbs clock skew) and refuses (null) any window
     * that is inverted or entirely in the future once capped. The editor's own guards should make
     * this unreachable; it exists so NO client code path can write a phantom night the display
     * merge cannot render.
     */
    fun clampedEditWindow(start: Long, end: Long, nowTs: Long, slackSec: Long = 300L): Pair<Long, Long>? {
        val cappedEnd = minOf(end, nowTs + slackSec)
        if (cappedEnd <= start) return null
        return start to cappedEnd
    }

    /** Default length of the window the "Add a nap" picker opens on, seconds. */
    const val NAP_SEED_DURATION_SEC = 30 * 60L

    /**
     * How long after the night's wake the nap seed is anchored, seconds — the natural place to look
     * for a missed late-morning/afternoon nap.
     */
    const val NAP_SEED_AFTER_WAKE_SEC = 60 * 60L

    /**
     * How old the last recorded wake may be and still drive the seed, seconds. Beyond this the night
     * is a STALE anchor (an unsynced strap leaves the newest recorded night a day or more behind), and
     * seeding a picker in the middle of a past day is worse than seeding the half-hour just gone.
     */
    const val NAP_SEED_MAX_WAKE_AGE_SEC = 18 * 3600L

    /**
     * Rule 4: the window the "Add a nap" picker should OPEN on, given the day's last recorded wake
     * ([lastWakeTs], null when the day has no main night yet) and the current time.
     *
     * The seed must always be a window that is already in the PAST, because [clampedEditWindow]
     * refuses a window lying entirely in the future — a picker seeded ahead of the clock therefore
     * opens on a window that saves to nothing at all. The wake+1h anchor is used only when its full
     * half-hour has already elapsed; right after a morning sync it has not, so the seed falls back to
     * the half-hour that just ended, which is valid at any time of day.
     *
     * Twin of `SleepEditGuard.napSeedWindow` (Swift). Returns (start, end), `start < end <= nowTs`.
     */
    fun napSeedWindow(lastWakeTs: Long?, nowTs: Long): Pair<Long, Long> {
        if (lastWakeTs != null && nowTs - lastWakeTs <= NAP_SEED_MAX_WAKE_AGE_SEC) {
            val start = lastWakeTs + NAP_SEED_AFTER_WAKE_SEC
            if (start + NAP_SEED_DURATION_SEC <= nowTs) return start to (start + NAP_SEED_DURATION_SEC)
        }
        return (nowTs - NAP_SEED_DURATION_SEC) to nowTs
    }
}
