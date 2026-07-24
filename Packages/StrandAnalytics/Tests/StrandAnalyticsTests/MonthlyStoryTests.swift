import XCTest
@testable import StrandAnalytics

final class MonthlyStoryTests: XCTestCase {

    private func input(_ rec: [Double], sleep: [Double] = [], sd: Double? = nil,
                       days: Int? = nil, total: Int? = nil) -> MonthlyStory.Input {
        .init(recoveries: rec, sleepHours: sleep, scheduleSDMin: sd,
              daysWithData: days ?? rec.count, totalDays: total ?? rec.count)
    }

    func testOlsSlopeOnLinearSeries() {
        // 0,2,4,6,8 → slope 2 per step.
        XCTAssertEqual(MonthlyStory.olsSlope([0, 2, 4, 6, 8]), 2, accuracy: 1e-9)
        XCTAssertEqual(MonthlyStory.olsSlope([5, 5, 5]), 0, accuracy: 1e-9)   // flat
    }

    func testImprovingMonth() {
        let rec = (0..<28).map { 50 + Double($0) }   // +1/day → +7/week
        let s = MonthlyStory.build(input(rec))
        XCTAssertTrue(s.hasEnough)
        XCTAssertEqual(s.trend, .improving)
        XCTAssertEqual(s.recoverySlopePerWeek, 7.0, accuracy: 1e-9)
        XCTAssertEqual(s.avgRecovery, 64)   // mean of 50..77 = 63.5 → 64
    }

    func testDecliningMonth() {
        let rec = (0..<28).map { 80 - Double($0) }
        XCTAssertEqual(MonthlyStory.build(input(rec)).trend, .declining)
    }

    func testSteadyMonth() {
        let rec = Array(repeating: 65.0, count: 28)
        let s = MonthlyStory.build(input(rec))
        XCTAssertEqual(s.trend, .steady)
        XCTAssertEqual(s.recoverySlopePerWeek, 0, accuracy: 1e-9)
    }

    func testInsufficientDataIsUnknown() {
        let rec = (0..<10).map { 60 + Double($0) }   // < minDaysWithData
        let s = MonthlyStory.build(input(rec))
        XCTAssertFalse(s.hasEnough)
        XCTAssertEqual(s.trend, .unknown)
    }

    func testScheduleConsistencyAndSleepAverage() {
        let rec = Array(repeating: 65.0, count: 20)
        let sleep = Array(repeating: 7.4, count: 20)
        let consistent = MonthlyStory.build(input(rec, sleep: sleep, sd: 40))
        XCTAssertTrue(consistent.consistentSchedule)
        XCTAssertEqual(consistent.avgSleepHours, 7.4, accuracy: 1e-9)

        let drifting = MonthlyStory.build(input(rec, sleep: sleep, sd: 95))
        XCTAssertFalse(drifting.consistentSchedule)
    }

    func testCompleteness() {
        let rec = Array(repeating: 65.0, count: 20)
        let s = MonthlyStory.build(input(rec, days: 20, total: 28))
        XCTAssertEqual(s.completeness, 20.0 / 28.0, accuracy: 1e-9)
    }
}
