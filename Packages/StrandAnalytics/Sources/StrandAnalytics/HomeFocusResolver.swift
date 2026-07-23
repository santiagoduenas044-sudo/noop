import Foundation

// HomeFocusResolver.swift — decides what the Home screen leads with today.
//
// The Adaptive Home answers ONE question first: "what is the most important thing I should know about
// my health today?" This resolver turns the already-ranked cross-domain feed (TodayInsightsBuilder →
// DailyInsightsEngine) plus a couple of event signals into a single FOCUS: which domain becomes the
// hero, whether the day is an "attention" day (something needs you) or an "optimization" day (all
// within normal — look at the bigger picture), and the priority order of the supporting rows beneath.
//
// Deterministic, pure, DB-free, framework-free — the hero VISUALS and copy live in the app; this only
// decides the shape of the screen. Fully testable with no strap.
//
// PRIORITY (deliberate):
//   1. A caution headline wins — the loudest real problem leads (recovery / sleep / vitals).
//   2. Else a standout training load leads (a hard day to absorb well) — surfaced from an event signal,
//      since strain is an achievement, not a caution, and wouldn't come through the caution path.
//   3. Else a strongly-primed recovery leads as an optimization ("you're primed — a good day to push").
//   4. Else nothing needs attention: focus shifts to TRENDS / momentum (the optimization day).
//
// iPhone-first feature logic; no Kotlin twin (per the owner's iPhone-first directive).

public enum HomeFocus {

    /// The domain the hero renders. Collapses the finer insight domains (sleepStages/sleepTiming →
    /// sleep, vitals → recovery) into the four hero identities the Home screen actually has.
    public enum Domain: String, Sendable, Equatable, CaseIterable, Codable {
        case recovery, sleep, strain, trends
    }

    /// Whether today is about acting on a problem, or making the most of a good day.
    public enum Mode: String, Sendable, Equatable, Codable {
        case attention      // something moved and wants your attention
        case optimization   // everything's within normal — look at the bigger picture
    }
}

public struct HomeFocusResult: Equatable, Sendable, Codable {
    /// The hero domain for today.
    public let domain: HomeFocus.Domain
    /// Attention vs optimization framing.
    public let mode: HomeFocus.Mode
    /// The supporting-row order beneath the hero (never contains `domain`), cautions bubbled up.
    public let supporting: [HomeFocus.Domain]

    public init(domain: HomeFocus.Domain, mode: HomeFocus.Mode, supporting: [HomeFocus.Domain]) {
        self.domain = domain
        self.mode = mode
        self.supporting = supporting
    }
}

public enum HomeFocusResolver {

    /// How strongly a primed recovery must read before it leads a calm morning as its own optimization
    /// hero (below this it just becomes a supporting row and Trends leads).
    public static let primedLeadMagnitude: Double = 0.5

    /// Map a fine-grained insight domain to a hero identity.
    public static func heroDomain(_ d: DailyInsight.Domain) -> HomeFocus.Domain {
        switch d {
        case .recovery, .vitals:                    return .recovery
        case .sleep, .sleepStages, .sleepTiming:    return .sleep
        case .activity:                             return .strain
        }
    }

    /// Resolve today's Home focus.
    ///
    /// - Parameters:
    ///   - ranked: the ranked cross-domain feed for today.
    ///   - strainStandout: true when yesterday's training load was a notable event (well above the
    ///     personal baseline) — the app computes this from the strain series; it is not a caution and so
    ///     does not arrive through `ranked`.
    public static func resolve(ranked: RankedInsights, strainStandout: Bool = false) -> HomeFocusResult {
        let focus: HomeFocus.Domain
        let mode: HomeFocus.Mode

        if let head = ranked.headline, head.tone == .caution {
            focus = heroDomain(head.domain); mode = .attention
        } else if strainStandout {
            focus = .strain; mode = .attention
        } else if let head = ranked.headline, head.tone == .positive,
                  heroDomain(head.domain) == .recovery, head.magnitude >= primedLeadMagnitude {
            focus = .recovery; mode = .optimization
        } else {
            focus = .trends; mode = .optimization
        }

        return HomeFocusResult(domain: focus, mode: mode,
                               supporting: supportingOrder(ranked: ranked, focus: focus,
                                                            strainStandout: strainStandout))
    }

    /// The supporting-row order: caution domains (in rank order) first, then a stable default, with the
    /// hero domain removed. Strain is inserted near the front on a standout-load day even when it isn't
    /// the hero, so the load stays visible.
    static func supportingOrder(ranked: RankedInsights, focus: HomeFocus.Domain,
                                strainStandout: Bool) -> [HomeFocus.Domain] {
        var order: [HomeFocus.Domain] = []
        func push(_ d: HomeFocus.Domain) { if !order.contains(d) { order.append(d) } }

        for i in ranked.insights where i.tone == .caution { push(heroDomain(i.domain)) }
        if strainStandout { push(.strain) }
        for d in HomeFocus.Domain.allCases { push(d) }   // stable default fills the rest

        return order.filter { $0 != focus }
    }
}
