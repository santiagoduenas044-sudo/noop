import Foundation

// SleepRegularity.swift — sleep-TIMING regularity over a trailing window of nights.
//
// PURELY ADDITIVE. This file introduces NO change to any Charge / Effort / Rest / sleep
// output. It is a brand-new, opt-in descriptive estimator the UI lanes can surface later
// (mirrors the way HRVFreqDomain / RhythmScreener landed their math ahead of the UI).
//
// WHAT IT MEASURES — and why it is a distinct signal from the ones NOOP already has:
//   NOOP already tracks how MUCH you slept (SleepDebt), how RESTORATIVE it was (Rest), and
//   the beat-to-beat regularity WITHIN a night (RhythmScreener). It does NOT track how
//   CONSISTENT the TIMING of your sleep is from night to night — i.e. whether you go to bed
//   and wake at a steady clock time or all over the map. That circadian *timing regularity*
//   is an independent, well-validated axis of sleep health: irregular sleep timing tracks
//   with worse cardiometabolic and mood outcomes even when total duration is held constant
//   (e.g. the sleep-regularity literature around Phillips et al. 2017; the "social jetlag"
//   line, Wittmann et al. 2006). We surface it as a plain, non-clinical descriptive read.
//
// WHY CIRCULAR STATISTICS (the correctness crux — read this before touching the math):
//   A clock time lives on a 24-hour CIRCLE, not a line. A midpoint of 23:50 one night and
//   00:10 the next are 20 minutes apart, NOT 23 h 40 m apart. A naive linear standard
//   deviation of "minutes past midnight" would report an ENORMOUS spurious variance for a
//   person who sleeps rock-steady around midnight, and would rank them as maximally
//   IRREGULAR — the exact opposite of the truth. So every timing statistic here is computed
//   with directional (circular) statistics: each clock time becomes an angle on the circle,
//   we average the unit vectors, and the spread is read from the mean resultant length R.
//     • R (mean resultant length) ∈ [0, 1]: 1 = every night at the same clock time
//       (perfectly regular); → 0 = times spread all around the circle (no rhythm).
//     • circular SD = sqrt(−2·ln R), converted from radians to MINUTES for a legible read
//       ("your sleep midpoint varied by ±X minutes"). Small = regular; large = irregular.
//
// HONEST by construction:
//   • Descriptive only — no clinical verdict, no condition name, no call-to-action. The
//     label is a benign four-way category (veryRegular / regular / variable / irregular).
//   • Nights with an implausible duration (a mis-staged nap, a data glitch) are SKIPPED, not
//     zero-filled — a gap never manufactures irregularity (mirrors SleepDebt's skip rule).
//   • Below `minNights` readable nights the read is withheld (label .unreadable, score nil,
//     confidence .calibrating) rather than faked from too little history.
//   • The 0–100 score is a documented, strictly-monotonic convenience over the circular SD;
//     the SD in minutes and R are the primary, interpretable outputs.
//
// PARITY: constant-explicit and dependency-free so the Kotlin mirror
// (android/…/analytics/SleepRegularity.kt) is byte-identical. Every SURFACED number is
// rounded (SD 1 dp, R 3 dp, score integer, mean-midpoint whole minute) and the label is
// derived from the ROUNDED SD, so tiny cross-platform libm ULP differences in cos/ln/exp
// can never diverge the reported value or the label between the two clients.

/// One night's sleep-timing inputs: its day key plus the local minute-of-day of sleep onset
/// and of final wake. The caller (app layer) supplies these from the staged session; this
/// engine stays a pure function of the timings. Minutes-of-day are 0…1439 (midnight = 0);
/// a window that crosses midnight is handled by the circular math, so `wakeMinOfDay` may be
/// numerically *smaller* than `onsetMinOfDay` (e.g. asleep 23:00 → 1380, wake 07:00 → 420).
public struct SleepTimingNight: Equatable, Sendable {
    /// "yyyy-MM-dd" day key for the night (as carried on the DailyMetric).
    public let day: String
    /// Local minute-of-day of sleep onset (0…1439).
    public let onsetMinOfDay: Int
    /// Local minute-of-day of final wake (0…1439).
    public let wakeMinOfDay: Int

    public init(day: String, onsetMinOfDay: Int, wakeMinOfDay: Int) {
        self.day = day
        self.onsetMinOfDay = onsetMinOfDay
        self.wakeMinOfDay = wakeMinOfDay
    }

    /// Sleep duration (minutes) as the forward arc onset → wake on the 24 h circle, so an
    /// overnight window (wake numerically before onset) yields the correct positive length.
    public var durationMin: Double {
        let d = ((wakeMinOfDay - onsetMinOfDay) % 1440 + 1440) % 1440
        return Double(d)
    }

    /// Sleep midpoint as a minute-of-day (0…1440), = onset + duration/2 wrapped onto the
    /// circle. This is the primary timing anchor the regularity read is built on, and the
    /// point the dial plots per night.
    public var midpointMinOfDay: Double {
        let mid = (Double(onsetMinOfDay) + durationMin / 2.0)
            .truncatingRemainder(dividingBy: 1440.0)
        return mid < 0 ? mid + 1440.0 : mid
    }

    /// Build a night from unix-epoch onset/wake timestamps, resolving each to a LOCAL
    /// minute-of-day in `timeZone` and keying the night by the wake date's civil day. Kept here
    /// (not in the app layer) so the timezone math is covered by `swift test`. The app passes the
    /// session's `effectiveStartTs` (honours a hand-edited onset) and `endTs`.
    public static func from(onsetEpoch: Int, wakeEpoch: Int,
                            timeZone: TimeZone = .current) -> SleepTimingNight {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let wakeDate = Date(timeIntervalSince1970: TimeInterval(wakeEpoch))
        return SleepTimingNight(day: fmt.string(from: wakeDate),
                                onsetMinOfDay: Self.minuteOfDay(onsetEpoch, cal),
                                wakeMinOfDay: Self.minuteOfDay(wakeEpoch, cal))
    }

    static func minuteOfDay(_ epoch: Int, _ cal: Calendar) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(epoch)))
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// Neutral, non-clinical timing-regularity category. Copy is deliberately benign — no
/// disease names, no diagnosis, no call-to-action. User-facing strings map these to plain
/// language, e.g. .veryRegular → "very consistent", .irregular → "all over the place".
public enum SleepRegularityLabel: String, Codable, Sendable, Equatable {
    case veryRegular
    case regular
    case variable
    case irregular
    case unreadable
}

/// The result of a timing-regularity assessment over the trailing window. Every surfaced
/// number is pre-rounded for cross-platform parity (see file header). Optional fields are
/// nil when the window was unreadable (fewer than `minNights` usable nights).
public struct SleepRegularityResult: Equatable, Sendable, Codable {
    /// 0–100 regularity score (100 = perfectly consistent timing). nil when unreadable.
    public let score: Int?
    /// Neutral descriptive category.
    public let label: SleepRegularityLabel
    /// Read certainty from the usable-night count (mirrors ScoreConfidence's tiers).
    public let confidence: ScoreConfidence
    /// Circular SD of the sleep MIDPOINT (minutes, 1 dp) — the headline "±X min" spread. nil when unreadable.
    public let midpointSDMinutes: Double?
    /// Circular SD of sleep ONSET (minutes, 1 dp) — bedtime consistency. nil when unreadable.
    public let onsetSDMinutes: Double?
    /// Circular SD of final WAKE (minutes, 1 dp) — wake consistency. nil when unreadable.
    public let wakeSDMinutes: Double?
    /// Circular MEAN sleep midpoint as a minute-of-day (0…1439) — "your typical mid-sleep". nil when unreadable.
    public let meanMidpointMinOfDay: Int?
    /// Mean resultant length R of the midpoint (0…1, 3 dp): 1 = identical timing every night. nil when unreadable.
    public let resultantLength: Double?
    /// Number of usable nights that fed the read (implausible nights skipped, window capped).
    public let nightCount: Int

    public init(score: Int?, label: SleepRegularityLabel, confidence: ScoreConfidence,
                midpointSDMinutes: Double?, onsetSDMinutes: Double?, wakeSDMinutes: Double?,
                meanMidpointMinOfDay: Int?, resultantLength: Double?, nightCount: Int) {
        self.score = score
        self.label = label
        self.confidence = confidence
        self.midpointSDMinutes = midpointSDMinutes
        self.onsetSDMinutes = onsetSDMinutes
        self.wakeSDMinutes = wakeSDMinutes
        self.meanMidpointMinOfDay = meanMidpointMinOfDay
        self.resultantLength = resultantLength
        self.nightCount = nightCount
    }

    /// True when the read is a real assessment (enough nights) rather than a withheld one.
    public var isReadable: Bool { label != .unreadable }

    /// The withheld read: too few usable nights to say anything honestly.
    static func unreadable(nightCount: Int) -> SleepRegularityResult {
        SleepRegularityResult(score: nil, label: .unreadable, confidence: .calibrating,
                              midpointSDMinutes: nil, onsetSDMinutes: nil, wakeSDMinutes: nil,
                              meanMidpointMinOfDay: nil, resultantLength: nil, nightCount: nightCount)
    }
}

public enum SleepRegularity {

    // MARK: - Thresholds (named, tunable in one place; tuned only on synthetic fixtures)

    /// Trailing window of nights to assess — a fortnight, matching SleepDebt: recent enough
    /// to be actionable, long enough for a stable timing read.
    public static let defaultWindowNights: Int = 14

    /// Minimum usable nights before a read is attempted at all. Below this the timing spread
    /// is too poorly determined to report; the read is withheld (.unreadable / .calibrating).
    public static let minNights: Int = 3

    /// Usable-night count at/above which the read is `.solid` — a full week of timings.
    public static let solidNights: Int = 7

    /// Plausible sleep-duration band (minutes). A night outside this is treated as a
    /// mis-staged nap / data glitch and SKIPPED, so garbage can't distort the circular stats.
    public static let minDurationMin: Double = 180.0   // 3 h
    public static let maxDurationMin: Double = 960.0   // 16 h

    /// Score scale (minutes): score = 100·exp(−midpointSD / scoreScaleMin). A larger scale is
    /// gentler. At 135 min: SD 0 → 100, ~30 → 80, ~60 → 64, ~120 → 41, ~180 → 26.
    public static let scoreScaleMin: Double = 135.0

    /// Midpoint circular-SD band edges (minutes) for the descriptive label. Derived from the
    /// ROUNDED SD so label and number never disagree across platforms.
    public static let tauVeryRegularMin: Double = 30.0
    public static let tauRegularMin: Double = 60.0
    public static let tauVariableMin: Double = 120.0

    /// Floor on R before ln, so a fully-dispersed set (R→0) yields a finite, capped SD
    /// instead of a non-finite one. Astronomically small in practice.
    static let rFloor: Double = 1e-9

    // MARK: - Public API

    /// The nights an assessment actually uses: implausible-duration nights dropped, chronological
    /// order preserved, capped to the most-recent `window`. Exposed so the dial can plot exactly
    /// the nights the score was built from (one source of truth for the windowing).
    public static func windowedNights(_ nights: [SleepTimingNight],
                                      window: Int = defaultWindowNights) -> [SleepTimingNight] {
        let cap = max(window, 1)
        let usable = nights.filter {
            let d = $0.durationMin
            return d >= minDurationMin && d <= maxDurationMin
        }
        return Array(usable.suffix(cap))
    }

    /// Assess sleep-timing regularity over the most-recent usable nights.
    ///
    /// - Parameters:
    ///   - nights: per-night timings in CHRONOLOGICAL order (oldest → newest). Nights with an
    ///     implausible duration are skipped.
    ///   - window: how many of the most-recent USABLE nights to include (default 14, ≥ 1).
    /// - Returns: a descriptive result. When fewer than `minNights` usable nights are present,
    ///   the read is withheld (`.unreadable`, score nil, `.calibrating`).
    public static func assess(nights: [SleepTimingNight],
                              window: Int = defaultWindowNights) -> SleepRegularityResult {
        let windowed = windowedNights(nights, window: window)

        guard windowed.count >= minNights else {
            return .unreadable(nightCount: windowed.count)
        }

        let midStats = circularStats(windowed.map { $0.midpointMinOfDay })
        let onsetStats = circularStats(windowed.map { Double($0.onsetMinOfDay) })
        let wakeStats = circularStats(windowed.map { Double($0.wakeMinOfDay) })

        // Round the headline SD FIRST, then derive both the score and the label from that same
        // rounded value — so the number, the score and the label are mutually consistent and
        // parity-stable regardless of tiny libm differences.
        let midSD = round1(midStats.sdMin)
        let score = round0(100.0 * exp(-midSD / scoreScaleMin))
        let label = classify(midpointSD: midSD)

        let meanMid = Int(midStats.meanMinOfDay.rounded()) % 1440

        return SleepRegularityResult(
            score: score,
            label: label,
            confidence: confidence(for: windowed.count),
            midpointSDMinutes: midSD,
            onsetSDMinutes: round1(onsetStats.sdMin),
            wakeSDMinutes: round1(wakeStats.sdMin),
            meanMidpointMinOfDay: meanMid,
            resultantLength: round3(midStats.r),
            nightCount: windowed.count)
    }

    // MARK: - Circular statistics

    /// Directional statistics over a set of clock times expressed as minutes-of-day.
    /// Returns the circular SD (minutes), the mean resultant length R (0…1) and the circular
    /// mean as a minute-of-day (0…1440). See the file header for why this must be circular.
    static func circularStats(_ minutes: [Double]) -> (sdMin: Double, r: Double, meanMinOfDay: Double) {
        let n = Double(minutes.count)
        guard n > 0 else { return (0, 1, 0) }
        let twoPi = 2.0 * Double.pi
        var sumCos = 0.0
        var sumSin = 0.0
        for m in minutes {
            let ang = (m / 1440.0) * twoPi
            sumCos += cos(ang)
            sumSin += sin(ang)
        }
        let c = sumCos / n
        let s = sumSin / n
        // Clamp R into (0, 1]: ≤ 1 keeps the sqrt real; ≥ rFloor keeps ln finite.
        let r = min(max((c * c + s * s).squareRoot(), rFloor), 1.0)
        let sdRad = (-2.0 * log(r)).squareRoot()
        let sdMin = sdRad * (1440.0 / twoPi)
        var meanAng = atan2(s, c)
        if meanAng < 0 { meanAng += twoPi }
        let meanMin = (meanAng / twoPi) * 1440.0
        return (sdMin, r, meanMin)
    }

    // MARK: - Classification & confidence

    /// Map the (rounded) midpoint circular SD to a neutral descriptive label.
    static func classify(midpointSD: Double) -> SleepRegularityLabel {
        if midpointSD <= tauVeryRegularMin { return .veryRegular }
        if midpointSD <= tauRegularMin { return .regular }
        if midpointSD <= tauVariableMin { return .variable }
        return .irregular
    }

    /// Read certainty from the usable-night count, mirroring ScoreConfidence's tiers.
    static func confidence(for nights: Int) -> ScoreConfidence {
        if nights < minNights { return .calibrating }
        return nights >= solidNights ? .solid : .building
    }

    // MARK: - Rounding (sign-aware, half-away-from-zero — mirrors SleepDebt.round1)

    /// Round to 1 dp, half-away-from-zero, matching Swift's `Double.rounded()` and the
    /// Kotlin mirror's sign-aware helper so both clients report the same value.
    static func round1(_ v: Double) -> Double { (v * 10.0).rounded() / 10.0 }
    /// Round to 3 dp (for R), same rounding rule.
    static func round3(_ v: Double) -> Double { (v * 1000.0).rounded() / 1000.0 }
    /// Round to the nearest integer, half-away-from-zero (score).
    static func round0(_ v: Double) -> Int { Int(v.rounded()) }
}
