import XCTest
@testable import StrandAnalytics

final class AchievementsTests: XCTestCase {

    func testNothingEarnedYet() {
        let r = Achievements.evaluate(scheduleBest: 0, restedBest: 0, recoveryBest: 0,
                                      peakRecovery: 0, daysTracked: 0)
        XCTAssertEqual(r.earnedCount, 0)
        XCTAssertTrue(r.earned.isEmpty)
        // Every category still offers a first target.
        XCTAssertEqual(r.nextUp.count, 5)
        XCTAssertEqual(r.totalCount, Achievements.streakTiers.count * 3
                       + Achievements.peakTiers.count + Achievements.trackedTiers.count)
    }

    func testEarnedTiersUpToBest() {
        // A 34-night steady-schedule best earns 7, 14, 30 (not 60/100); next up is 60.
        let r = Achievements.evaluate(scheduleBest: 34, restedBest: 0, recoveryBest: 0,
                                      peakRecovery: 0, daysTracked: 0)
        let sched = r.earned.filter { $0.category == "steadySchedule" }.map { $0.tier }.sorted()
        XCTAssertEqual(sched, [7, 14, 30])
        let next = r.nextUp.first { $0.category == "steadySchedule" }
        XCTAssertEqual(next?.tier, 60)
        XCTAssertEqual(next?.progress ?? 0, 34.0 / 60.0, accuracy: 1e-9)
    }

    func testPeakAndTrackedCategories() {
        let r = Achievements.evaluate(scheduleBest: 0, restedBest: 0, recoveryBest: 0,
                                      peakRecovery: 92, daysTracked: 40)
        XCTAssertEqual(r.earned.filter { $0.category == "peak" }.map { $0.tier }.sorted(), [85, 90])
        XCTAssertEqual(r.earned.filter { $0.category == "tracked" }.map { $0.tier }.sorted(), [7, 30])
        XCTAssertEqual(r.nextUp.first { $0.category == "peak" }?.tier, 95)
    }

    func testEarnedRankedByTierDescending() {
        let r = Achievements.evaluate(scheduleBest: 100, restedBest: 7, recoveryBest: 0,
                                      peakRecovery: 0, daysTracked: 0)
        // The 100-night schedule badge is the most impressive → first.
        XCTAssertEqual(r.earned.first?.category, "steadySchedule")
        XCTAssertEqual(r.earned.first?.tier, 100)
    }

    func testAllEarnedHasNoNextUpForMaxedCategory() {
        let r = Achievements.evaluate(scheduleBest: 100, restedBest: 100, recoveryBest: 100,
                                      peakRecovery: 100, daysTracked: 365)
        XCTAssertTrue(r.nextUp.isEmpty)                 // everything maxed
        XCTAssertEqual(r.earnedCount, r.totalCount)
    }

    func testNextUpSortedByProgress() {
        // schedule 6/7 (0.857) should rank ahead of tracked 1/7 (0.143).
        let r = Achievements.evaluate(scheduleBest: 6, restedBest: 0, recoveryBest: 0,
                                      peakRecovery: 0, daysTracked: 1)
        XCTAssertEqual(r.nextUp.first?.category, "steadySchedule")
    }
}
