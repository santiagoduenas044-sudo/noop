import XCTest
@testable import StrandAnalytics

/// Tests for the framework-free presentation mapper. Kotlin parity:
/// SleepConsistencyPresentationTest.kt asserts the same cases.
final class SleepConsistencyPresentationTests: XCTestCase {

    private func result(label: SleepRegularityLabel, confidence: ScoreConfidence,
                        score: Int? = 80, midSD: Double? = 18, onsetSD: Double? = 22,
                        wakeSD: Double? = 15, meanMid: Int? = 192) -> SleepRegularityResult {
        SleepRegularityResult(score: score, label: label, confidence: confidence,
                              midpointSDMinutes: midSD, onsetSDMinutes: onsetSD,
                              wakeSDMinutes: wakeSD, meanMidpointMinOfDay: meanMid,
                              resultantLength: 0.98, nightCount: 12)
    }

    /// A solid, very-regular read with both channels → positive tone, bars shown, clock derived.
    func testSolidVeryRegularShowsBars() {
        let p = SleepConsistencyPresentation.from(result(label: .veryRegular, confidence: .solid))
        XCTAssertEqual(p.tone, .positive)
        XCTAssertTrue(p.showChannelBars)
        XCTAssertEqual(p.midpointClockHour, 3)      // 192 min = 03:12
        XCTAssertEqual(p.midpointClockMinute, 12)
        XCTAssertNotNil(p.midpointBarFraction)
        XCTAssertNotNil(p.onsetBarFraction)
        XCTAssertNotNil(p.wakeBarFraction)
        XCTAssertEqual(p.midpointBarFraction ?? -1, 18.0 / 180.0, accuracy: 1e-9)
    }

    /// Variable / irregular map to `caution` — never a red/critical tone (product decision).
    func testVariableIsCautionNotCritical() {
        XCTAssertEqual(SleepConsistencyPresentation.from(result(label: .variable, confidence: .solid)).tone, .caution)
        XCTAssertEqual(SleepConsistencyPresentation.from(result(label: .irregular, confidence: .solid)).tone, .caution)
    }

    /// A regular read is still positive (encouraging).
    func testRegularIsPositive() {
        XCTAssertEqual(SleepConsistencyPresentation.from(result(label: .regular, confidence: .solid)).tone, .positive)
    }

    /// Bars are gated on SOLID confidence — a building read hides them even with both spreads present.
    func testBuildingConfidenceHidesBars() {
        let p = SleepConsistencyPresentation.from(result(label: .veryRegular, confidence: .building))
        XCTAssertFalse(p.showChannelBars)
        XCTAssertNil(p.onsetBarFraction)
        XCTAssertNil(p.wakeBarFraction)
        XCTAssertNotNil(p.midpointBarFraction)   // mid-sleep bar still available on a readable result
    }

    /// Missing a channel spread hides the bars even on a solid read.
    func testMissingChannelHidesBars() {
        let p = SleepConsistencyPresentation.from(
            result(label: .veryRegular, confidence: .solid, wakeSD: nil))
        XCTAssertFalse(p.showChannelBars)
        XCTAssertNil(p.onsetBarFraction)
    }

    /// The withheld (unreadable) read → neutral tone, no bars, no clock, no fractions.
    func testUnreadableIsNeutralAndBlank() {
        let r = SleepRegularityResult.unreadable(nightCount: 2)
        let p = SleepConsistencyPresentation.from(r)
        XCTAssertEqual(p.tone, .neutral)
        XCTAssertFalse(p.showChannelBars)
        XCTAssertNil(p.midpointClockHour)
        XCTAssertNil(p.midpointBarFraction)
        XCTAssertNil(p.onsetBarFraction)
    }

    /// Bar fractions clamp into [0, 1]: a 6 h spread pins full, a 0 spread pins empty.
    func testBarFractionClamps() {
        XCTAssertEqual(SleepConsistencyPresentation.barFraction(360), 1.0, accuracy: 1e-9)
        XCTAssertEqual(SleepConsistencyPresentation.barFraction(0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(SleepConsistencyPresentation.barFraction(90), 0.5, accuracy: 1e-9)
    }

    /// Clock derivation wraps and floors correctly (e.g. 1439 → 23:59, 0 → 00:00).
    func testClockDerivation() {
        let late = SleepConsistencyPresentation.from(result(label: .regular, confidence: .solid, meanMid: 1439))
        XCTAssertEqual(late.midpointClockHour, 23)
        XCTAssertEqual(late.midpointClockMinute, 59)
        let mid = SleepConsistencyPresentation.from(result(label: .regular, confidence: .solid, meanMid: 0))
        XCTAssertEqual(mid.midpointClockHour, 0)
        XCTAssertEqual(mid.midpointClockMinute, 0)
    }
}
