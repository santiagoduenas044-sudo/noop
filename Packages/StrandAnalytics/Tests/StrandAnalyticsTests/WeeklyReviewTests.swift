import XCTest
@testable import StrandAnalytics

final class WeeklyReviewTests: XCTestCase {

    private func stats(charge: Double? = nil, sleep: Double? = nil, effort: Double? = nil,
                       sd: Double? = nil, days: Int = 7, total: Int = 7) -> WeeklyReview.WeekStats {
        .init(avgCharge: charge, avgSleepHours: sleep, avgEffort: effort, scheduleSDMin: sd,
              daysWithData: days, totalDays: total)
    }

    func testInsufficientData() {
        let r = WeeklyReview.build(this: stats(charge: 70, days: 2), prior: stats(charge: 68))
        XCTAssertFalse(r.hasEnoughData)
    }

    func testCleanWeekIsAllWins() {
        let r = WeeklyReview.build(this: stats(charge: 72, sleep: 7.5), prior: stats(charge: 63, sleep: 6.5))
        XCTAssertEqual(r.wins.map { $0.kind }, [.recoveryUp, .sleptMore])   // ranked by magnitude
        XCTAssertTrue(r.setbacks.isEmpty)
        XCTAssertEqual(r.headline?.kind, .recoveryUp)
        XCTAssertEqual(r.recommendation, "rec.keepGoing")
        XCTAssertEqual(r.completeness, 1.0, accuracy: 1e-9)
    }

    func testRecoveryDownDrivesRecommendation() {
        let r = WeeklyReview.build(this: stats(charge: 55), prior: stats(charge: 68))
        XCTAssertEqual(r.setbacks.map { $0.kind }, [.recoveryDown])
        XCTAssertEqual(r.headline?.kind, .recoveryDown)
        XCTAssertEqual(r.recommendation, "rec.protectRecovery")
        XCTAssertEqual(r.setbacks.first?.delta ?? 0, -13, accuracy: 1e-9)
    }

    func testSleptLessRecommendation() {
        let r = WeeklyReview.build(this: stats(sleep: 6.0), prior: stats(sleep: 7.2))
        XCTAssertEqual(r.setbacks.map { $0.kind }, [.sleptLess])
        XCTAssertEqual(r.recommendation, "rec.prioritizeSleep")
    }

    func testSteadyScheduleIsWin() {
        let r = WeeklyReview.build(this: stats(sd: 30), prior: stats())
        XCTAssertEqual(r.wins.map { $0.kind }, [.steadySchedule])
    }

    func testDriftingScheduleRecommendation() {
        let r = WeeklyReview.build(this: stats(sd: 110), prior: stats())
        XCTAssertEqual(r.setbacks.map { $0.kind }, [.driftingSchedule])
        XCTAssertEqual(r.recommendation, "rec.steadyBedtime")
    }

    func testBelowThresholdProducesNoFindings() {
        let r = WeeklyReview.build(this: stats(charge: 70, sleep: 7.1), prior: stats(charge: 68, sleep: 6.9))
        XCTAssertTrue(r.wins.isEmpty)
        XCTAssertTrue(r.setbacks.isEmpty)
        XCTAssertNil(r.headline)
        XCTAssertEqual(r.recommendation, "rec.keepGoing")
    }

    func testTrainingLoadIsNeutralNotAWin() {
        let r = WeeklyReview.build(this: stats(effort: 60), prior: stats(effort: 48))
        XCTAssertEqual(r.neutrals.map { $0.kind }, [.trainedMore])
        XCTAssertTrue(r.wins.isEmpty)
        XCTAssertTrue(r.setbacks.isEmpty)
    }

    func testHeadlineIsBiggestMoverAcrossWinsAndSetbacks() {
        // Recovery down (|13| → 0.87) should headline over slept-more (+1 h → 0.5).
        let r = WeeklyReview.build(this: stats(charge: 55, sleep: 7.5), prior: stats(charge: 68, sleep: 6.5))
        XCTAssertEqual(r.headline?.kind, .recoveryDown)
        XCTAssertEqual(r.wins.map { $0.kind }, [.sleptMore])
        XCTAssertEqual(r.setbacks.map { $0.kind }, [.recoveryDown])
    }
}
