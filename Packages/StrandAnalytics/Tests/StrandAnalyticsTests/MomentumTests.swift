import XCTest
@testable import StrandAnalytics

final class MomentumTests: XCTestCase {

    private func s(_ kind: HealthStreaks.Kind, _ current: Int, _ best: Int) -> Momentum.Streak {
        Momentum.Streak(kind: kind, current: current, best: best)
    }

    func testEmptyHasNoActiveStreak() {
        let m = Momentum.summarize([])
        XCTAssertNil(m.featuredKind)
        XCTAssertFalse(m.hasActiveStreak)
        XCTAssertEqual(m.intensity, 0)
        XCTAssertEqual(m.nextMilestone, 3)   // the first rung is still the target
    }

    func testAllZeroStillReportsBestEver() {
        let m = Momentum.summarize([s(.restedNights, 0, 9), s(.recoveryReady, 0, 4)])
        XCTAssertNil(m.featuredKind)
        XCTAssertEqual(m.best, 9)
        XCTAssertFalse(m.hasActiveStreak)
    }

    func testFeaturesStrongestActiveRun() {
        let m = Momentum.summarize([
            s(.steadySchedule, 5, 9),
            s(.recoveryReady, 12, 12),
            s(.restedNights, 3, 6),
        ])
        XCTAssertEqual(m.featuredKind, .recoveryReady)
        XCTAssertEqual(m.current, 12)
        XCTAssertEqual(m.nextMilestone, 14)
        XCTAssertEqual(m.daysToNext, 2)
        XCTAssertEqual(m.prevMilestone, 7)
        XCTAssertTrue(m.isRecord)            // 12 >= best 12
    }

    func testTieBreaksByBest() {
        let m = Momentum.summarize([s(.steadySchedule, 6, 6), s(.restedNights, 6, 20)])
        XCTAssertEqual(m.featuredKind, .restedNights)  // same current, larger all-time best
    }

    func testNotRecordWhenBelowBest() {
        let m = Momentum.summarize([s(.steadySchedule, 5, 9)])
        XCTAssertFalse(m.isRecord)
        XCTAssertEqual(m.nextMilestone, 7)
        XCTAssertEqual(m.daysToNext, 2)
        XCTAssertEqual(m.prevMilestone, 3)
    }

    func testBeyondLadderTop() {
        let m = Momentum.summarize([s(.recoveryReady, 400, 400)])
        XCTAssertNil(m.nextMilestone)
        XCTAssertNil(m.daysToNext)
        XCTAssertEqual(m.prevMilestone, 365)
        XCTAssertEqual(m.intensity, 1, accuracy: 1e-9)   // capped
    }

    func testIntensityGrows() {
        let low = Momentum.summarize([s(.restedNights, 1, 1)]).intensity
        let mid = Momentum.summarize([s(.restedNights, 15, 15)]).intensity
        let full = Momentum.summarize([s(.restedNights, 30, 30)]).intensity
        XCTAssertLessThan(low, mid)
        XCTAssertLessThan(mid, full)
        XCTAssertEqual(full, 1, accuracy: 1e-9)
    }
}
