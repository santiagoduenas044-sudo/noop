import XCTest
@testable import StrandAnalytics

final class TodayInsightsBuilderTests: XCTestCase {

    // MARK: Recovery

    func testRecoveryInsufficientEmitsNothing() {
        XCTAssertNil(TodayInsightsBuilder.recoveryCandidate(.init(score: 50, band: .insufficient)))
    }

    func testRecoveryPrimedIsPositive() {
        let c = TodayInsightsBuilder.recoveryCandidate(.init(score: 90, band: .primed))
        XCTAssertEqual(c?.kind, "recovery.primed")
        XCTAssertEqual(c?.domain, .recovery)
        XCTAssertEqual(c?.tone, .positive)
        XCTAssertEqual(c?.magnitude ?? 0, 0.8, accuracy: 1e-9)   // |90-50|/50
    }

    func testRecoveryBalancedIsNeutral() {
        let c = TodayInsightsBuilder.recoveryCandidate(.init(score: 55, band: .balanced))
        XCTAssertEqual(c?.tone, .neutral)
    }

    /// A rundown morning gets a magnitude FLOOR so a red day always leads even near the midpoint.
    func testRecoveryRundownHasCautionFloor() {
        let c = TodayInsightsBuilder.recoveryCandidate(.init(score: 48, band: .rundown))
        XCTAssertEqual(c?.tone, .caution)
        XCTAssertEqual(c?.magnitude ?? 0, 0.5, accuracy: 1e-9)   // floored above |48-50|/50 = 0.04
    }

    func testRecoveryStrainedScalesWhenLow() {
        let c = TodayInsightsBuilder.recoveryCandidate(.init(score: 20, band: .strained))
        XCTAssertEqual(c?.magnitude ?? 0, 0.6, accuracy: 1e-9)   // |20-50|/50 = 0.6, above the floor
    }

    // MARK: Sleep stages

    func testStageCandidatesMapToneAndDelta() {
        let report = SleepStageInsights.Report(
            composition: SleepStageInsights.composition(.init(awake: 20, light: 240, deep: 90, rem: 100)),
            insights: [
                SleepStageInsights.Insight(kind: .deepAboveUsual, tone: .positive, deltaMin: 30),
                SleepStageInsights.Insight(kind: .fragmented, tone: .caution),
            ],
            hasBaseline: true)
        let cands = TodayInsightsBuilder.sleepStageCandidates(report)
        XCTAssertEqual(cands.map { $0.kind },
                       ["sleepStages.deepAboveUsual", "sleepStages.fragmented"])
        XCTAssertEqual(cands[0].tone, .positive)
        XCTAssertEqual(cands[0].magnitude, min(1, 30.0 / 45.0), accuracy: 1e-9)
        XCTAssertEqual(cands[1].tone, .caution)
        XCTAssertEqual(cands[1].magnitude, 0.6, accuracy: 1e-9)   // non-comparative fragmented prior
        XCTAssertTrue(cands.allSatisfy { $0.domain == .sleepStages })
    }

    // MARK: Sleep timing

    func testTimingUnreadableEmitsNothing() {
        XCTAssertNil(TodayInsightsBuilder.sleepTimingCandidate(.unreadable(nightCount: 2)))
    }

    func testTimingIrregularIsCaution() {
        let r = SleepRegularityResult(score: 40, label: .irregular, confidence: .building,
                                      midpointSDMinutes: 130, onsetSDMinutes: nil, wakeSDMinutes: nil,
                                      meanMidpointMinOfDay: 200, resultantLength: 0.5, nightCount: 8)
        let c = TodayInsightsBuilder.sleepTimingCandidate(r)
        XCTAssertEqual(c?.kind, "sleepTiming.irregular")
        XCTAssertEqual(c?.tone, .caution)
        XCTAssertEqual(c?.magnitude ?? 0, 0.6, accuracy: 1e-9)
    }

    func testTimingVeryRegularSolidGetsConfidenceBoost() {
        let r = SleepRegularityResult(score: 92, label: .veryRegular, confidence: .solid,
                                      midpointSDMinutes: 18, onsetSDMinutes: 20, wakeSDMinutes: 22,
                                      meanMidpointMinOfDay: 200, resultantLength: 0.98, nightCount: 10)
        let c = TodayInsightsBuilder.sleepTimingCandidate(r)
        XCTAssertEqual(c?.tone, .positive)
        XCTAssertEqual(c?.magnitude ?? 0, 0.6, accuracy: 1e-9)   // 0.5 + 0.1 solid boost
    }

    // MARK: Assemble

    /// A low-recovery morning leads with the recovery caution, ahead of a positive timing win.
    func testBuildRanksCautionRecoveryFirst() {
        let recovery = TodayInsightsBuilder.RecoverySignal(score: 30, band: .strained)
        let timing = SleepRegularityResult(score: 90, label: .veryRegular, confidence: .solid,
                                           midpointSDMinutes: 18, onsetSDMinutes: 20, wakeSDMinutes: 22,
                                           meanMidpointMinOfDay: 200, resultantLength: 0.98, nightCount: 9)
        let ranked = TodayInsightsBuilder.build(recovery: recovery, sleepStages: nil, sleepTiming: timing)
        XCTAssertEqual(ranked.headline?.kind, "recovery.strained")
        XCTAssertEqual(ranked.dayTone, .caution)
        XCTAssertEqual(ranked.attentionCount, 1)
    }

    /// With nothing but wins, the day tone is positive and the strongest win leads.
    func testBuildAllWins() {
        let recovery = TodayInsightsBuilder.RecoverySignal(score: 88, band: .primed)   // mag 0.76
        let timing = SleepRegularityResult(score: 80, label: .regular, confidence: .building,
                                           midpointSDMinutes: 40, onsetSDMinutes: nil, wakeSDMinutes: nil,
                                           meanMidpointMinOfDay: 200, resultantLength: 0.9, nightCount: 7)
        let ranked = TodayInsightsBuilder.build(recovery: recovery, sleepStages: nil, sleepTiming: timing)
        XCTAssertEqual(ranked.headline?.kind, "recovery.primed")
        XCTAssertEqual(ranked.dayTone, .positive)
        XCTAssertEqual(ranked.attentionCount, 0)
    }

    func testBuildEmptyWhenAllNil() {
        let ranked = TodayInsightsBuilder.build(recovery: nil, sleepStages: nil, sleepTiming: nil)
        XCTAssertTrue(ranked.insights.isEmpty)
        XCTAssertNil(ranked.headline)
    }
}
