#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Phase 2 · Blood Oxygen (SpO₂) — native rebuild of the prototype's `spo2.js`. Shows a REAL calibrated
/// SpO₂ percentage ONLY when the banked data carries one (`DailyMetric.spo2Pct`, present on imported rows).
/// The on-device WHOOP 4.0 engine banks only the RAW red/IR PPG ADC means (`spo2Red`/`spo2Ir`), not a
/// calibrated percentage — that needs WHOOP's proprietary curve — so for most users there is no honest
/// number to show, and this screen renders an explicit empty state rather than inventing one. "NOOP never
/// invents a measurement" is the whole point of this screen.
struct PremiumBloodOxygenView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var health: HealthKitBridge

    /// Real nightly SpO₂ percentages, oldest→newest, nil-free.
    private var series: [Double] { repo.days.compactMap { $0.spo2Pct } }
    private var latest: Double? { series.last }
    private var baseline: Double? { intel.baseline }
    private let tint = StrandPalette.metricPurple

    @State private var intel = PremiumSpo2Intel.empty
    private var analysis: PremiumMetricAnalysis { PremiumMetricCatalog.analysis(.spo2, repo: repo) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if series.isEmpty && !intel.hasOvernightSamples {
                    emptyState
                } else {
                    hero
                    overnightSection
                    baselineSection
                    trendSection
                    trendCard
                    distributionSection
                    rangeCard
                    heatmapCard
                }
                explanationCard
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 96)
        }
        .background(ambient.ignoresSafeArea())
        .navigationTitle("Blood Oxygen")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: repo.refreshSeq) {
            let sleep = await PremiumSleepIntel.load(repo: repo, window: 3)
            intel = await PremiumSpo2Intel.load(repo: repo, health: health, sleepIntel: sleep)
        }
    }

    // MARK: Overnight — from REAL individual samples, never derived from the daily mean

    @ViewBuilder private var overnightSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PremiumSectionHeader(title: "Overnight")
                Spacer()
                PremiumExplainer(
                    title: String(localized: "Overnight SpO₂"),
                    items: overnightExplainerItems,
                    methodology: String(localized: "Statistics are computed over the individual oxygen-saturation samples Apple Health holds for last night's sleep window (your recorded bedtime to wake time). Average, lowest and highest are taken across those samples only — none of them is derived from the single stored nightly value, which is a daily average and cannot describe a minimum. Readings NOOP itself wrote back into Health are excluded so its own output is never re-read as an independent measurement. Values outside 70–100% are rejected as implausible before any statistic is computed."))
            }
            StrandCard {
                if intel.hasOvernightSamples {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            overnightStat("AVERAGE", intel.overnightAverage, tint)
                            overnightStat("LOWEST", intel.overnightLow, StrandPalette.metricAmber)
                            overnightStat("HIGHEST", intel.overnightHigh, StrandPalette.recoveryColor(85))
                        }
                        if let r = intel.overnightRange {
                            Text(String(format: String(localized: "Range %1$@–%2$@%%  ·  %3$d reading(s)"),
                                        Self.pct(r.lo), Self.pct(r.hi), intel.sampleCount))
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        }
                        if intel.sampleCount >= 2 {
                            Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                            Text("READINGS ACROSS THE NIGHT", comment: "SpO2 overnight timeline label")
                                .font(StrandFont.overline).tracking(1.2)
                                .foregroundStyle(StrandPalette.textTertiary)
                            spotCheckTimeline
                        }
                        Text(intermittentNote)
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    MetricUnavailable(name: String(localized: "Overnight readings"),
                                      reason: noOvernightReason)
                }
            }
        }
    }

    private func overnightStat(_ label: String, _ v: Double?, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(v.map(Self.pct) ?? "—")
                    .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(v == nil ? StrandPalette.textTertiary : c)
                if v != nil {
                    Text("%").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            Text(label).font(StrandFont.overline).tracking(1.0)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Each real reading as a dot on the night's timeline. Deliberately dots and NOT a connected
    /// line: these are intermittent spot checks, and joining them would draw a continuous trace the
    /// watch never measured.
    private var spotCheckTimeline: some View {
        let vals = intel.sampleValues
        let lo = (vals.min() ?? 90) - 1, hi = (vals.max() ?? 100) + 1
        let span = max(hi - lo, 0.0001)
        let start = intel.windowStart ?? Date()
        let total = max(1, (intel.windowEnd ?? Date()).timeIntervalSince(start))
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(intel.samples.enumerated()), id: \.offset) { _, s in
                        let x = geo.size.width * CGFloat(min(max(s.t.timeIntervalSince(start) / total, 0), 1))
                        let y = geo.size.height * CGFloat(1 - (s.pct - lo) / span)
                        Circle().fill(tint)
                            .frame(width: 7, height: 7)
                            .offset(x: max(0, min(geo.size.width - 7, x - 3.5)), y: max(0, y - 3.5))
                    }
                }
            }
            .frame(height: 70)
            HStack {
                Text(Self.clock(intel.windowStart))
                Spacer()
                Text(Self.clock(intel.windowEnd))
            }
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
    }

    /// States the sampling is intermittent, and quantifies the largest gap when one is measurable.
    private var intermittentNote: String {
        let base = String(localized: "Blood oxygen is sampled in occasional spot checks, not monitored continuously — each dot is one real reading.")
        guard let gap = intel.longestGapMinutes, gap >= 30 else { return base }
        return base + " " + String(format: String(localized: "The longest stretch with no reading was %@."),
                                   PremiumAnalysis.durText(gap))
    }

    /// Distinguishes "we couldn't ask Health" from "we asked and your hardware recorded nothing" —
    /// they call for completely different user action.
    private var noOvernightReason: String {
        if intel.healthUnavailable {
            return String(localized: "Apple Health isn't connected, so NOOP can't read individual oxygen-saturation readings. Connect Health in Settings to see last night's readings.")
        }
        return String(localized: "No blood-oxygen readings were recorded for last night. Apple Watch takes these as occasional background spot checks, and only some models and regions support it — nights with no reading are normal.")
    }

    private var overnightExplainerItems: [PremiumExplainerItem] {
        var items: [PremiumExplainerItem] = [
            .init(question: String(localized: "What is SpO₂?"),
                  answer: String(localized: "Blood oxygen saturation — the share of your blood's oxygen-carrying capacity currently in use. Readings in the mid-to-high 90s are typical for most people at rest.")),
            .init(question: String(localized: "Where did this measurement come from?"),
                  answer: String(localized: "Either your WHOOP data export (percentages WHOOP itself calculated) or a device that measures blood oxygen optically, such as an Apple Watch, read via Apple Health.\n\nIt does NOT come from your WHOOP strap over Bluetooth. The strap streams a raw optical signal, and converting that to a percentage needs WHOOP's own calibration, which NOOP doesn't have — so NOOP never estimates or generates a value of its own.")),
        ]
        items.append(.init(
            question: String(localized: "How many readings were recorded?"),
            answer: intel.sampleCount == 0
                ? String(localized: "None for last night.")
                : String(format: String(localized: "%1$d reading(s) across last night's sleep window."), intel.sampleCount)))
        items.append(.init(
            question: String(localized: "Is this the latest, the average or the minimum?"),
            answer: String(localized: "All three are shown separately: AVERAGE is the mean of last night's readings, LOWEST and HIGHEST are the single lowest and highest of those readings, and the big number at the top is your most recent stored nightly value.")))
        if let d = intel.baselineDeltaPoints {
            items.append(.init(
                question: String(localized: "How does tonight compare with my history?"),
                answer: String(format: String(localized: "About %1$@ percentage points versus your %2$d-night personal baseline. NOOP compares you against yourself rather than a population target."),
                               Self.signedPoints(d), intel.baselineNightCount)))
        }
        items.append(.init(
            question: String(localized: "Why are there missing periods?"),
            answer: String(localized: "Blood oxygen is captured as occasional background spot checks rather than a continuous stream. Readings are skipped when the sensor can't get a reliable measurement — loose fit, movement, or the watch not being worn. Gaps are normal and are shown rather than filled in.")))
        return items
    }

    // MARK: Personal baseline

    @ViewBuilder private var baselineSection: some View {
        if let b = intel.baseline {
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "Against your baseline")
                StrandCard {
                    VStack(alignment: .leading, spacing: 12) {
                        MetricValueHeader(
                            value: intel.latestNightly.map(Self.pct) ?? "—",
                            unit: "%",
                            deltaText: intel.baselineDeltaPoints.map { Self.signedPoints($0) + String(localized: " pts") },
                            deltaGood: intel.baselineDeltaPoints.map { $0 >= 0 },
                            caption: String(format: String(localized: "Your %1$d-night baseline is %2$@%%. Compared in percentage points, because SpO₂ is itself a percentage."),
                                            intel.baselineNightCount, Self.pct(b)),
                            tint: tint)
                    }
                }
            }
        }
    }

    // MARK: Trend

    @ViewBuilder private var trendSection: some View {
        let a = analysis
        if a.change7Abs != nil || a.change30Abs != nil || a.change90Abs != nil {
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "Change over time")
                StrandCard {
                    HStack(spacing: 14) {
                        changePoints("7D", a.change7Abs)
                        changePoints("30D", a.change30Abs)
                        changePoints("90D", a.change90Abs)
                    }
                }
            }
        }
    }

    private func changePoints(_ label: String, _ delta: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(delta.map { Self.signedPoints($0) } ?? "—")
                .font(.system(size: 17, weight: .heavy)).monospacedDigit()
                .foregroundStyle(delta == nil ? StrandPalette.textTertiary
                                 : (delta! >= 0 ? StrandPalette.recoveryColor(85) : StrandPalette.metricRose))
            Text(label).font(StrandFont.overline).tracking(1.0)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Distribution

    @ViewBuilder private var distributionSection: some View {
        let a = analysis
        if a.series.count >= 10 {
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "How unusual is last night?")
                StrandCard {
                    VStack(alignment: .leading, spacing: 10) {
                        DistributionHistogram(values: a.series.map(\.value), buckets: 10,
                                              tint: tint, highlight: a.latest, height: 100)
                        Text(distributionCaption)
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var distributionCaption: String {
        let values = analysis.series.map(\.value)
        guard let l = analysis.latest, values.count >= 10 else {
            return String(localized: "Your recorded nights, bucketed.")
        }
        let below = values.filter { $0 < l }.count
        let pct = Int((Double(below) / Double(values.count) * 100).rounded())
        return String(format: String(localized: "Last night sits higher than %1$d%% of your %2$d recorded nights."),
                      pct, values.count)
    }

    // MARK: Formatting

    private static func pct(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func signedPoints(_ v: Double) -> String {
        (v >= 0 ? "+" : "") + String(format: "%.1f", v)
    }
    private static func clock(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private var ambient: some View {
        ZStack {
            StrandPalette.surfaceBase
            RadialGradient(colors: [tint.opacity(0.14), .clear],
                           center: .init(x: 0.5, y: 0.05), startRadius: 0, endRadius: 320)
        }
    }

    private var hero: some View {
        StrandCard(tint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    iconTile("drop.fill", tint: tint)
                    Text("BLOOD OXYGEN · LAST NIGHT").font(StrandFont.overline).tracking(1.4)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountUpText(value: latest ?? 0, format: { "\(Int($0.rounded()))" },
                                font: .system(size: 46, weight: .heavy), color: StrandPalette.textPrimary)
                        .monospacedDigit()
                    Text("%").font(StrandFont.headline).foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                    if let b = baseline {
                        Text("baseline \(Int(b.rounded()))%")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(StrandPalette.textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(StrandPalette.surfaceInset))
                    }
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile("AVG", baseline.map { "\(Int($0.rounded()))" } ?? "—", "%")
            statTile("LOW", series.min().map { "\(Int($0.rounded()))" } ?? "—", "%")
            statTile("HIGH", series.max().map { "\(Int($0.rounded()))" } ?? "—", "%")
        }
    }
    private func statTile(_ label: String, _ value: String, _ unit: String) -> some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(StrandFont.overline).tracking(1.2).foregroundStyle(StrandPalette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var trendCard: some View {
        let recent = Array(series.suffix(30))
        if recent.count >= 2 {
            StrandCard {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Nightly trend · last \(recent.count)")
                    Sparkline(values: recent,
                              gradient: Gradient(colors: [tint, tint.opacity(0.55)]),
                              lineWidth: 2.5, showsArea: true, showsHead: true, showsHover: true,
                              valueFormat: { "\(Int($0.rounded()))%" })
                        .frame(height: 130)
                }
            }
        }
    }

    @ViewBuilder private var rangeCard: some View {
        let lo = series.min() ?? 90, hi = series.max() ?? 100
        let now = latest ?? lo
        let frac = hi > lo ? (now - lo) / (hi - lo) : 0.5
        StrandCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Where last night sits")
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(StrandPalette.surfaceInset).frame(height: 8)
                        Capsule().fill(LinearGradient(colors: [tint.opacity(0.5), tint],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * CGFloat(min(1, max(0, frac)))), height: 8)
                        Circle().fill(tint).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(StrandPalette.surfaceBase, lineWidth: 2))
                            .offset(x: max(0, min(geo.size.width - 16, geo.size.width * CGFloat(min(1, max(0, frac))) - 8)))
                    }
                }
                .frame(height: 18)
                HStack {
                    Text("\(Int(lo.rounded()))%").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                    Text("\(Int(hi.rounded()))%").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    // MARK: 30-day calendar heatmap

    /// One cell per calendar day over the last 30, shaded to that night's real SpO₂ within the
    /// period's own min/max — the same calendar-heatmap language as Strain/Energy/Trends. A night
    /// with no calibrated reading draws a flat inset cell, never a guessed shade.
    @ViewBuilder private var heatmapCard: some View {
        let days = Array(repo.days.suffix(30))
        let values = days.map { $0.spo2Pct }
        let present = values.compactMap { $0 }
        if present.count >= 7 {
            let lo = present.min() ?? 90, hi = present.max() ?? 100
            let span = max(hi - lo, 0.0001)
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("SpO₂ · last 30 days")
                StrandCard {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                        ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(v == nil ? StrandPalette.surfaceInset
                                      : tint.opacity(0.22 + 0.68 * CGFloat((v! - lo) / span)))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
    }

    private var explanationCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("About blood oxygen")
                Text("SpO₂ is the percentage of your blood's oxygen-carrying capacity in use, measured overnight from the strap's optical sensor. Most nights sit in the mid-to-high 90s. NOOP shows a percentage only when it has a calibrated reading — the raw optical signal alone isn't a blood-oxygen number, so it's never presented as one.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
        }
    }

    /// Separates the three genuinely different reasons there is nothing to show, because each one
    /// calls for different (or no) user action. Never a fabricated number in place of any of them.
    private var emptyState: some View {
        StrandCard {
            VStack(spacing: 12) {
                iconTile("drop.fill", tint: tint)
                Text("No SpO₂ measurements available")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text(emptyReason)
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
        }
    }

    /// Leads with the WHOOP strap, because that is where most NOOP users' data comes from and it is
    /// the reason this screen is usually empty — an Apple-Health-first explanation reads as "connect
    /// Health and it'll work", which is false for a strap-only user.
    ///
    /// The honest position, traced end-to-end: the strap's historical stream carries only the RAW
    /// red/IR PPG counts (`spo2_red`/`spo2_ir` in `HistoricalStreams`), which NOOP banks as
    /// `DailyMetric.spo2Red`/`spo2Ir`. Turning those into a saturation percentage needs WHOOP's
    /// proprietary calibration curve, which NOOP does not have and cannot honestly approximate.
    /// There IS a decoded strap-computed candidate at offset 82 (#103), but its cross-device
    /// evidence is contradictory and it is explicitly barred from backing a shipped metric — so it
    /// stays instrumentation. The on-device engine therefore never writes `spo2Pct`; only a WHOOP
    /// CSV import or Apple Health supplies a real percentage.
    private var emptyReason: String {
        let strapNote = String(localized: "Your WHOOP strap does record a raw optical signal overnight, but turning that into a blood-oxygen percentage needs WHOOP's own calibration, which NOOP doesn't have and won't guess at. So NOOP shows nothing here rather than a number it can't stand behind.")
        let howTo = String(localized: "Two things do work: importing your WHOOP data export, which carries the percentages WHOOP already calculated for past nights, or an Apple Watch that records blood oxygen, which NOOP reads through Apple Health.")
        if intel.healthUnavailable {
            return strapNote + "\n\n" + howTo + " " + String(localized: "Apple Health isn't connected yet — you can connect it in Settings.")
        }
        return strapNote + "\n\n" + howTo + " " + String(localized: "Apple Health is connected but currently holds no blood-oxygen readings for you.")
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(StrandFont.overline).tracking(1.3).foregroundStyle(StrandPalette.textTertiary)
    }
    private func iconTile(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }
}
#endif
