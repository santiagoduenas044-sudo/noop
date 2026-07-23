import XCTest
@testable import StrandAnalytics

final class CoachAdvisorTests: XCTestCase {

    func testPrimedPushes() {
        XCTAssertEqual(CoachAdvisor.trainingVerdict(band: .primed, tomorrow: .rebound), .push)
        XCTAssertEqual(CoachAdvisor.trainingVerdict(band: .primed, tomorrow: nil), .push)
    }

    func testPrimedButTomorrowDipsCounselsMaintain() {
        // Don't dig a hole right before a downswing.
        XCTAssertEqual(CoachAdvisor.trainingVerdict(band: .primed, tomorrow: .dip), .maintain)
    }

    func testBalancedMaintains() {
        XCTAssertEqual(CoachAdvisor.trainingVerdict(band: .balanced, tomorrow: .steady), .maintain)
    }

    func testStrainedEasesIn() {
        XCTAssertEqual(CoachAdvisor.trainingVerdict(band: .strained, tomorrow: nil), .easeIn)
    }

    func testRundownRests() {
        XCTAssertEqual(CoachAdvisor.trainingVerdict(band: .rundown, tomorrow: .rebound), .rest)
    }

    func testInsufficientOrNilIsUnknown() {
        XCTAssertEqual(CoachAdvisor.trainingVerdict(band: .insufficient, tomorrow: nil), .unknown)
        XCTAssertEqual(CoachAdvisor.trainingVerdict(band: nil, tomorrow: .rebound), .unknown)
    }
}
