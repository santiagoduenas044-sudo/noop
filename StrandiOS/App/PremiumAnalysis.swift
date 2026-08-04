#if os(iOS)
import Foundation
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// PremiumAnalysis — the deterministic personal-analysis layer behind the Premium UI.
///
/// Every number the Premium screens surface as an *interpretation* ("9% below your baseline",
/// "shifted 43 minutes later", "these two move together") is computed HERE, in plain Swift, from
/// the user's own banked history. Nothing is inferred by a model and nothing is invented: the
/// engine either has enough real samples to compute a result or it reports `nil` and the UI says
/// so. This is also the layer the future Claude-powered Coach reads from — the Coach is handed
/// finished, already-computed findings so it can *explain* them, never asked to discover them.
///
/// Design rules:
/// * **Pure + nonisolated.** Every function takes plain arrays and returns plain values, so it is
///   cheap, testable and callable off the main actor. Only the small `@MainActor` builder at the
///   bottom touches `Repository`.
/// * **Reuses the shipping analytics package** (`CorrelationEngine`, `BehaviorInsights`,
///   `SleepDebt`) rather than re-deriving statistics that already have tests. This file adds the
///   *personal-history framing* on top: baselines, deltas, run-lengths, confidence and provenance.
/// * **Honest thresholds.** A relationship needs a real sample count before it is shown at all,
///   and its strength is labelled (`early` / `emerging` / `consistent`) so a thin pattern can
///   never read as an established fact.
enum PremiumAnalysis {}

// MARK: - Provenance (data-integrity labelling)

/// Where a displayed number actually came from. Shown next to values so a wearable *estimate* is
/// never mistaken for a clinical measurement, per the app's data-integrity rules.
enum PremiumProvenance: String, Hashable {
    /// A direct sensor reading (heart rate sampled by the strap's PPG).
    case measured
    /// Computed on-device from sensor patterns — sleep stages, HRV, respiratory rate, SpO₂.
    case estimated
    /// Arithmetic over other stored values — efficiency, consistency, debt, balance.
    case calculated

    var label: String {
        switch self {
        case .measured:  return String(localized: "Measured")
        case .estimated: return String(localized: "Estimated")
        case .calculated: return String(localized: "Calculated")
        }
    }
    var explanation: String {
        switch self {
        case .measured:
            return String(localized: "A direct sensor reading from your strap.")
        case .estimated:
            return String(localized: "Computed on-device from sensor patterns. Not a clinical measurement.")
        case .calculated:
            return String(localized: "Derived arithmetically from other values NOOP already stores.")
        }
    }
    var tint: Color {
        switch self {
        case .measured:  return StrandPalette.metricRose
        case .estimated: return StrandPalette.metricAmber
        case .calculated: return StrandPalette.textTertiary
        }
    }
}

// MARK: - Confidence

/// How much history stands behind a detected relationship. Gates the language the UI is allowed
/// to use: an `early` signal is described as a possibility, a `consistent` one as a pattern.
enum PremiumConfidence: Int, Comparable, Hashable {
    case early = 0
    case emerging = 1
    case consistent = 2

    var label: String {
        switch self {
        case .early:      return String(localized: "Early signal")
        case .emerging:   return String(localized: "Emerging pattern")
        case .consistent: return String(localized: "Consistent pattern")
        }
    }
    var tint: Color {
        switch self {
        case .early:      return StrandPalette.textTertiary
        case .emerging:   return StrandPalette.metricAmber
        case .consistent: return StrandPalette.recoveryColor(85)
        }
    }
    static func < (a: PremiumConfidence, b: PremiumConfidence) -> Bool { a.rawValue < b.rawValue }

    /// Confidence from sample count + statistical strength. Deliberately conservative: a large |r|
    /// on 5 points is still only an early signal, because n is what makes it trustworthy.
    static func from(n: Int, strength: Double) -> PremiumConfidence {
        let s = abs(strength)
        if n >= 21 && s >= 0.45 { return .consistent }
        if n >= 10 && s >= 0.30 { return .emerging }
        return .early
    }
}

// MARK: - Trend direction

enum PremiumTrendDirection: Hashable {
    case rising, falling, stable

    var symbol: String {
        switch self {
        case .rising:  return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .stable:  return "arrow.right"
        }
    }
    var word: String {
        switch self {
        case .rising:  return String(localized: "rising")
        case .falling: return String(localized: "falling")
        case .stable:  return String(localized: "steady")
        }
    }
}

// MARK: - Samples

/// One (day, value) pair. `day` is the `yyyy-MM-dd` key so series align across metrics by calendar
/// day — the join key every correlation in this file uses.
struct PremiumSample: Hashable {
    let day: String
    let value: Double
}

// MARK: - Physiological validation

/// Hard bounds per signal. Values outside these are *rejected as bad reads*, never displayed and
/// never allowed into a baseline — the "fix impossible values" rule. Bounds are deliberately wide
/// (they reject impossibilities, not unusual-but-real readings).
enum PremiumBounds {
    static let ranges: [String: ClosedRange<Double>] = [
        "hrv":          1...400,      // ms rMSSD
        "restingHr":    25...140,     // bpm
        "respiratory":  4...40,       // breaths/min
        "spo2":         70...100,     // %
        "skinTemp":     -8...8,       // °C deviation
        "recovery":     0...100,      // %
        "strain":       0...21,       // WHOOP scale
        "sleepEfficiency": 0...100,   // %
        "sleepDuration": 1...1200,    // minutes (20h ceiling)
        "steps":        0...200_000,
        "activeKcal":   0...20_000,
        "restingKcal":  0...10_000,
    ]

    /// True when `v` is a physiologically possible reading for `key`. Unknown keys pass through
    /// (a metric with no declared bound is not silently dropped) but NaN/infinite never do.
    static func valid(_ v: Double, for key: String) -> Bool {
        guard v.isFinite else { return false }
        guard let r = ranges[key] else { return true }
        return r.contains(v)
    }

    /// Filters a series to physiologically possible samples only.
    static func clean(_ samples: [PremiumSample], key: String) -> [PremiumSample] {
        samples.filter { valid($0.value, for: key) }
    }
}

// MARK: - Metric analysis

/// The full deterministic read-out for ONE metric: where it is now, what "normal" is for this
/// person, how far today sits from that, and which way it has been moving. Every field is
/// optional-by-necessity — a user with three nights of history genuinely has no 90-day change,
/// and the UI must show that rather than invent one.
struct PremiumMetricAnalysis {
    let key: String
    let series: [PremiumSample]          // cleaned, oldest→newest
    let higherBetter: Bool?              // nil = no single good direction

    // Current state
    let latest: Double?
    let latestDay: String?

    // Personal baseline (30-day mean + dispersion)
    let baseline: Double?
    let spread: Double?                  // standard deviation over the baseline window
    let baselineN: Int                   // samples behind the baseline

    // Deviation of `latest` from `baseline`
    let deviationPct: Double?            // signed % vs baseline
    let deviationZ: Double?              // signed z-score vs baseline spread
    /// Signed absolute delta (`latest - baseline`) in the metric's own unit. Always computable
    /// from a subtraction (unlike `deviationPct`, which needs `baseline != 0` and blows up when the
    /// baseline sits near zero — e.g. skin-temperature deviation, which is already a deviation from
    /// the wearable's own baseline, so its OWN 30-day mean is often within a few tenths of a degree
    /// of zero). Metrics flagged `usesAbsoluteDeviation` in the catalog display this instead of
    /// `deviationPct`.
    let deviationAbs: Double?

    // Period-over-period change (mean of window vs mean of the preceding window)
    let change7: Double?                 // signed % change
    let change30: Double?
    let change90: Double?
    /// Signed absolute equivalents of `change7/30/90`, for the same near-zero-baseline reason.
    let change7Abs: Double?
    let change30Abs: Double?
    let change90Abs: Double?

    let trend: PremiumTrendDirection

    /// How many consecutive most-recent days sit on the SAME side of the baseline, and which side.
    /// Drives "…has been below your baseline for 4 days" — a run is far more meaningful than one
    /// stray reading.
    let runLength: Int
    let runBelow: Bool

    /// Mean value per weekday (1 = Sunday … 7 = Saturday), only for weekdays with ≥2 samples.
    let byWeekday: [Int: Double]

    /// True when there is enough history for the baseline to mean anything. The UI must not show a
    /// "vs baseline" comparison when this is false.
    var hasBaseline: Bool { baseline != nil && baselineN >= PremiumAnalysis.minBaselineSamples }

    /// A rolling mean over `window` days, aligned to the end of the series (for trend overlays).
    func rollingMean(window: Int) -> [PremiumSample] {
        PremiumAnalysis.rollingMean(series, window: window)
    }

    /// Deviation is "meaningful" when it clears both a relative and a dispersion-based threshold —
    /// so a metric that is naturally jumpy needs a bigger move to qualify than a stable one.
    var deviationIsMeaningful: Bool {
        guard hasBaseline, let z = deviationZ, let pct = deviationPct else { return false }
        return abs(z) >= 1.0 && abs(pct) >= 3.0
    }
}

// MARK: - Findings

/// One surfaced, already-computed observation. The Coach receives these verbatim; it is never
/// asked to derive a relationship itself.
struct PremiumFinding: Identifiable, Hashable {
    enum Category: String, Hashable {
        case baseline      // deviation from personal normal
        case trend         // sustained directional movement
        case timing        // sleep/bedtime schedule shifts
        case relationship  // two metrics moving together
        case behavior      // journal behaviour association
        case quality       // data availability/quality warning
    }

    let id: String
    let category: Category
    /// Plain-language statement. Association language only — never causal.
    let text: String
    let confidence: PremiumConfidence
    /// Supporting detail (sample counts, r values) shown as small print.
    let detail: String?
    let tint: Color

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (a: PremiumFinding, b: PremiumFinding) -> Bool { a.id == b.id }
}

// MARK: - Data quality

/// What the engine could and could not compute, so both the UI and the Coach know the limits of
/// what they are looking at rather than presenting a thin dataset as a complete picture.
struct PremiumDataQuality {
    let totalDays: Int
    let daysWithSleep: Int
    let daysWithHrv: Int
    let daysWithRhr: Int
    let daysWithRecovery: Int
    let journalDays: Int
    let longestGapDays: Int

    var hasEnoughForBaselines: Bool { totalDays >= PremiumAnalysis.minBaselineSamples }
    var hasEnoughForCorrelations: Bool { totalDays >= PremiumAnalysis.minCorrelationSamples }

    var summary: String {
        if totalDays == 0 { return String(localized: "No history recorded yet.") }
        if !hasEnoughForBaselines {
            return String(format: String(localized: "%1$d days recorded — baselines need at least %2$d."),
                          totalDays, PremiumAnalysis.minBaselineSamples)
        }
        if !hasEnoughForCorrelations {
            return String(format: String(localized: "%1$d days recorded — enough for baselines; relationships need about %2$d."),
                          totalDays, PremiumAnalysis.minCorrelationSamples)
        }
        return String(format: String(localized: "%d days recorded."), totalDays)
    }
}

// MARK: - The engine

extension PremiumAnalysis {

    /// Minimum samples before a personal baseline is computed at all.
    static let minBaselineSamples: Int = 7
    /// Minimum aligned day-pairs before a correlation is computed at all.
    static let minCorrelationSamples: Int = 10
    /// Minimum logged occurrences before a journal behaviour association is surfaced.
    static let minBehaviorOccurrences: Int = 5
    /// The rolling window used as "your baseline" throughout the Premium UI.
    static let baselineWindow: Int = 30
    /// Metrics whose baseline can sit near zero, so a PERCENT deviation is not meaningful — a
    /// skin-temperature deviation is already a deviation from the wearable's own baseline, and this
    /// app's own 30-day mean of that value is typically within a few tenths of a degree of zero.
    /// Matches `PremiumMetricDef.usesAbsoluteDeviation`; kept here too as a defensive guard so a
    /// generic sentence-generating helper never fabricates an "X% below baseline" claim for one of
    /// these even if a future call site starts feeding it one.
    static let absoluteDeviationMetricKeys: Set<String> = ["skinTemp"]

    // MARK: Series helpers

    static func mean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    static func stdev(_ xs: [Double]) -> Double? {
        guard xs.count >= 2, let m = mean(xs) else { return nil }
        let sumSq = xs.reduce(0.0) { $0 + ($1 - m) * ($1 - m) }
        return (sumSq / Double(xs.count - 1)).squareRoot()
    }

    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    /// Trailing rolling mean. Emits a point once `window` samples are available, so the line never
    /// starts from a partial (and therefore misleading) average.
    static func rollingMean(_ samples: [PremiumSample], window: Int) -> [PremiumSample] {
        guard window > 1, samples.count >= window else { return [] }
        var out: [PremiumSample] = []
        out.reserveCapacity(samples.count - window + 1)
        var running: Double = 0
        for i in 0..<samples.count {
            running += samples[i].value
            if i >= window { running -= samples[i - window].value }
            if i >= window - 1 {
                out.append(PremiumSample(day: samples[i].day, value: running / Double(window)))
            }
        }
        return out
    }

    /// Signed percent change between the mean of the last `window` samples and the mean of the
    /// `window` samples before them. `nil` unless BOTH windows are fully populated — a half-filled
    /// comparison window would silently overstate the change.
    static func periodChangePct(_ samples: [PremiumSample], window: Int) -> Double? {
        guard samples.count >= window * 2 else { return nil }
        let recent = samples.suffix(window).map(\.value)
        let prior = samples.suffix(window * 2).prefix(window).map(\.value)
        guard let a = mean(recent), let b = mean(prior), b != 0 else { return nil }
        return (a - b) / abs(b) * 100.0
    }

    /// Signed absolute period-over-period change (mean of the last `window` minus the mean of the
    /// `window` before it), in the metric's own unit. Unlike `periodChangePct` this never needs to
    /// divide by the prior mean, so it stays sane for metrics whose baseline can sit near zero.
    static func periodChangeAbs(_ samples: [PremiumSample], window: Int) -> Double? {
        guard samples.count >= window * 2 else { return nil }
        let recent = samples.suffix(window).map(\.value)
        let prior = samples.suffix(window * 2).prefix(window).map(\.value)
        guard let a = mean(recent), let b = mean(prior) else { return nil }
        return a - b
    }

    /// Consecutive most-recent samples on one side of `baseline`, plus which side.
    static func run(_ samples: [PremiumSample], baseline: Double) -> (length: Int, below: Bool) {
        guard let last = samples.last else { return (0, false) }
        let below = last.value < baseline
        var count = 0
        for s in samples.reversed() {
            let isBelow = s.value < baseline
            if isBelow == below { count += 1 } else { break }
        }
        return (count, below)
    }

    /// Mean per weekday (1 = Sunday … 7 = Saturday). Weekdays with fewer than 2 samples are
    /// omitted, so a single Tuesday never becomes "your Tuesday pattern".
    static func byWeekday(_ samples: [PremiumSample]) -> [Int: Double] {
        var buckets: [Int: [Double]] = [:]
        let cal = Calendar.current
        for s in samples {
            guard let d = dayParser.date(from: s.day) else { continue }
            let wd = cal.component(.weekday, from: d)
            buckets[wd, default: []].append(s.value)
        }
        var out: [Int: Double] = [:]
        for (wd, vals) in buckets where vals.count >= 2 {
            if let m = mean(vals) { out[wd] = m }
        }
        return out
    }

    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    // MARK: Metric analysis

    /// Full analysis for one metric from its raw (possibly dirty, possibly sparse) samples.
    static func analyze(key: String, samples raw: [PremiumSample],
                        higherBetter: Bool?) -> PremiumMetricAnalysis {
        let series = PremiumBounds.clean(raw, key: key).sorted { $0.day < $1.day }

        let latest = series.last?.value
        let latestDay = series.last?.day

        let window = Array(series.suffix(baselineWindow))
        let values = window.map(\.value)
        let baseline: Double? = values.count >= minBaselineSamples ? mean(values) : nil
        let spread: Double? = values.count >= minBaselineSamples ? stdev(values) : nil

        var devPct: Double?
        var devZ: Double?
        var devAbs: Double?
        if let b = baseline, let l = latest {
            devAbs = l - b
            if b != 0 {
                devPct = (l - b) / abs(b) * 100.0
                if let sd = spread, sd > 0 { devZ = (l - b) / sd }
            }
        }

        let c7 = periodChangePct(series, window: 7)
        let c30 = periodChangePct(series, window: 30)
        let c90 = periodChangePct(series, window: 90)
        let c7Abs = periodChangeAbs(series, window: 7)
        let c30Abs = periodChangeAbs(series, window: 30)
        let c90Abs = periodChangeAbs(series, window: 90)

        // Trend from the shortest fully-populated window, so a new user still gets a direction.
        let trendPct: Double? = c7 ?? c30 ?? c90
        let direction: PremiumTrendDirection
        if let t = trendPct {
            direction = t >= 3 ? .rising : (t <= -3 ? .falling : .stable)
        } else {
            direction = .stable
        }

        let runInfo: (length: Int, below: Bool)
        if let b = baseline { runInfo = run(series, baseline: b) } else { runInfo = (0, false) }

        return PremiumMetricAnalysis(
            key: key, series: series, higherBetter: higherBetter,
            latest: latest, latestDay: latestDay,
            baseline: baseline, spread: spread, baselineN: values.count,
            deviationPct: devPct, deviationZ: devZ, deviationAbs: devAbs,
            change7: c7, change30: c30, change90: c90,
            change7Abs: c7Abs, change30Abs: c30Abs, change90Abs: c90Abs,
            trend: direction,
            runLength: runInfo.length, runBelow: runInfo.below,
            byWeekday: byWeekday(series))
    }

    // MARK: Relationships between two metrics

    /// Correlates two metrics on shared calendar days. Returns nil below
    /// `minCorrelationSamples` aligned pairs — the threshold that keeps noise off the screen.
    static func relationship(_ a: [PremiumSample], _ b: [PremiumSample]) -> Correlation? {
        let pairs = CorrelationEngine.alignByDay(a.map { (day: $0.day, value: $0.value) },
                                                 b.map { (day: $0.day, value: $0.value) })
        guard pairs.count >= minCorrelationSamples else { return nil }
        return CorrelationEngine.pearson(pairs)
    }

    /// Same-day correlation plus the "does today's x track tomorrow's y?" lag-1 variant, returning
    /// whichever is stronger along with the lag it came from. Lagged relationships are the
    /// interesting ones for behaviour → next-morning physiology.
    static func bestRelationship(_ a: [PremiumSample], _ b: [PremiumSample])
    -> (correlation: Correlation, lagDays: Int)? {
        let ax = a.map { (day: $0.day, value: $0.value) }
        let bx = b.map { (day: $0.day, value: $0.value) }
        var best: (Correlation, Int)?
        for lag in [0, 1] {
            let c: Correlation?
            if lag == 0 {
                let pairs = CorrelationEngine.alignByDay(ax, bx)
                c = pairs.count >= minCorrelationSamples ? CorrelationEngine.pearson(pairs) : nil
            } else {
                let candidate = CorrelationEngine.lagged(x: ax, y: bx, lagDays: lag)
                c = (candidate?.n ?? 0) >= minCorrelationSamples ? candidate : nil
            }
            guard let found = c else { continue }
            if best == nil || abs(found.r) > abs(best!.0.r) { best = (found, lag) }
        }
        return best.map { (correlation: $0.0, lagDays: $0.1) }
    }

    // MARK: Behaviour associations (journal)

    /// Associates one logged behaviour with one outcome metric, using the shipping
    /// `BehaviorInsights` engine. Both same-day and next-day framings are tried; the stronger
    /// (by |Cohen's d|) wins, because a late meal plausibly shows up in the FOLLOWING morning's
    /// numbers rather than the same day's.
    ///
    /// Returns nil unless the behaviour was logged at least `minBehaviorOccurrences` times AND
    /// there are comparison days without it — an association needs both groups to exist.
    static func behaviorAssociation(behaviorDays: Set<String>, behaviorName: String,
                                    outcome: [PremiumSample], outcomeName: String)
    -> (effect: BehaviorEffect, lagDays: Int)? {
        guard behaviorDays.count >= minBehaviorOccurrences else { return nil }

        // The outcome map is lag-independent: instead of shifting outcomes backward we shift the
        // BEHAVIOUR days forward, which compares each logged day against the NEXT day's outcome
        // while keeping the outcome series untouched.
        var outcomeByDay: [String: Double] = [:]
        for s in outcome { outcomeByDay[s.day] = s.value }
        guard !outcomeByDay.isEmpty else { return nil }

        func shiftedBehaviorDays(by lag: Int) -> Set<String> {
            guard lag != 0 else { return behaviorDays }
            var out: Set<String> = []
            for d in behaviorDays {
                guard let date = dayParser.date(from: d),
                      let next = Calendar.current.date(byAdding: .day, value: lag, to: date)
                else { continue }
                out.insert(dayParser.string(from: next))
            }
            return out
        }

        var best: (BehaviorEffect, Int)?
        for lag in [0, 1] {
            let days = shiftedBehaviorDays(by: lag)
            // Only days we actually have an outcome for count toward either group.
            let overlap = days.intersection(Set(outcomeByDay.keys))
            guard overlap.count >= minBehaviorOccurrences else { continue }
            guard let e = BehaviorInsights.effect(behaviorDays: days, outcomeByDay: outcomeByDay,
                                                  behavior: behaviorName, outcome: outcomeName)
            else { continue }
            if best == nil || abs(e.cohensD) > abs(best!.0.cohensD) { best = (e, lag) }
        }
        return best.map { (effect: $0.0, lagDays: $0.1) }
    }

    // MARK: Formatting helpers

    /// Signed percent, always with an explicit sign so a delta never reads as an absolute value.
    static func signedPct(_ v: Double, decimals: Int = 0) -> String {
        let n = decimals == 0 ? String(Int(v.rounded())) : String(format: "%.\(decimals)f", v)
        return (v >= 0 ? "+" : "") + n + "%"
    }

    static func durText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        let sign = m < 0 ? "−" : ""
        let a = abs(m), h = a / 60, mm = a % 60
        return h > 0 ? "\(sign)\(h)h \(mm)m" : "\(sign)\(mm)m"
    }

    static let weekdayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
}

// MARK: - Finding generation

extension PremiumAnalysis {

    /// Turns a metric's analysis into at most one *baseline* finding — the "your HRV has been 9%
    /// below your 30-day baseline for 4 days" sentence. Emits nothing unless the deviation is
    /// meaningful and has persisted, so a single noisy night stays quiet.
    static func baselineFinding(_ a: PremiumMetricAnalysis, name: String,
                                unit: String, tint: Color) -> PremiumFinding? {
        guard !absoluteDeviationMetricKeys.contains(a.key) else { return nil }
        guard a.hasBaseline, a.deviationIsMeaningful,
              let pct = a.deviationPct, let base = a.baseline else { return nil }
        guard a.runLength >= 2 else { return nil }

        // Localized as whole sentences with positional arguments rather than assembled from
        // fragments: word order and pluralisation differ per language, so a translator needs the
        // complete sentence to work with.
        let magnitude = String(Int(abs(pct).rounded()))
        let days = a.runLength
        let template = pct < 0
            ? String(localized: "Your %1$@ has been %2$@%% below your %3$d-day baseline for %4$d days.")
            : String(localized: "Your %1$@ has been %2$@%% above your %3$d-day baseline for %4$d days.")
        let text = String(format: template, name, magnitude, a.baselineN, days)
        let baseTxt = unit.isEmpty ? String(Int(base.rounded())) : "\(Int(base.rounded())) \(unit)"
        let conf = PremiumConfidence.from(n: a.baselineN, strength: abs((a.deviationZ ?? 0) / 3.0))

        return PremiumFinding(id: "baseline.\(a.key)", category: .baseline, text: text,
                              confidence: conf,
                              detail: String(format: String(localized: "Baseline %1$@ · %2$d days"),
                                             baseTxt, a.baselineN),
                              tint: tint)
    }

    /// A *relationship* finding between two metrics ("Recovery and sleep duration have been moving
    /// together over the last month"). Always phrased as association, never cause.
    static func relationshipFinding(id: String, aName: String, bName: String,
                                    correlation: Correlation, lagDays: Int,
                                    tint: Color) -> PremiumFinding? {
        // Below this the relationship is too weak to be worth a sentence at all.
        guard abs(correlation.r) >= 0.30 else { return nil }

        let template: String
        if correlation.r > 0 {
            template = lagDays == 1
                ? String(localized: "%1$@ and %2$@ have been moving together the following day, across your recent history.")
                : String(localized: "%1$@ and %2$@ have been moving together across your recent history.")
        } else {
            template = lagDays == 1
                ? String(localized: "%1$@ and %2$@ have been moving in opposite directions the following day, across your recent history.")
                : String(localized: "%1$@ and %2$@ have been moving in opposite directions across your recent history.")
        }
        let text = String(format: template, aName, bName)
        let conf = PremiumConfidence.from(n: correlation.n, strength: correlation.r)
        let detail = String(format: String(localized: "r = %1$@ · %2$d matched days · association, not cause"),
                            String(format: "%.2f", correlation.r), correlation.n)

        return PremiumFinding(id: id, category: .relationship, text: text,
                              confidence: conf, detail: detail, tint: tint)
    }

    /// A *behaviour* finding from a journal association ("Late meals have coincided with lower HRV
    /// across 14 logged occasions"). "Coincided with" is deliberate — the engine measures
    /// co-occurrence, not causation, and the copy must not overstate it.
    static func behaviorFinding(effect: BehaviorEffect, lagDays: Int, tint: Color) -> PremiumFinding? {
        guard let pct = effect.pctChange, abs(pct) >= 3 else { return nil }
        // "Coincided with" is deliberate and must survive translation: the engine measures
        // co-occurrence, and the copy must not imply cause in any language.
        let template: String
        if effect.delta < 0 {
            template = lagDays == 1
                ? String(localized: "%1$@ has coincided with %2$d%% lower %3$@ the following morning, across %4$d logged occasions.")
                : String(localized: "%1$@ has coincided with %2$d%% lower %3$@ the same day, across %4$d logged occasions.")
        } else {
            template = lagDays == 1
                ? String(localized: "%1$@ has coincided with %2$d%% higher %3$@ the following morning, across %4$d logged occasions.")
                : String(localized: "%1$@ has coincided with %2$d%% higher %3$@ the same day, across %4$d logged occasions.")
        }
        let text = String(format: template, effect.behavior, Int(abs(pct).rounded()),
                          effect.outcome, effect.nWith)
        let conf = PremiumConfidence.from(n: min(effect.nWith, effect.nWithout),
                                          strength: abs(effect.cohensD) / 2.0)
        let detail = String(format: String(localized: "%1$d days with · %2$d without · association, not cause"),
                            effect.nWith, effect.nWithout)

        return PremiumFinding(id: "behavior.\(effect.behavior).\(effect.outcome).\(lagDays)",
                              category: .behavior, text: text, confidence: conf,
                              detail: detail, tint: tint)
    }

    /// A *timing* finding for sleep schedule drift ("Your bedtime shifted 43 minutes later this
    /// week"). Takes clock-minute series (minutes since noon, the sleep views' convention).
    static func timingFinding(id: String, label: String, recent: [Double], prior: [Double],
                              tint: Color) -> PremiumFinding? {
        guard recent.count >= 3, prior.count >= 3,
              let a = mean(recent), let b = mean(prior) else { return nil }
        let deltaMin = a - b
        guard abs(deltaMin) >= 20 else { return nil }   // under 20 min is schedule noise

        let template = deltaMin > 0
            ? String(localized: "Your %1$@ shifted %2$@ later this week.")
            : String(localized: "Your %1$@ shifted %2$@ earlier this week.")
        let text = String(format: template, label, durText(abs(deltaMin)))
        let conf = PremiumConfidence.from(n: recent.count + prior.count,
                                          strength: min(1.0, abs(deltaMin) / 60.0))
        let detail = String(format: String(localized: "%1$d recent nights vs %2$d before"),
                            recent.count, prior.count)
        return PremiumFinding(id: id, category: .timing, text: text, confidence: conf,
                              detail: detail, tint: tint)
    }
}
#endif
