import SwiftUI
import StrandDesign
import StrandAnalytics

// AchievementsView.swift — the earned-badge wall on Today.
//
// The pure Achievements engine decides what's earned + what's next; this renders a compact, premium
// medallion row (most impressive first) and one "next up" progress nudge. Celebratory but calm — no
// points, no noise, just the badges you've genuinely built. Design-system only. iPhone-first.

enum AchievementsCopy {
    static func accent(_ category: String) -> Color {
        switch category {
        case "steadySchedule": return StrandPalette.metricPurple
        case "restedNights":   return StrandPalette.restColor
        case "recoveryReady":  return StrandPalette.chargeColor
        case "peak":           return StrandPalette.metricAmber
        default:               return StrandPalette.metricCyan   // tracked
        }
    }
    static func symbol(_ category: String) -> String {
        switch category {
        case "steadySchedule": return "clock.arrow.circlepath"
        case "restedNights":   return "bed.double.fill"
        case "recoveryReady":  return "bolt.heart.fill"
        case "peak":           return "star.fill"
        default:               return "calendar"
        }
    }
    /// A short label for the "next up" line.
    static func label(_ b: Achievements.Badge) -> String {
        switch b.category {
        case "steadySchedule": return String(format: String(localized: "%ld-night steady schedule"), b.tier)
        case "restedNights":   return String(format: String(localized: "%ld rested nights"), b.tier)
        case "recoveryReady":  return String(format: String(localized: "%ld days recovery-ready"), b.tier)
        case "peak":           return String(format: String(localized: "Reach Charge %ld"), b.tier)
        default:               return String(format: String(localized: "%ld days tracked"), b.tier)
        }
    }
}

struct AchievementsView: View {
    let report: Achievements.Report

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Achievements", overline: "What you've built")
                Spacer(minLength: 8)
                Text("\(report.earnedCount) of \(report.totalCount)")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(report.earned) { medallion($0) }
                }
                .padding(.horizontal, 2)
            }

            if let next = report.nextUp.first {
                nextUpRow(next)
            }
        }
    }

    private func medallion(_ b: Achievements.Badge) -> some View {
        let accent = AchievementsCopy.accent(b.category)
        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(accent.opacity(0.16))
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(accent.opacity(0.4), lineWidth: 0.5)
                VStack(spacing: 1) {
                    Image(systemName: AchievementsCopy.symbol(b.category))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("\(b.tier)")
                        .font(StrandFont.caption.weight(.bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .monospacedDigit()
                }
            }
            .frame(width: 58, height: 58)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AchievementsCopy.label(b)))
    }

    private func nextUpRow(_ b: Achievements.Badge) -> some View {
        let accent = AchievementsCopy.accent(b.category)
        return HStack(spacing: 10) {
            Image(systemName: "lock.open")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: String(localized: "Next: %@"), AchievementsCopy.label(b)))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(StrandPalette.surfaceInset).frame(height: 4)
                        Capsule().fill(accent).frame(width: geo.size.width * CGFloat(b.progress), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 2)
    }
}

#if DEBUG
#Preview("Achievements") {
    let r = Achievements.evaluate(scheduleBest: 34, restedBest: 12, recoveryBest: 61,
                                  peakRecovery: 92, daysTracked: 120)
    return ScrollView { AchievementsView(report: r).padding() }
        .background(StrandPalette.surfaceBase)
}
#endif
