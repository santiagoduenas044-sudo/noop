import XCTest
@testable import StrandAnalytics
import WhoopProtocol   // HRSample lives here, not in StrandAnalytics

/// Pins the per-sample TRIMP integration that fixed "strain starts the day unrealistically high".
///
/// The bug: `sampleDurationMinutes` derived ONE duration from `hr[1].ts - hr[0].ts` and the
/// integrators multiplied every sample by it. A single unrepresentative first gap therefore
/// rescaled the whole day — and early in the day, when the stream is sparse and irregular, that gap
/// is routinely minutes long, so every later reading was credited with minutes of time-in-zone.
final class StrainSampleDurationTests: XCTestCase {

    /// A uniformly sampled stream must integrate EXACTLY as before, so this fix cannot move a
    /// healthy 1 Hz day's score. This is the regression guard on the whole change.
    func testUniformStreamMatchesTheOldGlobalDurationIntegration() {
        let hr = (0..<600).map { HRSample(ts: $0, bpm: 120) }
        let resting = 60.0, reserve = 130.0

        let old = StrainScorer.edwardsTRIMP(hr, restingHR: resting, hrReserve: reserve,
                                            sampleDurationMin: StrainScorer.sampleDurationMinutes(hr))
        let new = StrainScorer.edwardsTRIMP(hr, restingHR: resting, hrReserve: reserve,
                                            durations: StrainScorer.sampleDurationsMinutes(hr))
        XCTAssertEqual(new, old, accuracy: 1e-9,
                       "A uniform stream must be unaffected by the per-sample integration")
    }

    /// The actual reported symptom. One long leading gap (asleep, sparse cadence) followed by a
    /// dense burst: the OLD code credits every dense sample with the whole leading gap, massively
    /// inflating TRIMP. The new code credits each sample with its own real elapsed time.
    func testLeadingGapNoLongerInflatesTheWholeDay() {
        // 00:00, then nothing until 00:30 (a 1800 s gap), then 1 Hz for 5 minutes.
        var hr = [HRSample(ts: 0, bpm: 60), HRSample(ts: 1800, bpm: 60)]
        for t in 1801..<2101 { hr.append(HRSample(ts: t, bpm: 150)) }
        let resting = 60.0, reserve = 130.0

        let oldDur = StrainScorer.sampleDurationMinutes(hr)          // 30 minutes (!)
        let old = StrainScorer.edwardsTRIMP(hr, restingHR: resting, hrReserve: reserve,
                                            sampleDurationMin: oldDur)
        let new = StrainScorer.edwardsTRIMP(hr, restingHR: resting, hrReserve: reserve,
                                            durations: StrainScorer.sampleDurationsMinutes(hr))

        XCTAssertEqual(oldDur, 30.0, accuracy: 1e-9, "sanity: the old path really did infer 30 min/sample")
        XCTAssertLessThan(new, old / 10,
                          "The leading gap must no longer be applied to every later sample")

        // The dense burst is ~300 samples of 1 s at a high zone weight, so the honest TRIMP is on
        // the order of minutes-of-zone, not hours.
        let burstMinutes = 300.0 / 60.0
        XCTAssertLessThan(new, burstMinutes * 5 + 5,
                          "TRIMP should be bounded by the real elapsed time in zone")
    }

    /// A gap longer than the cap contributes only the cap — a removed strap must not integrate as
    /// if the wearer held that heart rate continuously for hours.
    func testLongGapIsCappedNotIntegratedWhole() {
        // Two samples four hours apart.
        let hr = [HRSample(ts: 0, bpm: 150), HRSample(ts: 14_400, bpm: 150)]
        let durations = StrainScorer.sampleDurationsMinutes(hr)
        let capMinutes = StrainScorer.maxSampleGapSeconds / 60.0

        XCTAssertEqual(durations.count, 2)
        XCTAssertEqual(durations[0], capMinutes, accuracy: 1e-9, "the 4 h gap must clamp to the cap")
        XCTAssertLessThanOrEqual(durations[1], capMinutes, "the trailing median must also be bounded")
    }

    /// Mixed cadence — dense during a workout, sparse at rest — is the normal 5/MG shape. Each
    /// segment must contribute its own real time rather than one global guess.
    func testMixedCadenceIntegratesEachSegmentOnItsOwnTiming() {
        var hr: [HRSample] = []
        for t in stride(from: 0, to: 1800, by: 30) { hr.append(HRSample(ts: t, bpm: 60)) }   // rest, 30 s
        for t in 1800..<2400 { hr.append(HRSample(ts: t, bpm: 160)) }                        // work, 1 s

        let durations = StrainScorer.sampleDurationsMinutes(hr)
        XCTAssertEqual(durations.count, hr.count)
        XCTAssertEqual(durations[0], 0.5, accuracy: 1e-9, "resting samples span 30 s")
        // The first dense sample sits right after the last sparse one.
        let firstDenseIndex = 60
        XCTAssertEqual(durations[firstDenseIndex], 1.0 / 60.0, accuracy: 1e-9,
                       "workout samples span 1 s")
    }

    /// Coincident/duplicate timestamps keep the long-standing 1 s floor rather than contributing
    /// zero time, so a stream with repeated stamps still scores.
    func testDuplicateTimestampsUseTheOneSecondFloor() {
        let hr = [HRSample(ts: 100, bpm: 120), HRSample(ts: 100, bpm: 120), HRSample(ts: 101, bpm: 120)]
        let durations = StrainScorer.sampleDurationsMinutes(hr)
        XCTAssertEqual(durations[0], StrainScorer.fallbackSampleMin, accuracy: 1e-9)
    }

    /// Fewer than two samples has no gap to measure; every element falls back rather than crashing
    /// on an empty `gaps` array.
    func testDegenerateStreamsDoNotCrash() {
        XCTAssertTrue(StrainScorer.sampleDurationsMinutes([]).isEmpty)
        let one = StrainScorer.sampleDurationsMinutes([HRSample(ts: 5, bpm: 70)])
        XCTAssertEqual(one, [StrainScorer.fallbackSampleMin])
    }

    /// End-to-end through `strain(...)`: the same leading-gap day must now score lower than it did
    /// under the global-duration integration, and must stay within the 0…100 scale.
    func testStrainScoreForALeadingGapDayIsBounded() {
        var hr = [HRSample(ts: 0, bpm: 60)]
        for t in stride(from: 1800, to: 1800 + 1200, by: 1) { hr.append(HRSample(ts: t, bpm: 140)) }
        let score = StrainScorer.strain(hr, maxHR: 190, restingHR: 60)
        XCTAssertNotNil(score)
        if let s = score {
            XCTAssertGreaterThanOrEqual(s, 0)
            XCTAssertLessThanOrEqual(s, StrainScorer.maxStrain)
        }
    }
}
