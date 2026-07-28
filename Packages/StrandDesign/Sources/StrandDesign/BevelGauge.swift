import SwiftUI

// MARK: - BevelGauge — the shared gauge primitive, "Clinical Premium"
//
// The shared instrument behind StrainGauge (RecoveryRing stopped delegating here so it could
// lead the redesign standalone — see RecoveryRing.swift): a 240° open gauge with
//   • a nearly-invisible full-span track ring carved from `surfaceInset`
//   • a THIN flat-colour progress arc (no AngularGradient, no frosted disc, no end-cap bead)
//   • at most a very faint (2–3% opacity) glow behind the arc on dark backgrounds — never a bloom
//   • a centred New York serif bold number with an optional "of N" caption + state word
//
// It owns no domain logic — callers pass the fraction, the ramp stops (used only to sample the
// flat tip colour — never stroked as a gradient), the tip colour, and the centre read-out
// strings. StrainGauge keeps its own public init signature and delegates its visuals here, so a
// screen re-skins without any call-site change.

public struct BevelGauge: View {

    /// Fill fraction 0...1 of the 240° span.
    public var fraction: Double
    /// Angular gradient stops for the progress arc (the domain ramp).
    public var stops: [Gradient.Stop]
    /// Colour of the glowing end-cap + state word (usually the ramp sampled at `fraction`).
    public var tipColor: Color
    /// Big centred number, already formatted (e.g. "87" or "12.4").
    public var numberText: String
    /// Small caption under the number (e.g. "of 100" / "of 21"). nil hides it.
    public var captionText: String?
    /// State word above/below the number (e.g. "PRIMED"). nil hides it.
    public var stateText: String?
    /// Optional supporting line under the read-out.
    public var supporting: String?
    public var diameter: CGFloat
    public var lineWidth: CGFloat
    public var showsLabel: Bool
    /// Animated draw-in fraction supplied by the caller (so it owns the @State + animation).
    public var animatedFraction: Double
    /// Whether the bloom is at full (vs resting) intensity — caller drives the breathe pulse.
    public var bloomActive: Bool

    public init(
        fraction: Double,
        stops: [Gradient.Stop],
        tipColor: Color,
        numberText: String,
        captionText: String? = nil,
        stateText: String? = nil,
        supporting: String? = nil,
        diameter: CGFloat = 200,
        lineWidth: CGFloat = 5,
        showsLabel: Bool = true,
        animatedFraction: Double,
        bloomActive: Bool = true
    ) {
        self.fraction = fraction
        self.stops = stops
        self.tipColor = tipColor
        self.numberText = numberText
        self.captionText = captionText
        self.stateText = stateText
        self.supporting = supporting
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.showsLabel = showsLabel
        self.animatedFraction = animatedFraction
        self.bloomActive = bloomActive
    }

    private let arcSpanDegrees: Double = 240
    private var startAngle: Angle { .degrees(150) }

    @Environment(\.colorScheme) private var scheme

    public var body: some View {
        ZStack {
            // Nearly-invisible full-span track — the "well" the score arc sits in. Doesn't depend on
            // `animatedFraction`, so SwiftUI/CoreAnimation caches it as an unchanged layer.
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
        }
        .frame(width: diameter, height: diameter)
    }

    private var track: some View {
        arcShape(to: 1.0)
            .stroke(StrandPalette.surfaceInset, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    private var centerLabel: some View {
        VStack(spacing: 2) {
            Text(numberText)
                .font(StrandFont.rounded(diameter * 0.30, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
                .contentTransition(.numericText())
            if let captionText {
                Text(captionText)
                    .font(StrandFont.rounded(diameter * 0.085, weight: .medium))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            if let stateText {
                // Scale the state word WITH the gauge, like the number (0.30·d) and caption (0.085·d).
                // `min(11, …)` pins it to the original 11pt overline on the large solo-hero rings (≥130pt)
                // — byte-identical there — and shrinks it on the small three-up rings, where a fixed 11pt
                // word overflowed the arc and collided with the number/caption. Uses a *scaled overline*
                // (not rounded()) so Dynamic-Type text-scaling is preserved. Thanks @claypilat (#403).
                let stateSize = min(11, diameter * 0.085)
                Text(stateText)
                    .font(StrandFont.overlineScaled(stateSize))
                    .tracking(StrandFont.overlineTracking * stateSize / 11)
                    .foregroundStyle(tipColor)
                    .padding(.top, 2)
            }
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

#if DEBUG
#Preview("BevelGauge") {
    HStack(spacing: 24) {
        BevelGauge(
            fraction: 0.78, stops: StrandPalette.recoveryStops,
            tipColor: StrandPalette.recoveryColor(78), numberText: "78",
            captionText: "of 100", stateText: "PRIMED",
            diameter: 200, animatedFraction: 0.78
        )
        BevelGauge(
            fraction: 0.55, stops: StrandPalette.strainStops,
            tipColor: StrandPalette.strainColor(55), numberText: "11.6",
            captionText: "of 21", stateText: "MODERATE",
            diameter: 200, animatedFraction: 0.55
        )
    }
    .padding(40)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
