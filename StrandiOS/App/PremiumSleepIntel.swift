#if os(iOS)
import Foundation
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// PremiumSleepIntel — the sleep-analysis layer shared by the Sleep screen and the Coach context.
///
/// Everything here is derived from REAL recorded sleep sessions: each night's main-sleep window is
/// picked with the same `SleepView.mainNightSession` learned-timing logic the classic Sleep tab
/// uses, so bedtimes, wake times and stage timelines agree across the app rather than each screen
/// re-deriving them slightly differently.
///
/// Previously the Sleep view computed all of this inline, which meant the Coach had no access to
/// it. Extracting it here gives one definition per concept and lets the Coach be handed finished
/// sleep intelligence instead of raw rows.
struct PremiumSleepIntel {

    /// One night's real sleep window plus the stage timeline when the night has one.
    struct Night: Identifiable {
        /// Calendar day the night ENDED on — the key the rest of the app groups nights by.
        let day: Date
        let dayKey: String
        let bed: Date
        let wake: Date
        /// Decoded stage intervals, empty for an imported night that stored only stage minutes.
        let intervals: [SleepInterval]

        var id: String { dayKey }
        /// Time in bed, minutes.
        var inBedMin: Double { wake.timeIntervalSince(bed) / 60 }
        /// Bedtime as minutes since the preceding noon — see `PremiumSleepIntel.minutesSinceNoon`.
        var bedMinutes: Double { PremiumSleepIntel.minutesSinceNoon(bed) }
        var wakeMinutes: Double { PremiumSleepIntel.minutesSinceNoon(wake) }
        /// Sleep midpoint on the same continuous scale (wake is always "the next day" from bed).
        var midpointMinutes: Double { (bedMinutes + wakeMinutes + 1440) / 2 }
    }

    /// Nights, oldest→newest.
    let nights: [Night]
    /// Last night's decoded stage intervals (empty when unavailable).
    let latestIntervals: [SleepInterval]
    let latestBed: Date?
    let latestWake: Date?
    /// Real overnight heart-rate buckets across last night's window.
    let overnightHR: [(t: Date, bpm: Double)]

    // MARK: - Clock helpers

    /// Minutes since the PRECEDING noon (0..<1440). Anchors an evening bedtime and the following
    /// morning's wake time on one increasing scale (11 PM → 660, 6 AM → 1080), so averaging and
    /// standard deviation behave correctly across the midnight boundary — which a plain
    /// minutes-since-midnight representation cannot do.
    static func minutesSinceNoon(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let raw = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) - 12 * 60
        return raw < 0 ? raw + 1440 : raw
    }

    static func clockText(_ minutesSinceNoon: Double) -> String {
        PremiumMetricCatalog.clockText(minutesSinceNoon)
    }

    // MARK: - Continuity (from the real decoded hypnogram)

    /// Awakenings after sleep onset. The FIRST `.awake` interval is sleep-onset latency, not an
    /// awakening, so it is excluded — counting it would inflate every night's fragmentation.
    var awakenings: [SleepInterval] {
        Array(latestIntervals.filter { $0.stage == .awake }.dropFirst())
    }
    /// Wake After Sleep Onset, minutes.
    var wasoMin: Double { awakenings.reduce(0.0) { $0 + ($1.end - $1.start) } / 60 }
    /// The single longest awake stretch after onset, minutes.
    var longestAwakeMin: Double { (awakenings.map { $0.end - $0.start }.max() ?? 0) / 60 }
    var awakeningCount: Int { awakenings.count }

    /// Minutes in each stage last night, from the real decoded timeline.
    func stageMinutes(_ stage: SleepStage) -> Double {
        latestIntervals.filter { $0.stage == stage }
            .reduce(0.0) { $0 + ($1.end - $1.start) } / 60
    }

    // MARK: - Regularity

    /// Standard deviation of bedtime across the last `window` nights, in minutes.
    func bedtimeVariability(window: Int = 14) -> Double? {
        PremiumAnalysis.stdev(Array(nights.suffix(window)).map(\.bedMinutes))
    }
    func wakeVariability(window: Int = 14) -> Double? {
        PremiumAnalysis.stdev(Array(nights.suffix(window)).map(\.wakeMinutes))
    }
    func midpointVariability(window: Int = 14) -> Double? {
        PremiumAnalysis.stdev(Array(nights.suffix(window)).map(\.midpointMinutes))
    }

    /// A 0–100 regularity score: how tightly the sleep midpoint clusters. 100 = identical every
    /// night; it decays with the midpoint's standard deviation, reaching 0 at a 3-hour spread.
    /// Presented as a *calculated* value, not a clinical index.
    func regularityScore(window: Int = 14) -> Double? {
        guard let sd = midpointVariability(window: window) else { return nil }
        let score = 100.0 * (1.0 - min(1.0, sd / 180.0))
        return max(0, min(100, score))
    }

    /// Weekday-vs-weekend bedtime shift in minutes (positive = later at weekends), the "social
    /// jetlag" comparison. `nil` unless both groups have at least two nights.
    func weekendShiftMinutes() -> Double? {
        let cal = Calendar.current
        var weekday: [Double] = [], weekend: [Double] = []
        for n in nights {
            let wd = cal.component(.weekday, from: n.day)
            if wd == 1 || wd == 7 { weekend.append(n.bedMinutes) } else { weekday.append(n.bedMinutes) }
        }
        guard weekday.count >= 2, weekend.count >= 2,
              let a = PremiumAnalysis.mean(weekend), let b = PremiumAnalysis.mean(weekday) else { return nil }
        return a - b
    }

    // MARK: - Series for charts

    func bedtimeSeries(window: Int = 30) -> [Double] { Array(nights.suffix(window)).map(\.bedMinutes) }
    func wakeSeries(window: Int = 30) -> [Double] { Array(nights.suffix(window)).map(\.wakeMinutes) }
    func midpointSeries(window: Int = 30) -> [Double] { Array(nights.suffix(window)).map(\.midpointMinutes) }

    /// Bedtime as day-keyed samples so it can be correlated against other metrics.
    func bedtimeSamples() -> [PremiumSample] {
        nights.map { PremiumSample(day: $0.dayKey, value: $0.bedMinutes) }
    }

    // MARK: - Loading

    /// Builds the intelligence from the real store. Groups every recorded session by the calendar
    /// day it ENDS on, picks each day's main-night winner with the shared learned-timing logic, and
    /// decodes last night's stage timeline plus its overnight heart rate.
    @MainActor
    static func load(repo: Repository, window: Int = 60) async -> PremiumSleepIntel {
        let sessions = await repo.allSleepSessions()
        guard !sessions.isEmpty else {
            return PremiumSleepIntel(nights: [], latestIntervals: [], latestBed: nil,
                                     latestWake: nil, overnightHR: [])
        }
        let habitual = await repo.habitualMidsleepSec()
        let cal = Calendar.current
        let groups = Dictionary(grouping: sessions) { s in
            cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(s.endTs)))
        }
        let keyFmt = DateFormatter()
        keyFmt.dateFormat = "yyyy-MM-dd"
        keyFmt.locale = Locale(identifier: "en_US_POSIX")

        let orderedDays = groups.keys.sorted().suffix(window)
        var nights: [Night] = []
        nights.reserveCapacity(orderedDays.count)

        for day in orderedDays {
            guard let main = SleepView.mainNightSession(groups[day] ?? [],
                                                        habitualMidsleepSec: habitual) else { continue }
            let bed = Date(timeIntervalSince1970: TimeInterval(main.effectiveStartTs))
            let wake = Date(timeIntervalSince1970: TimeInterval(main.endTs))
            // Reject impossible windows rather than charting them (a corrupt row must not become a
            // 40-hour night on the timing map).
            let minutes = wake.timeIntervalSince(bed) / 60
            guard minutes > 30, minutes < 1000 else { continue }
            let ivs = SleepView.decodedIntervals(main.stagesJSON,
                                                 sessionStart: main.effectiveStartTs) ?? []
            nights.append(Night(day: day, dayKey: keyFmt.string(from: day),
                                bed: bed, wake: wake, intervals: ivs))
        }

        // Last night's detail: stage timeline + real overnight HR across the same window.
        var latestIntervals: [SleepInterval] = []
        var latestBed: Date?, latestWake: Date?
        var hr: [(t: Date, bpm: Double)] = []
        if let newest = orderedDays.last,
           let main = SleepView.mainNightSession(groups[newest] ?? [], habitualMidsleepSec: habitual) {
            latestIntervals = SleepView.decodedIntervals(main.stagesJSON,
                                                         sessionStart: main.effectiveStartTs) ?? []
            latestBed = Date(timeIntervalSince1970: TimeInterval(main.effectiveStartTs))
            latestWake = Date(timeIntervalSince1970: TimeInterval(main.endTs))
            let buckets = await repo.hrBuckets(from: main.effectiveStartTs, to: main.endTs,
                                               bucketSeconds: 120)
            hr = buckets.compactMap { b in
                guard b.bpm > 0 else { return nil }
                return (t: Date(timeIntervalSince1970: TimeInterval(b.ts)), bpm: b.bpm)
            }
        }

        return PremiumSleepIntel(nights: nights, latestIntervals: latestIntervals,
                                 latestBed: latestBed, latestWake: latestWake, overnightHR: hr)
    }
}
#endif
