import SwiftUI
import StrandDesign
import StrandAnalytics

// TomorrowOutlookView.swift — the forward-looking, CONDITIONAL forecast card.
//
// NOOP looks back all day; this is the one place it looks forward — carefully. The pure TomorrowOutlook
// engine runs the forecaster twice (a usual night vs a short one), so the card can say what tonight's
// sleep is worth without ever making a promise. Copy stays conditional and hedges on confidence.
//
// Design-system only. iPhone-first (compiles for shared macOS too).

struct TomorrowOutlookView: View {
    let outlook: TomorrowOutlook.Outlook

    private var accent: Color { StrandPalette.recoveryColor(Double(outlook.expected)) }

    var body: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: 7) {
                    Image(systemName: directionSymbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                    Text("Tomorrow's outlook")
                        .font(StrandFont.caption.weight(.bold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer(minLength: 6)
                    Text(rangeText)
                        .font(StrandFont.captionNumber.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(accent.opacity(0.14)))
                }

                Text(headline)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(bodyText)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if outlook.confidence != .solid {
                    Text("An early read — it sharpens as NOOP learns your patterns.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var directionSymbol: String {
        switch outlook.direction {
        case .rebound: return "arrow.up.forward.circle.fill"
        case .dip:     return "arrow.down.forward.circle.fill"
        case .steady:  return "equal.circle.fill"
        case .unknown: return "sparkles"
        }
    }

    private var headline: LocalizedStringKey {
        switch outlook.direction {
        case .rebound: return "Tomorrow looks like a rebound"
        case .dip:     return "Tomorrow may ease off a little"
        case .steady:  return "Tomorrow looks steady"
        case .unknown: return "A look at tomorrow"
        }
    }

    private var rangeText: String {
        String(format: String(localized: "≈ %ld–%ld"), outlook.expectedLow, outlook.expectedHigh)
    }

    private var bodyText: String {
        if outlook.sleepMatters, let short = outlook.ifShort {
            return String(format: String(localized: "Keep tonight's sleep near your usual and you're likely around %ld. A short night could pull it toward %ld."),
                          outlook.expected, short)
        }
        return String(format: String(localized: "If tonight goes to plan, expect somewhere around %ld."),
                      outlook.expected)
    }
}

#if DEBUG
#Preview("Tomorrow's outlook") {
    let rebound = TomorrowOutlook.Outlook(hasForecast: true, direction: .rebound, expected: 78,
                                          expectedLow: 70, expectedHigh: 86, ifShort: 71, sleepSwing: 7,
                                          confidence: .building)
    let steady = TomorrowOutlook.Outlook(hasForecast: true, direction: .steady, expected: 64,
                                         expectedLow: 56, expectedHigh: 72, ifShort: 62, sleepSwing: 2,
                                         confidence: .solid)
    return ScrollView {
        VStack(spacing: 16) {
            TomorrowOutlookView(outlook: rebound)
            TomorrowOutlookView(outlook: steady)
        }
        .padding()
    }
    .background(StrandPalette.surfaceBase)
}
#endif
