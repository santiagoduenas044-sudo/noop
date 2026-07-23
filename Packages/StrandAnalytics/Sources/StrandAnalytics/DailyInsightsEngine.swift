import Foundation

// DailyInsightsEngine.swift — the cross-domain "what matters today" ranker.
//
// NOOP computes insights per domain (recovery drivers, sleep stages, sleep-timing regularity, …), but a
// user shouldn't have to visit every screen to learn the two or three things that actually matter today.
// This engine takes heterogeneous candidate insights from any domain and produces ONE ranked, capped,
// de-duplicated feed plus a single headline and a day-level tone — the backbone of a signature
// "Today" insights surface.
//
// PURELY ADDITIVE, pure/DB-free, framework-free (no copy, no colour — the app owns those via `kind`).
//
// RANKING (deliberate, and the reason this is an engine, not a sort): each candidate carries a domain,
// a tone, and a 0…1 magnitude (how strong/important the signal is). The rank SCORE is
// `magnitude + toneBias(tone)`, where a caution is boosted and a positive is neutral — so genuine
// "worth attention" items generally lead, but a very strong positive ("you crushed recovery") can still
// out-rank a trivial nitpick. Ties break by magnitude, then by a stable domain order for determinism.
// De-duplicated by `kind` so the same insight can't arrive twice from two producers.
//
// iPhone-first feature logic; no Kotlin twin (per the owner's iPhone-first directive).

public struct DailyInsight: Equatable, Sendable, Codable {

    public enum Domain: String, Sendable, Codable, Equatable, CaseIterable {
        case recovery, sleep, sleepStages, sleepTiming, activity, vitals
    }

    public enum Tone: String, Sendable, Codable, Equatable {
        case positive, caution, neutral
    }

    /// Stable identifier for this insight (also the de-dup key and the app's copy lookup), e.g.
    /// "recovery.hrvBelowBaseline". Never user-facing.
    public let kind: String
    public let domain: Domain
    public let tone: Tone
    /// 0…1 strength of the signal (how far from normal / how important). Clamped on init.
    public let magnitude: Double

    public init(kind: String, domain: Domain, tone: Tone, magnitude: Double) {
        self.kind = kind
        self.domain = domain
        self.tone = tone
        self.magnitude = min(max(magnitude, 0), 1)
    }
}

public struct RankedInsights: Equatable, Sendable, Codable {
    /// Ranked, de-duplicated, capped feed (most important first).
    public let insights: [DailyInsight]
    /// The single most important insight, or nil when there were none.
    public let headline: DailyInsight?
    /// How many of the surfaced insights want attention (tone == caution).
    public let attentionCount: Int
    /// A day-level tone for a summary chip: caution if anything surfaced needs attention, else positive
    /// if there's a win to celebrate, else neutral.
    public let dayTone: DailyInsight.Tone

    public init(insights: [DailyInsight], headline: DailyInsight?, attentionCount: Int,
                dayTone: DailyInsight.Tone) {
        self.insights = insights
        self.headline = headline
        self.attentionCount = attentionCount
        self.dayTone = dayTone
    }
}

public enum DailyInsightsEngine {

    /// Default cap on the feed — enough to be useful, few enough to stay a glance.
    public static let defaultMax: Int = 5

    /// Tone bias added to magnitude to form the rank score. A caution is boosted so attention-worthy
    /// items lead; neutral is pushed down so it only shows when little else does.
    static func toneBias(_ t: DailyInsight.Tone) -> Double {
        switch t {
        case .caution:  return 0.35
        case .positive: return 0.0
        case .neutral:  return -0.5
        }
    }

    /// Composite rank score (higher = more important). Exposed for testing.
    public static func score(_ i: DailyInsight) -> Double { i.magnitude + toneBias(i.tone) }

    static func toneRank(_ t: DailyInsight.Tone) -> Int {
        switch t { case .caution: return 0; case .positive: return 1; case .neutral: return 2 }
    }

    /// Rank, de-duplicate (by `kind`) and cap a set of candidate insights, and derive the headline and
    /// day tone. Deterministic: ties break by magnitude, then tone, then a stable domain order.
    public static func rank(_ candidates: [DailyInsight], max: Int = defaultMax) -> RankedInsights {
        // De-dup by kind, keeping the strongest instance of each.
        var best: [String: DailyInsight] = [:]
        for c in candidates {
            if let existing = best[c.kind], score(existing) >= score(c) { continue }
            best[c.kind] = c
        }
        let unique = Array(best.values)

        let sorted = unique.sorted { a, b in
            let sa = score(a), sb = score(b)
            if sa != sb { return sa > sb }
            if a.magnitude != b.magnitude { return a.magnitude > b.magnitude }
            if toneRank(a.tone) != toneRank(b.tone) { return toneRank(a.tone) < toneRank(b.tone) }
            return domainOrder(a.domain) < domainOrder(b.domain)
        }

        let capped = Array(sorted.prefix(Swift.max(max, 0)))
        let attention = capped.filter { $0.tone == .caution }.count
        let dayTone: DailyInsight.Tone = {
            if capped.contains(where: { $0.tone == .caution }) { return .caution }
            if capped.contains(where: { $0.tone == .positive }) { return .positive }
            return .neutral
        }()
        return RankedInsights(insights: capped, headline: capped.first,
                              attentionCount: attention, dayTone: dayTone)
    }

    /// Stable domain tiebreak order (recovery leads, then sleep family, then activity/vitals).
    static func domainOrder(_ d: DailyInsight.Domain) -> Int {
        switch d {
        case .recovery:    return 0
        case .sleep:       return 1
        case .sleepStages: return 2
        case .sleepTiming: return 3
        case .activity:    return 4
        case .vitals:      return 5
        }
    }
}
