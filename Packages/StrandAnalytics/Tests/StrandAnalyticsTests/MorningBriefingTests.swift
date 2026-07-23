import XCTest
@testable import StrandAnalytics

final class MorningBriefingTests: XCTestCase {

    private func di(_ kind: String, _ domain: DailyInsight.Domain, _ tone: DailyInsight.Tone,
                    _ mag: Double) -> DailyInsight {
        DailyInsight(kind: kind, domain: domain, tone: tone, magnitude: mag)
    }

    func testPartOfDayBoundaries() {
        XCTAssertEqual(MorningBriefing.partOfDay(hour: 6), .morning)
        XCTAssertEqual(MorningBriefing.partOfDay(hour: 11), .morning)
        XCTAssertEqual(MorningBriefing.partOfDay(hour: 12), .afternoon)
        XCTAssertEqual(MorningBriefing.partOfDay(hour: 17), .evening)
        XCTAssertEqual(MorningBriefing.partOfDay(hour: 23), .night)
        XCTAssertEqual(MorningBriefing.partOfDay(hour: 3), .night)
    }

    /// An attention day: greeting → headline(attention/recovery) → support(sleep caution) → action → closer.
    func testAttentionDayFullArc() {
        let ranked = DailyInsightsEngine.rank([
            di("recovery.strained", .recovery, .caution, 0.7),
            di("sleepStages.fragmented", .sleepStages, .caution, 0.6),
        ])
        let focus = HomeFocusResolver.resolve(ranked: ranked)
        XCTAssertEqual(focus.domain, .recovery)
        let script = MorningBriefingPlanner.plan(part: .morning, focus: focus, ranked: ranked)

        XCTAssertEqual(script.lines.map { $0.role },
                       [.greeting, .headline, .support, .action, .closer])
        XCTAssertEqual(script.lines[0].kind, "greeting.morning")
        XCTAssertEqual(script.headline?.kind, "headline.attention.recovery")
        XCTAssertEqual(script.headline?.insightKind, "recovery.strained")
        XCTAssertEqual(script.lines[2].kind, "support.caution")
        XCTAssertEqual(script.lines[2].insightKind, "sleepStages.fragmented")
        XCTAssertEqual(script.lines[3].kind, "action.attention.recovery")
        XCTAssertEqual(script.lines.last?.kind, "closer.attention")
    }

    /// Support is skipped when the only other insight shares the focus domain (nothing new to add).
    func testNoSupportWhenOnlyFocusDomain() {
        let ranked = DailyInsightsEngine.rank([
            di("recovery.strained", .recovery, .caution, 0.7),
            di("vitals.rhrUp", .vitals, .caution, 0.6),   // vitals maps to the recovery hero too
        ])
        let focus = HomeFocusResolver.resolve(ranked: ranked)
        let script = MorningBriefingPlanner.plan(part: .morning, focus: focus, ranked: ranked)
        XCTAssertFalse(script.lines.contains { $0.role == .support })
        XCTAssertEqual(script.lines.map { $0.role }, [.greeting, .headline, .action, .closer])
    }

    /// A weak, non-caution secondary insight doesn't earn a support line (keeps the story short).
    func testWeakSecondaryDoesNotSupport() {
        let ranked = DailyInsightsEngine.rank([
            di("recovery.strained", .recovery, .caution, 0.7),
            di("sleepTiming.regular", .sleepTiming, .positive, 0.35),   // below supportMagnitude, not caution
        ])
        let focus = HomeFocusResolver.resolve(ranked: ranked)
        let script = MorningBriefingPlanner.plan(part: .morning, focus: focus, ranked: ranked)
        XCTAssertFalse(script.lines.contains { $0.role == .support })
    }

    /// An all-good day: focus is trends/optimization; headline+action reflect that; closer celebrates a streak.
    func testOptimizationDayWithStreak() {
        let ranked = DailyInsightsEngine.rank([di("recovery.primed", .recovery, .positive, 0.3)])
        let focus = HomeFocusResolver.resolve(ranked: ranked)
        XCTAssertEqual(focus.domain, .trends)
        let script = MorningBriefingPlanner.plan(part: .evening, focus: focus, ranked: ranked, streakDays: 12)
        XCTAssertEqual(script.lines[0].kind, "greeting.evening")
        XCTAssertEqual(script.headline?.kind, "headline.optimization.trends")
        XCTAssertEqual(script.lines.first { $0.role == .action }?.kind, "action.optimization.trends")
        XCTAssertEqual(script.lines.last?.kind, "closer.streak")
    }

    /// A strongly primed recovery leads as its own optimization headline.
    func testPrimedRecoveryOptimizationHeadline() {
        let ranked = DailyInsightsEngine.rank([di("recovery.primed", .recovery, .positive, 0.8)])
        let focus = HomeFocusResolver.resolve(ranked: ranked)
        let script = MorningBriefingPlanner.plan(part: .morning, focus: focus, ranked: ranked, streakDays: 1)
        XCTAssertEqual(script.headline?.kind, "headline.optimization.recovery")
        XCTAssertEqual(script.lines.last?.kind, "closer.optimization")   // streak too short to celebrate
    }
}
