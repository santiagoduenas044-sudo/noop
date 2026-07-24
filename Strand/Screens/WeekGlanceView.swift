import SwiftUI
import StrandDesign
import StrandAnalytics

// WeekGlanceView.swift — a beautiful, at-a-glance week dashboard on Today.
//
// Seven days of Charge as colour-ramped bars (the recovery palette everything else uses), each day's
// sleep as a quiet caption, and a one-line read. Pattern recognition in a single look — the premium
// "how has my week been?" answer without opening Trends. Design-system only; the colour ramp IS the
// information, so it reads for everyone alongside the value labels. iPhone-first.

struct WeekGlanceDay: Identifiable, Equatable {
    let id: String            // day key
    let label: String         // weekday initial
    let recovery: Double?
    let sleepHours: Double?
    let isToday: Bool
}

struct WeekGlanceView: View {
    let days: [WeekGlanceDay]

    private var scored: [Double] { days.compactMap { $0.recovery } }
    private var avgRecovery: Int? {
        scored.isEmpty ? nil : Int((scored.reduce(0, +) / Double(scored.count)).rounded())
    }

    private let barArea: CGFloat = 74

    var body: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last 7 days").strandOverline()
                        Text("Your week").font(StrandFont.title2)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    Spacer(minLength: 8)
                    if let avg = avgRecovery {
                        Text("avg \(avg)")
                            .font(StrandFont.captionNumber.weight(.semibold))
                            .foregroundStyle(StrandPalette.recoveryColor(Double(avg)))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(StrandPalette.recoveryColor(Double(avg)).opacity(0.14)))
                    }
                }

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(days) { day in
                        dayColumn(day)
                    }
                }

                if let summary = summaryText {
                    Text(summary)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func dayColumn(_ day: WeekGlanceDay) -> some View {
        VStack(spacing: 5) {
            // Value above the bar.
            Text(day.recovery.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(day.recovery == nil ? StrandPalette.textTertiary : StrandPalette.textSecondary)
                .monospacedDigit()

            // The bar.
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(StrandPalette.surfaceInset)
                    .frame(width: 20, height: barArea)
                if let r = day.recovery {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(StrandPalette.recoveryColor(r))
                        .frame(width: 20, height: max(6, barArea * CGFloat(min(1, r / 100))))
                }
            }
            .overlay(alignment: .bottom) {
                if day.isToday {
                    Circle().fill(StrandPalette.textPrimary).frame(width: 3, height: 3).offset(y: 7)
                }
            }

            // Weekday initial.
            Text(day.label)
                .font(StrandFont.caption.weight(day.isToday ? .bold : .regular))
                .foregroundStyle(day.isToday ? StrandPalette.textPrimary : StrandPalette.textTertiary)

            // Sleep hours caption.
            Text(day.sleepHours.map { String(format: "%.1f", $0) } ?? " ")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(StrandPalette.textTertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryText: String? {
        guard let avg = avgRecovery, scored.count >= 3 else { return nil }
        let first = scored.prefix(scored.count / 2)
        let last = scored.suffix(scored.count / 2)
        guard !first.isEmpty, !last.isEmpty else { return nil }
        let delta = (last.reduce(0, +) / Double(last.count)) - (first.reduce(0, +) / Double(first.count))
        let trend: String
        if delta >= 4 { trend = String(localized: "trending up") }
        else if delta <= -4 { trend = String(localized: "easing off") }
        else { trend = String(localized: "steady") }
        let sleeps = days.compactMap { $0.sleepHours }
        if !sleeps.isEmpty {
            let avgSleep = sleeps.reduce(0, +) / Double(sleeps.count)
            return String(format: String(localized: "Recovery averaged %ld and is %@. You slept %.1f h a night."),
                          avg, trend, avgSleep)
        }
        return String(format: String(localized: "Recovery averaged %ld and is %@."), avg, trend)
    }
}

#if DEBUG
#Preview("Your week") {
    let labels = ["M", "T", "W", "T", "F", "S", "S"]
    let recs: [Double?] = [58, 64, 49, 71, 66, nil, 78]
    let sleeps: [Double?] = [7.1, 7.6, 6.2, 7.9, 7.4, nil, 8.1]
    let days = (0..<7).map { i in
        WeekGlanceDay(id: "d\(i)", label: labels[i], recovery: recs[i], sleepHours: sleeps[i], isToday: i == 6)
    }
    return ScrollView { WeekGlanceView(days: days).padding() }
        .background(StrandPalette.surfaceBase)
}
#endif
