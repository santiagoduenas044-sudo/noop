import SwiftUI
import StrandDesign
import StrandAnalytics

// OnDeviceCoachView.swift — NOOP's private, network-free coach.
//
// Distinct from the optional bring-your-own-key cloud chat (CoachView): this answers the everyday
// questions instantly, on-device, from the user's own scores — no key, nothing leaves the phone. The
// pure CoachAdvisor decides the training verdict; every answer is composed here from engines already
// computed on Today (Charge drivers, tomorrow's outlook, personal correlations, the weekly review), in
// warm, non-clinical language that recommends and never diagnoses. Design-system only. iPhone-first.

/// Everything the on-device coach needs, resolved by Today.
struct CoachContext {
    let verdict: CoachAdvisor.Verdict
    let recoveryScore: Int?
    let topDriver: ChargeDriver?
    let outlook: TomorrowOutlook.Outlook
    let topFactor: PersonalCorrelations.Factor?
    let weekly: WeeklyReview.Review
}

struct OnDeviceCoachView: View {
    let context: CoachContext

    enum Question: String, CaseIterable, Identifiable {
        case train, recovery, sleep, week
        var id: String { rawValue }
        var chip: LocalizedStringKey {
            switch self {
            case .train:    return "Train today?"
            case .recovery: return "My recovery"
            case .sleep:    return "Sleep better"
            case .week:     return "My week"
            }
        }
    }

    @State private var selected: Question = .train

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(StrandPalette.restColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("NOOP Coach").font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("On-device · private").font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Question.allCases) { q in
                        let isOn = q == selected
                        Text(q.chip)
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(isOn ? StrandPalette.surfaceBase : StrandPalette.textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(isOn ? StrandPalette.restColor
                                                           : StrandPalette.surfaceInset))
                            .contentShape(Capsule())
                            .onTapGesture { selected = q }
                    }
                }
                .padding(.horizontal, 1)
            }

            Text(answer)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(nil, value: selected)
        }
        .padding(NoopMetrics.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .fill(StrandPalette.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .strokeBorder(StrandPalette.restColor.opacity(0.22), lineWidth: 0.5))
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Composed answers

    private var answer: String {
        switch selected {
        case .train:    return trainAnswer
        case .recovery: return recoveryAnswer
        case .sleep:    return sleepAnswer
        case .week:     return weekAnswer
        }
    }

    private var trainAnswer: String {
        let base: String
        switch context.verdict {
        case .push:
            base = String(localized: "Today's a good day to push — your body's ready for real stress.")
        case .maintain:
            base = String(localized: "A moderate day — train to how you feel, nothing forced.")
        case .easeIn:
            base = String(localized: "Ease in today. Keep it light and let your body catch up.")
        case .rest:
            base = String(localized: "Rest is the play today — light movement at most.")
        case .unknown:
            return String(localized: "Not enough history yet to call it — a few more nights of wear and I can.")
        }
        if context.outlook.hasForecast, context.outlook.sleepMatters, context.verdict != .rest {
            return base + " " + String(localized: "Protect tonight's sleep and tomorrow should hold up well.")
        }
        return base
    }

    private var recoveryAnswer: String {
        guard let score = context.recoveryScore else {
            return String(localized: "Your recovery isn't scored yet today — it builds from tonight's sleep and your morning vitals.")
        }
        if let d = context.topDriver {
            let value = d.valueText.isEmpty ? d.label : "\(d.label) \(d.valueText)"
            return String(format: String(localized: "Your Charge is %ld. The biggest factor right now is %@ — %@."),
                          score, value, d.verdict)
        }
        return String(format: String(localized: "Your Charge is %ld, built from your HRV, resting heart rate and sleep quality."), score)
    }

    private var sleepAnswer: String {
        if let f = context.topFactor {
            return String(format: String(localized: "In your own data, %@ That's the lever I'd focus on."),
                          RecoveryFactorsCopy.line(f))
        }
        return String(localized: "The basics move recovery most: a consistent bedtime and enough hours for you. NOOP will spot your personal patterns as more nights come in.")
    }

    private var weekAnswer: String {
        guard context.weekly.hasEnoughData else {
            return String(localized: "Still building this week's picture — check back in a few days.")
        }
        let head = context.weekly.headline.map { WeeklyReviewCopy.line($0) }
            ?? String(localized: "A steady week — nothing needed your attention.")
        return head + " " + recString(context.weekly.recommendation)
    }

    private func recString(_ key: String) -> String {
        switch key {
        case "rec.protectRecovery": return String(localized: "This week, protect recovery — earlier nights and easier sessions.")
        case "rec.prioritizeSleep": return String(localized: "This week, give sleep priority — even 30 minutes earlier adds up.")
        case "rec.steadyBedtime":   return String(localized: "This week, aim for a more consistent bedtime.")
        case "rec.steadyWeek":      return String(localized: "Small, consistent habits are what compound.")
        default:                    return String(localized: "Keep doing what you're doing — it's working.")
        }
    }
}

#if DEBUG
#Preview("On-device coach") {
    let ctx = CoachContext(
        verdict: .easeIn, recoveryScore: 48,
        topDriver: ChargeDriver(label: "HRV", deltaPoints: -6, valueText: "44 ms",
                                baselineText: "58 ms baseline", verdict: "below baseline, suppressing recovery"),
        outlook: TomorrowOutlook.Outlook(hasForecast: true, direction: .rebound, expected: 62,
                                         expectedLow: 54, expectedHigh: 70, ifShort: 55, sleepSwing: 7,
                                         confidence: .building),
        topFactor: .init(key: "sleepDuration", r: 0.55, n: 24, direction: .positive, strength: .strong),
        weekly: WeeklyReview.build(this: .init(avgCharge: 55, avgSleepHours: 6.4, avgEffort: nil,
                                               scheduleSDMin: 40, daysWithData: 7, totalDays: 7),
                                   prior: .init(avgCharge: 66, avgSleepHours: 7.0, avgEffort: nil,
                                                scheduleSDMin: nil, daysWithData: 7, totalDays: 7)))
    return ScrollView { OnDeviceCoachView(context: ctx).padding() }
        .background(StrandPalette.surfaceBase)
}
#endif
