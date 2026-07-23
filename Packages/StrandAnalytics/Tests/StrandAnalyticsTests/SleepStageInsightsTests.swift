import XCTest
@testable import StrandAnalytics

/// Tests for the sleep-stage composition + insights engine. Kotlin parity:
/// SleepStageInsightsTest.kt asserts the same vectors.
final class SleepStageInsightsTests: XCTestCase {

    private func m(awake: Double, light: Double, deep: Double, rem: Double) -> SleepStageTotals.Minutes {
        SleepStageTotals.Minutes(awake: awake, light: light, deep: deep, rem: rem)
    }
    private func kinds(_ r: SleepStageInsights.Report) -> [SleepStageInsights.Kind] { r.insights.map { $0.kind } }

    // MARK: - Composition

    func testCompositionFractionsAndShares() {
        let c = SleepStageInsights.composition(m(awake: 20, light: 240, deep: 110, rem: 110))
        XCTAssertEqual(c.inBedMin, 480, accuracy: 1e-9)
        XCTAssertEqual(c.asleepMin, 460, accuracy: 1e-9)
        XCTAssertEqual(c.efficiency, 0.958, accuracy: 1e-3)        // 460/480
        XCTAssertEqual(c.restorativeShare, 0.478, accuracy: 1e-3)  // 220/460
        // fractions are of in-bed and (with awake) sum to ~1
        let sum = c.awakeFrac + c.lightFrac + c.deepFrac + c.remFrac
        XCTAssertEqual(sum, 1.0, accuracy: 2e-3)
    }

    func testCompositionEmptyNightIsSafe() {
        let c = SleepStageInsights.composition(m(awake: 0, light: 0, deep: 0, rem: 0))
        XCTAssertEqual(c.efficiency, 0)
        XCTAssertEqual(c.restorativeShare, 0)
        XCTAssertEqual(c.deepFrac, 0)
    }

    // MARK: - Non-comparative insights

    func testEfficientAndRestorativeStrong() {
        let r = SleepStageInsights.analyze(tonight: m(awake: 20, light: 240, deep: 110, rem: 110), baseline: [])
        XCTAssertTrue(kinds(r).contains(.efficientNight))
        XCTAssertTrue(kinds(r).contains(.restorativeStrong))
    }

    func testFragmentedNight() {
        let r = SleepStageInsights.analyze(tonight: m(awake: 100, light: 240, deep: 80, rem: 60), baseline: [])
        XCTAssertTrue(kinds(r).contains(.fragmented))
        // fragmentation is a caution, so it ranks first
        XCTAssertEqual(r.insights.first?.tone, .caution)
    }

    func testRestorativeLight() {
        let r = SleepStageInsights.analyze(tonight: m(awake: 30, light: 350, deep: 30, rem: 20), baseline: [])
        XCTAssertTrue(kinds(r).contains(.restorativeLight))
    }

    // MARK: - Comparative (needs baseline)

    private func steadyBaseline(deep: Double, rem: Double, count: Int = 6) -> [SleepStageTotals.Minutes] {
        (0..<count).map { _ in m(awake: 25, light: 245, deep: deep, rem: rem) }
    }

    func testDeepBelowUsualEmitsNegativeDelta() {
        // baseline deep median 100; tonight deep 60 → −40, clears both gates.
        let r = SleepStageInsights.analyze(tonight: m(awake: 25, light: 300, deep: 60, rem: 95),
                                           baseline: steadyBaseline(deep: 100, rem: 95))
        let deep = r.insights.first { $0.kind == .deepBelowUsual }
        XCTAssertNotNil(deep)
        XCTAssertEqual(deep?.tone, .caution)
        XCTAssertEqual(deep?.deltaMin, -40)
        XCTAssertTrue(r.hasBaseline)
    }

    func testDeepAboveUsualIsPositive() {
        let r = SleepStageInsights.analyze(tonight: m(awake: 25, light: 245, deep: 140, rem: 95),
                                           baseline: steadyBaseline(deep: 100, rem: 95))
        XCTAssertTrue(kinds(r).contains(.deepAboveUsual))
        XCTAssertEqual(r.insights.first { $0.kind == .deepAboveUsual }?.tone, .positive)
    }

    func testSmallDeltaIsNotNotable() {
        // baseline deep 100, tonight 108 → +8 min, 8% — fails both gates → no deep insight.
        let r = SleepStageInsights.analyze(tonight: m(awake: 25, light: 245, deep: 108, rem: 95),
                                           baseline: steadyBaseline(deep: 100, rem: 95))
        XCTAssertFalse(kinds(r).contains(.deepAboveUsual))
        XCTAssertFalse(kinds(r).contains(.deepBelowUsual))
    }

    func testWithheldUntilBaseline() {
        // Only 3 baseline nights (< minBaselineNights) → no comparative, a "building" note present.
        let r = SleepStageInsights.analyze(tonight: m(awake: 25, light: 245, deep: 60, rem: 95),
                                           baseline: steadyBaseline(deep: 100, rem: 95, count: 3))
        XCTAssertFalse(r.hasBaseline)
        XCTAssertFalse(kinds(r).contains(.deepBelowUsual))
        XCTAssertTrue(kinds(r).contains(.buildingBaseline))
    }

    func testBalancedNightWhenNothingStandsOut() {
        // Mid efficiency (0.878 — between fragmented 0.82 and efficient 0.90), mid restorative, deep/rem
        // on baseline → nothing notable, so the single insight is the reassuring "balanced night".
        let mid = m(awake: 60, light: 250, deep: 95, rem: 85)     // asleep 430 / in-bed 490
        let r = SleepStageInsights.analyze(tonight: mid, baseline: steadyBaseline(deep: 95, rem: 85))
        XCTAssertEqual(kinds(r), [.balancedNight])
    }

    func testInsightsCappedAndCautionFirst() {
        // Fragmented (caution) + deep below (caution) + rem below (caution) → capped at maxInsights, all caution.
        let r = SleepStageInsights.analyze(tonight: m(awake: 120, light: 250, deep: 50, rem: 40),
                                           baseline: steadyBaseline(deep: 100, rem: 95))
        XCTAssertLessThanOrEqual(r.insights.count, SleepStageInsights.maxInsights)
        XCTAssertEqual(r.insights.first?.tone, .caution)
    }

    func testEmptyNightBuildsBaseline() {
        let r = SleepStageInsights.analyze(tonight: m(awake: 0, light: 0, deep: 0, rem: 0), baseline: [])
        XCTAssertEqual(kinds(r), [.buildingBaseline])
    }

    func testMedianIsRobust() {
        XCTAssertEqual(SleepStageInsights.median([90, 100, 100, 100, 100, 110]), 100, accuracy: 1e-9)
        XCTAssertEqual(SleepStageInsights.median([10, 20, 30]), 20, accuracy: 1e-9)
        XCTAssertEqual(SleepStageInsights.median([]), 0, accuracy: 1e-9)
    }
}
