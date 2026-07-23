import SwiftUI
import StrandDesign
import StrandAnalytics

// WeeklyReviewView.swift — the week-scale health story on Today.
//
// The pure WeeklyReview engine ranks week-over-week findings into wins/setbacks + one recommendation;
// this renders them: a headline (the biggest mover), the supporting findings with tone glyphs, and a
// "try this" nudge. Copy is warm and non-clinical; numbers come from the engine's deltas. Design-system
// only. iPhone-first.

enum WeeklyReviewCopy {

    static func line(_ f: WeeklyReview.Finding) -> String {
        let pts = abs(Int((f.delta ?? 0).rounded()))
        let hrs = String(format: "%.1f", abs(f.delta ?? 0))
        switch f.kind {
        case .recoveryUp:
            return String(format: String(localized: "Recovery up about %ld points on average."), pts)
        case .recoveryDown:
            return String(format: String(localized: "Recovery down about %ld points on average."), pts)
        case .sleptMore:
            return String(format: String(localized: "You slept about %@ h more per night."), hrs)
        case .sleptLess:
            return String(format: String(localized: "You slept about %@ h less per night."), hrs)
        case .steadySchedule:
            return String(localized: "Your sleep schedule stayed steady.")
        case .driftingSchedule:
            return String(localized: "Your sleep timing drifted this week.")
        case .trainedMore:
            return String(localized: "You trained more than last week.")
        case .trainedLess:
            return String(localized: "You trained less than last week.")
        case .buildingWeek:
            return String(localized: "Still building this week's picture.")
        }
    }

    static func recommendation(_ key: String) -> LocalizedStringKey {
        switch key {
        case "rec.protectRecovery": return "Try this: protect recovery — earlier nights and easier sessions until it climbs back."
        case "rec.prioritizeSleep": return "Try this: give sleep priority — even 30 minutes earlier adds up."
        case "rec.steadyBedtime":   return "Try this: aim for a more consistent bedtime — your body clock will thank you."
        case "rec.steadyWeek":      return "A steady week — small, consistent habits are what compound."
        default:                    return "Keep doing what you're doing — it's working."
        }
    }

    static func toneColor(_ tone: WeeklyReview.Tone) -> Color {
        switch tone {
        case .positive: return StrandPalette.statusPositive
        case .caution:  return StrandPalette.statusWarning
        case .neutral:  return StrandPalette.textTertiary
        }
    }

    static func toneSymbol(_ tone: WeeklyReview.Tone) -> String {
        switch tone {
        case .positive: return "checkmark.circle.fill"
        case .caution:  return "exclamationmark.triangle.fill"
        case .neutral:  return "circle.fill"
        }
    }
}

struct WeeklyReviewView: View {
    let review: WeeklyReview.Review

    /// Findings other than the headline, in a sensible reading order.
    private var supporting: [WeeklyReview.Finding] {
        let all = review.wins + review.setbacks + review.neutrals
        guard let head = review.headline else { return all }
        return all.filter { $0 != head }
    }

    var body: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(StrandPalette.restColor)
                    Text("This week in review")
                        .font(StrandFont.caption.weight(.bold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                }

                Text(headlineText)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !supporting.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(supporting.enumerated()), id: \.offset) { _, f in
                            findingRow(f)
                        }
                    }
                }

                Text(WeeklyReviewCopy.recommendation(review.recommendation))
                    .font(StrandFont.subhead.weight(.medium))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(NoopMetrics.space3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(StrandPalette.surfaceInset))

                if review.completeness < 0.7 {
                    Text("Based on the days you wore your strap this week.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var headlineText: String {
        if let head = review.headline { return WeeklyReviewCopy.line(head) }
        return String(localized: "A steady week — nothing needed your attention.")
    }

    private func findingRow(_ f: WeeklyReview.Finding) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: WeeklyReviewCopy.toneSymbol(f.tone))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WeeklyReviewCopy.toneColor(f.tone))
            Text(WeeklyReviewCopy.line(f))
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Weekly review") {
    let review = WeeklyReview.build(
        this: .init(avgCharge: 55, avgSleepHours: 7.6, avgEffort: nil, scheduleSDMin: 34,
                    daysWithData: 7, totalDays: 7),
        prior: .init(avgCharge: 68, avgSleepHours: 6.5, avgEffort: nil, scheduleSDMin: nil,
                     daysWithData: 7, totalDays: 7))
    return ScrollView { WeeklyReviewView(review: review).padding() }
        .background(StrandPalette.surfaceBase)
}
#endif
