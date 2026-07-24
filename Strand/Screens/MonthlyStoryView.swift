import SwiftUI
import StrandDesign
import StrandAnalytics

// MonthlyStoryView.swift — the month-scale story on Today (long-term trend read).
//
// Renders the pure MonthlyStory: a trend headline, a couple of month averages, a consistency note, and
// a short reflection. Warm, non-clinical copy; the trend is a measured slope, never a vibe. Design-
// system only. iPhone-first.

struct MonthlyStoryView: View {
    let story: MonthlyStory.Story

    private var accent: Color {
        switch story.trend {
        case .improving: return StrandPalette.statusPositive
        case .declining: return StrandPalette.statusWarning
        case .steady:    return StrandPalette.restColor
        case .unknown:   return StrandPalette.textTertiary
        }
    }

    var body: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: 7) {
                    Image(systemName: trendSymbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                    Text("This month")
                        .font(StrandFont.caption.weight(.bold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                }

                Text(headline)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !statLines.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(statLines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Circle().fill(accent).frame(width: 5, height: 5).offset(y: -1)
                                Text(line)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Text(reflection)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var trendSymbol: String {
        switch story.trend {
        case .improving: return "arrow.up.right.circle.fill"
        case .declining: return "arrow.down.right.circle.fill"
        case .steady:    return "arrow.right.circle.fill"
        case .unknown:   return "calendar"
        }
    }

    private var headline: LocalizedStringKey {
        switch story.trend {
        case .improving: return "Your recovery is trending up this month"
        case .declining: return "Your recovery has eased off this month"
        case .steady:    return "A steady month for your recovery"
        case .unknown:   return "Building your monthly picture"
        }
    }

    private var statLines: [String] {
        var out: [String] = []
        if let r = story.avgRecovery {
            let slope = story.recoverySlopePerWeek
            if abs(slope) >= MonthlyStory.trendSlopePerWeek {
                out.append(String(format: String(localized: "Charge averaged %ld, %@%.1f per week."),
                                  r, slope > 0 ? "+" : "", slope))
            } else {
                out.append(String(format: String(localized: "Charge averaged %ld."), r))
            }
        }
        if let h = story.avgSleepHours {
            out.append(String(format: String(localized: "You slept %.1f h a night on average."), h))
        }
        if story.consistentSchedule {
            out.append(String(localized: "Your sleep schedule stayed consistent."))
        }
        return out
    }

    private var reflection: String {
        switch story.trend {
        case .improving: return String(localized: "Whatever you've been doing is working — a good window to build on.")
        case .declining: return String(localized: "A gentle month is normal. Steady sleep and easy weeks bring it back.")
        case .steady:    return String(localized: "Consistency like this is the foundation everything else builds on.")
        case .unknown:   return String(localized: "A few more weeks of wear and the monthly trend will come into focus.")
        }
    }
}

#if DEBUG
#Preview("Monthly story") {
    let up = MonthlyStory.build(.init(recoveries: (0..<28).map { 52 + Double($0) * 0.6 },
                                      sleepHours: Array(repeating: 7.5, count: 28), scheduleSDMin: 38,
                                      daysWithData: 28, totalDays: 28))
    let flat = MonthlyStory.build(.init(recoveries: Array(repeating: 66, count: 26),
                                        sleepHours: Array(repeating: 7.1, count: 26), scheduleSDMin: 70,
                                        daysWithData: 26, totalDays: 28))
    return ScrollView {
        VStack(spacing: 16) {
            MonthlyStoryView(story: up)
            MonthlyStoryView(story: flat)
        }
        .padding()
    }
    .background(StrandPalette.surfaceBase)
}
#endif
