#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// The set of single-signal metrics the reusable `PremiumMetricDetailView` can render. Each case maps to
/// one real `DailyMetric` field (the mapping lives in `PremiumMetricKit.descriptor`), so a detail screen
/// is fully described by its kind + the live `Repository` — nothing is hardcoded per-screen. Blood-oxygen,
/// energy and strain get their OWN richer screens (`PremiumBloodOxygenView` / `PremiumEnergyView` /
/// `PremiumStrainView`); this covers the "value + trend + baseline" signals (HRV, resting HR, respiratory,
/// steps, recovery, sleep performance).
enum PremiumMetricKind: String, Hashable, CaseIterable {
    case hrv, restingHr, respiratory, steps, recovery, sleep
}

/// One (day, value) sample for a metric's history. `day` is the `YYYY-MM-DD` key so points stay ordered and
/// de-dupe naturally; oldest→newest.
struct PremiumMetricPoint: Identifiable, Hashable {
    let day: String
    let value: Double
    var id: String { day }
}

/// A fully-resolved description of one metric, computed from live `Repository` data — the single input to
/// `PremiumMetricDetailView`. Holds display metadata (name/unit/tint/icon/decimals) plus the real history
/// (`series`), the recent-baseline mean, and a plain-language explanation. `higherBetter` is `nil` for
/// signals with no single "good" direction (respiratory rate, steps): the detail screen then omits the
/// good/bad delta colouring and states the value neutrally.
struct PremiumMetricDescriptor {
    let kind: PremiumMetricKind
    let name: String            // "Heart Rate Variability"
    let shortName: String       // "HRV"
    let unit: String            // "ms" (may be "")
    let tint: Color
    let icon: String            // SF Symbol
    let decimals: Int
    let higherBetter: Bool?     // nil = neutral / context-dependent
    let series: [PremiumMetricPoint]   // oldest→newest, real values only
    let explanation: String

    /// The mean of the most recent `window` samples (default 30) — the "baseline" a hero value is compared
    /// against. `nil` when there aren't at least a few samples to average, so the UI shows "—" rather than a
    /// baseline built from one night.
    func baseline(window: Int = 30) -> Double? {
        let recent = series.suffix(window)
        guard recent.count >= 3 else { return nil }
        return recent.map(\.value).reduce(0, +) / Double(recent.count)
    }

    /// The freshest real value (last point), or nil when the strap has never recorded this signal.
    var latest: Double? { series.last?.value }

    /// Formats a value with this metric's decimals + unit (e.g. `62 ms`, `13.4 rpm`). `withUnit: false`
    /// drops the unit for tight callouts.
    func format(_ v: Double, withUnit: Bool = true) -> String {
        let num = decimals == 0 ? String(Int(v.rounded()))
                                : String(format: "%.\(decimals)f", v)
        return withUnit && !unit.isEmpty ? "\(num) \(unit)" : num
    }
}

/// Turns a `PremiumMetricKind` + the live `Repository` into a `PremiumMetricDescriptor`. This is the ONE
/// place a metric's field-mapping, palette tint, icon and copy live, so every screen that shows the metric
/// (Home tile, detail screen, future widgets) stays consistent. Reads only `repo.days` (oldest→newest) —
/// the same banked history the rest of the Premium UI uses — and compact-maps out the nil samples so the
/// series is real values only.
///
/// `@MainActor`-isolated: it reads `Repository.days`, a `@Published` property on the main-actor `Repository`.
/// A SwiftUI `View` is implicitly main-actor so the other Premium screens touch `repo.days` freely, but this
/// is a plain `enum` — without the annotation its `static` methods are nonisolated and can't read `days`.
/// Every caller is a Premium view (already main actor), so this costs nothing at the call sites.
@MainActor
enum PremiumMetricKit {

    static func descriptor(for kind: PremiumMetricKind, repo: Repository) -> PremiumMetricDescriptor {
        switch kind {
        case .hrv:
            return build(kind, name: "Heart Rate Variability", short: "HRV", unit: "ms",
                         tint: StrandPalette.metricCyan, icon: "waveform.path.ecg",
                         decimals: 0, higherBetter: true, repo: repo,
                         value: { $0.avgHrv },
                         explanation: "The beat-to-beat variation in your heart rate, measured overnight. Higher HRV generally reflects a well-recovered, adaptable nervous system; a drop below your baseline can flag accumulated strain, illness or poor sleep.")
        case .restingHr:
            return build(kind, name: "Resting Heart Rate", short: "Resting HR", unit: "bpm",
                         tint: StrandPalette.metricRose, icon: "heart.fill",
                         decimals: 0, higherBetter: false, repo: repo,
                         value: { $0.restingHr.map(Double.init) },
                         explanation: "Your lowest heart rate during sleep. A lower resting heart rate usually signals good cardiovascular fitness and recovery; a rise above baseline often accompanies stress, dehydration or the onset of illness.")
        case .respiratory:
            return build(kind, name: "Respiratory Rate", short: "Respiratory", unit: "rpm",
                         tint: StrandPalette.recoveryColor(80), icon: "lungs.fill",
                         decimals: 1, higherBetter: nil, repo: repo,
                         value: { $0.respRateBpm },
                         explanation: "Breaths per minute measured while you sleep. It's remarkably stable night to night, so a sustained change from your own baseline — up or down — is worth noticing rather than any single \"ideal\" number.")
        case .steps:
            return build(kind, name: "Steps", short: "Steps", unit: "",
                         tint: StrandPalette.metricAmber, icon: "figure.walk",
                         decimals: 0, higherBetter: nil, repo: repo,
                         value: { $0.steps.map(Double.init) },
                         explanation: "Your daily step count, estimated on-device from the strap's motion counter. A rough gauge of everyday movement — useful as a trend, not a precise pedometer.")
        case .recovery:
            return build(kind, name: "Recovery", short: "Recovery", unit: "%",
                         tint: StrandPalette.recoveryColor(80), icon: "bolt.heart.fill",
                         decimals: 0, higherBetter: true, repo: repo,
                         value: { $0.recovery },
                         explanation: "A daily readiness score blended from your overnight HRV, resting heart rate, sleep and respiratory rate. Higher means your body is better placed to take on strain today.")
        case .sleep:
            return build(kind, name: "Sleep Performance", short: "Sleep", unit: "%",
                         tint: StrandPalette.sleepDeep, icon: "bed.double.fill",
                         decimals: 0, higherBetter: true, repo: repo,
                         // `efficiency` is stored as a FRACTION in [0,1]; normalise to a percentage the same
                         // defensive way `SleepView.efficiencyPct` / PremiumHomeView do (a raw 0.92 → 92, not 1).
                         value: { $0.efficiency.map { $0 <= 1.0 ? $0 * 100 : $0 } },
                         explanation: "How much of your time in bed was spent actually asleep. Consistently high sleep performance means efficient, unbroken nights; a low score points to restlessness or fragmented sleep.")
        }
    }

    /// Shared builder: pulls the metric's real samples out of `repo.days` (nil-free, oldest→newest) and packs
    /// them into a descriptor with the supplied display metadata.
    private static func build(_ kind: PremiumMetricKind, name: String, short: String, unit: String,
                              tint: Color, icon: String, decimals: Int, higherBetter: Bool?,
                              repo: Repository, value: (DailyMetric) -> Double?,
                              explanation: String) -> PremiumMetricDescriptor {
        let points = repo.days.compactMap { d -> PremiumMetricPoint? in
            guard let v = value(d) else { return nil }
            return PremiumMetricPoint(day: d.day, value: v)
        }
        return PremiumMetricDescriptor(kind: kind, name: name, shortName: short, unit: unit,
                                       tint: tint, icon: icon, decimals: decimals,
                                       higherBetter: higherBetter, series: points,
                                       explanation: explanation)
    }
}
#endif
