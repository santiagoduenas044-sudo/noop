#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// The reusable single-metric detail screen — the native rebuild of the prototype's `metric.js`. Driven
/// entirely by a `PremiumMetricKind` + the live `Repository` (via `PremiumMetricKit`), so ONE view backs
/// HRV, resting HR, respiratory rate, steps, recovery and sleep performance. Real values only: if the strap
/// never recorded a signal the series is empty and the screen says so rather than inventing a number.
///
/// Layout mirrors the prototype: a range selector (2w / 1m / 3m / 6m over the banked daily history), a hero
/// value with a baseline-delta chip, a trend chart, avg/min/max, a "where today sits" range bar, the recent
/// list, and a plain-language explanation.
struct PremiumMetricDetailView: View {
    let kind: PremiumMetricKind
    @EnvironmentObject var repo: Repository

    /// History window in days. The banked data is daily, so the selector picks a day-count rather than a
    /// literal calendar span — 2 weeks / 1 month / 3 months / 6 months.
    private enum Window: Int, CaseIterable, Identifiable {
        case w14 = 14, w30 = 30, w90 = 90, w180 = 180
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .w14:  return "2W"
            case .w30:  return "1M"
            case .w90:  return "3M"
            case .w180: return "6M"
            }
        }
    }
    @State private var window: Window = .w30

    private var descriptor: PremiumMetricDescriptor { PremiumMetricKit.descriptor(for: kind, repo: repo) }
    /// The samples inside the selected window, oldest→newest.
    private var windowed: [PremiumMetricPoint] { Array(descriptor.series.suffix(window.rawValue)) }
    private var values: [Double] { windowed.map(\.value) }

    var body: some View {
        let d = descriptor
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                windowPicker
                if values.isEmpty {
                    emptyState(d)
                } else {
                    hero(d)
                    chartCard(d)
                    if values.count >= 8 { histogramCard(d) }
                    statsRow(d)
                    rangeCard(d)
                    recentCard(d)
                }
                explanationCard(d)
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .navigationTitle(d.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Window selector

    private var windowPicker: some View {
        HStack(spacing: 8) {
            ForEach(Window.allCases) { w in
                let active = w == window
                Button {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { window = w }
                } label: {
                    Text(w.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active ? StrandPalette.goldDeepText : StrandPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(active ? descriptor.tint : StrandPalette.surfaceInset))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Hero

    private func hero(_ d: PremiumMetricDescriptor) -> some View {
        StrandCard(tint: d.tint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    iconTile(d.icon, tint: d.tint)
                    Text(d.name.uppercased()).font(StrandFont.overline).tracking(1.4)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountUpText(value: d.latest ?? 0,
                                format: { d.decimals == 0 ? String(Int($0.rounded())) : String(format: "%.\(d.decimals)f", $0) },
                                font: .system(size: 46, weight: .heavy),
                                color: StrandPalette.textPrimary)
                        .monospacedDigit()
                    if !d.unit.isEmpty {
                        Text(d.unit).font(StrandFont.headline).foregroundStyle(StrandPalette.textTertiary)
                    }
                    Spacer()
                    deltaChip(d)
                }
            }
        }
    }

    /// Baseline-delta chip: the latest value vs the 30-day baseline, coloured by whether the change is in the
    /// metric's "good" direction (green/red) — or neutral grey when the metric has no single good direction.
    @ViewBuilder private func deltaChip(_ d: PremiumMetricDescriptor) -> some View {
        if let base = d.baseline(), let now = d.latest {
            let delta = now - base
            let sign = delta >= 0 ? "+" : "−"
            let mag = abs(delta)
            let magStr = d.decimals == 0 ? String(Int(mag.rounded())) : String(format: "%.\(d.decimals)f", mag)
            let good: Bool? = d.higherBetter.map { ($0 && delta >= 0) || (!$0 && delta <= 0) }
            let tint: Color = good == nil ? StrandPalette.textSecondary
                             : (good! ? StrandPalette.recoveryColor(80) : StrandPalette.metricRose)
            HStack(spacing: 4) {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                Text("\(sign)\(magStr) vs base").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.14)))
        }
    }

    // MARK: Chart

    private func chartCard(_ d: PremiumMetricDescriptor) -> some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Trend · last \(window.label)")
                Sparkline(values: values,
                          gradient: Gradient(colors: [d.tint, d.tint.opacity(0.55)]),
                          lineWidth: 2.5, showsArea: true, showsHead: true, showsHover: true,
                          valueFormat: { d.format($0) },
                          indexLabel: { i in dayLabel(windowed[safe: i]?.day) })
                    .frame(height: 150)
            }
        }
    }

    // MARK: Distribution

    /// A 10-bucket histogram of the windowed values — how the metric's real samples are actually
    /// distributed, not just where the trend line has been. Only shown once there are enough samples
    /// (≥8) for the shape to mean anything; below that it's just noise, so it's hidden rather than drawn.
    private func histogramCard(_ d: PremiumMetricDescriptor) -> some View {
        let buckets = Self.histogramCounts(values, bucketCount: 10)
        let maxCount = max(1, buckets.max() ?? 1)
        return StrandCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Distribution · last \(window.label)")
                GeometryReader { geo in
                    let barW = geo.size.width / CGFloat(buckets.count)
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(buckets.enumerated()), id: \.offset) { _, count in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(d.tint.opacity(0.75))
                                .frame(width: max(2, barW - 2),
                                       height: max(2, geo.size.height * CGFloat(count) / CGFloat(maxCount)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 70)
            }
        }
    }

    /// Bucket `values` into `bucketCount` equal-width bins over [min, max] and return each bin's count.
    /// A degenerate range (all-equal values) collapses to a single full bucket rather than dividing by
    /// zero.
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

    // MARK: Stats

    private func statsRow(_ d: PremiumMetricDescriptor) -> some View {
        let avg = values.reduce(0, +) / Double(max(1, values.count))
        return HStack(spacing: 12) {
            statTile("AVERAGE", d.format(avg, withUnit: false), d)
            statTile("LOW", d.format(values.min() ?? 0, withUnit: false), d)
            statTile("HIGH", d.format(values.max() ?? 0, withUnit: false), d)
        }
    }

    private func statTile(_ label: String, _ value: String, _ d: PremiumMetricDescriptor) -> some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(StrandFont.overline).tracking(1.2)
                    .foregroundStyle(StrandPalette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                    if !d.unit.isEmpty {
                        Text(d.unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Where today sits

    private func rangeCard(_ d: PremiumMetricDescriptor) -> some View {
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let now = d.latest ?? lo
        let frac = hi > lo ? (now - lo) / (hi - lo) : 0.5
        return StrandCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Where today sits")
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(StrandPalette.surfaceInset).frame(height: 8)
                        Capsule().fill(LinearGradient(colors: [d.tint.opacity(0.5), d.tint],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * CGFloat(min(1, max(0, frac)))), height: 8)
                        Circle().fill(d.tint)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(StrandPalette.surfaceBase, lineWidth: 2))
                            .shadow(color: d.tint.opacity(0.5), radius: 5)
                            .offset(x: max(0, min(geo.size.width - 16, geo.size.width * CGFloat(min(1, max(0, frac))) - 8)))
                    }
                }
                .frame(height: 18)
                HStack {
                    Text(d.format(lo)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                    Text("now \(d.format(now))").font(StrandFont.captionNumber).foregroundStyle(d.tint)
                    Spacer()
                    Text(d.format(hi)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    // MARK: Recent list

    private func recentCard(_ d: PremiumMetricDescriptor) -> some View {
        let recent = Array(windowed.suffix(7).reversed())
        return StrandCard {
            VStack(spacing: 0) {
                sectionLabel("Recent")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                ForEach(Array(recent.enumerated()), id: \.element.id) { idx, p in
                    HStack {
                        Text(dayLabel(p.day)).font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                        Spacer()
                        Text(d.format(p.value)).font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    .padding(.vertical, 11)
                    if idx < recent.count - 1 {
                        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: Explanation

    private func explanationCard(_ d: PremiumMetricDescriptor) -> some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("What it means")
                Text(d.explanation).font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
    }

    // MARK: Empty state

    private func emptyState(_ d: PremiumMetricDescriptor) -> some View {
        StrandCard {
            VStack(spacing: 12) {
                iconTile(d.icon, tint: d.tint)
                Text("No \(d.shortName) recorded yet")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text("Wear your strap overnight and this will fill in. NOOP only ever shows measurements it actually recorded.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    // MARK: Small shared pieces

    private func sectionLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(StrandFont.overline).tracking(1.3)
            .foregroundStyle(StrandPalette.textTertiary)
    }
    private func iconTile(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }
    /// "Mon 14" style short label for a `YYYY-MM-DD` key.
    private func dayLabel(_ key: String?) -> String {
        guard let key else { return "" }
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        guard let date = inF.date(from: key) else { return key }
        let outF = DateFormatter(); outF.dateFormat = "EEE d"
        return outF.string(from: date)
    }
}

/// Safe indexed access for the hover index-label closure (guards an out-of-range sample index).
private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
#endif
