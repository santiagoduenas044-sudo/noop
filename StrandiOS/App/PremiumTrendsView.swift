#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// Phase 2 · Trends — the prototype's Trends screen, native SwiftUI on real `repo.days`:
/// a metric picker that morphs the hero chart, a week/month/quarter range control, the
/// period average with a trend delta, a this-period-vs-previous comparison, digest tiles,
/// and an auto-generated insight. All series come from real DailyMetric history.
struct PremiumTrendsView: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal

    private struct Metric: Identifiable {
        let id = UUID(); let name: String; let unit: String; let tint: Color
        let higherBetter: Bool; let key: (DailyMetric) -> Double?
        let fmt: (Double) -> String
    }
    private var metrics: [Metric] {
        [Metric(name: "Recovery", unit: "%", tint: StrandPalette.recoveryColor(80), higherBetter: true,
                key: { $0.recovery }, fmt: { "\(Int($0.rounded()))" }),
         Metric(name: "HRV", unit: "ms", tint: StrandPalette.metricCyan, higherBetter: true,
                key: { $0.avgHrv }, fmt: { "\(Int($0.rounded()))" }),
         Metric(name: "Strain", unit: "", tint: StrandPalette.effortColor, higherBetter: true,
                key: { $0.strain.map { PremiumMetricCatalog.strainDisplay($0) } },
                fmt: { String(format: "%.1f", $0) }),
         // efficiency is a FRACTION in [0,1] (see SleepStageTotals.DailySleep's doc), not a 0-100
         // percentage — normalized here (same defensive `<= 1.0 ? *100 : as-is` guard SleepView.
         // efficiencyPct uses) so the "%" unit reads "92%", not "1%".
         Metric(name: "Sleep", unit: "%", tint: StrandPalette.sleepDeep, higherBetter: true,
                key: { $0.efficiency.map { $0 <= 1.0 ? $0 * 100 : $0 } }, fmt: { "\(Int($0.rounded()))" }),
         Metric(name: "Rest HR", unit: "bpm", tint: StrandPalette.metricRose, higherBetter: false,
                key: { $0.restingHr.map(Double.init) }, fmt: { "\(Int($0.rounded()))" })]
    }
    private let ranges: [(String, Int)] = [("Week", 7), ("Month", 30), ("Quarter", 90), ("Year", 365)]

    @State private var metricIndex = 0
    @State private var rangeIndex = 1
    /// User-chosen comparison metric for the relationship card. nil = the sensible default partner.
    @State private var partnerIndex: Int?
    /// A tapped calendar day, shown in a detail sheet with that day's full context. Wrapped because
    /// `DailyMetric` is a plain value type without an identity for `.sheet(item:)`.
    private struct DaySelection: Identifiable {
        let metric: DailyMetric
        var id: String { metric.day }
    }
    @State private var selectedDay: DaySelection?
    /// Deterministic findings: meaningful changes and journal relationships.
    @State private var findings: [PremiumFinding] = []

    /// The selected range's display name, localized. `ranges` keeps English raw labels because they
    /// double as identifiers; this is what the UI renders.
    private var rangeLabel: String {
        switch rangeIndex {
        case 0:  return String(localized: "Week")
        case 2:  return String(localized: "Quarter")
        case 3:  return String(localized: "Year")
        default: return String(localized: "Month")
        }
    }

    private var metric: Metric { metrics[metricIndex] }
    private var series: [Double] { Array(repo.days.suffix(ranges[rangeIndex].1).compactMap(metric.key)) }
    private var average: Double? { series.isEmpty ? nil : series.reduce(0,+) / Double(series.count) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 1).id("top")
                    header
                    metricPicker
                    weekStrip
                    heroCard
                    findingsCard
                    heatmapCard
                    comparisonCard
                    digestGrid
                    histogramCard
                    weekdayCard
                    correlationCard
                    insightCard
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 96)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .onChange(of: scrollToTopSignal) { _, _ in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
            }
            .sheet(item: $selectedDay) { sel in dayDetailSheet(sel.metric) }
            .task(id: repo.refreshSeq) { await loadFindings() }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR LONG GAME", comment: "Trends screen eyebrow").font(StrandFont.overline).tracking(1.4)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("Trends").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { i, m in
                    let on = i == metricIndex
                    Button { withAnimation(.easeOut(duration: 0.25)) { metricIndex = i } } label: {
                        HStack(spacing: 6) {
                            Circle().fill(m.tint).frame(width: 8, height: 8)
                            Text(m.name).font(StrandFont.subhead)
                        }
                        .foregroundStyle(on ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(Capsule().fill(on ? m.tint.opacity(0.18) : StrandPalette.surfaceRaised))
                        .overlay(Capsule().strokeBorder(on ? m.tint.opacity(0.5) : StrandPalette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// A 7-day "week at a glance" bar strip for the selected metric — bars scaled to that week's own
    /// real min/max (not a fixed 0–100 band, since strain/HRV/RHR don't share the recovery/sleep scale),
    /// tinted to the metric's colour, with a day-of-week label under each bar. A day with no value
    /// (strap not worn / not yet logged) draws a faint placeholder dot instead of a fabricated bar.
    private var weekStrip: some View {
        let days = Array(repo.days.suffix(7))
        let values = days.map(metric.key)
        let present = values.compactMap { $0 }
        let lo = present.min() ?? 0, hi = present.max() ?? 1
        let span = max(hi - lo, 0.0001)
        return StrandCard {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    let v = values[i]
                    VStack(spacing: 6) {
                        if let v {
                            Capsule().fill(metric.tint)
                                .frame(width: 14, height: 8 + CGFloat((v - lo) / span) * 44)
                        } else {
                            Circle().fill(StrandPalette.surfaceInset)
                                .frame(width: 6, height: 6)
                                .frame(height: 8, alignment: .bottom)
                        }
                        Text(dayAbbrev(day.day)).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .bottom)
        }
    }
    /// "Mon" style single-letter-safe short label for a `YYYY-MM-DD` key.
    private func dayAbbrev(_ key: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: key) else { return "" }
        let out = DateFormatter(); out.dateFormat = "EEE"
        return out.string(from: date)
    }

    private var heroCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    CountUpText(value: average ?? 0,
                                format: { average == nil ? "—" : metric.fmt($0) },
                                font: .system(size: 40, weight: .heavy),
                                color: StrandPalette.textPrimary)
                        .monospacedDigit()
                        .id(metric.id)
                    Text(metric.unit).font(StrandFont.headline).foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                    trendDelta
                }
                Text(String(format: String(localized: "%@ average"), rangeLabel)).font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textTertiary)
                rangeControl
                if series.count >= 2 {
                    // Plotted against the user's OWN typical range rather than as a bare line, so
                    // "is this normal for me?" is answerable without leaving the chart.
                    BaselineBandChart(values: series,
                                      baseline: PremiumAnalysis.mean(series),
                                      spread: PremiumAnalysis.stdev(series),
                                      tint: metric.tint, height: 170,
                                      valueFormat: { metric.fmt($0) })
                    HStack {
                        Text("Shaded band = your typical range for this period", comment: "Trends hero chart caption")
                        Spacer()
                        Text("\(series.count) days")
                    }
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                } else {
                    MetricUnavailable(name: metric.name, reason: "Not enough history in this range yet.")
                }
            }
        }
    }

    // MARK: Heatmap — calendar-style grid over the selected range

    /// A calendar heatmap of the selected range: one cell per day, oldest→newest, wrapped 7-per-row
    /// (so each column lines up to a weekday, like a GitHub-contributions grid), opacity scaled to
    /// that day's real value within the range's own min/max. A day with no recorded value draws a
    /// flat inset cell — never a guessed shade.
    @ViewBuilder private var heatmapCard: some View {
        let days = Array(repo.days.suffix(ranges[rangeIndex].1))
        let values = days.map(metric.key)
        let present = values.compactMap { $0 }
        if present.count >= 7 {
            let lo = present.min() ?? 0, hi = present.max() ?? 1
            let span = max(hi - lo, 0.0001)
            VStack(alignment: .leading, spacing: 14) {
                Text("Calendar").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                StrandCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(format: String(localized: "%1$@ · %2$d days"), rangeLabel, days.count)).font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                            ForEach(Array(days.enumerated()), id: \.offset) { idx, day in
                                heatCell(day: day, value: values[idx], lo: lo, span: span)
                            }
                        }
                        Text("Tap any day for its full context.", comment: "Trends calendar hint")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
    }

    /// One calendar cell. Tapping opens that day's real recorded values — which is what makes the
    /// grid actionable rather than decorative.
    private func heatCell(day: DailyMetric, value: Double?, lo: Double, span: Double) -> some View {
        let filled: Bool = value != nil
        let intensity: CGFloat = filled ? CGFloat((value! - lo) / span) : 0
        return Button {
            selectedDay = DaySelection(metric: day)
        } label: {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(filled ? metric.tint.opacity(0.22 + 0.68 * intensity) : StrandPalette.surfaceInset)
                .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibility(day, value: value))
    }

    private func dayAccessibility(_ day: DailyMetric, value: Double?) -> String {
        guard let v = value else { return "\(day.day): no data" }
        return "\(day.day): \(metric.fmt(v)) \(metric.unit)"
    }

    /// The tapped-day detail: every real signal recorded that day, so a dark or bright cell can be
    /// explained rather than just noticed.
    private func dayDetailSheet(_ day: DailyMetric) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StrandCard {
                        VStack(spacing: 0) {
                            dayRow("Recovery", day.recovery.map { "\(Int($0.rounded()))%" })
                            dayRow("Strain", day.strain.map { String(format: "%.1f", PremiumMetricCatalog.strainDisplay($0)) })
                            dayRow("HRV", day.avgHrv.map { "\(Int($0.rounded())) ms" })
                            dayRow("Resting HR", day.restingHr.map { "\($0) bpm" })
                            dayRow("Sleep", day.totalSleepMin.map { PremiumAnalysis.durText($0) })
                            dayRow("Efficiency", day.efficiency.map {
                                "\(Int(($0 <= 1 ? $0 * 100 : $0).rounded()))%" })
                            dayRow("Respiratory", day.respRateBpm.map { String(format: "%.1f rpm", $0) })
                            dayRow("Steps", day.steps.map { "\($0)" })
                        }
                    }
                    Text("Only signals actually recorded that day are shown.", comment: "Trends day-detail footnote")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
                .padding(20)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(prettyDay(day.day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { selectedDay = nil }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
    }

    @ViewBuilder private func dayRow(_ label: String, _ value: String?) -> some View {
        if let v = value {
            VStack(spacing: 0) {
                HStack {
                    Text(label).font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                    Text(v).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                }
                .padding(.vertical, 11)
                Rectangle().fill(StrandPalette.hairline).frame(height: 1)
            }
        }
    }

    private func prettyDay(_ key: String) -> String {
        guard let d = PremiumAnalysis.dayParser.date(from: key) else { return key }
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: d)
    }

    private var rangeControl: some View {
        HStack(spacing: 2) {
            ForEach(Array(ranges.enumerated()), id: \.offset) { i, r in
                let on = i == rangeIndex
                Button { withAnimation(.easeOut(duration: 0.25)) { rangeIndex = i } } label: {
                    Text(localizedRangeName(r.0)).font(StrandFont.subhead)
                        .foregroundStyle(on ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(on ? StrandPalette.surfaceRaised : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(StrandPalette.surfaceInset))
        .overlay(Capsule().strokeBorder(StrandPalette.hairline, lineWidth: 1))
    }

    /// Maps a raw range identifier to its localized display name.
    private func localizedRangeName(_ raw: String) -> String {
        switch raw {
        case "Week":    return String(localized: "Week")
        case "Quarter": return String(localized: "Quarter")
        case "Year":    return String(localized: "Year")
        default:        return String(localized: "Month")
        }
    }

    private var trendDelta: some View {
        let half = series.count / 2
        let rising: Bool? = half >= 1 ? {
            let a = series.prefix(half).reduce(0,+) / Double(max(1, half))
            let b = series.suffix(series.count - half).reduce(0,+) / Double(max(1, series.count - half))
            return b >= a
        }() : nil
        let better = rising.map { metric.higherBetter ? $0 : !$0 }
        return HStack(spacing: 4) {
            if let r = rising {
                Image(systemName: r ? "arrow.up.right" : "arrow.down.right").font(.system(size: 11, weight: .bold))
                Text(r ? String(localized: "Rising") : String(localized: "Easing")).font(StrandFont.captionNumber)
            } else { Text("—").font(StrandFont.captionNumber) }
        }
        .foregroundStyle(better == nil ? StrandPalette.textTertiary
                         : (better! ? StrandPalette.statusPositive : StrandPalette.metricRose))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(StrandPalette.surfaceInset))
    }

    /// This-period-vs-previous absolute and percentage change, computed once so the card and its
    /// delta chip agree. `nil` unless BOTH windows are fully populated — a half-filled comparison
    /// window would silently overstate the change, the same rule `PremiumAnalysis.periodChangePct`
    /// applies everywhere else.
    private var periodComparison: (cur: Double?, prev: Double?, deltaAbs: Double?, deltaPct: Double?) {
        let n = ranges[rangeIndex].1
        let all = repo.days.suffix(n * 2).compactMap(metric.key)
        guard all.count >= n * 2 else {
            let cur = Array(all.suffix(n))
            let curAvg = cur.isEmpty ? nil : cur.reduce(0,+)/Double(cur.count)
            return (curAvg, nil, nil, nil)
        }
        let cur = Array(all.suffix(n)), prev = Array(all.prefix(n))
        let curAvg = cur.reduce(0,+)/Double(cur.count)
        let prevAvg = prev.reduce(0,+)/Double(prev.count)
        let deltaAbs = curAvg - prevAvg
        let deltaPct: Double? = prevAvg != 0 ? deltaAbs / abs(prevAvg) * 100 : nil
        return (curAvg, prevAvg, deltaAbs, deltaPct)
    }

    private var comparisonCard: some View {
        let comp = periodComparison
        let better: Bool? = comp.deltaAbs.map { metric.higherBetter ? $0 >= 0 : $0 <= 0 }
        return VStack(alignment: .leading, spacing: 14) {
            Text(String(format: String(localized: "This %@ vs last"), rangeLabel.lowercased())).font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            StrandCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        compareStat("This period", comp.cur, metric.tint)
                        Rectangle().fill(StrandPalette.hairline).frame(width: 1, height: 44)
                        compareStat("Previous", comp.prev, StrandPalette.textTertiary)
                    }
                    if let dAbs = comp.deltaAbs {
                        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                        HStack(spacing: 8) {
                            Text(deltaAbsText(dAbs))
                                .font(StrandFont.captionNumber)
                                .foregroundStyle(better == nil ? StrandPalette.textSecondary
                                                 : (better! ? StrandPalette.recoveryColor(85) : StrandPalette.metricRose))
                            if let dPct = comp.deltaPct {
                                Text("(\(PremiumAnalysis.signedPct(dPct)))")
                                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            }
                            Spacer()
                            Text("vs previous period", comment: "Trends comparison delta caption")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }
            }
        }
    }
    /// A signed absolute delta in the metric's own unit — "+3 bpm", "-0.4" — so the change reads in
    /// the same terms as the metric itself, alongside the percentage.
    private func deltaAbsText(_ v: Double) -> String {
        let sign = v >= 0 ? "+" : ""
        let unit = metric.unit.isEmpty ? "" : " " + metric.unit
        return sign + metric.fmt(v) + unit
    }
    private func compareStat(_ label: String, _ v: Double?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(v.map(metric.fmt) ?? "—").font(.system(size: 26, weight: .heavy)).monospacedDigit()
                .foregroundStyle(tint)
            Text(label).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var digestGrid: some View {
        let best = metric.higherBetter ? series.max() : series.min()
        let worst = metric.higherBetter ? series.min() : series.max()
        let sd = Self.stdDev(series)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Digest", comment: "Trends section title").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                digestTile(metric.higherBetter ? "Best" : "Lowest", best.map(metric.fmt) ?? "—", metric.unit, metric.tint)
                digestTile("Average", average.map(metric.fmt) ?? "—", metric.unit, StrandPalette.gold)
                digestTile(metric.higherBetter ? "Lowest" : "Best", worst.map(metric.fmt) ?? "—", metric.unit,
                           StrandPalette.textTertiary)
                digestTile("Consistency", sd.map { metric.fmt($0) } ?? "—", metric.unit, StrandPalette.metricCyan)
            }
            Text("Consistency is the standard deviation across the period — lower means steadier day to day.", comment: "Trends digest footnote")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
    }
    /// Population standard deviation — how much the period's values actually wandered day to day, not
    /// just their average. `nil` below 2 samples (a spread needs at least two points).
    private static func stdDev(_ xs: [Double]) -> Double? {
        guard xs.count >= 2 else { return nil }
        let mean = xs.reduce(0, +) / Double(xs.count)
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
        return variance.squareRoot()
    }
    private func digestTile(_ label: String, _ value: String, _ unit: String, _ tint: Color) -> some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased()).font(StrandFont.overline).tracking(1.2)
                    .foregroundStyle(StrandPalette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 26, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Distribution histogram

    /// Where this metric usually lands, with the LATEST reading marked inside it. The old version
    /// drew bare bucket bars with no reference point at all — pretty, but it answered nothing.
    /// `DistributionHistogram` marks today's value, and the caption states its percentile, so the
    /// card answers "how unusual is this for me?" rather than leaving the shape to be admired.
    @ViewBuilder private var histogramCard: some View {
        if series.count >= 8 {
            VStack(alignment: .leading, spacing: 14) {
                Text("Distribution", comment: "Trends section title").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                StrandCard {
                    VStack(alignment: .leading, spacing: 10) {
                        DistributionHistogram(values: series, buckets: 10, tint: metric.tint,
                                              highlight: series.last, height: 90)
                        HStack {
                            Text(series.min().map(metric.fmt) ?? "—")
                            Spacer()
                            Text(series.max().map(metric.fmt) ?? "—")
                        }
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        Text(percentileCaption)
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Places the most recent value inside the period's own distribution.
    private var percentileCaption: String {
        guard let latest = series.last, series.count >= 8 else {
            return String(localized: "Your recorded readings for this period, bucketed.")
        }
        let below: Int = series.filter { $0 < latest }.count
        let pct: Int = Int((Double(below) / Double(series.count) * 100).rounded())
        return String(format: String(localized: "Latest %1$@ sits higher than %2$d%% of this period's %3$d readings."),
                      metric.fmt(latest), pct, series.count)
    }

    // MARK: Day-of-week breakdown

    /// The metric's average by day of week (Mon…Sun), over the SELECTED metric's full banked history
    /// (not just the current range — a weekday pattern needs more than a week or two to mean anything).
    /// A weekday with no samples yet just shows no bar rather than a guessed average.
    @ViewBuilder private var weekdayCard: some View {
        let byWeekday = Self.weekdayAverages(repo.days, key: metric.key)
        let present = byWeekday.compactMap { $0.1 }
        if present.count >= 3 {
            let lo = present.min() ?? 0, hi = present.max() ?? 1
            let span = max(hi - lo, 0.0001)
            VStack(alignment: .leading, spacing: 14) {
                Text("By day of week", comment: "Trends section title").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                StrandCard {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Array(byWeekday.enumerated()), id: \.offset) { _, entry in
                            let (label, v) = entry
                            VStack(spacing: 6) {
                                VStack {
                                    Spacer(minLength: 0)
                                    if let v {
                                        Capsule().fill(metric.tint)
                                            .frame(height: 8 + CGFloat((v - lo) / span) * 60)
                                    } else {
                                        Circle().fill(StrandPalette.surfaceInset).frame(width: 6, height: 6)
                                    }
                                }
                                .frame(height: 70)
                                Text(label).font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    if let split = Self.weekdayVsWeekend(byWeekday) {
                        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                        HStack(spacing: 16) {
                            compareStat("Weekday avg", split.weekday, StrandPalette.textSecondary)
                            Rectangle().fill(StrandPalette.hairline).frame(width: 1, height: 36)
                            compareStat("Weekend avg", split.weekend, metric.tint)
                        }
                    }
                }
            }
        }
    }
    /// Weekday (Mon–Fri) vs weekend (Sat–Sun) averages, from the SAME per-weekday means the bar
    /// chart plots — "does this metric behave differently on weekends?" without a separate query.
    /// `nil` unless both sides have at least one real weekday's average behind them.
    private static func weekdayVsWeekend(_ byWeekday: [(String, Double?)]) -> (weekday: Double, weekend: Double)? {
        guard byWeekday.count == 7 else { return nil }
        let weekdayVals = byWeekday[0..<5].compactMap(\.1)
        let weekendVals = byWeekday[5..<7].compactMap(\.1)
        guard !weekdayVals.isEmpty, !weekendVals.isEmpty else { return nil }
        return (weekdayVals.reduce(0,+) / Double(weekdayVals.count),
                weekendVals.reduce(0,+) / Double(weekendVals.count))
    }
    /// Mean value per weekday (Mon-first) across ALL banked days with a real value for this metric.
    private static func weekdayAverages(_ days: [DailyMetric], key: (DailyMetric) -> Double?) -> [(String, Double?)] {
        let cal = Calendar.current
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        var buckets: [Int: [Double]] = [:]
        for d in days {
            guard let v = key(d), let date = inF.date(from: d.day) else { continue }
            buckets[cal.component(.weekday, from: date), default: []].append(v)
        }
        // Calendar.weekday is 1=Sun…7=Sat; reorder Mon…Sun for a familiar week strip.
        let order: [(Int, String)] = [(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"),
                                       (6, "Fri"), (7, "Sat"), (1, "Sun")]
        return order.map { wd, label in
            let vals = buckets[wd] ?? []
            return (label, vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count))
        }
    }

    // MARK: Correlation scatter

    /// The metric paired against Recovery (or, when Recovery itself is selected, against Sleep — so
    /// there's always a distinct second variable), same-day pairs only, over the current range.
    /// The metric the primary one is compared against. User-selectable (defaults to a sensible
    /// partner) so Trends is an exploration tool — "do THESE two move together?" — rather than a
    /// fixed pairing the user can't question.
    private var correlationPartner: Metric {
        if let idx = partnerIndex, idx != metricIndex, idx < metrics.count { return metrics[idx] }
        return metrics[metricIndex == 0 ? 3 : 0]
    }
    /// Each series independently (own-day, own-nil filtering only) — `CorrelationEngine.alignByDay`
    /// does the actual inner join, so this doesn't need to pre-filter for co-presence itself.
    private var pairedDaySeries: (x: [(day: String, value: Double)], y: [(day: String, value: Double)]) {
        let partner = correlationPartner
        let days = Array(repo.days.suffix(ranges[rangeIndex].1))
        var xs: [(day: String, value: Double)] = [], ys: [(day: String, value: Double)] = []
        for d in days {
            if let xv = metric.key(d) { xs.append((day: d.day, value: xv)) }
            if let yv = partner.key(d) { ys.append((day: d.day, value: yv)) }
        }
        return (xs, ys)
    }

    /// Normalizes paired samples into unit-square plot points. Pulled out of `correlationCard` (a
    /// plain loop with explicit types, not `zip(...).map { }` inline) so the SwiftUI `@ViewBuilder`
    /// expression above it doesn't have to jointly solve this arithmetic — inlined, the compiler hit
    /// "unable to type-check this expression in reasonable time".
    private static func normalizedPoints(xs: [Double], ys: [Double], xlo: Double, xspan: Double, ylo: Double, yspan: Double) -> [CGPoint] {
        var pts: [CGPoint] = []
        pts.reserveCapacity(xs.count)
        for i in 0..<xs.count {
            let nx: Double = (xs[i] - xlo) / xspan
            let ny: Double = 1 - (ys[i] - ylo) / yspan
            pts.append(CGPoint(x: CGFloat(nx), y: CGFloat(ny)))
        }
        return pts
    }

    /// Choose which metric the primary one is compared against. Excludes the primary itself, so the
    /// card can never plot a metric against a copy of itself.
    private var partnerPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { idx, m in
                    if idx != metricIndex {
                        let isOn: Bool = correlationPartner.name == m.name
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { partnerIndex = idx }
                        } label: {
                            Text(m.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isOn ? StrandPalette.surfaceBase : StrandPalette.textSecondary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(isOn ? m.tint : StrandPalette.surfaceInset))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Deterministic findings across the user's whole history: sustained baseline deviations and
    /// journal behaviour associations. These are the "meaningful changes" the request asks for —
    /// computed, thresholded and confidence-labelled, never a model's impression.
    @ViewBuilder private var findingsCard: some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("What changed").font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                StrandCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(findings) { f in PremiumFindingRow(finding: f) }
                        Text("Computed on-device from your own history. Associations, not causes.", comment: "Findings disclaimer")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
    }

    /// Loads findings, including journal-behaviour associations against HRV / recovery / sleep.
    private func loadFindings() async {
        var out: [PremiumFinding] = []
        for id in [PremiumMetricID.hrv, .restingHr, .recovery, .sleepDuration] {
            let a = PremiumMetricCatalog.analysis(id, repo: repo)
            let d = PremiumMetricCatalog.def(id)
            if let f = PremiumAnalysis.baselineFinding(a, name: d.shortName, unit: d.unit, tint: d.tint) {
                out.append(f)
            }
        }
        // Journal relationships — the request's "Journal relationships once Journal is available".
        let entries = await repo.journalEntries()
        var behaviorDays: [String: Set<String>] = [:]
        for e in entries where e.answeredYes { behaviorDays[e.question, default: []].insert(e.day) }
        let outcomes: [(PremiumMetricID, Color)] = [
            (.hrv, StrandPalette.metricCyan),
            (.recovery, StrandPalette.recoveryColor(85)),
            (.sleepDuration, StrandPalette.sleepDeep),
        ]
        for (behavior, days) in behaviorDays {
            for (id, tint) in outcomes {
                let series = PremiumMetricCatalog.series(id, repo: repo)
                let name = PremiumMetricCatalog.def(id).shortName
                guard let assoc = PremiumAnalysis.behaviorAssociation(
                    behaviorDays: days, behaviorName: behavior,
                    outcome: series, outcomeName: name) else { continue }
                if let f = PremiumAnalysis.behaviorFinding(effect: assoc.effect,
                                                           lagDays: assoc.lagDays, tint: tint) {
                    out.append(f)
                }
            }
        }
        out.sort { $0.confidence > $1.confidence }
        findings = Array(out.prefix(6))
    }

    /// Day-aligned pairs plus the Pearson fit, from the shared `CorrelationEngine` — the same tested
    /// engine `PremiumAnalysis` uses everywhere else — rather than a second, hand-rolled Pearson
    /// implementation that could silently drift from it.
    private var correlationResult: (pairs: [(Double, Double)], correlation: Correlation)? {
        let day = pairedDaySeries
        let aligned = CorrelationEngine.alignByDay(day.x, day.y)
        guard let corr = CorrelationEngine.pearson(aligned) else { return nil }
        return (aligned, corr)
    }

    @ViewBuilder private var correlationCard: some View {
        let partner = correlationPartner
        if let result = correlationResult {
            let xs = result.pairs.map(\.0), ys = result.pairs.map(\.1)
            let xlo = xs.min() ?? 0, xhi = xs.max() ?? 1
            let ylo = ys.min() ?? 0, yhi = ys.max() ?? 1
            let xspan = max(xhi - xlo, 0.0001), yspan = max(yhi - ylo, 0.0001)
            let points = Self.normalizedPoints(xs: xs, ys: ys, xlo: xlo, xspan: xspan, ylo: ylo, yspan: yspan)
            let r = result.correlation.r
            let confidence = PremiumConfidence.from(n: result.correlation.n, strength: r)
            VStack(alignment: .leading, spacing: 14) {
                Text(String(format: String(localized: "%1$@ vs %2$@"), metric.name, partner.name)).font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                partnerPicker
                StrandCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            Text(correlationText(r, partner: partner)).font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text("r \(String(format: "%.2f", r))").font(StrandFont.captionNumber)
                                .foregroundStyle(metric.tint)
                        }
                        Canvas { ctx, size in
                            for p in points {
                                let c = CGPoint(x: p.x * size.width, y: p.y * size.height)
                                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)),
                                         with: .color(metric.tint.opacity(0.65)))
                            }
                        }
                        .frame(height: 140)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(StrandPalette.surfaceInset))
                        HStack {
                            Text(metric.name).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            Spacer()
                            Text(partner.name).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        }
                        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                        HStack {
                            Text(confidence.label).font(StrandFont.footnote)
                                .foregroundStyle(confidence.tint)
                            Spacer()
                            Text(String(format: String(localized: "%d matched days"), result.correlation.n))
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }
            }
        }
    }
    /// A plain-language, non-causal read of the coefficient — "tend to move together", never "causes".
    private func correlationText(_ r: Double, partner: Metric) -> String {
        let mag = abs(r)
        let strength = mag >= 0.6 ? "a strong" : mag >= 0.3 ? "a moderate" : "a weak"
        let dir = r >= 0 ? "tend to rise and fall together" : "tend to move in opposite directions"
        return "Over this period, \(metric.name) and \(partner.name) show \(strength) relationship — they \(dir)."
    }

    private var insightCard: some View {
        StrandCard(tint: StrandPalette.gold) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(StrandPalette.gold)
                Text(insightText).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var insightText: String {
        guard series.count >= 4, let avg = average else {
            return "Keep logging — a few more days unlock \(metric.name.lowercased()) trends."
        }
        let half = series.count / 2
        let a = series.prefix(half).reduce(0,+)/Double(max(1,half))
        let b = series.suffix(series.count-half).reduce(0,+)/Double(max(1,series.count-half))
        let up = b >= a
        let dir = up ? "risen" : "eased"
        return "Your \(ranges[rangeIndex].0.lowercased()) \(metric.name.lowercased()) has \(dir) to about \(metric.fmt(avg))\(metric.unit.isEmpty ? "" : " " + metric.unit)."
    }
}
#endif
