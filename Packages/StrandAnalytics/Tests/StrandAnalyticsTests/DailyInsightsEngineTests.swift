import XCTest
@testable import StrandAnalytics

final class DailyInsightsEngineTests: XCTestCase {

    private func di(_ kind: String, _ domain: DailyInsight.Domain, _ tone: DailyInsight.Tone,
                    _ mag: Double) -> DailyInsight {
        DailyInsight(kind: kind, domain: domain, tone: tone, magnitude: mag)
    }

    func testMagnitudeClamped() {
        XCTAssertEqual(di("k", .recovery, .positive, 1.5).magnitude, 1.0)
        XCTAssertEqual(di("k", .recovery, .positive, -1).magnitude, 0.0)
    }

    /// A caution outranks a positive of equal magnitude (attention-worthy leads).
    func testCautionBeatsEqualPositive() {
        let caution = di("a", .recovery, .caution, 0.3)
        let positive = di("b", .sleep, .positive, 0.3)
        XCTAssertGreaterThan(DailyInsightsEngine.score(caution), DailyInsightsEngine.score(positive))
        let r = DailyInsightsEngine.rank([positive, caution])
        XCTAssertEqual(r.headline?.kind, "a")
    }

    /// …but a very strong positive can still lead a trivial caution.
    func testStrongPositiveBeatsWeakCaution() {
        let strongPos = di("win", .recovery, .positive, 0.9)   // score 0.9
        let weakCaution = di("nit", .vitals, .caution, 0.1)    // score 0.45
        let r = DailyInsightsEngine.rank([weakCaution, strongPos])
        XCTAssertEqual(r.headline?.kind, "win")
    }

    /// A real caution still leads a strong positive.
    func testRealCautionLeadsStrongPositive() {
        let caution = di("c", .recovery, .caution, 0.7)   // 1.05
        let pos = di("p", .sleep, .positive, 0.9)         // 0.9
        XCTAssertEqual(DailyInsightsEngine.rank([pos, caution]).headline?.kind, "c")
    }

    func testDedupKeepsStrongest() {
        let weak = di("dup", .sleep, .caution, 0.2)
        let strong = di("dup", .sleep, .caution, 0.6)
        let r = DailyInsightsEngine.rank([weak, strong])
        XCTAssertEqual(r.insights.count, 1)
        XCTAssertEqual(r.insights.first!.magnitude, 0.6, accuracy: 1e-9)
    }

    func testCap() {
        let cands = (0..<7).map { di("k\($0)", .vitals, .caution, Double($0) / 7.0) }
        XCTAssertEqual(DailyInsightsEngine.rank(cands, max: 3).insights.count, 3)
    }

    func testAttentionCountAndDayTone() {
        let r = DailyInsightsEngine.rank([
            di("a", .recovery, .caution, 0.6),
            di("b", .sleep, .positive, 0.5),
            di("c", .vitals, .caution, 0.3),
        ])
        XCTAssertEqual(r.attentionCount, 2)
        XCTAssertEqual(r.dayTone, .caution)
    }

    func testDayTonePositiveWhenOnlyWins() {
        let r = DailyInsightsEngine.rank([
            di("a", .recovery, .positive, 0.6),
            di("b", .sleep, .positive, 0.4),
        ])
        XCTAssertEqual(r.dayTone, .positive)
        XCTAssertEqual(r.attentionCount, 0)
    }

    func testEmpty() {
        let r = DailyInsightsEngine.rank([])
        XCTAssertTrue(r.insights.isEmpty)
        XCTAssertNil(r.headline)
        XCTAssertEqual(r.dayTone, .neutral)
        XCTAssertEqual(r.attentionCount, 0)
    }

    /// Deterministic order for equal scores: magnitude, then tone, then domain order.
    func testDeterministicTiebreak() {
        // Same score (both positive, same magnitude) → domain order decides (recovery before sleep).
        let sleep = di("s", .sleep, .positive, 0.5)
        let recovery = di("r", .recovery, .positive, 0.5)
        let r = DailyInsightsEngine.rank([sleep, recovery])
        XCTAssertEqual(r.insights.map { $0.kind }, ["r", "s"])
    }
}
