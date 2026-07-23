import XCTest
@testable import StrandAnalytics

/// Tests for the sleep-TIMING regularity engine. The decisive correctness case is
/// `testWrapAroundNearMidnightReadsRegular`: it proves the statistics are CIRCULAR (a
/// steady near-midnight sleeper reads as very regular, where a naive linear SD would rank
/// them maximally irregular). Kotlin parity: SleepRegularityTest.kt asserts the same vectors.
final class SleepRegularityTests: XCTestCase {

    /// Build a night from an onset minute-of-day with a fixed 8 h duration, so the midpoint
    /// is exactly `onset + 240` (mod 1440). Keeps the timing vectors easy to reason about.
    private func night(_ day: String, onset: Int, durMin: Int = 480) -> SleepTimingNight {
        SleepTimingNight(day: day, onsetMinOfDay: onset,
                         wakeMinOfDay: (onset + durMin) % 1440)
    }

    private func nights(_ onsets: [Int], durMin: Int = 480) -> [SleepTimingNight] {
        onsets.enumerated().map { night(String(format: "2026-06-%02d", $0.offset + 1),
                                        onset: $0.element, durMin: durMin) }
    }

    // MARK: - Perfect regularity

    /// Seven identical nights (asleep 23:00, wake 07:00) → perfectly consistent timing:
    /// score 100, zero spread, R 1, veryRegular, solid confidence, mean midpoint 03:00.
    func testIdenticalNightsScorePerfect() {
        let r = SleepRegularity.assess(nights: nights(Array(repeating: 1380, count: 7)))
        XCTAssertEqual(r.score, 100)
        XCTAssertEqual(r.label, .veryRegular)
        XCTAssertEqual(r.confidence, .solid)
        XCTAssertEqual(r.midpointSDMinutes, 0.0)
        XCTAssertEqual(r.onsetSDMinutes, 0.0)
        XCTAssertEqual(r.wakeSDMinutes, 0.0)
        XCTAssertEqual(r.resultantLength, 1.0)
        XCTAssertEqual(r.meanMidpointMinOfDay, 180)   // 03:00
        XCTAssertEqual(r.nightCount, 7)
        XCTAssertTrue(r.isReadable)
    }

    // MARK: - The circular-statistics proof (must not use a linear SD)

    /// Onsets straddle midnight (23:40…00:20) but are all within ~20 min of each other. A
    /// CIRCULAR onset SD is tiny (≤ 30); a naive linear SD of these minutes-of-day would be
    /// ~700+ and would mislabel a rock-steady sleeper as maximally irregular. This is the
    /// test that pins the wrap-around handling.
    func testWrapAroundNearMidnightReadsRegular() {
        let r = SleepRegularity.assess(
            nights: nights([1425, 15, 1435, 5, 1420, 20, 0]))   // 23:45, 00:15, … around midnight
        XCTAssertEqual(r.label, .veryRegular)
        XCTAssertNotNil(r.score)
        XCTAssertGreaterThanOrEqual(r.score ?? 0, 80)
        // Onsets literally cross the midnight boundary; a linear SD would be ~700+ minutes.
        XCTAssertNotNil(r.onsetSDMinutes)
        XCTAssertLessThanOrEqual(r.onsetSDMinutes ?? 999, 30.0)
        XCTAssertLessThanOrEqual(r.midpointSDMinutes ?? 999, 30.0)
    }

    // MARK: - Tracks a varying input (monotonicity)

    /// A tight schedule must score strictly higher, with a strictly smaller midpoint spread,
    /// than a loose one — the "prove it tracks a varying input" discipline.
    func testTighterScheduleScoresHigherThanLooser() {
        let tight = SleepRegularity.assess(
            nights: nights([1380, 1370, 1390, 1380, 1360, 1400, 1380]))   // ±20 min
        let loose = SleepRegularity.assess(
            nights: nights([720, 600, 840, 720, 590, 850, 720]))          // ±130 min

        XCTAssertNotNil(tight.score); XCTAssertNotNil(loose.score)
        XCTAssertGreaterThan(tight.score ?? 0, loose.score ?? 100)
        XCTAssertLessThan(tight.midpointSDMinutes ?? 999, loose.midpointSDMinutes ?? 0)
        XCTAssertEqual(tight.label, .veryRegular)
        XCTAssertNotEqual(loose.label, .veryRegular)
        // Higher spread ⇒ lower resultant length.
        XCTAssertGreaterThan(tight.resultantLength ?? 0, loose.resultantLength ?? 1)
    }

    /// A balanced set of midpoints at exactly base ± 50 min (three each) has an analytic
    /// resultant length R = cos(2π·50/1440) ≈ 0.976, giving a circular midpoint SD ≈ 50.2 min
    /// and a `.regular` label. Pins the formula (with margin for cross-platform libm ULP).
    func testBalancedSpreadMatchesCircularFormula() {
        // midpoint = onset + 240; onsets 50 → mid 290, 1390 → mid 190 (base 240 ± 50).
        let r = SleepRegularity.assess(nights: nights([50, 1390, 50, 1390, 50, 1390]))
        XCTAssertEqual(r.label, .regular)
        XCTAssertNotNil(r.midpointSDMinutes)
        XCTAssertEqual(r.midpointSDMinutes ?? 0, 50.2, accuracy: 1.5)
        XCTAssertEqual(r.resultantLength ?? 0, 0.976, accuracy: 0.01)
        XCTAssertNotNil(r.score)
        XCTAssertEqual(Double(r.score ?? 0), 69.0, accuracy: 3.0)
    }

    // MARK: - Honesty: withholding, skipping, confidence, windowing

    /// Fewer than `minNights` usable nights → the read is withheld, not faked.
    func testTooFewNightsIsUnreadable() {
        let r = SleepRegularity.assess(nights: nights([1380, 1380]))   // 2 nights
        XCTAssertEqual(r.label, .unreadable)
        XCTAssertNil(r.score)
        XCTAssertNil(r.midpointSDMinutes)
        XCTAssertEqual(r.confidence, .calibrating)
        XCTAssertFalse(r.isReadable)
        XCTAssertEqual(r.nightCount, 2)
    }

    /// A night with an implausible duration (30 min "sleep") is skipped, not counted.
    func testImplausibleDurationSkipped() {
        var ns = nights([1380, 1380, 1380])          // three good 8 h nights
        ns.append(SleepTimingNight(day: "2026-06-09", onsetMinOfDay: 600, wakeMinOfDay: 630))  // 30 min
        let r = SleepRegularity.assess(nights: ns)
        XCTAssertEqual(r.nightCount, 3)              // the 30 min night dropped
        XCTAssertTrue(r.isReadable)
    }

    /// Confidence rises with usable-night count: 4 nights → building, 7 → solid.
    func testConfidenceTiers() {
        XCTAssertEqual(SleepRegularity.assess(nights: nights(Array(repeating: 1380, count: 4))).confidence, .building)
        XCTAssertEqual(SleepRegularity.assess(nights: nights(Array(repeating: 1380, count: 7))).confidence, .solid)
    }

    /// The window keeps only the most-recent N usable nights.
    func testWindowCapKeepsMostRecent() {
        let r = SleepRegularity.assess(nights: nights(Array(repeating: 1380, count: 20)), window: 14)
        XCTAssertEqual(r.nightCount, 14)
    }

    /// Duration is the forward arc onset → wake even when the window crosses midnight.
    func testDurationWrapsAcrossMidnight() {
        let n = SleepTimingNight(day: "d", onsetMinOfDay: 1380, wakeMinOfDay: 420)   // 23:00 → 07:00
        XCTAssertEqual(n.durationMin, 480.0, accuracy: 1e-9)
        XCTAssertEqual(n.midpointMinOfDay, 180.0, accuracy: 1e-9)                    // 03:00
    }

    /// The epoch factory resolves onset/wake to a LOCAL minute-of-day and keys the night by the
    /// wake civil date. Built from components so the test carries no hand-computed epoch constants.
    func testFromEpochResolvesLocalMinuteOfDay() {
        var cal = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        cal.timeZone = utc
        func epoch(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Int {
            let comps = DateComponents(calendar: cal, timeZone: utc, year: y, month: mo, day: d, hour: h, minute: mi)
            return Int(cal.date(from: comps)!.timeIntervalSince1970)
        }
        let n = SleepTimingNight.from(onsetEpoch: epoch(2026, 6, 1, 23, 0),
                                      wakeEpoch: epoch(2026, 6, 2, 7, 0), timeZone: utc)
        XCTAssertEqual(n.onsetMinOfDay, 1380)   // 23:00
        XCTAssertEqual(n.wakeMinOfDay, 420)     // 07:00
        XCTAssertEqual(n.day, "2026-06-02")     // keyed by wake date
        XCTAssertEqual(n.durationMin, 480.0, accuracy: 1e-9)
    }

    /// `windowedNights` drops implausible nights and caps to the most-recent window — and is the
    /// same set `assess` scores, so a dial built from it matches the number.
    func testWindowedNightsFiltersAndCaps() {
        var ns = nights(Array(repeating: 1380, count: 20))
        ns.append(SleepTimingNight(day: "nap", onsetMinOfDay: 600, wakeMinOfDay: 630))  // 30 min → dropped
        let w = SleepRegularity.windowedNights(ns, window: 14)
        XCTAssertEqual(w.count, 14)
        XCTAssertTrue(w.allSatisfy { $0.durationMin >= SleepRegularity.minDurationMin })
    }
}
