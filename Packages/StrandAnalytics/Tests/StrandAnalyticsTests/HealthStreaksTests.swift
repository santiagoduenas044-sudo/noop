import XCTest
@testable import StrandAnalytics

final class HealthStreaksTests: XCTestCase {

    private func days(_ n: Int) -> [String] { (0..<n).map { "d\($0)" } }

    // MARK: Rested nights

    func testRestedTargetAdaptsToPersonalMedian() {
        // Typical 8 h (480) → target 480 - 30 grace = 450.
        XCTAssertEqual(HealthStreaks.restedTargetMin(Array(repeating: 480, count: 10)), 450, accuracy: 1e-9)
    }

    func testRestedTargetClamped() {
        // A very short sleeper still isn't asked for less than the 6 h floor.
        XCTAssertEqual(HealthStreaks.restedTargetMin(Array(repeating: 300, count: 5)),
                       HealthStreaks.restedFloorMin, accuracy: 1e-9)
    }

    func testRestedFlags() {
        // median 480 → target 450. Nights: 470 (met), 400 (miss), 460 (met).
        let f = HealthStreaks.restedFlags(days: days(3), asleepMins: [480, 480, 480].map { _ in 480 })
        XCTAssertTrue(f.allSatisfy { $0.met })
        let g = HealthStreaks.restedFlags(days: days(3), asleepMins: [470, 400, 460])
        // median of [470,400,460] = 460 → target 430; 470✓ 400✗ 460✓
        XCTAssertEqual(g.map { $0.met }, [true, false, true])
    }

    // MARK: Recovery ready

    func testRecoveryFloorAdaptive() {
        // median 60 → floor 60 - 12 = 48.
        XCTAssertEqual(HealthStreaks.recoveryFloor(Array(repeating: 60, count: 8)), 48, accuracy: 1e-9)
    }

    func testRecoveryFlags() {
        // median([70,40,66,52]) = 59 → floor 47; 70✓ 40✗ 66✓ 52✓
        let f = HealthStreaks.recoveryFlags(days: days(4), recoveries: [70, 40, 66, 52])
        XCTAssertEqual(f.map { $0.met }, [true, false, true, true])
    }

    // MARK: Steady schedule

    func testSteadyBaselineNightsAreNotMet() {
        // First `scheduleMinBaseline` nights have nothing to compare to.
        let mids = Array(repeating: 180.0, count: 6)   // perfectly steady
        let f = HealthStreaks.steadyFlags(days: days(6), midpointsMinOfDay: mids)
        XCTAssertEqual(f.prefix(HealthStreaks.scheduleMinBaseline).map { $0.met },
                       Array(repeating: false, count: HealthStreaks.scheduleMinBaseline))
        XCTAssertTrue(f.dropFirst(HealthStreaks.scheduleMinBaseline).allSatisfy { $0.met })
    }

    func testSteadyBreaksOnOutlier() {
        // Steady at ~180, then a night 2 h off (300) → that night misses.
        let mids: [Double] = [180, 185, 175, 182, 300, 178]
        let f = HealthStreaks.steadyFlags(days: days(6), midpointsMinOfDay: mids)
        XCTAssertTrue(f[3].met)          // within tolerance of the ~180 mean
        XCTAssertFalse(f[4].met)         // 300 is ~120 min off → miss
        XCTAssertTrue(f[5].met)          // back near the mean
    }

    func testSteadyHandlesMidnightWrap() {
        // Mean near 1430 (23:50), a night at 5 (00:05) is only 15 min away circularly → steady.
        let mids: [Double] = [1430, 1435, 1425, 5]
        let f = HealthStreaks.steadyFlags(days: days(4), midpointsMinOfDay: mids)
        XCTAssertTrue(f[3].met)
    }
}
