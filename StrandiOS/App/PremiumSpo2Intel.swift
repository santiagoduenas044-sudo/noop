#if os(iOS)
import Foundation
import SwiftUI
import StrandDesign
import WhoopStore

/// PremiumSpo2Intel — the SpO₂ analysis layer, built strictly from REAL readings.
///
/// Two different shapes of truth feed this, and keeping them apart is the whole point:
///
/// * **Per-night history** (`nightly`) comes from `DailyMetric.spo2Pct` — ONE stored value per day.
///   It answers baseline, trend and night-to-night questions.
/// * **Individual samples** (`samples`) come straight from HealthKit for one night's window. Only
///   these can answer "lowest reading tonight", "how many readings were there", and "where were the
///   gaps" — a single daily mean cannot, and guessing them from it would be fabrication.
///
/// Nothing here invents a measurement. Every field is optional-by-necessity, and a device that has
/// never recorded SpO₂ produces an empty intel object that the UI renders as an explicit
/// unavailable state rather than a zero.
///
/// **Do not present this as continuous monitoring.** Apple Watch records SpO₂ in intermittent spot
/// checks, so `samples` is typically a handful of readings across a night, not a curve. `coverage`
/// exists so the UI can say so honestly.
struct PremiumSpo2Intel {

    /// Per-night stored percentages, oldest→newest (bounds-checked upstream by the catalog).
    let nightly: [PremiumSample]
    /// Individual real readings across the most recent night's window, oldest→newest.
    let samples: [HealthKitBridge.Spo2Sample]
    /// The window the samples were read over (last night's bed→wake when known).
    let windowStart: Date?
    let windowEnd: Date?
    /// True when Apple Health could not be queried at all (not authorised / unavailable), which is a
    /// DIFFERENT statement from "queried successfully and your hardware recorded nothing".
    let healthUnavailable: Bool

    static let empty = PremiumSpo2Intel(nightly: [], samples: [], windowStart: nil,
                                        windowEnd: nil, healthUnavailable: false)

    // MARK: - Overnight statistics (from the real samples only)

    var sampleValues: [Double] { samples.map(\.pct) }
    var overnightAverage: Double? { PremiumAnalysis.mean(sampleValues) }
    var overnightLow: Double? { sampleValues.min() }
    var overnightHigh: Double? { sampleValues.max() }
    var sampleCount: Int { samples.count }
    /// Spread between the lowest and highest reading of the night.
    var overnightRange: (lo: Double, hi: Double)? {
        guard let lo = overnightLow, let hi = overnightHigh else { return nil }
        return (lo, hi)
    }

    /// How much of the window the readings actually span, 0…1. Deliberately NOT called "coverage of
    /// monitoring": it reports the spread of intermittent spot checks, so the UI can avoid implying
    /// a continuous trace. `nil` when there aren't two samples or no window to measure against.
    var coverage: Double? {
        guard samples.count >= 2, let s = windowStart, let e = windowEnd else { return nil }
        let span = e.timeIntervalSince(s)
        guard span > 0 else { return nil }
        let covered = samples[samples.count - 1].t.timeIntervalSince(samples[0].t)
        return max(0, min(1, covered / span))
    }

    /// The longest stretch of the window with NO reading, in minutes — the honest way to describe
    /// gaps in intermittent sampling. Counts the leading and trailing edges too, so a night with two
    /// readings an hour apart in the middle of an eight-hour window reports the real gap.
    var longestGapMinutes: Double? {
        guard let s = windowStart, let e = windowEnd, !samples.isEmpty else { return nil }
        var largest: TimeInterval = samples[0].t.timeIntervalSince(s)
        for i in 1..<samples.count {
            largest = max(largest, samples[i].t.timeIntervalSince(samples[i - 1].t))
        }
        largest = max(largest, e.timeIntervalSince(samples[samples.count - 1].t))
        return largest > 0 ? largest / 60 : nil
    }

    // MARK: - Personal baseline (from stored per-night values)

    /// 30-night mean of the stored per-night values, excluding the most recent night so "tonight vs
    /// baseline" compares against history rather than against a window containing tonight itself.
    var baseline: Double? {
        let prior = nightly.dropLast()
        let window = Array(prior.suffix(PremiumAnalysis.baselineWindow)).map(\.value)
        guard window.count >= PremiumAnalysis.minBaselineSamples else { return nil }
        return PremiumAnalysis.mean(window)
    }
    var baselineNightCount: Int {
        min(nightly.dropLast().count, PremiumAnalysis.baselineWindow)
    }

    /// The most recent stored per-night value.
    var latestNightly: Double? { nightly.last?.value }

    /// Tonight against the personal baseline, in PERCENTAGE POINTS — SpO₂ is itself a percentage, so
    /// a percent-of-a-percent would be ambiguous.
    var baselineDeltaPoints: Double? {
        guard let l = latestNightly, let b = baseline else { return nil }
        return l - b
    }

    // MARK: - Availability

    /// True when there is at least one real stored reading to talk about.
    var hasNightlyData: Bool { !nightly.isEmpty }
    /// True when last night produced real individual samples.
    var hasOvernightSamples: Bool { !samples.isEmpty }

    // MARK: - Loading

    /// Builds the intel from the real store plus a live HealthKit sample read for the most recent
    /// night. `sleepIntel` supplies the night window so the overnight statistics describe the actual
    /// night rather than an arbitrary calendar day.
    @MainActor
    static func load(repo: Repository, health: HealthKitBridge,
                     sleepIntel: PremiumSleepIntel) async -> PremiumSpo2Intel {
        let nightly = PremiumMetricCatalog.series(.spo2, repo: repo)

        // Prefer last night's real bed→wake window; fall back to the last 24h so a user with SpO₂
        // readings but no recorded sleep session still sees their samples.
        let end = sleepIntel.latestWake ?? Date()
        let start = sleepIntel.latestBed ?? Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end

        let unavailable = health.auth != .authorized
        let samples = unavailable ? [] : await health.oxygenSaturationSamples(from: start, to: end)

        return PremiumSpo2Intel(nightly: nightly, samples: samples,
                                windowStart: start, windowEnd: end,
                                healthUnavailable: unavailable)
    }
}
#endif
