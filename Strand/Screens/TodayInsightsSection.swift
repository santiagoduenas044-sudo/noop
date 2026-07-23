import SwiftUI
import StrandDesign
import StrandAnalytics

// TodayInsightsSection.swift — the "What matters today" feed on the Today screen.
//
// The cross-domain ranking lives in the pure StrandAnalytics engines (TodayInsightsBuilder →
// DailyInsightsEngine); this file owns ONLY presentation: it turns a ranked, copy-free `DailyInsight`
// into a user-facing card (title, subtitle, SF Symbol, tint, tone dot). Every specific number in a
// subtitle is re-derived from the SAME domain output the ranker saw (the Charge drivers, the sleep
// Report, the regularity Result), so the copy can never describe a signal the ranking didn't use.
//
// Design-system only: StrandPalette / StrandFont / NoopMetrics tokens, no hardcoded colours or fonts.
// iPhone-first surface (also compiles for the shared macOS app; no Kotlin twin).

/// A fully-resolved insight ready to render. `id` is the engine's stable `kind` (also the de-dup key).
struct TodayInsightCard: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: String
    /// Icon tint (a domain hue). The tone *dot* is coloured separately, so colour is never the only
    /// signal — every card carries a symbol + a word too.
    let tint: Color
    let tone: DailyInsight.Tone

    /// Build the card for a ranked insight, pulling specifics from the domain outputs the ranker used.
    static func make(for insight: DailyInsight,
                     drivers: [ChargeDriver],
                     stageReport: SleepStageInsights.Report?,
                     timing: SleepRegularityResult?) -> TodayInsightCard {
        switch insight.domain {
        case .recovery:    return recoveryCard(insight, drivers: drivers)
        case .sleepStages: return stageCard(insight, report: stageReport)
        case .sleepTiming: return timingCard(insight, timing: timing)
        default:           return fallback(insight)
        }
    }

    // MARK: Recovery

    private static func recoveryCard(_ insight: DailyInsight, drivers: [ChargeDriver]) -> TodayInsightCard {
        let title: LocalizedStringKey
        let symbol: String
        switch insight.kind {
        case "recovery.primed":
            title = "You're primed today";           symbol = "bolt.heart.fill"
        case "recovery.strained":
            title = "Recovery is running low";       symbol = "bolt.heart"
        case "recovery.rundown":
            title = "Your body is still recovering"; symbol = "bolt.heart"
        default:
            title = "A balanced day";                symbol = "bolt.heart"
        }
        return TodayInsightCard(id: insight.kind, symbol: symbol, title: title,
                                subtitle: recoverySubtitle(drivers),
                                tint: toneTint(insight.tone), tone: insight.tone)
    }

    /// Cite the single biggest driver of today's Charge in plain English (the driver already carries
    /// its own value + verdict), so the "why" is honest and specific, never invented here.
    private static func recoverySubtitle(_ drivers: [ChargeDriver]) -> String {
        guard let d = drivers.first else {
            return String(localized: "From your HRV, resting heart rate and sleep quality.")
        }
        let value = d.valueText.isEmpty ? d.label : "\(d.label) \(d.valueText)"
        return "\(value) — \(d.verdict)"
    }

    // MARK: Sleep stages

    private static func stageCard(_ insight: DailyInsight,
                                  report: SleepStageInsights.Report?) -> TodayInsightCard {
        let delta = report?.insights.first { "sleepStages.\($0.kind.rawValue)" == insight.kind }?.deltaMin
        let mins = abs(delta ?? 0)
        let title: LocalizedStringKey
        let subtitle: String
        var symbol = "bed.double.fill"
        var tint = StrandPalette.restColor

        switch insight.kind {
        case "sleepStages.efficientNight":
            title = "Efficient sleep"
            subtitle = String(localized: "You spent very little time awake in bed.")
        case "sleepStages.fragmented":
            title = "A restless night"
            subtitle = String(localized: "More time awake than usual — sleep was broken up.")
            symbol = "wave.3.right"
        case "sleepStages.restorativeStrong":
            title = "Deeply restorative"
            subtitle = String(localized: "A strong share of deep and REM sleep.")
            symbol = "moon.stars.fill"; tint = StrandPalette.sleepDeep
        case "sleepStages.restorativeLight":
            title = "Light on restorative sleep"
            subtitle = String(localized: "Less deep and REM than your body usually gets.")
            tint = StrandPalette.sleepDeep
        case "sleepStages.deepAboveUsual":
            title = "Strong deep sleep"
            subtitle = String(format: String(localized: "+%ld min above your usual — physically restorative."), mins)
            symbol = "moon.fill"; tint = StrandPalette.sleepDeep
        case "sleepStages.deepBelowUsual":
            title = "Less deep sleep than usual"
            subtitle = String(format: String(localized: "%ld min below your usual deep sleep."), mins)
            symbol = "moon"; tint = StrandPalette.sleepDeep
        case "sleepStages.remAboveUsual":
            title = "More REM than usual"
            subtitle = String(format: String(localized: "+%ld min above your usual — supports mood and memory."), mins)
            symbol = "brain.head.profile"; tint = StrandPalette.sleepREM
        case "sleepStages.remBelowUsual":
            title = "Less REM than usual"
            subtitle = String(format: String(localized: "%ld min below your usual REM sleep."), mins)
            symbol = "brain.head.profile"; tint = StrandPalette.sleepREM
        case "sleepStages.balancedNight":
            title = "A steady night"
            subtitle = String(localized: "Nothing stood out — a healthy-looking night.")
        default: // buildingBaseline
            title = "Building your sleep baseline"
            subtitle = String(localized: "A few more nights and NOOP can compare tonight to your usual.")
            symbol = "hourglass"; tint = StrandPalette.textTertiary
        }
        return TodayInsightCard(id: insight.kind, symbol: symbol, title: title,
                                subtitle: subtitle, tint: tint, tone: insight.tone)
    }

    // MARK: Sleep timing

    private static func timingCard(_ insight: DailyInsight,
                                   timing: SleepRegularityResult?) -> TodayInsightCard {
        let sd = timing?.midpointSDMinutes.map { Int($0.rounded()) }
        let title: LocalizedStringKey
        let subtitle: String
        switch insight.kind {
        case "sleepTiming.veryRegular":
            title = "Very consistent sleep timing"
            subtitle = sd.map { String(format: String(localized: "Mid-sleep within ±%ld min — great for your body clock."), $0) }
                ?? String(localized: "Your bed and wake times barely move — great for your body clock.")
        case "sleepTiming.regular":
            title = "Consistent sleep timing"
            subtitle = sd.map { String(format: String(localized: "Mid-sleep within ±%ld min most nights."), $0) }
                ?? String(localized: "Your timing stays fairly steady.")
        case "sleepTiming.variable":
            title = "Sleep timing is drifting"
            subtitle = String(localized: "Your bed and wake times vary night to night.")
        default: // irregular
            title = "Irregular sleep timing"
            subtitle = String(localized: "Steadying your schedule could lift recovery over time.")
        }
        return TodayInsightCard(id: insight.kind, symbol: "clock.arrow.circlepath", title: title,
                                subtitle: subtitle, tint: StrandPalette.metricPurple, tone: insight.tone)
    }

    // MARK: Shared

    private static func fallback(_ insight: DailyInsight) -> TodayInsightCard {
        TodayInsightCard(id: insight.kind, symbol: "sparkles", title: "Something to note",
                         subtitle: "", tint: toneTint(insight.tone), tone: insight.tone)
    }

    static func toneTint(_ tone: DailyInsight.Tone) -> Color {
        switch tone {
        case .positive: return StrandPalette.statusPositive
        case .caution:  return StrandPalette.statusWarning
        case .neutral:  return StrandPalette.restColor
        }
    }

    static func toneColor(_ tone: DailyInsight.Tone) -> Color {
        switch tone {
        case .positive: return StrandPalette.statusPositive
        case .caution:  return StrandPalette.statusWarning
        case .neutral:  return StrandPalette.textTertiary
        }
    }
}

/// The dumb feed: a section header + a day-tone chip + one row per ranked card.
struct TodayInsightsFeed: View {
    let cards: [TodayInsightCard]
    let dayTone: DailyInsight.Tone
    let attentionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(alignment: .firstTextBaseline) {
                Text("What matters today").strandOverline()
                Spacer(minLength: 8)
                dayToneChip
            }
            VStack(spacing: NoopMetrics.space2) {
                ForEach(cards) { card in
                    TodayInsightRow(card: card)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var dayToneChip: some View {
        let (text, color): (LocalizedStringKey, Color) = {
            switch dayTone {
            case .caution:  return (attentionCount > 1 ? "A few things to watch" : "One thing to watch",
                                    StrandPalette.statusWarning)
            case .positive: return ("A strong morning", StrandPalette.statusPositive)
            case .neutral:  return ("Steady", StrandPalette.textTertiary)
            }
        }()
        Text(text)
            .font(StrandFont.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// One insight row — icon chip, title + subtitle, and a tone dot (so colour is never the only signal).
private struct TodayInsightRow: View {
    let card: TodayInsightCard

    var body: some View {
        StrandCard {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(card.tint.opacity(0.16))
                    Image(systemName: card.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(card.tint)
                }
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !card.subtitle.isEmpty {
                        Text(card.subtitle)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                Circle()
                    .fill(TodayInsightCard.toneColor(card.tone))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Today insights") {
    let cards: [TodayInsightCard] = [
        TodayInsightCard(id: "recovery.strained", symbol: "bolt.heart",
                         title: "Recovery is running low",
                         subtitle: "HRV 44 ms — below baseline, suppressing recovery",
                         tint: StrandPalette.statusWarning, tone: .caution),
        TodayInsightCard(id: "sleepStages.deepAboveUsual", symbol: "moon.fill",
                         title: "Strong deep sleep",
                         subtitle: "+22 min above your usual — physically restorative.",
                         tint: StrandPalette.sleepDeep, tone: .positive),
        TodayInsightCard(id: "sleepTiming.veryRegular", symbol: "clock.arrow.circlepath",
                         title: "Very consistent sleep timing",
                         subtitle: "Mid-sleep within ±18 min — great for your body clock.",
                         tint: StrandPalette.metricPurple, tone: .positive),
    ]
    return ScrollView {
        TodayInsightsFeed(cards: cards, dayTone: .caution, attentionCount: 1)
            .padding()
    }
    .background(StrandPalette.surfaceBase)
}
#endif
