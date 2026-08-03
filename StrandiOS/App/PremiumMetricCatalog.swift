#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// PremiumMetricCatalog — the single registry of every health signal the Premium UI can surface.
///
/// One entry per metric describes how to READ it from the real store, how to LABEL it, what its
/// provenance is, and how to format it. Home's customisable grid, the metric-detail screen and the
/// Coach context layer all enumerate this catalog rather than each hardcoding their own list, so a
/// metric added here appears everywhere at once and can never drift between screens.
///
/// **Availability is computed, not assumed.** `isAvailable` asks the real history whether the
/// signal has ever been recorded. A strap or phone that never produced SpO₂ shows SpO₂ as
/// unavailable rather than rendering an empty card that looks broken — the "show unavailable
/// rather than fabricate" rule.
enum PremiumMetricCatalog {}

// MARK: - Metric identity

/// Every metric the catalog knows about. Raw values are stable storage keys (they persist in the
/// user's Home layout preference), so renaming a case would reset saved layouts — don't.
enum PremiumMetricID: String, CaseIterable, Hashable, Identifiable {
    // Heart
    case liveHeartRate, restingHr, hrv, hrvBaseline
    // Respiratory / blood
    case respiratory, spo2, skinTemp
    // Recovery / load
    case recovery, strain, stressLoad
    // Sleep
    case sleepScore, sleepDuration, sleepEfficiency, restorativeSleep
    case sleepRegularity, sleepBalance, bedtime, wakeTime
    // Activity
    case steps, workouts, activeEnergy, restingEnergy, totalEnergy
    // Meta
    case journalStatus

    var id: String { rawValue }
}

/// Broad grouping used by the Edit-Home picker so a 24-item list stays navigable.
enum PremiumMetricGroup: String, CaseIterable, Hashable {
    case heart = "Heart"
    case sleep = "Sleep"
    case recovery = "Recovery & load"
    case activity = "Activity"
    case journal = "Journal"

    /// The display name. The raw values stay English because they are stable identifiers; this is
    /// what the UI shows, so a Spanish user sees "Corazón" rather than the identifier.
    var label: String {
        switch self {
        case .heart:    return String(localized: "Heart")
        case .sleep:    return String(localized: "Sleep")
        case .recovery: return String(localized: "Recovery & load")
        case .activity: return String(localized: "Activity")
        case .journal:  return String(localized: "Journal")
        }
    }
}

// MARK: - Metric definition

/// The static description of one metric plus the closure that pulls its real value. Value readers
/// return `nil` whenever the underlying field is absent — never a zero stand-in.
struct PremiumMetricDef: Identifiable {
    let id: PremiumMetricID
    let name: String
    let shortName: String
    let unit: String
    let icon: String
    let tint: Color
    let group: PremiumMetricGroup
    let provenance: PremiumProvenance
    let decimals: Int
    /// nil = no single "good" direction (respiratory rate, steps, bedtime).
    let higherBetter: Bool?
    let explanation: String
    /// Pulls the per-day value out of a `DailyMetric`, already normalised (e.g. efficiency scaled
    /// to 0–100) and bounds-checked by the catalog's `series(...)`.
    let read: (DailyMetric) -> Double?
    /// Some metrics are not per-day `DailyMetric` fields (live HR, sleep regularity, journal
    /// status). They render from a live/derived source instead and have no history series.
    let isDerived: Bool

    /// Formats a value with this metric's decimals, optionally with its unit.
    func format(_ v: Double, withUnit: Bool = true) -> String {
        let num: String
        if id == .sleepDuration || id == .sleepBalance {
            num = PremiumAnalysis.durText(v)                     // durations read as "7h 12m"
        } else if id == .bedtime || id == .wakeTime {
            num = PremiumMetricCatalog.clockText(v)              // clock metrics read as "11:16 PM"
        } else if decimals == 0 {
            num = String(Int(v.rounded()))
        } else {
            num = String(format: "%.\(decimals)f", v)
        }
        let unitless = (id == .sleepDuration || id == .sleepBalance || id == .bedtime || id == .wakeTime)
        return withUnit && !unit.isEmpty && !unitless ? "\(num) \(unit)" : num
    }
}

// MARK: - Catalog

extension PremiumMetricCatalog {

    /// Clock formatting for the "minutes since noon" convention the sleep-timing metrics use, so an
    /// 11:16 PM bedtime and a 6:22 AM wake time sit on one increasing axis without a midnight flip.
    static func clockText(_ minutesSinceNoon: Double) -> String {
        let total = ((Int(minutesSinceNoon.rounded()) + 12 * 60) % 1440 + 1440) % 1440
        let h = total / 60, m = total % 60
        let ap = h < 12 ? "AM" : "PM"
        let hh = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", hh, m, ap)
    }

    /// Normalises `DailyMetric.efficiency`, which is stored as a FRACTION in [0,1] by the on-device
    /// path but as 0–100 by some import paths. Applied once here so every screen agrees.
    static func efficiencyPct(_ d: DailyMetric) -> Double? {
        d.efficiency.map { $0 <= 1.0 ? $0 * 100 : $0 }
    }

    /// The full registry, in a sensible default display order.
    static let all: [PremiumMetricDef] = [
        // ---- Heart -------------------------------------------------------------------
        PremiumMetricDef(
            id: .liveHeartRate, name: String(localized: "Heart Rate"), shortName: String(localized: "Heart rate"), unit: "bpm",
            icon: "heart.fill", tint: StrandPalette.metricRose, group: .heart,
            provenance: .measured, decimals: 0, higherBetter: nil,
            explanation: String(localized: "Your heart rate right now, straight from the strap's optical sensor."),
            read: { _ in nil }, isDerived: true),
        PremiumMetricDef(
            id: .restingHr, name: String(localized: "Resting Heart Rate"), shortName: String(localized: "Resting HR"), unit: "bpm",
            icon: "heart.text.square.fill", tint: StrandPalette.metricRose, group: .heart,
            provenance: .estimated, decimals: 0, higherBetter: false,
            explanation: String(localized: "Your lowest heart rate during sleep. Lower usually reflects good cardiovascular fitness and recovery; a rise above your baseline often accompanies stress, dehydration or the onset of illness."),
            read: { $0.restingHr.map(Double.init) }, isDerived: false),
        PremiumMetricDef(
            id: .hrv, name: String(localized: "Heart Rate Variability"), shortName: String(localized: "HRV"), unit: "ms",
            icon: "waveform.path.ecg", tint: StrandPalette.metricCyan, group: .heart,
            provenance: .estimated, decimals: 0, higherBetter: true,
            explanation: String(localized: "The beat-to-beat variation in your heart rhythm, measured overnight. Higher HRV generally reflects a well-recovered, adaptable nervous system."),
            read: { $0.avgHrv }, isDerived: false),

        // ---- Respiratory / blood ------------------------------------------------------
        PremiumMetricDef(
            id: .respiratory, name: String(localized: "Respiratory Rate"), shortName: String(localized: "Respiratory"), unit: "rpm",
            icon: "lungs.fill", tint: StrandPalette.recoveryColor(80), group: .heart,
            provenance: .estimated, decimals: 1, higherBetter: nil,
            explanation: String(localized: "Breaths per minute while you sleep. Remarkably stable night to night, so a sustained shift from your own baseline matters more than any single ideal number."),
            read: { $0.respRateBpm }, isDerived: false),
        PremiumMetricDef(
            id: .spo2, name: String(localized: "Blood Oxygen"), shortName: String(localized: "Blood oxygen"), unit: "%",
            icon: "drop.fill", tint: StrandPalette.metricPurple, group: .heart,
            provenance: .estimated, decimals: 0, higherBetter: true,
            explanation: String(localized: "The share of oxygen carried in your blood, sampled overnight. Healthy readings typically sit between 95 and 100%."),
            read: { $0.spo2Pct }, isDerived: false),
        PremiumMetricDef(
            id: .skinTemp, name: String(localized: "Skin Temperature"), shortName: String(localized: "Skin temp"), unit: "°C",
            icon: "thermometer.medium", tint: StrandPalette.metricAmber, group: .heart,
            provenance: .estimated, decimals: 1, higherBetter: nil,
            explanation: String(localized: "How far your overnight skin temperature sat from your own baseline. Shown as a deviation, not an absolute body temperature."),
            read: { $0.skinTempDevC }, isDerived: false),

        // ---- Recovery / load ----------------------------------------------------------
        PremiumMetricDef(
            id: .recovery, name: String(localized: "Recovery"), shortName: String(localized: "Recovery"), unit: "%",
            icon: "bolt.heart.fill", tint: StrandPalette.recoveryColor(80), group: .recovery,
            provenance: .calculated, decimals: 0, higherBetter: true,
            explanation: String(localized: "A daily readiness score blended from your overnight HRV, resting heart rate, sleep and respiratory rate."),
            read: { $0.recovery }, isDerived: false),
        PremiumMetricDef(
            id: .strain, name: String(localized: "Day Strain"), shortName: String(localized: "Strain"), unit: "",
            icon: "flame.fill", tint: StrandPalette.effortColor, group: .recovery,
            provenance: .calculated, decimals: 1, higherBetter: nil,
            explanation: String(localized: "Cardiovascular load accumulated across the day on a 0–21 scale, weighted by time spent in each heart-rate zone."),
            read: { $0.strain }, isDerived: false),
        PremiumMetricDef(
            id: .stressLoad, name: String(localized: "Physiological Load"), shortName: String(localized: "Load"), unit: "",
            icon: "waveform.path", tint: StrandPalette.metricAmber, group: .recovery,
            provenance: .calculated, decimals: 1, higherBetter: nil,
            explanation: String(localized: "An estimate of daytime physiological load from your heart-rate pattern relative to your resting baseline. An estimated signal, not a medical stress measurement."),
            read: { _ in nil }, isDerived: true),

        // ---- Sleep --------------------------------------------------------------------
        PremiumMetricDef(
            id: .sleepScore, name: String(localized: "Sleep Performance"), shortName: String(localized: "Sleep score"), unit: "%",
            icon: "bed.double.fill", tint: StrandPalette.sleepDeep, group: .sleep,
            provenance: .calculated, decimals: 0, higherBetter: true,
            explanation: String(localized: "How much of your time in bed was actually spent asleep."),
            read: { efficiencyPct($0) }, isDerived: false),
        PremiumMetricDef(
            id: .sleepDuration, name: String(localized: "Sleep Duration"), shortName: String(localized: "Time asleep"), unit: "",
            icon: "moon.zzz.fill", tint: StrandPalette.sleepREM, group: .sleep,
            provenance: .estimated, decimals: 0, higherBetter: true,
            explanation: String(localized: "Total time asleep last night, excluding time awake in bed."),
            read: { $0.totalSleepMin }, isDerived: false),
        PremiumMetricDef(
            id: .sleepEfficiency, name: String(localized: "Sleep Efficiency"), shortName: String(localized: "Efficiency"), unit: "%",
            icon: "checkmark.seal.fill", tint: StrandPalette.sleepLight, group: .sleep,
            provenance: .calculated, decimals: 0, higherBetter: true,
            explanation: String(localized: "The share of your time in bed spent asleep. Above 85% is generally considered strong."),
            read: { efficiencyPct($0) }, isDerived: false),
        PremiumMetricDef(
            id: .restorativeSleep, name: String(localized: "Restorative Sleep"), shortName: String(localized: "Restorative"), unit: "",
            icon: "sparkles", tint: StrandPalette.sleepDeep, group: .sleep,
            provenance: .estimated, decimals: 0, higherBetter: true,
            explanation: String(localized: "Deep and REM sleep combined — the stages most associated with physical repair and memory consolidation."),
            read: { d in
                guard let deep = d.deepMin, let rem = d.remMin else { return nil }
                return deep + rem
            }, isDerived: false),
        PremiumMetricDef(
            id: .sleepRegularity, name: String(localized: "Sleep Regularity"), shortName: String(localized: "Regularity"), unit: "",
            icon: "calendar.badge.clock", tint: StrandPalette.metricCyan, group: .sleep,
            provenance: .calculated, decimals: 0, higherBetter: true,
            explanation: String(localized: "How consistent your bed and wake times have been. Computed from your real per-night sleep windows."),
            read: { _ in nil }, isDerived: true),
        PremiumMetricDef(
            id: .sleepBalance, name: String(localized: "Sleep Balance"), shortName: String(localized: "Balance"), unit: "",
            icon: "scalemass.fill", tint: StrandPalette.sleepREM, group: .sleep,
            provenance: .calculated, decimals: 0, higherBetter: true,
            explanation: String(localized: "Your running sleep surplus or deficit against your personal sleep need."),
            read: { _ in nil }, isDerived: true),
        PremiumMetricDef(
            id: .bedtime, name: String(localized: "Bedtime"), shortName: String(localized: "Bedtime"), unit: "",
            icon: "moon.stars.fill", tint: StrandPalette.sleepDeep, group: .sleep,
            provenance: .estimated, decimals: 0, higherBetter: nil,
            explanation: String(localized: "When you fell asleep, from your real recorded sleep window."),
            read: { _ in nil }, isDerived: true),
        PremiumMetricDef(
            id: .wakeTime, name: String(localized: "Wake Time"), shortName: String(localized: "Wake time"), unit: "",
            icon: "sunrise.fill", tint: StrandPalette.metricAmber, group: .sleep,
            provenance: .estimated, decimals: 0, higherBetter: nil,
            explanation: String(localized: "When you woke, from your real recorded sleep window."),
            read: { _ in nil }, isDerived: true),

        // ---- Activity -----------------------------------------------------------------
        PremiumMetricDef(
            id: .steps, name: String(localized: "Steps"), shortName: String(localized: "Steps"), unit: "",
            icon: "figure.walk", tint: StrandPalette.recoveryColor(80), group: .activity,
            provenance: .estimated, decimals: 0, higherBetter: nil,
            explanation: String(localized: "Your daily step count, estimated on-device from the strap's motion counter. A trend gauge rather than a precise pedometer."),
            read: { $0.steps.map(Double.init) }, isDerived: false),
        PremiumMetricDef(
            id: .workouts, name: String(localized: "Workouts"), shortName: String(localized: "Workouts"), unit: "",
            icon: "figure.run", tint: StrandPalette.effortColor, group: .activity,
            provenance: .calculated, decimals: 0, higherBetter: nil,
            explanation: String(localized: "How many workouts were recorded or detected today."),
            read: { $0.exerciseCount.map(Double.init) }, isDerived: false),
        PremiumMetricDef(
            id: .activeEnergy, name: String(localized: "Active Energy"), shortName: String(localized: "Active energy"), unit: "kcal",
            icon: "flame.fill", tint: StrandPalette.metricAmber, group: .activity,
            provenance: .estimated, decimals: 0, higherBetter: nil,
            explanation: String(localized: "Calories burned through movement, estimated on-device from your heart rate."),
            read: { $0.activeKcalEst }, isDerived: false),
        PremiumMetricDef(
            id: .restingEnergy, name: String(localized: "Resting Energy"), shortName: String(localized: "Resting energy"), unit: "kcal",
            icon: "bed.double.circle.fill", tint: StrandPalette.gold, group: .activity,
            provenance: .calculated, decimals: 0, higherBetter: nil,
            explanation: String(localized: "The energy your body uses at rest, estimated from your profile."),
            read: { _ in nil }, isDerived: true),
        PremiumMetricDef(
            id: .totalEnergy, name: String(localized: "Total Energy"), shortName: String(localized: "Total energy"), unit: "kcal",
            icon: "bolt.fill", tint: StrandPalette.metricAmber, group: .activity,
            provenance: .calculated, decimals: 0, higherBetter: nil,
            explanation: String(localized: "Active plus resting energy for the day."),
            read: { _ in nil }, isDerived: true),

        // ---- Journal ------------------------------------------------------------------
        PremiumMetricDef(
            id: .journalStatus, name: String(localized: "Journal"), shortName: String(localized: "Journal"), unit: "",
            icon: "square.and.pencil", tint: StrandPalette.gold, group: .journal,
            provenance: .calculated, decimals: 0, higherBetter: nil,
            explanation: String(localized: "Whether you've logged today, and your current logging streak."),
            read: { _ in nil }, isDerived: true),
    ]

    static func def(_ id: PremiumMetricID) -> PremiumMetricDef {
        // Every case is present in `all`; the fallback keeps this total without a force-unwrap.
        all.first { $0.id == id } ?? all[0]
    }

    /// The catalog's per-metric bounds key, used to reject impossible readings.
    static func boundsKey(_ id: PremiumMetricID) -> String {
        switch id {
        case .hrv: return "hrv"
        case .restingHr, .liveHeartRate: return "restingHr"
        case .respiratory: return "respiratory"
        case .spo2: return "spo2"
        case .skinTemp: return "skinTemp"
        case .recovery: return "recovery"
        case .strain: return "strain"
        case .sleepScore, .sleepEfficiency: return "sleepEfficiency"
        case .sleepDuration, .restorativeSleep: return "sleepDuration"
        case .steps: return "steps"
        case .activeEnergy: return "activeKcal"
        case .restingEnergy, .totalEnergy: return "restingKcal"
        default: return id.rawValue
        }
    }

    // MARK: Reading real data

    /// The metric's real, bounds-checked history from banked days, oldest→newest.
    @MainActor
    static func series(_ id: PremiumMetricID, repo: Repository) -> [PremiumSample] {
        let d = def(id)
        guard !d.isDerived else { return [] }
        let raw: [PremiumSample] = repo.days.compactMap { day in
            guard let v = d.read(day) else { return nil }
            return PremiumSample(day: day.day, value: v)
        }
        return PremiumBounds.clean(raw, key: boundsKey(id))
    }

    /// The freshest real value, carrying back through banked days the same way the rest of the
    /// Premium UI does (an unscored today still shows last night's vitals).
    @MainActor
    static func latest(_ id: PremiumMetricID, repo: Repository) -> Double? {
        series(id, repo: repo).last?.value
    }

    /// Whether this signal has ever been recorded. Derived metrics report availability through
    /// their own source and are treated as available so the UI can decide.
    @MainActor
    static func isAvailable(_ id: PremiumMetricID, repo: Repository) -> Bool {
        let d = def(id)
        if d.isDerived { return true }
        return !series(id, repo: repo).isEmpty
    }

    /// Full deterministic analysis for a metric — baseline, deviation, changes, trend, weekday
    /// pattern. The single entry point every screen uses for "vs your normal" framing.
    @MainActor
    static func analysis(_ id: PremiumMetricID, repo: Repository) -> PremiumMetricAnalysis {
        let d = def(id)
        return PremiumAnalysis.analyze(key: id.rawValue,
                                       samples: series(id, repo: repo),
                                       higherBetter: d.higherBetter)
    }
}

// MARK: - Home layout preferences

/// The user's Home dashboard configuration, persisted in `UserDefaults`. Holds which metric cards
/// are shown, in what order, and whether the grid renders compact (value only) or expanded (value
/// plus trend). Defaults reproduce the previous fixed six-card Home so an existing user's screen is
/// unchanged until they customise it.
@MainActor
final class PremiumHomeLayoutStore: ObservableObject {

    private enum K {
        static let order = "premiumHome.order"
        static let hidden = "premiumHome.hidden"
        static let compact = "premiumHome.compact"
    }

    /// The historical Home grid — kept as the default so upgrading the app doesn't rearrange
    /// anyone's dashboard.
    static let defaultOrder: [PremiumMetricID] = [
        .restingHr, .hrv, .respiratory, .spo2, .activeEnergy, .steps,
    ]

    @Published var order: [PremiumMetricID] { didSet { persistOrder() } }
    @Published var hidden: Set<PremiumMetricID> { didSet { persistHidden() } }
    @Published var compact: Bool { didSet { UserDefaults.standard.set(compact, forKey: K.compact) } }

    init() {
        let defaults = UserDefaults.standard
        let savedOrder = (defaults.array(forKey: K.order) as? [String]) ?? []
        let restored = savedOrder.compactMap { PremiumMetricID(rawValue: $0) }
        // Any metric added to the catalog after the user last saved lands at the end, hidden, so a
        // new release never silently rearranges a customised Home.
        let known = Set(restored)
        let appended = PremiumMetricCatalog.all.map(\.id).filter { !known.contains($0) }
        self.order = restored.isEmpty ? Self.fullDefaultOrder() : restored + appended

        let savedHidden = (defaults.array(forKey: K.hidden) as? [String]) ?? []
        if savedHidden.isEmpty && restored.isEmpty {
            // First run: everything except the default six starts hidden.
            let shown = Set(Self.defaultOrder)
            self.hidden = Set(PremiumMetricCatalog.all.map(\.id).filter { !shown.contains($0) })
        } else {
            var h = Set(savedHidden.compactMap { PremiumMetricID(rawValue: $0) })
            for id in appended { h.insert(id) }
            self.hidden = h
        }
        self.compact = defaults.bool(forKey: K.compact)
    }

    /// Default order = the historical six first, then everything else in catalog order.
    private static func fullDefaultOrder() -> [PremiumMetricID] {
        let firstSix = defaultOrder
        let rest = PremiumMetricCatalog.all.map(\.id).filter { !firstSix.contains($0) }
        return firstSix + rest
    }

    /// The metrics actually rendered on Home, in the user's order.
    var visible: [PremiumMetricID] { order.filter { !hidden.contains($0) } }

    func toggle(_ id: PremiumMetricID) {
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
    }

    func move(_ id: PremiumMetricID, by offset: Int) {
        guard let idx = order.firstIndex(of: id) else { return }
        let target = idx + offset
        guard target >= 0, target < order.count else { return }
        order.swapAt(idx, target)
    }

    func resetToDefaults() {
        order = Self.fullDefaultOrder()
        let shown = Set(Self.defaultOrder)
        hidden = Set(PremiumMetricCatalog.all.map(\.id).filter { !shown.contains($0) })
        compact = false
    }

    private func persistOrder() {
        UserDefaults.standard.set(order.map(\.rawValue), forKey: K.order)
    }
    private func persistHidden() {
        UserDefaults.standard.set(hidden.map(\.rawValue).sorted(), forKey: K.hidden)
    }
}
#endif
