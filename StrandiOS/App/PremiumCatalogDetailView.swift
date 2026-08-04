#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// The reusable metric-detail screen for every entry in `PremiumMetricCatalog`.
///
/// One layout, driven entirely by the catalog definition plus the deterministic analysis engine:
/// current value against the personal baseline, a baseline-band history chart, period changes over
/// 7 / 30 / 90 days, the value distribution, a day-of-week pattern, related-signal navigation and a
/// plain-language explanation. Adding a metric to the catalog gives it a full detail screen for
/// free — no per-metric view.
///
/// Where a section can't be computed honestly (no baseline yet, too few samples for a distribution,
/// a derived metric with no per-day history), that section is omitted or replaced by an explicit
/// unavailable state rather than filled with a placeholder.
struct PremiumCatalogDetailView: View {
    let metric: PremiumMetricID

    @EnvironmentObject var repo: Repository
    @State private var rangeIndex: Int = 1   // 0 = 7D, 1 = 30D, 2 = 90D

    private static let ranges: [(label: String, days: Int)] = [("7D", 7), ("30D", 30), ("90D", 90)]

    private var def: PremiumMetricDef { PremiumMetricCatalog.def(metric) }
    private var analysis: PremiumMetricAnalysis { PremiumMetricCatalog.analysis(metric, repo: repo) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                headerSection
                if def.isDerived {
                    derivedNotice
                } else if analysis.series.isEmpty {
                    StrandCard {
                        MetricUnavailable(name: def.name,
                                          reason: "Your strap hasn't recorded this signal yet.")
                    }
                } else {
                    historySection
                    changeSection
                    if analysis.series.count >= 10 { distributionSection }
                    if analysis.byWeekday.count >= 3 { weekdaySection }
                }
                explanationSection
                relatedSection
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 96)
        }
        .background(ambient.ignoresSafeArea())
        .navigationTitle(def.name)
    }

    private var ambient: some View {
        ZStack {
            StrandPalette.surfaceBase
            RadialGradient(colors: [def.tint.opacity(0.14), .clear],
                           center: .init(x: 0.5, y: 0.02), startRadius: 0, endRadius: 340)
        }
    }

    // MARK: Header — current value vs personal baseline

    private var headerSection: some View {
        let a = analysis
        return StrandCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    PremiumIconTile(system: def.icon, tint: def.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def.name).font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(def.group.label).font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    ProvenanceChip(provenance: def.provenance)
                }
                MetricValueHeader(value: currentValueText, unit: headerUnit,
                                  deltaText: deltaText(a), deltaGood: deltaGood(a),
                                  caption: baselineCaption(a), tint: def.tint)
            }
        }
    }

    private var currentValueText: String {
        guard let v = analysis.latest else { return "—" }
        return def.format(v, withUnit: false)
    }
    /// Durations and clock times carry their own formatting, so the separate unit label is dropped.
    private var headerUnit: String {
        switch metric {
        case .sleepDuration, .sleepBalance, .bedtime, .wakeTime, .restorativeSleep: return ""
        default: return def.unit
        }
    }

    private func deltaText(_ a: PremiumMetricAnalysis) -> String? {
        guard let text = PremiumMetricCatalog.deviationText(metric, a) else { return nil }
        return text + " vs baseline"
    }
    /// Colours the delta only when the metric has a meaningful direction — respiratory rate and
    /// steps have no "good" side, so their delta stays neutral rather than falsely reassuring.
    private func deltaGood(_ a: PremiumMetricAnalysis) -> Bool? {
        PremiumMetricCatalog.deviationGood(metric, a)
    }
    private func baselineCaption(_ a: PremiumMetricAnalysis) -> String? {
        guard let b = a.baseline else {
            let n = a.series.count
            return "Not enough history for a baseline yet — \(n) reading\(n == 1 ? "" : "s") so far."
        }
        var s = "Your \(a.baselineN)-day baseline is \(def.format(b))"
        if a.runLength >= 3 {
            s += " · \(a.runLength) days \(a.runBelow ? "below" : "above") it"
        }
        return s + "."
    }

    // MARK: History — baseline band chart

    private var historySection: some View {
        let a = analysis
        let days = Self.ranges[rangeIndex].days
        let windowed: [PremiumSample] = Array(a.series.suffix(days))
        let values: [Double] = windowed.map(\.value)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                PremiumSectionHeader(title: "History")
                Spacer()
                rangePicker
            }
            StrandCard {
                VStack(alignment: .leading, spacing: 10) {
                    if values.count >= 2 {
                        BaselineBandChart(values: values, baseline: a.baseline, spread: a.spread,
                                          tint: def.tint, height: 150,
                                          valueFormat: { self.def.format($0, withUnit: false) })
                        HStack {
                            Text("\(values.count) reading\(values.count == 1 ? "" : "s")")
                            Spacer()
                            if a.hasBaseline {
                                Text("Shaded band = your typical range")
                            }
                        }
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                    } else {
                        MetricUnavailable(name: def.shortName,
                                          reason: "Need at least two readings in this range.")
                    }
                }
            }
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(Array(Self.ranges.enumerated()), id: \.offset) { idx, r in
                let selected: Bool = idx == rangeIndex
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { rangeIndex = idx }
                } label: {
                    Text(r.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? StrandPalette.surfaceBase : StrandPalette.textSecondary)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Capsule().fill(selected ? def.tint : StrandPalette.surfaceInset))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Period changes

    private var changeSection: some View {
        let a = analysis
        return VStack(alignment: .leading, spacing: 14) {
            PremiumSectionHeader(title: "Change over time")
            StrandCard {
                VStack(spacing: 0) {
                    changeRow("7 days", pct: a.change7, abs: a.change7Abs)
                    Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                    changeRow("30 days", pct: a.change30, abs: a.change30Abs)
                    Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                    changeRow("90 days", pct: a.change90, abs: a.change90Abs)
                }
            }
        }
    }

    @ViewBuilder private func changeRow(_ label: String, pct: Double?, abs: Double?) -> some View {
        HStack {
            Text(label).font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            if let text = PremiumMetricCatalog.changeText(metric, pct: pct, abs: abs) {
                let good: Bool? = PremiumMetricCatalog.changeGood(metric, pct: pct, abs: abs)
                let tint: Color = good == nil
                    ? StrandPalette.textSecondary
                    : (good! ? StrandPalette.recoveryColor(85) : StrandPalette.metricRose)
                Text(text)
                    .font(StrandFont.captionNumber).foregroundStyle(tint)
            } else {
                Text("Not enough history")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: Distribution

    private var distributionSection: some View {
        let a = analysis
        let values: [Double] = a.series.map(\.value)
        return VStack(alignment: .leading, spacing: 14) {
            PremiumSectionHeader(title: "Where this usually lands")
            StrandCard {
                VStack(alignment: .leading, spacing: 10) {
                    DistributionHistogram(values: values, buckets: 12, tint: def.tint,
                                          highlight: a.latest, height: 110)
                    if let lo = values.min(), let hi = values.max() {
                        HStack {
                            Text(def.format(lo))
                            Spacer()
                            Text(def.format(hi))
                        }
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    }
                    Text("Your recorded readings, bucketed. The dashed line marks your latest.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    // MARK: Day-of-week pattern

    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PremiumSectionHeader(title: "By day of week")
            StrandCard {
                VStack(alignment: .leading, spacing: 12) {
                    WeekdayPatternChart(byWeekday: analysis.byWeekday, tint: def.tint,
                                        format: { self.def.format($0, withUnit: false) })
                    Text("Averages per weekday. Only days with at least two readings appear.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    // MARK: Derived-metric notice

    /// Derived metrics (live HR, regularity, balance, bedtime…) have no per-day `DailyMetric`
    /// column, so instead of an empty chart this points at the screen that owns them.
    private var derivedNotice: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where to find this")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text(derivedDestinationText)
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var derivedDestinationText: String {
        switch metric {
        case .liveHeartRate, .stressLoad:
            return "This is a live signal — see the Heart tab for the real-time reading and today's full heart-rate picture."
        case .sleepRegularity, .sleepBalance, .bedtime, .wakeTime:
            return "This is computed from your recorded sleep windows — see the Sleep tab for the full timing and regularity breakdown."
        case .restingEnergy, .totalEnergy:
            return "Energy totals are shown together on the Energy screen, reachable from Home's Active Energy card."
        case .journalStatus:
            return "Open the Journal to log today's check-in and see your streak."
        default:
            return "This metric is shown in context on its own screen."
        }
    }

    // MARK: Explanation

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PremiumSectionHeader(title: "What this means")
            StrandCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(def.explanation)
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                    Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                    HStack(alignment: .top, spacing: 10) {
                        ProvenanceChip(provenance: def.provenance)
                        Text(def.provenance.explanation)
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Related metrics

    /// Signals worth looking at next to this one. A fixed adjacency map — small, curated and
    /// physiologically sensible rather than an algorithmic guess.
    private static let related: [PremiumMetricID: [PremiumMetricID]] = [
        .hrv: [.restingHr, .recovery, .sleepDuration],
        .restingHr: [.hrv, .recovery, .respiratory],
        .respiratory: [.hrv, .spo2, .sleepScore],
        .spo2: [.respiratory, .sleepScore],
        .skinTemp: [.restingHr, .hrv],
        .recovery: [.hrv, .restingHr, .sleepDuration],
        .strain: [.recovery, .activeEnergy, .workouts],
        .sleepScore: [.sleepDuration, .sleepEfficiency, .restorativeSleep],
        .sleepDuration: [.sleepScore, .recovery, .sleepBalance],
        .sleepEfficiency: [.sleepScore, .sleepDuration],
        .restorativeSleep: [.sleepDuration, .sleepScore],
        .steps: [.activeEnergy, .strain],
        .activeEnergy: [.steps, .strain, .totalEnergy],
        .workouts: [.strain, .activeEnergy],
    ]

    @ViewBuilder private var relatedSection: some View {
        let ids: [PremiumMetricID] = Self.related[metric] ?? []
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "Related")
                VStack(spacing: 10) {
                    ForEach(ids) { id in
                        relatedRow(id)
                    }
                }
            }
        }
    }

    private func relatedRow(_ id: PremiumMetricID) -> some View {
        let d = PremiumMetricCatalog.def(id)
        let value: Double? = PremiumMetricCatalog.latest(id, repo: repo)
        return NavigationLink(value: PremiumRoute.catalogMetric(id)) {
            StrandCard(padding: 14) {
                HStack(spacing: 12) {
                    PremiumIconTile(system: d.icon, tint: d.tint, size: 30)
                    Text(d.shortName).font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Text(value.map { d.format($0) } ?? "—")
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(value == nil ? StrandPalette.textTertiary : StrandPalette.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
