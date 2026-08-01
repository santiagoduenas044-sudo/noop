#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Phase 2 · Sleep — the approved prototype's Sleep screen, native SwiftUI on real
/// `Repository`/`DailyMetric` data: an efficiency score ring, a time-resolved hypnogram of last
/// night's real stage timeline, the dual "Hours of sleep / Restorative sleep" headline with
/// 30-day-typical baselines, per-stage breakdown lanes (Deep / REM / Light / Awake) sized from
/// the real recorded stage minutes, and a weekly sleep-hours trend.
///
/// The hypnogram reuses `SleepView.decodedIntervals` — the SAME tested stage-segment decode the
/// classic Sleep screen's timeline uses — over the day's real main-night session (picked by
/// `SleepView.mainNightSession`, the same learned-timing winner logic), rather than re-deriving
/// that decode. Falls back to the proportional lanes alone when a night has no time-resolved
/// data (an imported night stores only stage minutes, no segment timing).
struct PremiumSleepView: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal

    @State private var hypnogramIntervals: [SleepInterval] = []
    @State private var hypnogramNightStart: Date?

    private func latest<T>(_ key: (DailyMetric) -> T?) -> T? {
        for d in repo.days.reversed() { if let v = key(d) { return v } }
        return repo.today.flatMap(key)
    }
    private func mean(_ key: (DailyMetric) -> Double?) -> Double? {
        let xs = repo.days.suffix(30).compactMap(key)
        return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    private var efficiency: Double? { latest { $0.efficiency } }
    private var sleepMin: Double  { latest { $0.totalSleepMin } ?? 0 }
    private var deepMin: Double   { latest { $0.deepMin } ?? 0 }
    private var remMin: Double    { latest { $0.remMin } ?? 0 }
    private var lightMin: Double  { latest { $0.lightMin } ?? 0 }
    private var restorativeMin: Double { deepMin + remMin }
    private var inBedMin: Double {
        guard let e = efficiency, e > 0 else { return sleepMin }
        return sleepMin / (e / 100.0)
    }
    private var awakeMin: Double { max(0, inBedMin - sleepMin) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 1).id("top")
                    header
                    scoreHero
                    hypnogramCard
                    breakdownCard
                    trendCard
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 96)
            }
            .background(ambient.ignoresSafeArea())
            .onChange(of: scrollToTopSignal) { _, _ in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
            }
        }
        .task(id: repo.refreshSeq) { await loadHypnogram() }
    }

    // MARK: - Hypnogram (real, time-resolved)

    @ViewBuilder private var hypnogramCard: some View {
        if !hypnogramIntervals.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sleep stages").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                StrandCard {
                    Hypnogram(intervals: hypnogramIntervals, height: 160,
                              nightStart: hypnogramNightStart, showsTimeAxis: hypnogramNightStart != nil)
                }
            }
        }
    }

    /// The most recent night's real stage timeline: group sessions by the calendar day they END on
    /// (mirroring `SleepView.navDays`), take the newest day, pick its main-night session (the same
    /// learned-timing winner `SleepView` uses), and decode its stored segment JSON into the
    /// `Hypnogram`'s `[SleepInterval]` domain. Empty when the newest night has no time-resolved data
    /// (an imported night stores only stage minutes) — `hypnogramCard` hides itself in that case, and
    /// `breakdownCard`'s proportional lanes below still show the real per-stage minutes either way.
    private func loadHypnogram() async {
        let sessions = await repo.allSleepSessions()
        guard !sessions.isEmpty else {
            await MainActor.run { hypnogramIntervals = []; hypnogramNightStart = nil }
            return
        }
        let habitual = await repo.habitualMidsleepSec()
        let cal = Calendar.current
        let groups = Dictionary(grouping: sessions) { s in
            cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(s.endTs)))
        }
        guard let newestDay = groups.keys.max(),
              let main = SleepView.mainNightSession(groups[newestDay] ?? [], habitualMidsleepSec: habitual)
        else {
            await MainActor.run { hypnogramIntervals = []; hypnogramNightStart = nil }
            return
        }
        let intervals = SleepView.decodedIntervals(main.stagesJSON, sessionStart: main.effectiveStartTs) ?? []
        let start = Date(timeIntervalSince1970: TimeInterval(main.effectiveStartTs))
        await MainActor.run {
            hypnogramIntervals = intervals
            hypnogramNightStart = intervals.isEmpty ? nil : start
        }
    }

    private var ambient: some View {
        ZStack {
            StrandPalette.surfaceBase
            RadialGradient(colors: [StrandPalette.sleepDeep.opacity(0.16), .clear],
                           center: .init(x: 0.5, y: 0.0), startRadius: 0, endRadius: 360)
            RadialGradient(colors: [StrandPalette.sleepREM.opacity(0.10), .clear],
                           center: .init(x: 1.0, y: 0.3), startRadius: 0, endRadius: 300)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LAST NIGHT").font(StrandFont.overline).tracking(1.4)
                .foregroundStyle(StrandPalette.textTertiary)
            Text("Sleep").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Score hero ring

    /// Animated ring fill — draws in on appear/change, the same `StrandMotion.drawIn` curve
    /// `RecoveryRing` uses, instead of snapping straight to the target fraction.
    @State private var animatedRingFraction: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scoreHero: some View {
        let frac = min(1, max(0, (efficiency ?? 0) / 100))
        return VStack(spacing: 14) {
            ZStack {
                Circle().stroke(StrandPalette.surfaceInset, lineWidth: 14)
                Circle().trim(from: 0, to: animatedRingFraction)
                    .stroke(LinearGradient(colors: [StrandPalette.sleepREM, StrandPalette.sleepDeep],
                                           startPoint: .topTrailing, endPoint: .bottomLeading),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: StrandPalette.sleepDeep.opacity(0.5), radius: 10)
                VStack(spacing: 2) {
                    CountUpText(value: efficiency ?? 0,
                                format: { efficiency == nil ? "—" : "\(Int($0.rounded()))" },
                                font: .system(size: 58, weight: .heavy),
                                color: StrandPalette.textPrimary)
                        .monospacedDigit()
                    Text("EFFICIENCY").font(StrandFont.overline).tracking(1.4)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .frame(width: 208, height: 208)
            .onAppear { withAnimation(StrandMotion.drawIn(reduced: reduceMotion)) { animatedRingFraction = frac } }
            .onChange(of: frac) { _, new in
                withAnimation(StrandMotion.drawIn(reduced: reduceMotion)) { animatedRingFraction = new }
            }
            Text("\(durText(sleepMin)) asleep · \(durText(inBedMin)) in bed")
                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Stage breakdown

    private var breakdownCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Stage breakdown").font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                // Dual headline: hours + restorative, each with a typical baseline.
                HStack(alignment: .top, spacing: 16) {
                    dualStat(title: "Hours of sleep", value: durText(sleepMin),
                             typical: mean { $0.totalSleepMin }.map { "typically \(durText($0))" },
                             tint: StrandPalette.textPrimary)
                    dualStat(title: "Restorative", value: durText(restorativeMin),
                             typical: restorativeTypicalText, tint: StrandPalette.sleepDeep)
                }
                stageLane("Awake", awakeMin, StrandPalette.sleepAwake)
                stageLane("Light", lightMin, StrandPalette.sleepLight)
                stageLane("Deep", deepMin, StrandPalette.sleepDeep)
                stageLane("REM", remMin, StrandPalette.sleepREM)
                Text(hypnogramIntervals.isEmpty
                     ? "Stage proportions from your recorded sleep · on-device"
                     : "Per-stage totals from the hypnogram above · on-device")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private var restorativeTypicalText: String? {
        guard let d = mean({ $0.deepMin }), let r = mean({ $0.remMin }) else { return nil }
        return "typically \(durText(d + r))"
    }

    private func dualStat(title: String, value: String, typical: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 30, weight: .heavy)).monospacedDigit()
                .foregroundStyle(tint)
            Text(title.uppercased()).font(StrandFont.overline).tracking(1.2)
                .foregroundStyle(StrandPalette.textTertiary)
            if let t = typical {
                Text(t).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One per-stage density lane: name · % of night · duration, over a hatched track with a
    /// proportional filled block. (Proportional, not time-resolved — see the file header.)
    private func stageLane(_ name: String, _ minutes: Double, _ color: Color) -> some View {
        let total = max(1, inBedMin)
        let pct = Int((minutes / total * 100).rounded())
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(name.uppercased()).font(StrandFont.overline).tracking(0.8)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("\(pct)%").font(StrandFont.captionNumber).foregroundStyle(color)
                Spacer()
                Text(durText(minutes)).font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(StrandPalette.surfaceInset)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color)
                        .frame(width: max(3, geo.size.width * CGFloat(minutes / total)))
                        .shadow(color: color.opacity(0.5), radius: 6)
                        .padding(3)
                }
            }
            .frame(height: 26)
        }
    }

    // MARK: Trend

    private var trendCard: some View {
        let hours = Array(repo.days.suffix(90).compactMap { $0.totalSleepMin }.map { $0 / 60 }.suffix(14))
        return VStack(alignment: .leading, spacing: 14) {
            Text("Sleep hours · last 14 days").font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            StrandCard {
                if hours.count >= 2 {
                    Sparkline(values: hours,
                              gradient: Gradient(colors: [StrandPalette.sleepREM, StrandPalette.sleepDeep]),
                              lineWidth: 2.5, showsArea: true, showsHead: true, showsHover: true,
                              valueFormat: { String(format: "%.1f h", $0) })
                        .frame(height: 120)
                } else {
                    Text("Not enough nights yet").font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
    }

    private func durText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded()); let h = m / 60, mm = m % 60
        return h > 0 ? "\(h)h \(mm)m" : "\(mm)m"
    }
}
#endif
