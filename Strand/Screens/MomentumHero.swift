import SwiftUI
import StrandDesign
import StrandAnalytics

// MomentumHero.swift — NOOP's signature "streak flame", reimagined.
//
// Instead of a generic orange fire, the ember burns in the COLOUR of the habit you're building (steady
// schedule → violet, rested nights → blue, recovery-ready → green), and its brightness/height grows
// with the run. It answers "what am I building right now" with one proud number and a milestone to
// climb. Pure Momentum engine decides the numbers + intensity; this view is presentation only.
//
// Design-system tokens for text/surfaces; the ember gradient is derived from the habit's accent so it
// always belongs to NOOP's palette. iPhone-first (compiles for shared macOS too).

/// An original, tasteful flame silhouette (not a copied fire glyph). Points upward in its rect.
struct FlameShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.10, y: r.minY + h * 0.44),
                   control1: CGPoint(x: r.minX + w * 0.30, y: r.maxY),
                   control2: CGPoint(x: r.minX + w * 0.02, y: r.minY + h * 0.74))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.minX + w * 0.18, y: r.minY + h * 0.14),
                   control2: CGPoint(x: r.midX - w * 0.12, y: r.minY + h * 0.04))
        p.addCurve(to: CGPoint(x: r.maxX - w * 0.10, y: r.minY + h * 0.44),
                   control1: CGPoint(x: r.midX + w * 0.26, y: r.minY + h * 0.04),
                   control2: CGPoint(x: r.maxX - w * 0.02, y: r.minY + h * 0.16))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.maxX - w * 0.02, y: r.minY + h * 0.76),
                   control2: CGPoint(x: r.maxX - w * 0.30, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct MomentumHero: View {
    let summary: Momentum.Summary
    let accent: Color
    /// The featured habit's name ("Recovery-ready", …); nil when nothing is active.
    let title: LocalizedStringKey?
    /// A short, proud line.
    let message: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { summary.hasActiveStreak }
    private var featured: Int { active ? summary.current : summary.best }

    var body: some View {
        HStack(spacing: NoopMetrics.space4) {
            ember
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(featured)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(active ? accent : StrandPalette.textTertiary)
                        .monospacedDigit()
                    Text(active ? "day streak" : "best so far")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                    if summary.isRecord && active {
                        Text("Personal best")
                            .font(StrandFont.caption.weight(.bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(accent.opacity(0.16)))
                            .padding(.leading, 2)
                    }
                }
                if let title {
                    Text(title)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                Text(verbatim: message)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                milestone
            }
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.cardPadding)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .fill(StrandPalette.surfaceRaised)
                RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .fill(RadialGradient(colors: [accent.opacity(0.16 * summary.intensity + 0.04), .clear],
                                         center: .leading, startRadius: 4, endRadius: 240))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(accent.opacity(0.10 + 0.22 * summary.intensity), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Ember

    private var ember: some View {
        let base: CGFloat = 44
        let height = base + CGFloat(summary.intensity) * 46      // 44…90
        let width = height * 0.62
        return ZStack {
            // Glow.
            FlameShape()
                .fill(accent)
                .frame(width: width * 1.5, height: height * 1.35)
                .blur(radius: 16)
                .opacity(active ? (0.25 + 0.4 * summary.intensity) : 0.10)
            // Body.
            FlameShape()
                .fill(LinearGradient(colors: [accent, accent.opacity(0.6)],
                                     startPoint: .bottom, endPoint: .top))
                .frame(width: width, height: height)
                .opacity(active ? 1 : 0.35)
            // Bright core.
            FlameShape()
                .fill(LinearGradient(colors: [.white.opacity(0.9), accent.opacity(0.2)],
                                     startPoint: .bottom, endPoint: .top))
                .frame(width: width * 0.5, height: height * 0.52)
                .offset(y: height * 0.14)
                .opacity(active ? (0.5 + 0.4 * summary.intensity) : 0.12)
        }
        .frame(width: 76, height: 96)
        .accessibilityHidden(true)
    }

    // MARK: Milestone progress

    @ViewBuilder private var milestone: some View {
        if let next = summary.nextMilestone, active {
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    let span = Double(next - summary.prevMilestone)
                    let done = Double(summary.current - summary.prevMilestone)
                    let frac = span > 0 ? min(1, max(0, done / span)) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(StrandPalette.surfaceInset).frame(height: 5)
                        Capsule().fill(accent).frame(width: geo.size.width * CGFloat(frac), height: 5)
                    }
                }
                .frame(height: 5)
                Text(daysToNextText(next))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.top, 2)
        } else if active {
            Text("Top of the ladder — extraordinary.")
                .font(StrandFont.caption)
                .foregroundStyle(accent)
                .padding(.top, 2)
        }
    }

    private func daysToNextText(_ next: Int) -> String {
        let n = summary.daysToNext ?? 0
        return String(format: String(localized: "%ld to your next milestone (%ld)"), n, next)
    }
}

#if DEBUG
#Preview("Momentum") {
    let s = Momentum.summarize([
        Momentum.Streak(kind: .recoveryReady, current: 12, best: 12),
        Momentum.Streak(kind: .steadySchedule, current: 5, best: 9),
    ])
    return ScrollView {
        VStack(spacing: 16) {
            MomentumHero(summary: s, accent: StrandPalette.chargeColor,
                         title: "Recovery-ready", message: "Twelve days starting recovered — your best run yet.")
            MomentumHero(summary: Momentum.summarize([]), accent: StrandPalette.restColor,
                         title: nil, message: "A rested night or a steady bedtime starts a new streak.")
        }
        .padding()
    }
    .background(StrandPalette.surfaceBase)
}
#endif
