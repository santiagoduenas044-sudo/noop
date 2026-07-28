import SwiftUI

// MARK: - Recovery Ring (§9.3) — THE signature component, "Clinical Premium"
//
// watchOS NOTE: the `RecoveryRing` view (below) uses .onContinuousHover + ChartHover
// tooltips, neither of which exist on watchOS, so the VIEW is excluded there (the watch uses the
// lightweight GlowRing instead). The pure `RecoveryArc` Shape at the bottom of this file stays
// available on ALL platforms because the watch-safe GlowRing / BrandMark depend on it.
//
// A 240° open gauge arc (gap at the bottom), THIN rounded-cap stroke (4–6pt — not the thick
// hero ring of the old skin) filled with a FLAT solid colour sampled at the current score — no
// AngularGradient, no bloom, no liquid animation — over a nearly-invisible `surfaceInset` track.
// Center shows just the big New York serif number, a small tinted state word underneath, and an
// optional supporting line — no icon, no wordmark lock-up, no core dot. At most a very faint
// (2–3% opacity) glow sits behind the arc on dark backgrounds; it is never a bloom.
//
// This view intentionally does NOT delegate to `BevelGauge` (the old thick/gradient/frosted-disc
// gauge shared with `StrainGauge`): the Clinical Premium redesign starts with this component
// alone, so `StrainGauge` and the shared primitive are untouched until that's approved too.

#if !os(watchOS)
public struct RecoveryRing: View {

    /// Recovery score 0...100.
    public var score: Double
    /// Optional supporting line, e.g. "HRV 62ms · RHR 51 · ready for moderate strain".
    public var supporting: String?
    /// Diameter of the ring.
    public var diameter: CGFloat
    /// Stroke thickness — thin, 4–6pt, per the Clinical Premium spec (was a thick 14pt hero ring).
    public var lineWidth: CGFloat
    /// Whether to show the center read-out (number + state word + supporting).
    public var showsLabel: Bool
    /// Retired for Clinical Premium (the brand wordmark lock-up is gone — center shows just the
    /// number). Kept on the type for API stability; no longer renders anything.
    public var showsWordmark: Bool
    /// Whether hovering the ring shows a subtle tooltip (score + state word).
    public var showsHover: Bool
    /// Formats the score for the hover tooltip's bold line.
    public var valueFormat: (Double) -> String

    public init(
        score: Double,
        supporting: String? = nil,
        diameter: CGFloat = 240,
        lineWidth: CGFloat = 5,
        showsLabel: Bool = true,
        showsWordmark: Bool = true,
        showsHover: Bool = true,
        valueFormat: @escaping (Double) -> String = { "Recovery \(Int($0.rounded()))" }
    ) {
        self.score = score
        self.supporting = supporting
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.showsLabel = showsLabel
        self.showsWordmark = showsWordmark
        self.showsHover = showsHover
        self.valueFormat = valueFormat
    }

    /// Cursor location while hovering, in ring-local coordinates.
    @State private var hoverPoint: CGPoint? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    // Animated fill fraction so changing `score` draws the arc in — the one motion this view
    // keeps; restrained (a simple draw-in), never the old "liquid" breathing bloom.
    @State private var animatedFraction: Double = 0

    private let arcSpanDegrees: Double = 240
    private var startAngle: Angle { .degrees(150) }

    private var fraction: Double { min(max(score / 100.0, 0), 1) }
    private var tipColor: Color { StrandPalette.recoveryColor(score) }
    private var stateWord: String { StrandPalette.recoveryState(score) }

    public var body: some View {
        ZStack {
            // Nearly-invisible full-span track — the "well" the score arc sits in.
            track

            // A very faint (2–3% opacity) glow behind the arc, dark-mode only — never a bloom.
            if scheme == .dark {
                arcShape(to: animatedFraction)
                    .stroke(tipColor, style: StrokeStyle(lineWidth: lineWidth * 2.4, lineCap: .round))
                    .blur(radius: lineWidth)
                    .opacity(0.025)
                    .allowsHitTesting(false)
            }

            // The flat, solid-colour progress arc. No gradient, no end-cap bead.
            arcShape(to: animatedFraction)
                .stroke(tipColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            if showsLabel { centerLabel }

            if showsHover, let pt = hoverPoint {
                PositionedTooltip(
                    anchor: pt,
                    container: CGSize(width: diameter, height: diameter),
                    tooltip: ChartTooltip(
                        value: valueFormat(score),
                        label: stateWord,
                        accent: tipColor
                    )
                )
                .animation(StrandMotion.fade, value: hoverPoint == nil)
            }
        }
        .frame(width: diameter, height: diameter)
        // Collapse the loose center Text fragments (and the otherwise-unlabeled
        // standalone ring) into one coherent VoiceOver element.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(valueFormat(score)))
        .accessibilityValue(Text(stateWord))
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard showsHover else { return }
            switch phase {
            case .active(let location): hoverPoint = location
            case .ended: hoverPoint = nil
            }
        }
        .onAppear {
            withAnimation(StrandMotion.drawIn(reduced: reduceMotion)) { animatedFraction = fraction }
        }
        .onChangeCompat(of: score) { _ in
            withAnimation(StrandMotion.drawIn(reduced: reduceMotion)) { animatedFraction = fraction }
        }
    }

    private var track: some View {
        arcShape(to: 1.0)
            .stroke(StrandPalette.surfaceInset, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    private var numberString: String {
        String(Int(score.rounded()))
    }

    private var centerLabel: some View {
        VStack(spacing: 4) {
            Text(numberString)
                .font(StrandFont.rounded(diameter * 0.30, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .contentTransition(.numericText())
            Text(stateWord)
                .font(StrandFont.overlineScaled(min(11, diameter * 0.06)))
                .tracking(StrandFont.overlineTracking)
                .foregroundStyle(tipColor)
            if let supporting {
                Text(supporting)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: diameter * 0.78)
                    .padding(.top, 2)
            }
        }
    }

    private func arcShape(to fraction: Double) -> RecoveryArc {
        RecoveryArc(startAngle: startAngle, spanDegrees: arcSpanDegrees,
                    fraction: fraction, lineWidth: lineWidth)
    }
}
#endif

// MARK: - Arc Shape

/// An open 240° gauge arc that fills clockwise from the start angle.
public struct RecoveryArc: Shape {
    public var startAngle: Angle
    public var spanDegrees: Double
    public var fraction: Double
    public var lineWidth: CGFloat

    public var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let radius = (min(rect.width, rect.height) - lineWidth) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let end = Angle.degrees(startAngle.degrees + spanDegrees * min(max(fraction, 0), 1))
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: end,
            clockwise: false
        )
        return path
    }
}

#if DEBUG && !os(watchOS)
#Preview("RecoveryRing — scores") {
    VStack(spacing: 16) {
        HStack(spacing: 28) {
            RecoveryRing(score: 22, supporting: "HRV 38ms · RHR 58 · take it easy", diameter: 220)
            RecoveryRing(score: 55, supporting: "HRV 49ms · RHR 54 · moderate ok", diameter: 220)
        }
        Text("Hover a ring for a recovery + state-word tooltip.")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
    }
    .padding(40)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}

#Preview("RecoveryRing — primed/peak") {
    HStack(spacing: 28) {
        RecoveryRing(score: 78, supporting: "HRV 62ms · RHR 51 · ready for moderate strain", diameter: 220)
        RecoveryRing(score: 91, supporting: "HRV 74ms · RHR 47 · primed to push", diameter: 220)
    }
    .padding(40)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}

private struct RecoveryRingLive: View {
    @State private var score: Double = 64
    var body: some View {
        VStack(spacing: 24) {
            RecoveryRing(score: score, supporting: "drag to feel the draw-in", diameter: 260)
            Slider(value: $score, in: 0...100)
                .frame(width: 280)
        }
        .padding(40)
        .background(StrandPalette.surfaceBase)
        .preferredColorScheme(.dark)
    }
}

#Preview("RecoveryRing — interactive") { RecoveryRingLive() }
#endif
