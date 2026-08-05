#if os(iOS)
import Foundation
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// PremiumCoachContext — the structured brief handed to the (future) Claude-powered Coach.
///
/// **The Coach does not analyse; it explains.** Every relationship, deviation and association in
/// here has already been computed deterministically by `PremiumAnalysis` from the user's own
/// history. The model's job is to put finished findings into plain language and answer follow-up
/// questions about them — never to invent a correlation, guess at a baseline, or claim a cause.
/// That division is what keeps a language model from fabricating health conclusions.
///
/// The context is also deliberately explicit about what it DOESN'T know: `dataQuality` reports how
/// much history exists and which signals are missing, so the Coach can say "there isn't enough
/// history yet" instead of confidently answering from three nights of data.
///
/// Nothing here performs any network call. Building the context is entirely on-device, consistent
/// with the project's offline guarantee; wiring it to an API is a separate, explicit step.
struct PremiumCoachContext {

    // MARK: Current state

    /// One metric's current standing: value now, personal baseline, and how far today sits from it.
    struct MetricState {
        let id: PremiumMetricID
        let name: String
        let unit: String
        let provenance: PremiumProvenance
        let current: Double?
        let baseline: Double?
        let deviationPct: Double?
        let deviationAbs: Double?
        let change7: Double?
        let change7Abs: Double?
        let change30: Double?
        let trend: PremiumTrendDirection
        let sampleCount: Int

        /// A compact single-line rendering for the model prompt. Deviation and change go through
        /// `PremiumMetricCatalog`'s shared formatting, same as the on-screen UI, so a near-zero
        /// baseline (skin temperature) never hands the model an absurd percentage to explain.
        var brief: String {
            guard let c = current else { return "\(name): no data" }
            var s = "\(name): \(fmt(c))\(unit.isEmpty ? "" : " " + unit)"
            if let b = baseline {
                s += " (baseline \(fmt(b))"
                let devText = PremiumMetricCatalog.def(id).usesAbsoluteDeviation
                    ? deviationAbs.map { PremiumMetricCatalog.def(id).formatSigned($0) }
                    : deviationPct.map { PremiumAnalysis.signedPct($0) }
                if let d = devText { s += ", \(d) vs baseline" }
                s += ")"
            } else {
                s += " (no baseline yet — \(sampleCount) samples)"
            }
            let changeText = PremiumMetricCatalog.def(id).usesAbsoluteDeviation
                ? change7Abs.map { PremiumMetricCatalog.def(id).formatSigned($0) }
                : change7.map { PremiumAnalysis.signedPct($0) }
            if let c7 = changeText { s += ", 7-day change \(c7)" }
            s += ", trend \(trend.word)"
            s += " [\(provenance.label.lowercased())]"
            return s
        }
        private func fmt(_ v: Double) -> String {
            abs(v) >= 100 || v.rounded() == v ? String(Int(v.rounded())) : String(format: "%.1f", v)
        }
    }

    /// Sleep-specific intelligence, beyond the plain per-night duration/score metrics.
    struct SleepState {
        let lastNightInBedMin: Double?
        let lastNightAsleepMin: Double?
        let wasoMin: Double?
        let awakeningCount: Int?
        let longestAwakeMin: Double?
        let bedtimeVariabilityMin: Double?
        let wakeVariabilityMin: Double?
        let midpointVariabilityMin: Double?
        let regularityScore: Double?
        let weekendShiftMin: Double?
        let sleepNeedMin: Double
        let balanceMin: Double?
        let nightsAnalysed: Int

        var brief: String {
            var lines: [String] = []
            if let a = lastNightAsleepMin, let b = lastNightInBedMin {
                lines.append("Last night: \(PremiumAnalysis.durText(a)) asleep of \(PremiumAnalysis.durText(b)) in bed")
            }
            if let w = wasoMin, let n = awakeningCount {
                lines.append("Awake after onset: \(PremiumAnalysis.durText(w)) across \(n) awakening\(n == 1 ? "" : "s")")
            }
            if let r = regularityScore {
                lines.append("Sleep regularity: \(Int(r.rounded()))/100")
            }
            if let bv = bedtimeVariabilityMin {
                lines.append("Bedtime varies ±\(PremiumAnalysis.durText(bv)) night to night")
            }
            if let ws = weekendShiftMin, abs(ws) >= 15 {
                lines.append("Weekend bedtime runs \(PremiumAnalysis.durText(abs(ws))) \(ws > 0 ? "later" : "earlier") than weekdays")
            }
            if let bal = balanceMin {
                lines.append("Sleep balance vs \(PremiumAnalysis.durText(sleepNeedMin)) need: \(bal >= 0 ? "+" : "")\(PremiumAnalysis.durText(bal))")
            }
            lines.append("Nights analysed: \(nightsAnalysed)")
            return lines.joined(separator: "\n")
        }
    }

    /// Cardiovascular intelligence.
    struct HeartState {
        let liveBpm: Int?
        let restingHr: Double?
        let restingHrBaseline: Double?
        let hrv: Double?
        let hrvBaseline: Double?
        let dayMinBpm: Double?
        let dayMaxBpm: Double?
        let dayAvgBpm: Double?
        let minutesInZone: [String: Double]

        var brief: String {
            var lines: [String] = []
            if let l = liveBpm { lines.append("Current heart rate: \(l) bpm") }
            if let r = restingHr {
                var s = "Resting HR: \(Int(r.rounded())) bpm"
                if let b = restingHrBaseline { s += " (baseline \(Int(b.rounded())))" }
                lines.append(s)
            }
            if let h = hrv {
                var s = "HRV: \(Int(h.rounded())) ms"
                if let b = hrvBaseline { s += " (baseline \(Int(b.rounded())))" }
                lines.append(s)
            }
            if let mn = dayMinBpm, let mx = dayMaxBpm {
                lines.append("Today's heart-rate range: \(Int(mn.rounded()))–\(Int(mx.rounded())) bpm")
            }
            if !minutesInZone.isEmpty {
                let zones = minutesInZone
                    .filter { $0.value >= 1 }
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key) \(Int($0.value.rounded()))m" }
                if !zones.isEmpty { lines.append("Time in zone: " + zones.joined(separator: ", ")) }
            }
            return lines.isEmpty ? "No heart data recorded." : lines.joined(separator: "\n")
        }
    }

    /// What the user has logged, and what it has coincided with.
    /// ONE already-computed factor↔outcome comparison, handed to the model as finished numbers.
    ///
    /// This is the concrete shape of the division of labour: the engine has already done the
    /// with/without split, the means, the difference and the confidence banding. The model's only
    /// job is to put it in plain language. It must never be asked to derive an association, and it
    /// has no access to the raw rows that would let it try.
    struct JournalFactorFinding {
        let factor: String
        let outcome: String
        let withValue: Double
        let withoutValue: Double
        let difference: Double
        let pctDifference: Double?
        let sampleSize: Int
        let confidence: PremiumConfidence
        /// 0 = same day, 1 = following day.
        let lagDays: Int

        /// One prompt line. Matches the structure the brief asked for
        /// (`withHRV = 48, withoutHRV = 55, difference = -7, sampleSize = 36, confidence = emerging`)
        /// while staying readable, since this text is also what a debug view would show the user.
        var brief: String {
            var s = "\(factor) → \(outcome): with = \(fmt(withValue)), without = \(fmt(withoutValue))"
            s += ", difference = \(difference >= 0 ? "+" : "")\(fmt(difference))"
            if let p = pctDifference { s += " (\(PremiumAnalysis.signedPct(p)))" }
            s += ", n = \(sampleSize), confidence = \(confidence.promptWord)"
            if lagDays == 1 { s += ", measured next-day" }
            return s
        }
        private func fmt(_ v: Double) -> String {
            abs(v) >= 100 || v.rounded() == v ? String(Int(v.rounded())) : String(format: "%.1f", v)
        }
    }

    struct JournalState {
        /// Behaviour name → the days it was logged on.
        let behaviorDays: [String: Set<String>]
        let daysLogged: Int
        let currentStreak: Int
        let todayLogged: Bool
        /// Ranked, already-computed factor comparisons. Empty until factors clear the
        /// `minBehaviorOccurrences` gate — the model is never handed a thin comparison to explain.
        let factorFindings: [JournalFactorFinding]

        var brief: String {
            guard daysLogged > 0 else { return "No journal entries logged yet." }
            let top = behaviorDays
                .sorted { ($0.value.count, $0.key) > ($1.value.count, $1.key) }
                .prefix(8)
                .map { "\($0.key) (\($0.value.count)×)" }
            var s = "Logged on \(daysLogged) days, current streak \(currentStreak). "
                  + "Today logged: \(todayLogged ? "yes" : "no").\n"
                  + "Most-logged behaviours: " + top.joined(separator: ", ")
            if !factorFindings.isEmpty {
                s += "\n\nComputed factor comparisons (already calculated — explain these, do not "
                   + "re-derive or extrapolate beyond them):\n"
                s += factorFindings.map { "- " + $0.brief }.joined(separator: "\n")
            }
            return s
        }
    }

    // MARK: Fields

    let generatedAt: Date
    let metrics: [MetricState]
    let sleep: SleepState
    let heart: HeartState
    let journal: JournalState
    /// Already-computed findings — baseline deviations, trends, relationships, associations.
    let findings: [PremiumFinding]
    let dataQuality: PremiumDataQuality

    // MARK: Prompt rendering

    /// The whole context as a plain-text brief for a model prompt. Deliberately readable rather
    /// than JSON: it is also what the debug view shows the user, so they can see exactly what
    /// would be sent before anything ever is.
    var promptBrief: String {
        var out: [String] = []
        out.append("# NOOP context (generated on-device, \(Self.stamp.string(from: generatedAt)))")
        out.append("")
        out.append("## Data quality")
        out.append(dataQuality.summary)
        out.append("Baselines available: \(dataQuality.hasEnoughForBaselines ? "yes" : "no"). "
                 + "Relationship analysis available: \(dataQuality.hasEnoughForCorrelations ? "yes" : "no").")
        out.append("")
        out.append("## Current metrics")
        if metrics.isEmpty {
            out.append("No metrics recorded.")
        } else {
            for m in metrics { out.append("- " + m.brief) }
        }
        out.append("")
        out.append("## Sleep")
        out.append(sleep.brief)
        out.append("")
        out.append("## Heart")
        out.append(heart.brief)
        out.append("")
        out.append("## Journal")
        out.append(journal.brief)
        out.append("")
        out.append("## Computed findings")
        if findings.isEmpty {
            out.append("None yet — not enough history for any finding to clear its threshold.")
        } else {
            for f in findings {
                var line = "- [\(f.confidence.label)] \(f.text)"
                if let d = f.detail { line += " (\(d))" }
                out.append(line)
            }
        }
        out.append("")
        out.append("## Rules for the assistant")
        out.append(Self.groundingRules)
        return out.joined(separator: "\n")
    }

    /// The findings-only block fed to `AICoachEngine.groundingProvider`.
    ///
    /// Deliberately NOT `promptBrief`: the coach engine already builds and sends its own metrics
    /// summary (charge/effort/rest, HRV, resting HR, recent workouts), so sending the full brief
    /// would duplicate all of that in every request — more tokens, and two independently-formatted
    /// copies of the same numbers for the model to potentially disagree with itself about. This
    /// carries only what the engine does NOT already have: the deterministic findings and the
    /// journal with/without comparisons.
    ///
    /// Returns nil when there is nothing that cleared a threshold, so the caller can omit the
    /// section entirely — an empty "Computed findings" heading would read as "no relationships
    /// exist in your data", which is a different and unsupported claim.
    var groundingBlock: String? {
        var out: [String] = []
        if !findings.isEmpty {
            for f in findings {
                var line = "- [\(f.confidence.promptWord)] \(f.text)"
                if let d = f.detail { line += " (\(d))" }
                out.append(line)
            }
        }
        if !journal.factorFindings.isEmpty {
            if !out.isEmpty { out.append("") }
            out.append("Journal factor comparisons (with vs without, already computed):")
            out.append(contentsOf: journal.factorFindings.map { "- " + $0.brief })
        }
        guard !out.isEmpty else { return nil }
        out.append("")
        out.append("Data coverage: " + dataQuality.summary)
        return out.joined(separator: "\n")
    }

    /// The instructions that travel with every context. They exist to make fabrication a rule
    /// violation rather than a stylistic preference.
    static let groundingRules: String = """
    - Use ONLY the numbers in this context. Never estimate, interpolate or recall a value that is not here.
    - Findings above were computed deterministically from the user's own history. Explain them; do not add new ones.
    - Every relationship here is an ASSOCIATION. Never state or imply causation.
    - Respect the confidence labels: an "Early signal" is a possibility, not a fact.
    - If the data needed to answer is missing, say so plainly instead of guessing.
    - You are not a medical device. Do not diagnose. Suggest seeing a clinician for anything concerning.
    """

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

// MARK: - Builder

extension PremiumCoachContext {

    /// Assembles the full context from live stores. Runs the deterministic analysis for every
    /// available metric, derives the sleep/heart states, and computes journal associations and
    /// cross-metric relationships — then packages the results.
    ///
    /// Everything expensive is already `nil`-guarded by sample-count thresholds, so on a new
    /// install this returns quickly with an honest "not enough history" picture rather than a
    /// screenful of spurious correlations.
    @MainActor
    /// `async` because the journal factor comparisons come from `PremiumJournalIntel`, which reads
    /// journal rows from the store. Nothing here performs a network call — building the context is
    /// entirely on-device, per the project's offline guarantee.
    static func build(repo: Repository,
                      sleepIntel: PremiumSleepIntel,
                      liveBpm: Int?,
                      dayHR: [Double],
                      minutesInZone: [String: Double],
                      journalEntries: [JournalEntry]) async -> PremiumCoachContext {

        // ---- Metric states ------------------------------------------------------------------
        // Only real, non-derived metrics with recorded history; derived ones are represented by
        // the sleep/heart states instead.
        var states: [MetricState] = []
        var analyses: [PremiumMetricID: PremiumMetricAnalysis] = [:]
        for def in PremiumMetricCatalog.all where !def.isDerived {
            let a = PremiumMetricCatalog.analysis(def.id, repo: repo)
            guard !a.series.isEmpty else { continue }
            analyses[def.id] = a
            states.append(MetricState(
                id: def.id, name: def.name, unit: def.unit, provenance: def.provenance,
                current: a.latest, baseline: a.baseline, deviationPct: a.deviationPct,
                deviationAbs: a.deviationAbs,
                change7: a.change7, change7Abs: a.change7Abs, change30: a.change30, trend: a.trend,
                sampleCount: a.series.count))
        }

        // ---- Sleep state --------------------------------------------------------------------
        let sleepNeed = sleepNeedMinutes(repo: repo)
        let asleepSeries = PremiumMetricCatalog.series(.sleepDuration, repo: repo)
        let balance: Double? = {
            let recent = asleepSeries.suffix(7).map(\.value)
            guard recent.count >= 3, let m = PremiumAnalysis.mean(recent) else { return nil }
            return m - sleepNeed
        }()
        let sleepState = SleepState(
            lastNightInBedMin: sleepIntel.nights.last?.inBedMin,
            lastNightAsleepMin: asleepSeries.last?.value,
            wasoMin: sleepIntel.latestIntervals.isEmpty ? nil : sleepIntel.wasoMin,
            awakeningCount: sleepIntel.latestIntervals.isEmpty ? nil : sleepIntel.awakeningCount,
            longestAwakeMin: sleepIntel.latestIntervals.isEmpty ? nil : sleepIntel.longestAwakeMin,
            bedtimeVariabilityMin: sleepIntel.bedtimeVariability(),
            wakeVariabilityMin: sleepIntel.wakeVariability(),
            midpointVariabilityMin: sleepIntel.midpointVariability(),
            regularityScore: sleepIntel.regularityScore(),
            weekendShiftMin: sleepIntel.weekendShiftMinutes(),
            sleepNeedMin: sleepNeed,
            balanceMin: balance,
            nightsAnalysed: sleepIntel.nights.count)

        // ---- Heart state --------------------------------------------------------------------
        let rhrA = analyses[.restingHr]
        let hrvA = analyses[.hrv]
        let heartState = HeartState(
            liveBpm: liveBpm,
            restingHr: rhrA?.latest, restingHrBaseline: rhrA?.baseline,
            hrv: hrvA?.latest, hrvBaseline: hrvA?.baseline,
            dayMinBpm: dayHR.min(), dayMaxBpm: dayHR.max(),
            dayAvgBpm: PremiumAnalysis.mean(dayHR),
            minutesInZone: minutesInZone)

        // ---- Journal ------------------------------------------------------------------------
        var behaviorDays: [String: Set<String>] = [:]
        for e in journalEntries where e.answeredYes {
            behaviorDays[e.question, default: []].insert(e.day)
        }
        let loggedDays = Set(journalEntries.filter(\.answeredYes).map(\.day))
        let todayKey = Repository.localDayKey(Date())

        // Ranked factor comparisons, computed by the SAME `PremiumJournalIntel` the Journal screen
        // renders — so the Coach can never state a number the user can't find in the UI, and can
        // never be handed a comparison that failed the sample-size gate. Capped because a prompt
        // wants the headline findings, not every factor×outcome pair the engine produced.
        let intel = await PremiumJournalIntel.load(repo: repo) { $0 }
        let factorFindings: [JournalFactorFinding] = intel.topPerFactor.prefix(8).map { d in
            JournalFactorFinding(
                factor: d.factorDisplay,
                outcome: PremiumMetricCatalog.def(d.outcome).shortName,
                withValue: d.effect.meanWith,
                withoutValue: d.effect.meanWithout,
                difference: d.effect.delta,
                pctDifference: d.effect.pctChange,
                sampleSize: d.totalSamples,
                confidence: d.confidence,
                lagDays: d.lagDays)
        }

        let journalState = JournalState(
            behaviorDays: behaviorDays,
            daysLogged: loggedDays.count,
            currentStreak: streak(days: loggedDays),
            todayLogged: loggedDays.contains(todayKey),
            factorFindings: factorFindings)

        // ---- Findings -----------------------------------------------------------------------
        var findings: [PremiumFinding] = []

        // 1. Baseline deviations for the headline signals.
        for id in [PremiumMetricID.hrv, .restingHr, .recovery, .sleepDuration, .respiratory] {
            guard let a = analyses[id] else { continue }
            let def = PremiumMetricCatalog.def(id)
            if let f = PremiumAnalysis.baselineFinding(a, name: def.shortName,
                                                       unit: def.unit, tint: def.tint) {
                findings.append(f)
            }
        }

        // 2. Sleep timing drift (this week vs the week before).
        let bedSeries = sleepIntel.bedtimeSeries(window: 30)
        if bedSeries.count >= 10 {
            let recent = Array(bedSeries.suffix(7))
            let prior = Array(bedSeries.dropLast(7).suffix(7))
            if let f = PremiumAnalysis.timingFinding(id: "timing.bedtime", label: "bedtime",
                                                     recent: recent, prior: prior,
                                                     tint: StrandPalette.sleepDeep) {
                findings.append(f)
            }
        }

        // 3. Cross-metric relationships worth surfacing.
        let pairs: [(PremiumMetricID, PremiumMetricID, Color)] = [
            (.sleepDuration, .recovery, StrandPalette.sleepDeep),
            (.hrv, .recovery, StrandPalette.metricCyan),
            (.restingHr, .recovery, StrandPalette.metricRose),
            (.strain, .recovery, StrandPalette.effortColor),
        ]
        for (a, b, tint) in pairs {
            guard let sa = analyses[a]?.series, let sb = analyses[b]?.series else { continue }
            guard let best = PremiumAnalysis.bestRelationship(sa, sb) else { continue }
            let na = PremiumMetricCatalog.def(a).shortName
            let nb = PremiumMetricCatalog.def(b).shortName
            if let f = PremiumAnalysis.relationshipFinding(
                id: "rel.\(a.rawValue).\(b.rawValue)", aName: na, bName: nb,
                correlation: best.correlation, lagDays: best.lagDays, tint: tint) {
                findings.append(f)
            }
        }

        // 4. Journal behaviour associations against the signals people actually ask about.
        let outcomes: [(PremiumMetricID, Color)] = [
            (.hrv, StrandPalette.metricCyan),
            (.recovery, StrandPalette.recoveryColor(85)),
            (.sleepDuration, StrandPalette.sleepDeep),
        ]
        for (behavior, days) in behaviorDays {
            for (outcomeID, tint) in outcomes {
                guard let series = analyses[outcomeID]?.series else { continue }
                let outcomeName = PremiumMetricCatalog.def(outcomeID).shortName
                guard let assoc = PremiumAnalysis.behaviorAssociation(
                    behaviorDays: days, behaviorName: behavior,
                    outcome: series, outcomeName: outcomeName) else { continue }
                if let f = PremiumAnalysis.behaviorFinding(effect: assoc.effect,
                                                           lagDays: assoc.lagDays, tint: tint) {
                    findings.append(f)
                }
            }
        }

        // Strongest, most-supported findings first; cap so neither the UI nor a prompt is flooded.
        findings.sort { a, b in
            if a.confidence != b.confidence { return a.confidence > b.confidence }
            return a.id < b.id
        }
        let capped = Array(findings.prefix(12))

        // ---- Data quality --------------------------------------------------------------------
        let quality = PremiumDataQuality(
            totalDays: repo.days.count,
            daysWithSleep: repo.days.filter { ($0.totalSleepMin ?? 0) > 0 }.count,
            daysWithHrv: repo.days.filter { $0.avgHrv != nil }.count,
            daysWithRhr: repo.days.filter { $0.restingHr != nil }.count,
            daysWithRecovery: repo.days.filter { $0.recovery != nil }.count,
            journalDays: loggedDays.count,
            longestGapDays: longestGap(repo.days.map(\.day)))

        return PremiumCoachContext(generatedAt: Date(), metrics: states, sleep: sleepState,
                                   heart: heartState, journal: journalState,
                                   findings: capped, dataQuality: quality)
    }

    /// The personal sleep need used across the Premium UI: at least 7.5 h, else the user's own
    /// 30-day mean — the same rule `SleepView.sleepNeedMin` applies, so the two agree.
    @MainActor
    static func sleepNeedMinutes(repo: Repository) -> Double {
        let recent = repo.days.suffix(30).compactMap(\.totalSleepMin)
        let personal = PremiumAnalysis.mean(recent) ?? 450
        return max(450, personal)
    }

    /// Consecutive days ending today (or yesterday) present in `days`.
    ///
    /// Uses `PremiumAnalysis.dayParser` rather than `Repository.localDayKey` because that helper is
    /// main-actor isolated and this needs to stay callable from any context. Both produce the same
    /// `yyyy-MM-dd` key in the current time zone, so the two agree.
    static func streak(days: Set<String>) -> Int {
        let cal = Calendar.current
        let fmt = PremiumAnalysis.dayParser
        var count = 0
        var cursor = Date()
        // A streak survives "haven't logged yet today": start from yesterday if today is absent.
        if !days.contains(fmt.string(from: cursor)) {
            guard let y = cal.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = y
        }
        while days.contains(fmt.string(from: cursor)) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    /// The longest run of missing calendar days inside the recorded range — a blunt but honest
    /// wear-consistency signal.
    static func longestGap(_ dayKeys: [String]) -> Int {
        let f = PremiumAnalysis.dayParser
        let dates = dayKeys.compactMap { f.date(from: $0) }.sorted()
        guard dates.count >= 2 else { return 0 }
        var longest = 0
        for i in 1..<dates.count {
            let gap = Calendar.current.dateComponents([.day], from: dates[i - 1], to: dates[i]).day ?? 0
            longest = max(longest, max(0, gap - 1))
        }
        return longest
    }
}
#endif
