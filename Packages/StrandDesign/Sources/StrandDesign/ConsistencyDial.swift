import SwiftUI

// ConsistencyDial.swift — a 24-hour polar dial visualising sleep-TIMING consistency.
//
// The subject is circular: a clock time lives on a ring, so midnight sits at the top and the day
// runs clockwise. Each night's MID-SLEEP is a point on the ring; a glowing arc spans the typical
// mid-sleep ± its spread (both computed by the SleepRegularity engine and PASSED IN — the dial does
// no statistics of its own, so the arc can never disagree with the number beside it). A tight,
// bright arc reads "steady" at a glance; a wide, faint one reads "scattered".
//
// Design-system-owned: all colour/'geometry' come from StrandPalette (Rest domain) — no caller
// tokens, no hard-coded hues. Reduce-Motion aware. Decorative to VoiceOver by default (the numbers
// live in the surrounding card's accessibility label); pass `accessibilityText` to give it a voice.

#if !os(watchOS)
public struct ConsistencyDial: View {

    /// Per-night mid-sleep as a minute-of-day (0…1440). Drawn as the point cloud.
    public var midpointsMinutes: [Double]
    /// Circular-mean mid-sleep (minute-of-day), from the engine. nil → withheld/empty dial.
    public var meanMinutes: Double?
    /// Circular SD of the mid-sleep (minutes), from the engine — the arc half-width. nil → empty.
    public var spreadMinutes: Double?
    /// Overall diameter.
    public var diameter: CGFloat
    /// Stroke thickness of the track and consistency arc.
    public var lineWidth: CGFloat
    /// Whether to draw the 12a/6a/12p/6p hour labels (on for the large detail dial, off when compact).
    public var showsHourLabels: Bool
    /// Optional VoiceOver description. When nil the dial is hidden from assistive tech (decorative).
    public var accessibilityText: String?

    public init(midpointsMinutes: [Double],
                meanMinutes: Double?,
                spreadMinutes: Double?,
                diameter: CGFloat = 220,
                lineWidth: CGFloat = 10,
                showsHourLabels: Bool = false,
                accessibilityText: String? = nil) {
        self.midpointsMinutes = midpointsMinutes
        self.meanMinutes = meanMinutes
        self.spreadMinutes = spreadMinutes
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.showsHourLabels = showsHourLabels
        self.accessibilityText = accessibilityText
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the draw-in: points fade/scale up, the arc sweeps out from the mean to full width.
    @State private var appear: Double = 0

    private var isReadable: Bool { meanMinutes != nil && spreadMinutes != nil }

    /// Arc half-width in minutes, clamped so a very irregular week stays an open arc (never a full
    /// ring that would read as a solid band).
    private var halfSpanMinutes: Double { min(max(spreadMinutes ?? 0, 0), 690) }

    public var body: some View {
        Canvas { ctx, size in draw(&ctx, size) }
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(accessibilityText == nil)
            .accessibilityLabel(Text(accessibilityText ?? ""))
            .onAppear {
                if reduceMotion { appear = 1 }
                else { withAnimation(.easeOut(duration: 0.55)) { appear = 1 } }
            }
    }

    // MARK: - Drawing

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - lineWidth
        let dimmed = !isReadable

        // Track ring.
        let trackRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.stroke(Path(ellipseIn: trackRect),
                   with: .color(StrandPalette.surfaceInset.opacity(dimmed ? 0.6 : 1)),
                   lineWidth: lineWidth)

        // Hour ticks every 3 h.
        for h in stride(from: 0, to: 24, by: 3) {
            let m = Double(h) * 60
            var tick = Path()
            tick.move(to: point(m, radius - 6, center))
            tick.addLine(to: point(m, radius + 6, center))
            ctx.stroke(tick, with: .color(StrandPalette.hairline), lineWidth: 1.5)
        }

        if showsHourLabels {
            drawHourLabels(&ctx, center: center, radius: radius)
        }

        guard isReadable, let mean = meanMinutes else { return }

        // Consistency arc: mean ± halfSpan, swept out by `appear`.
        let half = halfSpanMinutes * appear
        let start = mean - half
        let end = mean + half
        let glow = arcPath(start: start, end: end, radius: radius, center: center)
        ctx.stroke(glow, with: .color(StrandPalette.restGlow.opacity(0.18)),
                   style: StrokeStyle(lineWidth: lineWidth + 8, lineCap: .round))
        ctx.stroke(arcPath(start: start, end: end, radius: radius, center: center),
                   with: .color(StrandPalette.restBright),
                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        // Mean marker.
        let meanPt = point(mean, radius, center)
        let dotR: CGFloat = 4.5
        ctx.fill(Path(ellipseIn: CGRect(x: meanPt.x - dotR, y: meanPt.y - dotR, width: dotR * 2, height: dotR * 2)),
                 with: .color(StrandPalette.restBright))

        // Per-night points, nudged inward and staggered slightly so overlaps read as density.
        let pointColor = StrandPalette.sleepLight
        for (i, m) in midpointsMinutes.enumerated() {
            let r = radius - lineWidth - 6 - CGFloat(i % 3) * 5
            let p = point(m, r, center)
            let pr: CGFloat = 3.0 * (0.4 + 0.6 * appear)
            ctx.opacity = 0.85 * appear
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - pr, y: p.y - pr, width: pr * 2, height: pr * 2)),
                     with: .color(pointColor))
            ctx.opacity = 1
        }
    }

    private func drawHourLabels(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let labels: [(String, Double)] = [("12a", 0), ("6a", 360), ("12p", 720), ("6p", 1080)]
        for (text, m) in labels {
            let p = point(m, radius - 20, center)
            let resolved = ctx.resolve(Text(text)
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textTertiary))
            ctx.draw(resolved, at: p, anchor: .center)
        }
    }

    /// Point on the dial for a minute-of-day at a given radius. Midnight at top, clockwise.
    private func point(_ minute: Double, _ radius: CGFloat, _ center: CGPoint) -> CGPoint {
        let theta = (minute / 1440.0) * 2 * .pi - .pi / 2
        return CGPoint(x: center.x + radius * cos(theta), y: center.y + radius * sin(theta))
    }

    private func arcPath(start: Double, end: Double, radius: CGFloat, center: CGPoint) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .radians((start / 1440.0) * 2 * .pi - .pi / 2),
                    endAngle: .radians((end / 1440.0) * 2 * .pi - .pi / 2),
                    clockwise: false)
        return path
    }
}
#endif

#if DEBUG && !os(watchOS)
#Preview("ConsistencyDial — steady vs scattered") {
    HStack(spacing: 28) {
        ConsistencyDial(
            midpointsMinutes: [186, 174, 192, 180, 168, 198, 180, 176, 190, 182],
            meanMinutes: 182, spreadMinutes: 12, diameter: 200, showsHourLabels: true)
        ConsistencyDial(
            midpointsMinutes: [40, 300, 620, 120, 500, 200, 700, 60, 420, 260],
            meanMinutes: 300, spreadMinutes: 150, diameter: 200, showsHourLabels: true)
    }
    .padding(40)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}

#Preview("ConsistencyDial — withheld") {
    ConsistencyDial(midpointsMinutes: [], meanMinutes: nil, spreadMinutes: nil,
                    diameter: 200, showsHourLabels: true)
        .padding(40)
        .background(StrandPalette.surfaceBase)
        .preferredColorScheme(.light)
}
#endif
