import SwiftUI
import StrandDesign
import StrandAnalytics

// FocusHero.swift — the Adaptive Home's morphing hero.
//
// The pure HomeFocusResolver decides WHICH domain leads today; this view renders that domain as the
// hero, reusing the established StrandDesign visuals (RecoveryRing / StageCompositionBar / StrainGauge /
// Sparkline) and adding the two things a bare score never gives you: WHY it is what it is, and WHAT TO
// DO about it. On a calm day the focus is Trends/optimization, so the hero turns forward-looking.
//
// Design-system only. The app builds the FocusHeroModel from the same domain outputs the feed uses.
// iPhone-first (compiles for the shared macOS app too).

/// One driver row inside the recovery focus hero (the biggest movers behind today's Charge).
struct FocusDriver: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let value: String
    /// true when the term supported recovery (green), false when it suppressed it (amber).
    let positive: Bool
}

/// The sleep visual payload.
struct FocusSleep: Equatable {
    let deep: Double, light: Double, rem: Double, awake: Double
    let duration: String
    let efficiency: String
}

/// Everything the hero needs, resolved by the app. Only the payload for `domain` is populated.
struct FocusHeroModel {
    let domain: HomeFocus.Domain
    let mode: HomeFocus.Mode
    let accent: Color
    let title: LocalizedStringKey
    let explanation: String
    let action: String
    let actionIcon: String
    var recoveryScore: Double? = nil
    var recoveryDrivers: [FocusDriver] = []
    var sleep: FocusSleep? = nil
    var strain: Double? = nil
    var trendValues: [Double]? = nil
}

/// The morphing hero card.
struct FocusHero: View {
    let model: FocusHeroModel

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            header
            visual
            whatToDo
        }
        .padding(NoopMetrics.cardPadding)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .fill(StrandPalette.surfaceRaised)
                RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .fill(
                        RadialGradient(colors: [model.accent.opacity(0.16), .clear],
                                       center: .topTrailing, startRadius: 8, endRadius: 260)
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(model.accent.opacity(0.28), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Header (eyebrow + title + why)

    private var header: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(spacing: 6) {
                Image(systemName: model.mode == .optimization ? "arrow.up.forward.circle.fill" : "target")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(model.accent)
                Text(model.mode == .optimization ? "Today's opportunity" : "Today's focus")
                    .font(StrandFont.caption.weight(.bold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            Text(model.title)
                .font(StrandFont.title2.weight(.bold))
                .foregroundStyle(model.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.explanation)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Domain visual

    @ViewBuilder private var visual: some View {
        switch model.domain {
        case .recovery: recoveryVisual
        case .sleep:    sleepVisual
        case .strain:   strainVisual
        case .trends:   trendsVisual
        }
    }

    @ViewBuilder private var recoveryVisual: some View {
        HStack(alignment: .center, spacing: NoopMetrics.space4) {
            if let score = model.recoveryScore {
                RecoveryRing(score: score, diameter: 92, lineWidth: 9,
                             showsLabel: true, showsWordmark: false, showsHover: false,
                             valueFormat: { "\(Int($0.rounded()))" })
                    .frame(width: 92, height: 92)
            }
            if !model.recoveryDrivers.isEmpty {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    ForEach(model.recoveryDrivers.prefix(3)) { d in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(d.positive ? StrandPalette.statusPositive : StrandPalette.statusWarning)
                                .frame(width: 6, height: 6)
                            Text(d.label)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                            Spacer(minLength: 6)
                            Text(d.value)
                                .font(StrandFont.captionNumber.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var sleepVisual: some View {
        if let s = model.sleep {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(s.duration)
                        .font(StrandFont.title1.weight(.bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(s.efficiency)
                        .font(StrandFont.footnote.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                    Spacer(minLength: 0)
                }
                StageCompositionBar(deepMin: s.deep, lightMin: s.light, remMin: s.rem, awakeMin: s.awake)
            }
        }
    }

    @ViewBuilder private var strainVisual: some View {
        if let strain = model.strain {
            HStack {
                Spacer(minLength: 0)
                StrainGauge(strain: strain, diameter: 120, lineWidth: 11,
                            showsLabel: true, showsHover: false,
                            valueFormat: { String(format: "%.1f", $0) })
                    .frame(width: 120, height: 120)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var trendsVisual: some View {
        if let vals = model.trendValues, vals.count >= 3 {
            Sparkline(values: vals, gradient: Gradient(colors: [model.accent.opacity(0.28), .clear]),
                      lineWidth: 2.4, showsArea: true, showsHead: true, showsHover: false)
                .frame(height: 72)
        }
    }

    // MARK: What to do

    private var whatToDo: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.actionIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.mode == .optimization ? "Make the most of it" : "What to do")
                    .font(StrandFont.caption.weight(.bold))
                    .foregroundStyle(model.accent)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(model.action)
                    .font(StrandFont.subhead.weight(.medium))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(NoopMetrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(StrandPalette.surfaceInset)
        )
    }
}

#if DEBUG
#Preview("Focus hero — recovery") {
    let m = FocusHeroModel(
        domain: .recovery, mode: .attention, accent: StrandPalette.recoveryColor(38),
        title: "Take it easy today", explanation: "Charge 38 — well below your baseline. Two signals moved together, which usually means your body is still repairing.",
        action: "Keep it light: gentle movement, hydration, and an early night.",
        actionIcon: "leaf.fill",
        recoveryScore: 38,
        recoveryDrivers: [
            FocusDriver(label: "HRV", value: "44 ms", positive: false),
            FocusDriver(label: "Resting HR", value: "60 bpm", positive: false),
            FocusDriver(label: "Sleep quality", value: "83%", positive: false),
        ])
    return ScrollView { FocusHero(model: m).padding() }
        .background(StrandPalette.surfaceBase)
}

#Preview("Focus hero — trends") {
    let m = FocusHeroModel(
        domain: .trends, mode: .optimization, accent: StrandPalette.chargeColor,
        title: "Looking good — a chance to build", explanation: "Your recovery has trended up 8% over two weeks, and you're on a 12-day sleep-consistency streak.",
        action: "A steady stretch like this is a great time to build on your habits.",
        actionIcon: "chart.line.uptrend.xyaxis",
        trendValues: [62, 58, 64, 60, 66, 63, 70, 68, 74, 72, 78, 76, 82, 86])
    return ScrollView { FocusHero(model: m).padding() }
        .background(StrandPalette.surfaceBase)
}
#endif
