import SwiftUI
import StrandDesign
import StrandAnalytics

// StreaksSection.swift — NOOP's meaningful health streaks on Today.
//
// Streaks reward real behaviours (a steady sleep schedule, enough rest, starting the day recovered),
// each judged against the user's OWN baseline by the pure HealthStreaks + StreakEngine. This file owns
// presentation only: a calm, premium row of streak cards — a current count, a seven-day pattern strip
// (so you see the rhythm, not just a number), the personal target, and an honest "at risk today" nudge
// when a live run hasn't been extended yet. Motivating, not gamey: no confetti, no points, just the
// pattern of a habit forming.
//
// Design-system only. iPhone-first (compiles for the shared macOS app too).

/// A fully-resolved streak ready to render.
struct StreakSummary: Identifiable, Equatable {
    let id: HealthStreaks.Kind
    let title: LocalizedStringKey
    let symbol: String
    let accent: Color
    /// "night streak" / "day streak" — the counted unit.
    let unit: LocalizedStringKey
    let result: StreakEngine.Result
    /// Met/miss for the last (up to) seven days, oldest → newest.
    let recentFlags: [Bool]
    /// The adaptive personal target, in words ("≈ your usual 7h 30m").
    let targetText: String
}

/// The streak row: a header and a horizontally-scrolling set of streak cards.
struct StreaksSection: View {
    let summaries: [StreakSummary]

    var body: some View {
        if !summaries.isEmpty {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                SectionHeader("Your streaks", overline: "Healthy habits, kept up")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NoopMetrics.gap) {
                        ForEach(summaries) { StreakCard(summary: $0) }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }
}

private struct StreakCard: View {
    let summary: StreakSummary

    /// The number to feature: the live run, or the at-risk run you'd save by acting today.
    private var featured: Int {
        summary.result.current > 0 ? summary.result.current : summary.result.atRisk
    }
    private var isAtRisk: Bool { summary.result.current == 0 && summary.result.atRisk > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: summary.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(summary.accent)
                Text(summary.title)
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(featured)")
                    .font(StrandFont.title1.weight(.bold))
                    .foregroundStyle(isAtRisk ? StrandPalette.textTertiary : summary.accent)
                    .monospacedDigit()
                Text(summary.unit)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }

            dotStrip

            Group {
                if isAtRisk {
                    Text("Keep it going today")
                        .foregroundStyle(summary.accent)
                } else if summary.result.best > summary.result.current {
                    Text("Best \(summary.result.best) · \(summary.targetText)")
                        .foregroundStyle(StrandPalette.textTertiary)
                } else {
                    Text(verbatim: summary.targetText)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .font(StrandFont.footnote)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NoopMetrics.space4)
        .frame(width: 168, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(StrandPalette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(summary.accent.opacity(isAtRisk ? 0.22 : 0.30), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(summary.title))
        .accessibilityValue(Text(isAtRisk
            ? "At risk. \(summary.result.atRisk) in a row, not yet today."
            : "\(featured). Best \(summary.result.best)."))
    }

    /// Seven cells: filled in the accent for a met day, faint for a miss.
    private var dotStrip: some View {
        HStack(spacing: 4) {
            ForEach(Array(paddedFlags.enumerated()), id: \.offset) { _, met in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(met ? summary.accent : StrandPalette.hairline)
                    .frame(height: 7)
            }
        }
    }

    /// Left-pad to seven cells so short histories still read as a strip.
    private var paddedFlags: [Bool] {
        let f = summary.recentFlags.suffix(7)
        return Array(repeating: false, count: Swift.max(0, 7 - f.count)) + Array(f)
    }
}

#if DEBUG
#Preview("Streaks") {
    let mk: (HealthStreaks.Kind, LocalizedStringKey, String, Color, LocalizedStringKey, Int, Int, Int, [Bool], String) -> StreakSummary = {
        StreakSummary(id: $0, title: $1, symbol: $2, accent: $3, unit: $4,
                      result: StreakEngine.Result(current: $5, best: $6, metCount: $7, total: 7, atRisk: $8),
                      recentFlags: $9, targetText: $10)
    }
    let s = [
        mk(.steadySchedule, "Steady schedule", "clock.arrow.circlepath", StrandPalette.metricPurple, "night streak",
           5, 9, 6, 0, [true, false, true, true, true, true, true], "Within ±60 min of your usual"),
        mk(.restedNights, "Rested nights", "bed.double.fill", StrandPalette.restColor, "night streak",
           0, 6, 4, 3, [true, true, false, true, true, true, false], "≈ your usual 7h 30m"),
        mk(.recoveryReady, "Recovery-ready", "bolt.heart.fill", StrandPalette.chargeColor, "day streak",
           12, 12, 12, 0, [true, true, true, true, true, true, true], "Charge 52 or higher"),
    ]
    return ScrollView { StreaksSection(summaries: s).padding() }
        .background(StrandPalette.surfaceBase)
}
#endif
