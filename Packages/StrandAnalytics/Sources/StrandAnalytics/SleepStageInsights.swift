import Foundation

// SleepStageInsights.swift — turn a night's sleep-stage minutes into a composition read plus a
// small set of NEUTRAL, actionable insights, relative to the sleeper's own recent baseline.
//
// PURELY ADDITIVE and pure/DB-free: it takes SleepStageTotals.Minutes (tonight) + a trailing baseline
// of prior nights and returns framework-free values (fractions, an efficiency/restorative read, and a
// ranked list of insight kinds with a tone + signed delta). No SwiftUI, no localized copy — the view
// owns colour and words. Every DECISION (what counts as "low deep", "fragmented", "efficient") lives
// here so it is covered by `swift test` and mirrored byte-for-byte in Kotlin.
//
// HONEST by construction:
//   • Comparative insights ("below your usual deep") are WITHHELD until there are at least
//     `minBaselineNights` nights to compare against — before that only a descriptive composition and a
//     neutral "building your baseline" note are produced. No made-up norms.
//   • A stage only reads as notably low/high when it clears BOTH a relative gate (±`notableRatio`) AND
//     an absolute gate (`notableMinutes`), so a couple of stray minutes never trips an insight.
//   • Descriptive and non-clinical: "some fragmentation", "solid deep-sleep night" — never a diagnosis,
//     a target, or a call to a clinician.
//   • Baselines use the MEDIAN (robust to one odd night), never the mean.

public enum SleepStageInsights {

    // MARK: - Thresholds (named, tuned only against synthetic fixtures)

    /// Baseline nights required before comparative (vs-usual) insights are emitted.
    public static let minBaselineNights: Int = 5
    /// A stage's deviation from its baseline median must exceed this FRACTION to be "notable".
    public static let notableRatio: Double = 0.20
    /// …AND exceed this many MINUTES, so tiny nights don't trip a percentage gate.
    public static let notableMinutes: Double = 15.0
    /// Restorative (deep+REM) share of asleep at/above which the night reads "restorative-strong".
    public static let restorativeStrongShare: Double = 0.45
    /// …and below which (on a night that still slept enough) it reads "restorative-light".
    public static let restorativeLowShare: Double = 0.28
    /// Sleep efficiency (asleep / in-bed) at/above which the night reads "efficient".
    public static let efficientThreshold: Double = 0.90
    /// …and below which it reads "fragmented".
    public static let fragmentedThreshold: Double = 0.82
    /// Cap on how many insights the report surfaces (highest-signal first).
    public static let maxInsights: Int = 3

    // MARK: - Types

    /// The stage distribution + derived shares for one night. All fractions are of IN-BED time except
    /// `restorativeShare` (of asleep) and `efficiency` (asleep / in-bed). Rounded for parity.
    public struct Composition: Equatable, Sendable, Codable {
        public let awakeMin: Double, lightMin: Double, deepMin: Double, remMin: Double
        public let asleepMin: Double, inBedMin: Double
        public let awakeFrac: Double, lightFrac: Double, deepFrac: Double, remFrac: Double
        public let restorativeShare: Double
        public let efficiency: Double

        public init(awakeMin: Double, lightMin: Double, deepMin: Double, remMin: Double,
                    asleepMin: Double, inBedMin: Double,
                    awakeFrac: Double, lightFrac: Double, deepFrac: Double, remFrac: Double,
                    restorativeShare: Double, efficiency: Double) {
            self.awakeMin = awakeMin; self.lightMin = lightMin; self.deepMin = deepMin; self.remMin = remMin
            self.asleepMin = asleepMin; self.inBedMin = inBedMin
            self.awakeFrac = awakeFrac; self.lightFrac = lightFrac; self.deepFrac = deepFrac; self.remFrac = remFrac
            self.restorativeShare = restorativeShare; self.efficiency = efficiency
        }
    }

    /// A neutral, non-clinical observation. `kind` maps to the view's (localized) copy; `tone` drives
    /// emphasis; `deltaMin` is the signed minutes vs baseline where the insight is comparative (else nil).
    public enum Kind: String, Sendable, Equatable, Codable {
        case buildingBaseline   // not enough history to compare yet
        case balancedNight      // nothing stands out — a steady, healthy-looking night
        case efficientNight     // very little time awake in bed
        case fragmented         // notable time awake / low efficiency
        case restorativeStrong  // deep+REM share high
        case restorativeLight   // deep+REM share low
        case deepAboveUsual
        case deepBelowUsual
        case remAboveUsual
        case remBelowUsual
    }

    public enum Tone: String, Sendable, Equatable, Codable {
        case positive
        case caution
        case neutral
    }

    public struct Insight: Equatable, Sendable, Codable {
        public let kind: Kind
        public let tone: Tone
        public let deltaMin: Int?
        public init(kind: Kind, tone: Tone, deltaMin: Int? = nil) {
            self.kind = kind; self.tone = tone; self.deltaMin = deltaMin
        }
    }

    public struct Report: Equatable, Sendable, Codable {
        public let composition: Composition
        public let insights: [Insight]
        public let hasBaseline: Bool
        public init(composition: Composition, insights: [Insight], hasBaseline: Bool) {
            self.composition = composition; self.insights = insights; self.hasBaseline = hasBaseline
        }
    }

    // MARK: - Composition

    /// Pure distribution read for one night. Safe on an all-zero night (fractions 0, efficiency 0).
    public static func composition(_ m: SleepStageTotals.Minutes) -> Composition {
        let inBed = m.inBed
        let asleep = m.asleep
        let frac: (Double) -> Double = { inBed > 0 ? round3($0 / inBed) : 0 }
        return Composition(
            awakeMin: round1(m.awake), lightMin: round1(m.light), deepMin: round1(m.deep), remMin: round1(m.rem),
            asleepMin: round1(asleep), inBedMin: round1(inBed),
            awakeFrac: frac(m.awake), lightFrac: frac(m.light), deepFrac: frac(m.deep), remFrac: frac(m.rem),
            restorativeShare: asleep > 0 ? round3((m.deep + m.rem) / asleep) : 0,
            efficiency: inBed > 0 ? round3(asleep / inBed) : 0)
    }

    // MARK: - Analyze

    /// Build the full report: composition + ranked insights vs the trailing `baseline` (prior nights,
    /// any order). Comparative insights need `minBaselineNights`; below that only descriptive ones run.
    public static func analyze(tonight: SleepStageTotals.Minutes,
                               baseline: [SleepStageTotals.Minutes]) -> Report {
        let comp = composition(tonight)
        var insights: [Insight] = []

        // Non-comparative reads (always available on a real night).
        if tonight.inBed > 0 {
            if comp.efficiency >= efficientThreshold {
                insights.append(Insight(kind: .efficientNight, tone: .positive))
            } else if comp.efficiency < fragmentedThreshold {
                insights.append(Insight(kind: .fragmented, tone: .caution))
            }
            if comp.restorativeShare >= restorativeStrongShare {
                insights.append(Insight(kind: .restorativeStrong, tone: .positive))
            } else if comp.asleepMin > 0 && comp.restorativeShare < restorativeLowShare {
                insights.append(Insight(kind: .restorativeLight, tone: .caution))
            }
        }

        // Comparative reads vs personal baseline median.
        let usable = baseline.filter { $0.inBed > 0 }
        let hasBaseline = usable.count >= minBaselineNights
        if hasBaseline {
            let deepBase = median(usable.map { $0.deep })
            let remBase = median(usable.map { $0.rem })
            if let d = notableDelta(tonight.deep, deepBase) {
                insights.append(Insight(kind: d > 0 ? .deepAboveUsual : .deepBelowUsual,
                                        tone: d > 0 ? .positive : .caution, deltaMin: Int(d.rounded())))
            }
            if let d = notableDelta(tonight.rem, remBase) {
                insights.append(Insight(kind: d > 0 ? .remAboveUsual : .remBelowUsual,
                                        tone: d > 0 ? .positive : .caution, deltaMin: Int(d.rounded())))
            }
        }

        // Rank: caution before positive before neutral; within a tone, larger |delta| first.
        insights.sort { lhs, rhs in
            if toneRank(lhs.tone) != toneRank(rhs.tone) { return toneRank(lhs.tone) < toneRank(rhs.tone) }
            return abs(lhs.deltaMin ?? 0) > abs(rhs.deltaMin ?? 0)
        }
        insights = Array(insights.prefix(maxInsights))

        // Always say SOMETHING honest.
        if insights.isEmpty {
            if tonight.inBed <= 0 {
                insights = [Insight(kind: .buildingBaseline, tone: .neutral)]
            } else if !hasBaseline {
                insights = [Insight(kind: .buildingBaseline, tone: .neutral)]
            } else {
                insights = [Insight(kind: .balancedNight, tone: .positive)]
            }
        } else if !hasBaseline && tonight.inBed > 0 {
            // Real night, descriptive insights present, but no baseline yet — append the honest note
            // (kept last, not counted against the cap's spirit) so the user knows more is coming.
            if insights.count < maxInsights {
                insights.append(Insight(kind: .buildingBaseline, tone: .neutral))
            }
        }

        return Report(composition: comp, insights: insights, hasBaseline: hasBaseline)
    }

    // MARK: - Helpers

    /// Signed minutes delta vs baseline, but only when it clears BOTH the relative and absolute gates;
    /// otherwise nil (not notable). Positive = more than usual.
    static func notableDelta(_ value: Double, _ base: Double) -> Double? {
        guard base > 0 else { return nil }
        let delta = value - base
        guard abs(delta) >= notableMinutes, abs(delta) / base >= notableRatio else { return nil }
        return delta
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0
    }

    static func toneRank(_ t: Tone) -> Int { t == .caution ? 0 : (t == .positive ? 1 : 2) }

    static func round1(_ v: Double) -> Double { (v * 10.0).rounded() / 10.0 }
    static func round3(_ v: Double) -> Double { (v * 1000.0).rounded() / 1000.0 }
}
