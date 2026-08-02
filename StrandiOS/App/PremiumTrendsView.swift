#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

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
                key: { $0.strain }, fmt: { String(format: "%.1f", $0) }),
         // efficiency is a FRACTION in [0,1] (see SleepStageTotals.DailySleep's doc), not a 0-100
         // percentage — normalized here (same defensive `<= 1.0 ? *100 : as-is` guard SleepView.
         // efficiencyPct uses) so the "%" unit reads "92%", not "1%".
         Metric(name: "Sleep", unit: "%", tint: StrandPalette.sleepDeep, higherBetter: true,
                key: { $0.efficiency.map { $0 <= 1.0 ? $0 * 100 : $0 } }, fmt: { "\(Int($0.rounded()))" }),
         Metric(name: "Rest HR", unit: "bpm", tint: StrandPalette.metricRose, higherBetter: false,
                key: { $0.restingHr.map(Double.init) }, fmt: { "\(Int($0.rounded()))" })]
    }
    private let ranges: [(String, Int)] = [("Week", 7), ("Month", 30), ("Quarter", 90)]

    @State private var metricIndex = 0
    @State private var rangeIndex = 1

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
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR LONG GAME").font(StrandFont.overline).tracking(1.4)
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
                Text("\(ranges[rangeIndex].0) average").font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textTertiary)
                rangeControl
                if series.count >= 2 {
                    Sparkline(values: series,
                              gradient: Gradient(colors: [metric.tint, metric.tint.opacity(0.55)]),
                              lineWidth: 2.5, showsArea: true, showsHead: true, showsHover: true,
                              valueFormat: { metric.fmt($0) + (metric.unit.isEmpty ? "" : " " + metric.unit) })
                        .frame(height: 170)
                } else {
                    Text("Not enough history yet").font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary).frame(maxWidth: .infinity, minHeight: 170)
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
                        Text("\(ranges[rangeIndex].0) · \(days.count) days").font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(v == nil ? StrandPalette.surfaceInset
                                          : metric.tint.opacity(0.22 + 0.68 * CGFloat((v! - lo) / span)))
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }
        }
    }

    private var rangeControl: some View {
        HStack(spacing: 2) {
            ForEach(Array(ranges.enumerated()), id: \.offset) { i, r in
                let on = i == rangeIndex
                Button { withAnimation(.easeOut(duration: 0.25)) { rangeIndex = i } } label: {
                    Text(r.0).font(StrandFont.subhead)
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
                Text(r ? "Rising" : "Easing").font(StrandFont.captionNumber)
            } else { Text("—").font(StrandFont.captionNumber) }
        }
        .foregroundStyle(better == nil ? StrandPalette.textTertiary
                         : (better! ? StrandPalette.statusPositive : StrandPalette.metricRose))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(StrandPalette.surfaceInset))
    }

    private var comparisonCard: some View {
        let n = ranges[rangeIndex].1
        let all = repo.days.suffix(n * 2).compactMap(metric.key)
        let cur = Array(all.suffix(n)), prev = Array(all.prefix(max(0, all.count - n)))
        let curAvg = cur.isEmpty ? nil : cur.reduce(0,+)/Double(cur.count)
        let prevAvg = prev.isEmpty ? nil : prev.reduce(0,+)/Double(prev.count)
        return VStack(alignment: .leading, spacing: 14) {
            Text("This \(ranges[rangeIndex].0.lowercased()) vs last").font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            StrandCard {
                HStack(spacing: 16) {
                    compareStat("This period", curAvg, metric.tint)
                    Rectangle().fill(StrandPalette.hairline).frame(width: 1, height: 44)
                    compareStat("Previous", prevAvg, StrandPalette.textTertiary)
                }
            }
        }
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
            Text("Digest").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                digestTile(metric.higherBetter ? "Best" : "Lowest", best.map(metric.fmt) ?? "—", metric.unit, metric.tint)
                digestTile("Average", average.map(metric.fmt) ?? "—", metric.unit, StrandPalette.gold)
                digestTile(metric.higherBetter ? "Lowest" : "Best", worst.map(metric.fmt) ?? "—", metric.unit,
                           StrandPalette.textTertiary)
                digestTile("Consistency", sd.map { metric.fmt($0) } ?? "—", metric.unit, StrandPalette.metricCyan)
            }
            Text("Consistency is the standard deviation across the period — lower means steadier day to day.")
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

    /// A 10-bucket histogram of the period's real values — shape, not just trend. Hidden below 8
    /// samples, where a histogram is just noise rather than a meaningful distribution.
    @ViewBuilder private var histogramCard: some View {
        if series.count >= 8 {
            let buckets = Self.histogramCounts(series, bucketCount: 10)
            let maxCount = max(1, buckets.max() ?? 1)
            VStack(alignment: .leading, spacing: 14) {
                Text("Distribution").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                StrandCard {
                    GeometryReader { geo in
                        let barW = geo.size.width / CGFloat(buckets.count)
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(Array(buckets.enumerated()), id: \.offset) { _, count in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(metric.tint.opacity(0.75))
                                    .frame(width: max(2, barW - 2),
                                           height: max(2, geo.size.height * CGFloat(count) / CGFloat(maxCount)))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: 80)
                }
            }
        }
    }
    /// Bucket `values` into `bucketCount` equal-width bins over [min, max]; an all-equal series
    /// collapses to one full bucket rather than dividing by zero.
    private static func histogramCounts(_ values: [Double], bucketCount: Int) -> [Int] {
        guard let lo = values.min(), let hi = values.max(), hi > lo else {
            return values.isEmpty ? [] : [values.count]
        }
        var buckets = [Int](repeating: 0, count: bucketCount)
        let span = hi - lo
        for v in values {
            let idx = min(bucketCount - 1, max(0, Int((v - lo) / span * Double(bucketCount))))
            buckets[idx] += 1
        }
        return buckets
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
                Text("By day of week").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
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
                }
            }
        }
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
    private var correlationPartner: Metric { metrics[metricIndex == 0 ? 3 : 0] }
    private var pairedSeries: (x: [Double], y: [Double]) {
        let partner = correlationPartner
        let days = Array(repo.days.suffix(ranges[rangeIndex].1))
        var xs: [Double] = [], ys: [Double] = []
        for d in days {
            if let xv = metric.key(d), let yv = partner.key(d) { xs.append(xv); ys.append(yv) }
        }
        return (xs, ys)
    }
    /// Pearson correlation coefficient over paired same-day samples. `nil` below 3 pairs (too few to
    /// mean anything) or when one series has zero variance (a flat line correlates with nothing).
    private static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 3 else { return nil }
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var num = 0.0, dx2 = 0.0, dy2 = 0.0
        for i in 0..<xs.count {
            let dx = xs[i] - mx, dy = ys[i] - my
            num += dx * dy; dx2 += dx * dx; dy2 += dy * dy
        }
        let denom = (dx2 * dy2).squareRoot()
        guard denom > 0 else { return nil }
        return num / denom
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

    @ViewBuilder private var correlationCard: some View {
        let partner = correlationPartner
        let pair = pairedSeries
        if let r = Self.pearson(pair.x, pair.y) {
            let xlo = pair.x.min() ?? 0, xhi = pair.x.max() ?? 1
            let ylo = pair.y.min() ?? 0, yhi = pair.y.max() ?? 1
            let xspan = max(xhi - xlo, 0.0001), yspan = max(yhi - ylo, 0.0001)
            let points = Self.normalizedPoints(xs: pair.x, ys: pair.y, xlo: xlo, xspan: xspan, ylo: ylo, yspan: yspan)
            VStack(alignment: .leading, spacing: 14) {
                Text("\(metric.name) vs \(partner.name)").font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
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
