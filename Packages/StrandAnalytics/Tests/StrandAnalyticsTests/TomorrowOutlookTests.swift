import XCTest
@testable import StrandAnalytics

final class TomorrowOutlookTests: XCTestCase {

    private let steady10 = Array(repeating: 70.0, count: 10)   // mean 70, sd 0, flat

    func testInsufficientHistoryWithholds() {
        let o = TomorrowOutlook.build(recentCharge: Array(repeating: 70.0, count: 4),
                                      todayEffort: nil, todayCharge: 70, needHours: 8)
        XCTAssertFalse(o.hasForecast)
        XCTAssertEqual(o.direction, .unknown)
    }

    func testSteadyForecastAndBand() {
        let o = TomorrowOutlook.build(recentCharge: steady10, todayEffort: nil, todayCharge: 70,
                                      needHours: 8, needNights: 10)
        XCTAssertTrue(o.hasForecast)
        XCTAssertEqual(o.direction, .steady)
        XCTAssertEqual(o.expected, 70)
        XCTAssertEqual(o.expectedLow, 62)
        XCTAssertEqual(o.expectedHigh, 78)
        XCTAssertEqual(o.confidence, .solid)   // full baseline + informed need
    }

    func testReboundWhenTodayIsLow() {
        let o = TomorrowOutlook.build(recentCharge: steady10, todayEffort: nil, todayCharge: 60, needHours: 8)
        XCTAssertEqual(o.direction, .rebound)   // 70 >= 60 + 5
    }

    func testDipWhenTodayIsHigh() {
        let o = TomorrowOutlook.build(recentCharge: steady10, todayEffort: nil, todayCharge: 82, needHours: 8)
        XCTAssertEqual(o.direction, .dip)       // 70 <= 82 - 5
    }

    func testUnknownDirectionWithoutToday() {
        let o = TomorrowOutlook.build(recentCharge: steady10, todayEffort: nil, todayCharge: nil, needHours: 8)
        XCTAssertEqual(o.direction, .unknown)
        XCTAssertTrue(o.hasForecast)
    }

    func testSleepSwingIsCostOfAShortNight() {
        // need 6: usual night → 70; short (4h) night → ~65 → swing 5 (matters).
        let o = TomorrowOutlook.build(recentCharge: steady10, todayEffort: nil, todayCharge: 70, needHours: 6)
        XCTAssertEqual(o.expected, 70)
        XCTAssertEqual(o.ifShort, 65)
        XCTAssertEqual(o.sleepSwing, 5)
        XCTAssertTrue(o.sleepMatters)
    }

    func testSmallSwingDoesNotMatter() {
        // need 8: short (6h) night → ~67 → swing 3 (< meaningfulSwing).
        let o = TomorrowOutlook.build(recentCharge: steady10, todayEffort: nil, todayCharge: 70, needHours: 8)
        XCTAssertEqual(o.sleepSwing, 3)
        XCTAssertFalse(o.sleepMatters)
    }

    func testConfidenceBuildingOnThinNeed() {
        // Full baseline but need not informed (needNights 0) → building, not solid.
        let o = TomorrowOutlook.build(recentCharge: steady10, todayEffort: nil, todayCharge: 70,
                                      needHours: 8, needNights: 0)
        XCTAssertEqual(o.confidence, .building)
    }
}
