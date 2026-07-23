import Foundation

// TodayInsightsBuilder.swift — turns each domain's own output into ranked "what matters today"
// candidates for the DailyInsightsEngine.
//
// This is the mapping layer between the domain engines (recovery score + readiness band, sleep-stage
// composition/insights, sleep-timing regularity) and the cross-domain ranker. It decides, per domain,
// the stable `kind`, the `tone`, and the 0…1 `magnitude` (how strongly this signal deserves attention
// today). It carries NO user-facing copy or colour — the app owns those, keyed by `kind` (see
// TodayInsightCard on iOS) — so this stays pure, DB-free, framework-free, and fully testable with no
// strap, no CoreBluetooth, no database.
//
// HONESTY (mirrors the domain engines it maps): a candidate is emitted ONLY from a real, present
// signal. Neutral / placeholder reads ("building baseline", "balanced night") are emitted but with low
// magnitude, and the ranker's tone bias pushes neutrals down, so they only surface when nothing
// stronger competes. Magnitudes are bounded [0,1], monotone in the underlying delta, and never
// invented. A caution carries a floor so a genuinely rough morning always leads.
//
// iPhone-first feature logic; no Kotlin twin (per the owner's iPhone-first directive).

public enum TodayInsightsBuilder {

    // MARK: Recovery

    /// Today's recovery signal: the 0…100 Charge score and the readiness band it resolved to. The band
    /// (not the raw score) decides tone, so the feed agrees with the hero's Push / Maintain / Rest read.
    public struct RecoverySignal: Equatable, Sendable {
        public let score: Int
        public let band: ReadinessEngine.Level
        public init(score: Int, band: ReadinessEngine.Level) {
            self.score = score
            self.band = band
        }
    }

    /// Distance of a 0…100 score from the neutral midpoint (50), normalised to 0…1. A score of 50
    /// carries no urgency; 100 or 0 is maximal.
    static func centeredMagnitude(_ score: Int) -> Double {
        min(1, abs(Double(score) - 50) / 50)
    }

    /// The single recovery candidate, or nil when readiness is `.insufficient` (not enough history —
    /// no honest read to surface). A `.balanced` band is neutral (rarely leads); primed is a win;
    /// strained / rundown are cautions with a magnitude floor so a red morning always leads the feed.
    public static func recoveryCandidate(_ s: RecoverySignal) -> DailyInsight? {
        let tone: DailyInsight.Tone
        switch s.band {
        case .primed:             tone = .positive
        case .strained, .rundown: tone = .caution
        case .balanced:           tone = .neutral
        case .insufficient:       return nil
        }
        let base = centeredMagnitude(s.score)
        let mag = (tone == .caution) ? Swift.max(base, 0.5) : base
        return DailyInsight(kind: "recovery.\(s.band.rawValue)", domain: .recovery, tone: tone,
                            magnitude: mag)
    }

    // MARK: Sleep stages

    static func stageTone(_ t: SleepStageInsights.Tone) -> DailyInsight.Tone {
        switch t {
        case .positive: return .positive
        case .caution:  return .caution
        case .neutral:  return .neutral
        }
    }

    /// Magnitude for a stage insight. Comparative reads (deep/REM above/below usual) scale with the
    /// minute delta the engine measured; non-comparative reads carry a fixed prior sized to how much
    /// they matter (fragmentation loudest, a steady/placeholder night quietest).
    static func stageMagnitude(_ ins: SleepStageInsights.Insight) -> Double {
        if let d = ins.deltaMin { return min(1, Double(abs(d)) / 45.0) }
        switch ins.kind {
        case .fragmented:        return 0.6
        case .restorativeStrong: return 0.55
        case .restorativeLight:  return 0.5
        case .efficientNight:    return 0.45
        case .balancedNight:     return 0.2
        case .buildingBaseline:  return 0.15
        default:                 return 0.4
        }
    }

    /// One candidate per stage insight the engine surfaced (already ranked/capped inside the report).
    public static func sleepStageCandidates(_ report: SleepStageInsights.Report) -> [DailyInsight] {
        report.insights.map { ins in
            DailyInsight(kind: "sleepStages.\(ins.kind.rawValue)", domain: .sleepStages,
                         tone: stageTone(ins.tone), magnitude: stageMagnitude(ins))
        }
    }

    // MARK: Sleep timing

    /// The single sleep-timing candidate, or nil when the regularity read is withheld (unreadable /
    /// still building a baseline). Regular timing is a quiet win; variable / irregular is a caution,
    /// nudged up a touch when the read is solid-confidence.
    public static func sleepTimingCandidate(_ r: SleepRegularityResult) -> DailyInsight? {
        guard r.isReadable, r.score != nil else { return nil }
        let tone: DailyInsight.Tone
        let mag: Double
        switch r.label {
        case .veryRegular: tone = .positive; mag = 0.5
        case .regular:     tone = .positive; mag = 0.35
        case .variable:    tone = .caution;  mag = 0.4
        case .irregular:   tone = .caution;  mag = 0.6
        case .unreadable:  return nil
        }
        let confidenceBoost = (r.confidence == .solid) ? 0.1 : 0.0
        return DailyInsight(kind: "sleepTiming.\(r.label.rawValue)", domain: .sleepTiming,
                            tone: tone, magnitude: min(1, mag + confidenceBoost))
    }

    // MARK: Assemble

    /// Build every domain's candidates and hand them to the cross-domain ranker, producing the ranked,
    /// de-duplicated, capped feed plus a headline and day tone. Any nil domain is simply absent — the
    /// feed adapts to whatever the user actually has today.
    public static func build(recovery: RecoverySignal?,
                             sleepStages: SleepStageInsights.Report?,
                             sleepTiming: SleepRegularityResult?,
                             max: Int = DailyInsightsEngine.defaultMax) -> RankedInsights {
        var candidates: [DailyInsight] = []
        if let recovery, let c = recoveryCandidate(recovery) { candidates.append(c) }
        if let sleepStages { candidates.append(contentsOf: sleepStageCandidates(sleepStages)) }
        if let sleepTiming, let c = sleepTimingCandidate(sleepTiming) { candidates.append(c) }
        return DailyInsightsEngine.rank(candidates, max: max)
    }
}
