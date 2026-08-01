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
         Metric(name: "Sleep", unit: "%", tint: StrandPalette.sleepDeep, higherBetter: true,
                key: { $0.efficiency }, fmt: { "\(Int($0.rounded()))" }),
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
                    heroCard
                    comparisonCard
                    digestGrid
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
        VStack(alignment: .leading, spacing: 2) {
            Text("YOUR LONG GAME").font(StrandFont.overline).tracking(1.4)
                .foregroundStyle(StrandPalette.textTertiary)
            Text("Trends").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
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
        return VStack(alignment: .leading, spacing: 14) {
            Text("Digest").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                digestTile(metric.higherBetter ? "Best" : "Lowest", best.map(metric.fmt) ?? "—", metric.unit, metric.tint)
                digestTile("Average", average.map(metric.fmt) ?? "—", metric.unit, StrandPalette.gold)
            }
        }
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
