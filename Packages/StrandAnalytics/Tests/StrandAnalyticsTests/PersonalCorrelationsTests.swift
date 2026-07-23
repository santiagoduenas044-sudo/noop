import XCTest
@testable import StrandAnalytics

final class PersonalCorrelationsTests: XCTestCase {

    private let days = (0..<16).map { String(format: "d%02d", $0) }
    private let tvals: [Double] = [50, 55, 48, 60, 52, 58, 49, 62, 54, 57, 51, 63, 55, 59, 53, 61]

    private func series(_ f: (Double) -> Double, count: Int? = nil) -> [(day: String, value: Double)] {
        let n = count ?? days.count
        return (0..<n).map { (day: days[$0], value: f(tvals[$0])) }
    }
    private var target: [(day: String, value: Double)] { series { $0 } }

    func testStrengthBuckets() {
        XCTAssertEqual(PersonalCorrelations.strength(0.6), .strong)
        XCTAssertEqual(PersonalCorrelations.strength(0.4), .clear)
        XCTAssertEqual(PersonalCorrelations.strength(0.2), .mild)
    }

    func testPerfectPositiveAndNegative() {
        let report = PersonalCorrelations.analyze(target: target, factors: [
            ("pos", series { $0 }),          // r = +1
            ("neg", series { 100 - $0 }),    // r = -1
        ])
        XCTAssertEqual(report.factors.count, 2)
        XCTAssertTrue(report.hasEnough)
        let pos = report.factors.first { $0.key == "pos" }
        let neg = report.factors.first { $0.key == "neg" }
        XCTAssertEqual(pos?.direction, .positive)
        XCTAssertEqual(pos?.strength, .strong)
        XCTAssertEqual(neg?.direction, .negative)
        XCTAssertEqual(neg?.n, 16)
    }

    func testConstantFactorExcluded() {
        // Zero variance → pearson undefined → dropped (never a fake correlation).
        let report = PersonalCorrelations.analyze(target: target, factors: [("flat", series { _ in 5 })])
        XCTAssertTrue(report.factors.isEmpty)
    }

    func testTooFewOverlappingDaysExcluded() {
        // Only 5 aligned days < minN.
        let report = PersonalCorrelations.analyze(target: target,
                                                  factors: [("short", series({ $0 }, count: 5))])
        XCTAssertTrue(report.factors.isEmpty)
    }

    func testRankedByAbsoluteRAndCapped() {
        // Build factors with descending |r|; cap at maxFactors (3).
        let strong = series { $0 }                                   // r ≈ 1
        let mixed = series { 0.6 * $0 + Double(Int($0) % 3) * 4 }     // weaker but real
        let report = PersonalCorrelations.analyze(target: target, factors: [
            ("weak", mixed), ("strong", strong), ("neg", series { 100 - $0 }),
            ("also", series { $0 * 0.9 + 2 }),
        ], maxFactors: 3)
        XCTAssertLessThanOrEqual(report.factors.count, 3)
        // Strongest first.
        XCTAssertGreaterThanOrEqual(abs(report.factors[0].r), abs(report.factors.last!.r))
    }

    func testEmptyFactors() {
        XCTAssertFalse(PersonalCorrelations.analyze(target: target, factors: []).hasEnough)
    }
}
