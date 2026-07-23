import XCTest
@testable import StrandAnalytics

final class HomeFocusResolverTests: XCTestCase {

    private func di(_ kind: String, _ domain: DailyInsight.Domain, _ tone: DailyInsight.Tone,
                    _ mag: Double) -> DailyInsight {
        DailyInsight(kind: kind, domain: domain, tone: tone, magnitude: mag)
    }

    // MARK: Attention days — the loudest caution leads

    func testCautionRecoveryLeadsAsAttention() {
        let ranked = DailyInsightsEngine.rank([
            di("recovery.strained", .recovery, .caution, 0.6),
            di("sleepStages.deepAboveUsual", .sleepStages, .positive, 0.5),
        ])
        let r = HomeFocusResolver.resolve(ranked: ranked)
        XCTAssertEqual(r.domain, .recovery)
        XCTAssertEqual(r.mode, .attention)
        XCTAssertFalse(r.supporting.contains(.recovery))
        XCTAssertEqual(r.supporting.first, .sleep)   // the positive sleep insight is present but demoted
    }

    func testCautionSleepLeads() {
        let ranked = DailyInsightsEngine.rank([
            di("sleepStages.fragmented", .sleepStages, .caution, 0.6),
            di("recovery.balanced", .recovery, .neutral, 0.1),
        ])
        let r = HomeFocusResolver.resolve(ranked: ranked)
        XCTAssertEqual(r.domain, .sleep)
        XCTAssertEqual(r.mode, .attention)
    }

    func testVitalsCautionMapsToRecoveryHero() {
        let ranked = DailyInsightsEngine.rank([di("vitals.rhrUp", .vitals, .caution, 0.5)])
        XCTAssertEqual(HomeFocusResolver.resolve(ranked: ranked).domain, .recovery)
    }

    // MARK: Standout training load

    func testStrainStandoutLeadsWhenNoCaution() {
        let ranked = DailyInsightsEngine.rank([di("recovery.primed", .recovery, .positive, 0.4)])
        let r = HomeFocusResolver.resolve(ranked: ranked, strainStandout: true)
        XCTAssertEqual(r.domain, .strain)
        XCTAssertEqual(r.mode, .attention)
    }

    func testCautionStillBeatsStrainStandout() {
        let ranked = DailyInsightsEngine.rank([di("sleepStages.fragmented", .sleepStages, .caution, 0.6)])
        let r = HomeFocusResolver.resolve(ranked: ranked, strainStandout: true)
        XCTAssertEqual(r.domain, .sleep)   // a real caution outranks a hard-load day
        XCTAssertEqual(r.supporting.first, .strain)  // but the load stays front-of-queue in support
    }

    // MARK: Optimization days

    func testStronglyPrimedRecoveryLeadsAsOptimization() {
        let ranked = DailyInsightsEngine.rank([di("recovery.primed", .recovery, .positive, 0.8)])
        let r = HomeFocusResolver.resolve(ranked: ranked)
        XCTAssertEqual(r.domain, .recovery)
        XCTAssertEqual(r.mode, .optimization)
    }

    func testWeakPrimedFallsThroughToTrends() {
        // A positive but not-strong recovery read does not seize the hero; the calm day goes to Trends.
        let ranked = DailyInsightsEngine.rank([di("recovery.primed", .recovery, .positive, 0.3)])
        let r = HomeFocusResolver.resolve(ranked: ranked)
        XCTAssertEqual(r.domain, .trends)
        XCTAssertEqual(r.mode, .optimization)
    }

    func testEmptyFeedIsTrendsOptimization() {
        let r = HomeFocusResolver.resolve(ranked: DailyInsightsEngine.rank([]))
        XCTAssertEqual(r.domain, .trends)
        XCTAssertEqual(r.mode, .optimization)
        // Trends is the hero, so the other three are the support, in stable order.
        XCTAssertEqual(r.supporting, [.recovery, .sleep, .strain])
    }

    // MARK: Support ordering

    func testSupportingNeverContainsFocusAndIsDeduped() {
        let ranked = DailyInsightsEngine.rank([
            di("recovery.strained", .recovery, .caution, 0.6),
            di("sleepTiming.irregular", .sleepTiming, .caution, 0.5),
        ])
        let r = HomeFocusResolver.resolve(ranked: ranked)
        XCTAssertEqual(r.domain, .recovery)
        XCTAssertFalse(r.supporting.contains(.recovery))
        XCTAssertEqual(r.supporting, [.sleep, .strain, .trends])  // sleep bubbled up (caution), then default
        XCTAssertEqual(Set(r.supporting).count, r.supporting.count)
    }
}
