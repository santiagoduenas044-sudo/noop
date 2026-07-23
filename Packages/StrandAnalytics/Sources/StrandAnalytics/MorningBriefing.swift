import Foundation

// MorningBriefing.swift — the narrative planner behind NOOP's "health story".
//
// A companion doesn't hand you six charts; it tells you, in a few honest sentences, what today is
// about. This engine decides the SHAPE of that little story — which sentences to say, in what order —
// from the already-ranked cross-domain feed and the resolved Home focus. It emits an ordered list of
// LINES, each a (role, template-kind) pair plus an optional underlying insight id; the APP turns each
// line into localized prose (numbers re-derived from the same domain outputs, so nothing is invented).
//
// Keeping the WORDS in the app and the NARRATIVE LOGIC here means the story stays: (a) deterministic
// and unit-testable with no strap, (b) localizable, and (c) honest — a line exists only when the
// underlying signal does. The briefing never diagnoses; the app's copy is non-clinical by contract.
//
// Deterministic, pure, DB-free, framework-free. iPhone-first; no Kotlin twin.

public enum MorningBriefing {

    /// Which part of the day the briefing greets. Drives only the opener.
    public enum PartOfDay: String, Sendable, Equatable, Codable {
        case morning, afternoon, evening, night
    }

    /// The narrative slot a line fills. The app styles/spaces lines by role.
    public enum LineRole: String, Sendable, Equatable, Codable {
        case greeting   // "Good morning."
        case headline   // the single most important thing today
        case support    // one secondary point worth knowing (optional)
        case action     // what to do about it
        case closer     // encouragement / streak / neutral sign-off
    }

    /// One sentence of the story. `kind` selects the app's template; `insightKind`, when present, is the
    /// underlying DailyInsight this line speaks to, so the app can render the same specific numbers the
    /// feed shows (never a second, divergent read).
    public struct Line: Equatable, Sendable, Codable {
        public let role: LineRole
        public let kind: String
        public let insightKind: String?

        public init(role: LineRole, kind: String, insightKind: String? = nil) {
            self.role = role
            self.kind = kind
            self.insightKind = insightKind
        }
    }

    /// The ordered story.
    public struct Script: Equatable, Sendable, Codable {
        public let lines: [Line]
        public init(lines: [Line]) { self.lines = lines }

        /// Convenience: the headline line, if any.
        public var headline: Line? { lines.first { $0.role == .headline } }
    }

    /// Local-hour → part of day (pure; the app passes its local hour). 5–11 morning, 12–16 afternoon,
    /// 17–21 evening, else night.
    public static func partOfDay(hour: Int) -> PartOfDay {
        switch hour {
        case 5...11:  return .morning
        case 12...16: return .afternoon
        case 17...21: return .evening
        default:      return .night
        }
    }
}

public enum MorningBriefingPlanner {

    /// A ranked insight (other than the headline's domain) is worth a support line when it's a caution,
    /// or a genuinely strong win. Below this, the story stays short rather than padded.
    public static let supportMagnitude: Double = 0.5

    /// A streak this long (days) earns a celebratory closer instead of the generic one.
    public static let streakCloserMinDays: Int = 3

    /// Plan the story. Order is always greeting → headline → (optional support) → action → closer, so a
    /// briefing is 3–5 sentences: enough to be a read, few enough to stay a glance.
    public static func plan(part: MorningBriefing.PartOfDay,
                            focus: HomeFocusResult,
                            ranked: RankedInsights,
                            streakDays: Int? = nil) -> MorningBriefing.Script {
        var lines: [MorningBriefing.Line] = []

        // 1. Greeting.
        lines.append(.init(role: .greeting, kind: "greeting.\(part.rawValue)"))

        // 2. Headline — the one thing today is about.
        let headlineKind = "headline.\(focus.mode.rawValue).\(focus.domain.rawValue)"
        lines.append(.init(role: .headline, kind: headlineKind, insightKind: ranked.headline?.kind))

        // 3. Support — the strongest OTHER-domain insight, if it clears the bar.
        if let support = supportInsight(ranked: ranked, focusDomain: focus.domain) {
            lines.append(.init(role: .support, kind: "support.\(support.tone.rawValue)",
                               insightKind: support.kind))
        }

        // 4. Action — what to do, tied to the focus + framing.
        lines.append(.init(role: .action, kind: "action.\(focus.mode.rawValue).\(focus.domain.rawValue)"))

        // 5. Closer — celebrate a streak, else a framing-appropriate sign-off.
        if let s = streakDays, s >= streakCloserMinDays {
            lines.append(.init(role: .closer, kind: "closer.streak"))
        } else {
            lines.append(.init(role: .closer, kind: "closer.\(focus.mode.rawValue)"))
        }

        return MorningBriefing.Script(lines: lines)
    }

    /// The strongest ranked insight whose hero domain differs from the focus (so the support line adds
    /// something new), provided it's a caution or a strong-enough win.
    static func supportInsight(ranked: RankedInsights, focusDomain: HomeFocus.Domain) -> DailyInsight? {
        for i in ranked.insights where HomeFocusResolver.heroDomain(i.domain) != focusDomain {
            if i.tone == .caution || i.magnitude >= supportMagnitude { return i }
        }
        return nil
    }
}
