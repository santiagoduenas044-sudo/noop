#if os(iOS)
import SwiftUI
import StrandDesign

/// PremiumCharts — the Premium UI's rich visualisation vocabulary.
///
/// These replace the generic single-line sparkline that used to carry every screen. Each chart
/// here answers a specific analytical question rather than just plotting a series:
///
/// * `BaselineBandChart` — "where does this sit against MY normal?" (line over a personal band)
/// * `RangeColumnChart` — "how wide was each day?" (daily min/max columns)
/// * `DeviationBars` — "which days were above or below target?" (diverging bars around zero)
/// * `DistributionHistogram` — "where does this metric usually land?" (value distribution)
/// * `WeekdayPatternChart` — "does this depend on the day of the week?"
/// * `ScrubbableChart` — an interactive time-series with a draggable readout cursor
/// * `DualMetricChart` — two normalised metrics overlaid to reveal shared movement
/// * `CorrelationScatter` — paired samples plus a least-squares fit
///
/// All are `Canvas`-based (cheap, no per-point view allocation) and take explicit, pre-computed
/// inputs — deliberately, so a SwiftUI `@ViewBuilder` never has to type-check chart arithmetic
/// inline, which is what previously blew the compiler's expression budget.
enum PremiumCharts {}

// MARK: - Shared geometry helpers

extension PremiumCharts {
    /// Maps a value into a y pixel coordinate inside `height` for the given range (inverted: high
    /// values sit near the top).
    static func y(_ value: Double, lo: Double, hi: Double, height: CGFloat) -> CGFloat {
        guard hi > lo else { return height / 2 }
        let clamped = min(max(value, lo), hi)
        let frac = (clamped - lo) / (hi - lo)
        return height * CGFloat(1 - frac)
    }

    /// Evenly spaces `count` points across `width`, returning the x for `index`.
    static func x(_ index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return width / 2 }
        return width * CGFloat(index) / CGFloat(count - 1)
    }

    /// A padded [lo, hi] range covering the values, with an optional extra series (a baseline band)
    /// folded in so both always fit on one scale.
    static func range(values: [Double], including extra: [Double] = [],
                      padFraction: Double = 0.12) -> (lo: Double, hi: Double) {
        let all = values + extra
        guard let mn = all.min(), let mx = all.max() else { return (0, 1) }
        if mn == mx { return (mn - 1, mx + 1) }
        let pad = (mx - mn) * padFraction
        return (mn - pad, mx + pad)
    }
}

// MARK: - Baseline band chart

/// A metric's recent history drawn over its PERSONAL baseline band (mean ± spread). The single
/// most useful health chart shape: it answers "is this normal *for me*?" at a glance, which a bare
/// line never can. Points outside the band are emphasised.
struct BaselineBandChart: View {
    let values: [Double]
    /// Personal baseline mean. When nil the band is omitted and only the line draws — the honest
    /// rendering when there isn't enough history for a baseline yet.
    var baseline: Double?
    /// Baseline dispersion (σ). The band spans baseline ± spread.
    var spread: Double?
    var tint: Color
    var height: CGFloat = 140
    /// Formats the value shown at the emphasised final point.
    var valueFormat: (Double) -> String = { String(Int($0.rounded())) }

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2 else { return }
            let band: [Double]
            if let b = baseline, let s = spread, s > 0 {
                band = [b - s, b + s]
            } else if let b = baseline {
                band = [b]
            } else {
                band = []
            }
            let r = PremiumCharts.range(values: values, including: band)
            let w = size.width, h = size.height

            // 1. The baseline band behind everything.
            if let b = baseline, let s = spread, s > 0 {
                let yTop = PremiumCharts.y(b + s, lo: r.lo, hi: r.hi, height: h)
                let yBot = PremiumCharts.y(b - s, lo: r.lo, hi: r.hi, height: h)
                let rect = CGRect(x: 0, y: yTop, width: w, height: max(1, yBot - yTop))
                ctx.fill(Path(roundedRect: rect, cornerRadius: 4),
                         with: .color(tint.opacity(0.10)))
            }
            // 2. The baseline centre line, dashed.
            if let b = baseline {
                let yb = PremiumCharts.y(b, lo: r.lo, hi: r.hi, height: h)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: yb))
                line.addLine(to: CGPoint(x: w, y: yb))
                ctx.stroke(line, with: .color(tint.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            // 3. The value line + soft area fill.
            var pts: [CGPoint] = []
            pts.reserveCapacity(values.count)
            for (i, v) in values.enumerated() {
                let px = PremiumCharts.x(i, count: values.count, width: w)
                let py = PremiumCharts.y(v, lo: r.lo, hi: r.hi, height: h)
                pts.append(CGPoint(x: px, y: py))
            }
            var line = Path()
            line.addLines(pts)
            var area = line
            area.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h))
            area.addLine(to: CGPoint(x: pts[0].x, y: h))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.22), tint.opacity(0.01)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(line, with: .color(tint), lineWidth: 2)

            // 4. Emphasise the most recent point.
            if let last = pts.last {
                let dot = CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: dot), with: .color(tint))
                ctx.stroke(Path(ellipseIn: dot), with: .color(StrandPalette.surfaceBase), lineWidth: 2)
            }
        }
        .frame(height: height)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let last = values.last else { return "No data" }
        if let b = baseline {
            let dir = last >= b ? "above" : "below"
            return "Latest \(valueFormat(last)), \(dir) your baseline of \(valueFormat(b))"
        }
        return "Latest \(valueFormat(last))"
    }
}

// MARK: - Range columns (daily min/max)

/// One vertical column per day spanning that day's min→max, with an optional marker for a
/// representative value (e.g. the day's average or resting HR). Communicates *spread*, which a
/// line of daily averages hides entirely.
struct RangeColumnChart: View {
    struct Column: Identifiable {
        let id: Int
        let lo: Double
        let hi: Double
        /// Optional emphasised point inside the column (average, resting…).
        let marker: Double?
        let label: String?
    }

    let columns: [Column]
    var tint: Color
    var markerTint: Color = StrandPalette.textPrimary
    var height: CGFloat = 150

    var body: some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in
                guard !columns.isEmpty else { return }
                let lows: [Double] = columns.map(\.lo)
                let highs: [Double] = columns.map(\.hi)
                let r = PremiumCharts.range(values: lows + highs, padFraction: 0.10)
                let h = size.height
                let slot = size.width / CGFloat(columns.count)
                let barW = min(14, max(4, slot * 0.5))

                for (i, col) in columns.enumerated() {
                    let cx = slot * (CGFloat(i) + 0.5)
                    let yHi = PremiumCharts.y(col.hi, lo: r.lo, hi: r.hi, height: h)
                    let yLo = PremiumCharts.y(col.lo, lo: r.lo, hi: r.hi, height: h)
                    let rect = CGRect(x: cx - barW / 2, y: yHi,
                                      width: barW, height: max(2, yLo - yHi))
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2),
                             with: .linearGradient(
                                Gradient(colors: [tint.opacity(0.95), tint.opacity(0.45)]),
                                startPoint: CGPoint(x: 0, y: yHi), endPoint: CGPoint(x: 0, y: yLo)))

                    if let m = col.marker {
                        let ym = PremiumCharts.y(m, lo: r.lo, hi: r.hi, height: h)
                        let dot = CGRect(x: cx - 2.5, y: ym - 2.5, width: 5, height: 5)
                        ctx.fill(Path(ellipseIn: dot), with: .color(markerTint))
                    }
                }
            }
            .frame(height: height)

            if columns.contains(where: { $0.label != nil }) {
                HStack(spacing: 0) {
                    ForEach(columns) { col in
                        Text(col.label ?? "")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Diverging deviation bars

/// Bars growing up (surplus) or down (deficit) from a centre line. Used for sleep balance vs
/// target and debt ledgers, where the SIGN is the whole point and a normal bar chart would bury it.
struct DeviationBars: View {
    /// Signed deltas, oldest→newest.
    let deltas: [Double]
    var positiveTint: Color = StrandPalette.recoveryColor(85)
    var negativeTint: Color = StrandPalette.metricRose
    var height: CGFloat = 90
    var labels: [String] = []

    var body: some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in
                guard !deltas.isEmpty else { return }
                let scale = max(deltas.map { abs($0) }.max() ?? 1, 1)
                let h = size.height
                let mid = h / 2
                let slot = size.width / CGFloat(deltas.count)
                let barW = min(16, max(3, slot * 0.55))

                var axis = Path()
                axis.move(to: CGPoint(x: 0, y: mid))
                axis.addLine(to: CGPoint(x: size.width, y: mid))
                ctx.stroke(axis, with: .color(StrandPalette.hairline), lineWidth: 1)

                for (i, d) in deltas.enumerated() {
                    let cx = slot * (CGFloat(i) + 0.5)
                    let magnitude = CGFloat(abs(d) / scale) * (mid - 4)
                    let barH = max(2, magnitude)
                    let rect = d >= 0
                        ? CGRect(x: cx - barW / 2, y: mid - barH, width: barW, height: barH)
                        : CGRect(x: cx - barW / 2, y: mid, width: barW, height: barH)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                             with: .color(d >= 0 ? positiveTint : negativeTint))
                }
            }
            .frame(height: height)

            if !labels.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { _, l in
                        Text(l).font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Distribution histogram

/// Bucketed value distribution with the current value marked. Answers "where does this usually
/// land, and is today unusual?" — far more informative than another time-series.
struct DistributionHistogram: View {
    let values: [Double]
    var buckets: Int = 10
    var tint: Color
    /// Marks where a specific value falls in the distribution (e.g. today's reading).
    var highlight: Double?
    var height: CGFloat = 120

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 3, let mn = values.min(), let mx = values.max(), mx > mn else { return }
            let n = max(3, buckets)
            let span = (mx - mn) / Double(n)
            var counts = [Int](repeating: 0, count: n)
            for v in values {
                var idx = Int((v - mn) / span)
                if idx >= n { idx = n - 1 }
                if idx < 0 { idx = 0 }
                counts[idx] += 1
            }
            let peak = max(counts.max() ?? 1, 1)
            let h = size.height
            let slot = size.width / CGFloat(n)

            for (i, c) in counts.enumerated() {
                let barH = CGFloat(Double(c) / Double(peak)) * (h - 4)
                let rect = CGRect(x: slot * CGFloat(i) + slot * 0.12,
                                  y: h - barH, width: slot * 0.76, height: max(1, barH))
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                         with: .linearGradient(
                            Gradient(colors: [tint.opacity(0.9), tint.opacity(0.35)]),
                            startPoint: CGPoint(x: 0, y: h - barH), endPoint: CGPoint(x: 0, y: h)))
            }

            if let hv = highlight, hv >= mn, hv <= mx {
                let frac = (hv - mn) / (mx - mn)
                let hx = size.width * CGFloat(frac)
                var marker = Path()
                marker.move(to: CGPoint(x: hx, y: 0))
                marker.addLine(to: CGPoint(x: hx, y: h))
                ctx.stroke(marker, with: .color(StrandPalette.textPrimary),
                           style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Weekday pattern

/// Mean value per weekday as a horizontal bar set, with the overall mean marked. Surfaces
/// day-of-week structure (weekend late nights, Monday load) that a chronological chart hides.
struct WeekdayPatternChart: View {
    /// weekday (1 = Sunday … 7 = Saturday) → mean value.
    let byWeekday: [Int: Double]
    var tint: Color
    var format: (Double) -> String = { String(Int($0.rounded())) }

    private static let shortNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        let present: [Int] = (1...7).filter { byWeekday[$0] != nil }
        let vals: [Double] = present.compactMap { byWeekday[$0] }
        let lo: Double = vals.min() ?? 0
        let hi: Double = vals.max() ?? 1
        let span: Double = hi > lo ? hi - lo : 1

        return VStack(spacing: 8) {
            ForEach(present, id: \.self) { wd in
                let v: Double = byWeekday[wd] ?? 0
                let frac: Double = (v - lo) / span
                HStack(spacing: 10) {
                    Text(Self.shortNames[wd])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(width: 32, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(StrandPalette.surfaceInset)
                            Capsule()
                                .fill(LinearGradient(colors: [tint, tint.opacity(0.6)],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, geo.size.width * CGFloat(0.15 + 0.85 * frac)))
                        }
                    }
                    .frame(height: 10)
                    Text(format(v))
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Scrubbable time series

/// An interactive line chart with a draggable cursor that reports the value under the finger.
/// The readout is supplied by the caller so the same component serves heart rate, HRV and any
/// other series with the right units and secondary context.
struct ScrubbableChart: View {
    let values: [Double]
    var tint: Color
    var height: CGFloat = 150
    /// Optional horizontal reference line (resting HR, personal baseline…).
    var reference: Double?
    var referenceTint: Color = StrandPalette.metricCyan
    /// Builds the readout text for a scrubbed index.
    var readout: (Int, Double) -> String
    /// Optional caption shown when nothing is being scrubbed.
    var idleLabel: String = "Drag to explore"

    @State private var cursor: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(cursorText)
                .font(StrandFont.captionNumber)
                .foregroundStyle(cursor == nil ? StrandPalette.textTertiary : StrandPalette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                let w: CGFloat = geo.size.width
                chartCanvas(width: w)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                guard values.count > 1, w > 0 else { return }
                                let frac = min(max(0, g.location.x / w), 1)
                                cursor = Int((frac * CGFloat(values.count - 1)).rounded())
                            }
                            .onEnded { _ in cursor = nil }
                    )
            }
            .frame(height: height)
        }
    }

    private var cursorText: String {
        guard let c = cursor, c >= 0, c < values.count else { return idleLabel }
        return readout(c, values[c])
    }

    private func chartCanvas(width: CGFloat) -> some View {
        Canvas { ctx, size in
            guard values.count >= 2 else { return }
            let r = PremiumCharts.range(values: values, including: reference.map { [$0] } ?? [])
            let h = size.height

            if let ref = reference {
                let yr = PremiumCharts.y(ref, lo: r.lo, hi: r.hi, height: h)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: yr))
                line.addLine(to: CGPoint(x: size.width, y: yr))
                ctx.stroke(line, with: .color(referenceTint.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            var pts: [CGPoint] = []
            pts.reserveCapacity(values.count)
            for (i, v) in values.enumerated() {
                let px = PremiumCharts.x(i, count: values.count, width: size.width)
                let py = PremiumCharts.y(v, lo: r.lo, hi: r.hi, height: h)
                pts.append(CGPoint(x: px, y: py))
            }
            var line = Path()
            line.addLines(pts)
            var area = line
            area.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h))
            area.addLine(to: CGPoint(x: pts[0].x, y: h))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.28), tint.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(line, with: .color(tint), lineWidth: 2)

            if let c = cursor, c >= 0, c < pts.count {
                let p = pts[c]
                var vline = Path()
                vline.move(to: CGPoint(x: p.x, y: 0))
                vline.addLine(to: CGPoint(x: p.x, y: h))
                ctx.stroke(vline, with: .color(StrandPalette.textSecondary.opacity(0.5)), lineWidth: 1)
                let dot = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: dot), with: .color(tint))
                ctx.stroke(Path(ellipseIn: dot), with: .color(StrandPalette.surfaceBase), lineWidth: 2)
            }
        }
    }
}

// MARK: - Dual-metric comparison

/// Two metrics normalised to a shared 0–1 axis and overlaid, so their shared (or opposing)
/// movement is visible even though their units are unrelated. The normalisation is stated in the
/// caption by the caller — the shape is the message here, not the absolute values.
struct DualMetricChart: View {
    let primary: [Double]
    let secondary: [Double]
    var primaryTint: Color
    var secondaryTint: Color
    var height: CGFloat = 150

    var body: some View {
        Canvas { ctx, size in
            guard primary.count >= 2, secondary.count >= 2 else { return }
            drawSeries(ctx: ctx, size: size, values: primary, tint: primaryTint, filled: true)
            drawSeries(ctx: ctx, size: size, values: secondary, tint: secondaryTint, filled: false)
        }
        .frame(height: height)
    }

    private func drawSeries(ctx: GraphicsContext, size: CGSize, values: [Double],
                            tint: Color, filled: Bool) {
        let r = PremiumCharts.range(values: values)
        let h = size.height
        var pts: [CGPoint] = []
        pts.reserveCapacity(values.count)
        for (i, v) in values.enumerated() {
            let px = PremiumCharts.x(i, count: values.count, width: size.width)
            let py = PremiumCharts.y(v, lo: r.lo, hi: r.hi, height: h)
            pts.append(CGPoint(x: px, y: py))
        }
        var line = Path()
        line.addLines(pts)
        if filled {
            var area = line
            area.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h))
            area.addLine(to: CGPoint(x: pts[0].x, y: h))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.20), tint.opacity(0.01)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(line, with: .color(tint), lineWidth: 2)
        } else {
            ctx.stroke(line, with: .color(tint),
                       style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        }
    }
}

// MARK: - Correlation scatter

/// Paired samples plotted in a unit square with a least-squares fit line. Used wherever the app
/// claims two signals relate — showing the actual cloud keeps the claim honest, because a weak
/// relationship visibly looks weak.
struct CorrelationScatter: View {
    /// Already-normalised points in [0,1]² (y already inverted for screen space by the caller's
    /// normalisation, or left natural — this view plots y upward).
    let points: [CGPoint]
    var tint: Color
    var height: CGFloat = 160
    /// Slope/intercept in normalised space, when the caller computed a fit.
    var fit: (slope: Double, intercept: Double)?

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // Faint grid so position is readable without axis labels.
            var grid = Path()
            for i in 1..<4 {
                let gy = h * CGFloat(i) / 4
                grid.move(to: CGPoint(x: 0, y: gy))
                grid.addLine(to: CGPoint(x: w, y: gy))
            }
            ctx.stroke(grid, with: .color(StrandPalette.hairline), lineWidth: 0.5)

            if let f = fit {
                let y0 = f.intercept
                let y1 = f.slope + f.intercept
                var line = Path()
                line.move(to: CGPoint(x: 0, y: h * CGFloat(1 - min(max(y0, 0), 1))))
                line.addLine(to: CGPoint(x: w, y: h * CGFloat(1 - min(max(y1, 0), 1))))
                ctx.stroke(line, with: .color(tint.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }

            for p in points {
                let cx = w * min(max(p.x, 0), 1)
                let cy = h * (1 - min(max(p.y, 0), 1))
                let dot = CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: dot), with: .color(tint.opacity(0.65)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Stage-highlight timeline

/// A stacked stage ribbon (sleep stages, HR zones) where ONE category can be isolated: the
/// selected category keeps full colour and every other dims. The interaction that ties the sleep
/// stage list to the overnight chart.
struct StageRibbon: View {
    struct Block: Identifiable {
        let id: Int
        /// Position within the timeline, both in [0,1].
        let start: Double
        let end: Double
        let category: String
        let tint: Color
    }

    let blocks: [Block]
    /// When non-nil, only blocks of this category render at full strength.
    var selected: String?
    var height: CGFloat = 18
    var cornerRadius: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(StrandPalette.surfaceInset)
                ForEach(blocks) { b in
                    let isDimmed: Bool = selected != nil && b.category != selected
                    let x0: CGFloat = geo.size.width * CGFloat(min(max(b.start, 0), 1))
                    let x1: CGFloat = geo.size.width * CGFloat(min(max(b.end, 0), 1))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(b.tint)
                        .opacity(isDimmed ? 0.16 : 1)
                        .frame(width: max(1.5, x1 - x0), height: height)
                        .offset(x: x0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.22), value: selected)
    }
}

// MARK: - Value + delta header

/// The standard "big number with its personal context" header used above charts across the
/// Premium screens: current value, unit, and a signed comparison against the user's own baseline
/// (omitted entirely when there isn't enough history to have one).
struct MetricValueHeader: View {
    let value: String
    let unit: String
    var deltaText: String?
    var deltaGood: Bool?
    var caption: String?
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 34, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                if !unit.isEmpty {
                    Text(unit).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer(minLength: 8)
                if let d = deltaText {
                    Text(d)
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(deltaColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(deltaColor.opacity(0.15)))
                }
            }
            if let c = caption {
                Text(c).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var deltaColor: Color {
        guard let good = deltaGood else { return StrandPalette.textTertiary }
        return good ? StrandPalette.recoveryColor(85) : StrandPalette.metricRose
    }
}

// MARK: - Finding row

/// Renders one `PremiumFinding` with its confidence badge. The single presentation for every
/// computed insight across Home, Sleep, Heart, Trends and Journal, so a pattern always carries its
/// strength label with it and can never be read as a bare fact.
struct PremiumFindingRow: View {
    let finding: PremiumFinding

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(finding.tint)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text(finding.text)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(finding.confidence.label)
                        .font(.system(size: 9, weight: .bold)).tracking(0.5)
                        .foregroundStyle(finding.confidence.tint)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(finding.confidence.tint.opacity(0.16)))
                    if let d = finding.detail {
                        Text(d).font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Provenance chip

/// The small "Measured / Estimated / Calculated" tag. Applied beside values whose origin matters,
/// so an on-device estimate is never mistaken for a clinical reading.
struct ProvenanceChip: View {
    let provenance: PremiumProvenance
    var body: some View {
        Text(provenance.label.uppercased())
            .font(.system(size: 9, weight: .bold)).tracking(0.5)
            .foregroundStyle(provenance.tint)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(provenance.tint.opacity(0.14)))
            .accessibilityLabel("\(provenance.label): \(provenance.explanation)")
    }
}

// MARK: - Unavailable state

/// The honest empty state for a metric this device or strap never recorded. Shown instead of an
/// empty chart, which reads as a bug rather than as "no data".
struct MetricUnavailable: View {
    let name: String
    var reason: String = "No readings recorded yet."
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "minus.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name) unavailable")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                Text(reason).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}
#endif
