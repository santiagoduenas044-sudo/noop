import XCTest
@testable import StrandAnalytics

final class StreakEngineTests: XCTestCase {

    private func flags(_ pattern: [Bool]) -> [StreakEngine.DayFlag] {
        pattern.enumerated().map { StreakEngine.DayFlag(day: "d\($0.offset)", met: $0.element) }
    }

    func testEmpty() {
        let r = StreakEngine.assess(days: [])
        XCTAssertEqual(r, StreakEngine.Result(current: 0, best: 0, metCount: 0, total: 0, atRisk: 0))
    }

    func testAllMet() {
        let r = StreakEngine.assess(days: flags([true, true, true, true]))
        XCTAssertEqual(r.current, 4)
        XCTAssertEqual(r.best, 4)
        XCTAssertEqual(r.metCount, 4)
        XCTAssertEqual(r.atRisk, 0)
        XCTAssertTrue(r.isActive)
    }

    func testTrailingRunAfterBreak() {
        // T T F T T T  → current 3, best 3, met 5
        let r = StreakEngine.assess(days: flags([true, true, false, true, true, true]))
        XCTAssertEqual(r.current, 3)
        XCTAssertEqual(r.best, 3)
        XCTAssertEqual(r.metCount, 5)
        XCTAssertEqual(r.atRisk, 0)
    }

    func testBestFromEarlierRun() {
        // T T T T F T T → current 2, best 4
        let r = StreakEngine.assess(days: flags([true, true, true, true, false, true, true]))
        XCTAssertEqual(r.current, 2)
        XCTAssertEqual(r.best, 4)
    }

    func testAtRiskWhenLatestNotMet() {
        // T T T F → current 0, best 3, atRisk 3 (do it today to save the streak)
        let r = StreakEngine.assess(days: flags([true, true, true, false]))
        XCTAssertEqual(r.current, 0)
        XCTAssertEqual(r.best, 3)
        XCTAssertEqual(r.atRisk, 3)
        XCTAssertFalse(r.isActive)
    }

    func testNoAtRiskWhenLatestMet() {
        let r = StreakEngine.assess(days: flags([false, true, true]))
        XCTAssertEqual(r.current, 2)
        XCTAssertEqual(r.atRisk, 0)
    }

    func testGapResetsRun() {
        let r = StreakEngine.assess(days: flags([true, true, false, false, true]))
        XCTAssertEqual(r.current, 1)
        XCTAssertEqual(r.best, 2)
    }
}
