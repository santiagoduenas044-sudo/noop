import SwiftUI
import StrandDesign
import StrandAnalytics

// SleepConsistencyDetailView.swift — the Sleep-tab detail for sleep-TIMING consistency.
//
// A thin, dumb renderer: every decision (tone, whether the bedtime/wake bars are trustworthy, the
// mid-sleep clock, the bar fractions) comes pre-computed from SleepConsistencyPresentation (pure,
// tested in StrandAnalytics). This view only maps those framework-free values to design tokens and
// localized copy — no new math lives here. Shared file: compiles for macOS + iOS.
//
// Copy is deliberately premium, neutral and ENCOURAGING (never judgemental): an irregular week reads
// "room to steady it", not a failure, and there is no clinical claim, streak, or call-to-action.

struct SleepConsistencyDetailView: View {

    let result: SleepRegularityResult
    let presentation: SleepConsistencyPresentation
    /// Per-night mid-sleep minutes for the dial + trend — exactly the nights the score used.
    let midpoints: [Double]

    /// Build the whole read from raw nights (the windowing/scoring happens in the engine).
    init(nights: [SleepTimingNight]) {
        let windowed = SleepRegularity.windowedNights(nights)
        let r = SleepRegularity.assess(nights: nights)
        self.result = r
        self.presentation = SleepConsistencyPresentation.from(r)
        self.midpoints = windowed.map { $0.midpointMinOfDay }
    }

    /// Direct init (for previews / callers that already have a result).
    init(result: SleepRegularityResult, midpoints: [Double]) {
        self.result = result
        self.presentation = SleepConsistencyPresentation.from(result)
        self.midpoints = midpoints
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                dialCard
                if presentation.showChannelBars { channelCard }
                if midpoints.count >= 2 { trendCard }
                explainerCard
            }
            .padding(NoopMetrics.screenPadding)
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .navigationTitle(Text(String(localized: "Sleep Consistency")))
    }

    // MARK: - Dial + headline

    private var dialCard: some View {
        StrandCard {
            VStack(spacing: NoopMetrics.space5) {
                SectionHeader(headlineKey,
                              overline: "Sleep consistency",
                              trailing: nil)
                ConsistencyDial(midpointsMinutes: midpoints,
                                meanMinutes: result.meanMidpointMinOfDay.map(Double.init),
                                spreadMinutes: result.midpointSDMinutes,
                                diameter: 224,
                                lineWidth: 11,
                                showsHourLabels: true,
                                accessibilityText: accessibilitySummary)
                    .frame(maxWidth: .infinity)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(result.score.map { String($0) } ?? "—")
                        .font(StrandFont.number(40))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(String(localized: "of 100"))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                if let clock = midpointClockString {
                    Text(String(localized: "Typical mid-sleep \(clock)"))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                confidenceRow
            }
        }
    }

    private var confidenceRow: some View {
        HStack(spacing: 8) {
            Text(chipTextKey)
                .font(StrandFont.captionNumber)
                .foregroundStyle(toneColor)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(toneColor.opacity(0.15)))
            Text(confidenceText)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    // MARK: - Per-channel bars (only when high-confidence — presentation gates this)

    private var channelCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                SectionHeader("Where the drift is", overline: "This week")
                channelBar(String(localized: "Bedtime"),
                           fraction: presentation.onsetBarFraction ?? 0, sd: result.onsetSDMinutes)
                channelBar(String(localized: "Wake"),
                           fraction: presentation.wakeBarFraction ?? 0, sd: result.wakeSDMinutes)
                channelBar(String(localized: "Mid-sleep"),
                           fraction: presentation.midpointBarFraction ?? 0, sd: result.midpointSDMinutes)
                Text(String(localized: "Shorter is steadier — each bar is how far that time drifted night to night."))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func channelBar(_ label: String, fraction: Double, sd: Double?) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 84, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset)
                    Capsule().fill(StrandPalette.restBright)
                        .frame(width: max(6, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 7)
            Text(spreadText(sd))
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 64, alignment: .trailing)
        }
    }

    // MARK: - Trend

    private var trendCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                SectionHeader("Mid-sleep trend", overline: "Recent nights")
                Sparkline(values: unwrappedMidpoints,
                          gradient: StrandPalette.restGradient,
                          showsHover: false,
                          valueFormat: { clockString(fromMinutes: $0) })
                    .frame(height: 64)
            }
        }
    }

    // MARK: - Explainer

    private var explainerCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text(String(localized: "Why timing matters"))
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(String(localized: "Going to bed and waking at steady times helps your body clock settle, which supports how you sleep and feel. This is a wellness read of your timing, not a medical assessment."))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Copy & formatting

    private var headlineKey: LocalizedStringKey {
        switch result.label {
        case .veryRegular: return "Very consistent"
        case .regular:     return "Consistent"
        case .variable:    return "A little variable"
        case .irregular:   return "Quite variable — room to steady it"
        case .unreadable:  return "Building your baseline"
        }
    }

    private var headlineString: String {
        switch result.label {
        case .veryRegular: return String(localized: "Very consistent")
        case .regular:     return String(localized: "Consistent")
        case .variable:    return String(localized: "A little variable")
        case .irregular:   return String(localized: "Quite variable — room to steady it")
        case .unreadable:  return String(localized: "Building your baseline")
        }
    }

    private var chipTextKey: LocalizedStringKey {
        switch presentation.tone {
        case .positive: return "Steady"
        case .caution:  return "Variable"
        case .neutral:  return "Building"
        }
    }

    private var toneColor: Color {
        switch presentation.tone {
        case .positive: return StrandPalette.statusPositive
        case .caution:  return StrandPalette.statusWarning
        case .neutral:  return StrandPalette.textTertiary
        }
    }

    private var confidenceText: String {
        let tier: String
        switch result.confidence {
        case .calibrating: tier = String(localized: "Calibrating")
        case .building:    tier = String(localized: "Building")
        case .solid:       tier = String(localized: "Solid")
        }
        return String(localized: "\(tier) · \(result.nightCount) nights")
    }

    private func spreadText(_ sd: Double?) -> String {
        guard let sd else { return "—" }
        return String(localized: "±\(Int(sd.rounded())) min")
    }

    private var midpointClockString: String? {
        guard let h = presentation.midpointClockHour, let m = presentation.midpointClockMinute else { return nil }
        return clockString(h: h, m: m)
    }

    private func clockString(h: Int, m: Int) -> String {
        var c = DateComponents(); c.hour = h; c.minute = m
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func clockString(fromMinutes minutes: Double) -> String {
        let norm = ((Int(minutes.rounded()) % 1440) + 1440) % 1440
        return clockString(h: norm / 60, m: norm % 60)
    }

    /// Sparkline values with the wrap removed: each midpoint pulled to the equivalent clock time
    /// within ±12 h of the mean, so a night just after midnight sits next to one just before it
    /// instead of jumping the full 24 h.
    private var unwrappedMidpoints: [Double] {
        let mean = Double(result.meanMidpointMinOfDay ?? 0)
        return midpoints.map { m in
            var v = m
            while v - mean > 720 { v -= 1440 }
            while v - mean < -720 { v += 1440 }
            return v
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = [String(localized: "Sleep consistency"), headlineString]
        if let s = result.score { parts.append(String(localized: "\(s) of 100")) }
        if let sd = result.midpointSDMinutes {
            parts.append(String(localized: "mid-sleep varied by plus or minus \(Int(sd.rounded())) minutes"))
        }
        parts.append(String(localized: "over \(result.nightCount) nights"))
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Sleep Consistency — solid") {
    let r = SleepRegularityResult(score: 84, label: .veryRegular, confidence: .solid,
                                  midpointSDMinutes: 18, onsetSDMinutes: 22, wakeSDMinutes: 15,
                                  meanMidpointMinOfDay: 192, resultantLength: 0.98, nightCount: 12)
    return NavigationStack {
        SleepConsistencyDetailView(result: r,
            midpoints: [186, 174, 192, 180, 168, 198, 180, 176, 190, 182, 172, 188])
    }
    .preferredColorScheme(.dark)
}

#Preview("Sleep Consistency — building baseline") {
    NavigationStack {
        SleepConsistencyDetailView(result: .unreadable(nightCount: 2), midpoints: [])
    }
    .preferredColorScheme(.light)
}
#endif
