#if os(iOS)
import Foundation
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// PremiumJournalIntel — ranked "what may be affecting you" discoveries from the user's own logs.
///
/// **This computes nothing new statistically.** The with/without split, the means, the effect size
/// and the p-value all come from the shipping, already-tested `BehaviorInsights` engine via
/// `PremiumAnalysis.behaviorAssociation`. This layer only decides WHICH factor×outcome pairs are
/// worth surfacing, ranks them, and attaches the honesty labelling — so the engine stays the single
/// source of statistical truth and the Coach can be handed the same finished numbers the UI shows.
///
/// Two honesty rules are structural here, not cosmetic:
/// * A pair below `PremiumAnalysis.minBehaviorOccurrences` logged days is NEVER ranked as a
///   discovery. It appears — if at all — as a `collecting` row that states how many more days are
///   needed, so a user who has logged something twice can never see it presented as a finding.
/// * Every surfaced discovery carries its sample size and a confidence band. "n = 1 vs n = 11 must
///   not look like a meaningful discovery" is enforced by the gate, not by wording.
struct PremiumJournalIntel {

    /// One factor measured against one outcome. `effect` is the engine's verbatim output.
    struct Discovery: Identifiable {
        let factorCanonical: String
        let factorDisplay: String
        let outcome: PremiumMetricID
        let effect: BehaviorEffect
        /// 0 = same day, 1 = the following day (the engine picks whichever framing is stronger).
        let lagDays: Int
        let confidence: PremiumConfidence

        var id: String { "\(factorCanonical)|\(outcome.rawValue)|\(lagDays)" }

        /// Ranking strength: absolute effect size. Deliberately NOT the percent change — a percent
        /// on a near-zero baseline would dominate the list for the wrong reason (the same trap the
        /// skin-temperature display bug came from).
        var strength: Double { abs(effect.cohensD) }

        /// Signed difference in the outcome's own unit, e.g. "-7 ms", "+3 bpm".
        var deltaText: String {
            let d = PremiumMetricCatalog.def(outcome)
            return d.formatSigned(effect.delta)
        }
        /// Signed percent difference, or nil when the engine couldn't compute one.
        var pctText: String? {
            effect.pctChange.map { PremiumAnalysis.signedPct($0) }
        }
        /// Whether this direction reads as favourable for this metric. `nil` for metrics with no
        /// single good direction (respiratory rate), which then render neutrally.
        var isGood: Bool? {
            guard let hb = PremiumMetricCatalog.def(outcome).higherBetter else { return nil }
            return hb ? effect.delta >= 0 : effect.delta <= 0
        }
        var totalSamples: Int { effect.nWith + effect.nWithout }
    }

    /// A factor the user is logging that has not yet cleared the honesty gate. Surfaced so logging
    /// feels like progress rather than silence, WITHOUT presenting a conclusion.
    struct Collecting: Identifiable {
        let factorCanonical: String
        let factorDisplay: String
        let daysLogged: Int
        var daysNeeded: Int { max(0, PremiumAnalysis.minBehaviorOccurrences - daysLogged) }
        var id: String { factorCanonical }
    }

    /// Ranked strongest-first.
    let discoveries: [Discovery]
    /// Factors still below the gate, most-logged first.
    let collecting: [Collecting]
    /// Total distinct factors the user has logged at least once.
    let factorsLogged: Int

    static let empty = PremiumJournalIntel(discoveries: [], collecting: [], factorsLogged: 0)

    /// The outcomes a journal factor is tested against. Every one is a real stored per-day metric;
    /// SpO₂ is included because Apple Health SpO₂ now reaches `repo.days` (see the merge fix in
    /// `Repository.mergeDaily`), and it self-gates — a user with no SpO₂ history simply produces no
    /// aligned pairs and the pair is dropped, rather than showing an empty comparison.
    static let outcomes: [PremiumMetricID] = [
        .recovery, .hrv, .restingHr, .sleepDuration, .sleepEfficiency, .respiratory, .spo2,
    ]

    /// Builds the ranked discoveries from real journal rows + real metric history.
    ///
    /// `displayName` maps a canonical key to what the user actually sees — a renamed factor must
    /// still read under its rename here, while all the joining stays on the canonical key.
    @MainActor
    static func load(repo: Repository, displayName: (String) -> String) async -> PremiumJournalIntel {
        let entries = await repo.journalEntries()
        var behaviorDays: [String: Set<String>] = [:]
        for e in entries where e.answeredYes {
            behaviorDays[e.question, default: []].insert(e.day)
        }
        guard !behaviorDays.isEmpty else { return .empty }

        // Cache each outcome's series once rather than per factor — this loop is
        // factors × outcomes, and `series` walks the whole banked history each call.
        var seriesByOutcome: [PremiumMetricID: [PremiumSample]] = [:]
        for id in outcomes {
            let s = PremiumMetricCatalog.series(id, repo: repo)
            if !s.isEmpty { seriesByOutcome[id] = s }
        }

        var found: [Discovery] = []
        var pending: [Collecting] = []

        for (canonical, days) in behaviorDays {
            let shown = displayName(canonical)
            // Below the gate: report progress, never a conclusion.
            guard days.count >= PremiumAnalysis.minBehaviorOccurrences else {
                pending.append(Collecting(factorCanonical: canonical, factorDisplay: shown,
                                          daysLogged: days.count))
                continue
            }
            for id in outcomes {
                guard let series = seriesByOutcome[id] else { continue }
                let name = PremiumMetricCatalog.def(id).shortName
                guard let assoc = PremiumAnalysis.behaviorAssociation(
                    behaviorDays: days, behaviorName: shown,
                    outcome: series, outcomeName: name) else { continue }
                let conf = PremiumConfidence.from(n: min(assoc.effect.nWith, assoc.effect.nWithout),
                                                  strength: abs(assoc.effect.cohensD) / 2.0)
                found.append(Discovery(factorCanonical: canonical, factorDisplay: shown,
                                       outcome: id, effect: assoc.effect,
                                       lagDays: assoc.lagDays, confidence: conf))
            }
        }

        // Rank by effect size, then by sample size so a well-evidenced finding outranks an equally
        // strong one measured on fewer days.
        found.sort {
            if $0.strength != $1.strength { return $0.strength > $1.strength }
            return $0.totalSamples > $1.totalSamples
        }
        pending.sort { $0.daysLogged > $1.daysLogged }

        return PremiumJournalIntel(discoveries: found, collecting: pending,
                                   factorsLogged: behaviorDays.count)
    }

    /// The strongest discovery per FACTOR — so the headline list shows five different factors rather
    /// than one factor's five outcomes crowding everything else out.
    var topPerFactor: [Discovery] {
        var seen = Set<String>()
        var out: [Discovery] = []
        for d in discoveries where seen.insert(d.factorCanonical).inserted {
            out.append(d)
        }
        return out
    }

    /// Every discovery for one factor, strongest first — the detail screen's content.
    func discoveries(for factorCanonical: String) -> [Discovery] {
        discoveries.filter { $0.factorCanonical == factorCanonical }
    }
}
#endif
