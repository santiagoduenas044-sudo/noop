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
    @State private var hypnogramNightEnd: Date?
    /// Which stage lane is tapped-open, WHOOP style: the selected row keeps its colour while every
    /// other row's blocks grey out, and the insight line below compares it to the 30-day typical.
    @State private var selectedStage: SleepStage? = nil
    /// Real overnight heart-rate samples across the main-night window (downsampled buckets). Heart rate is
    /// the ONLY per-time overnight signal NOOP stores on-device — HRV / respiratory / SpO₂ are nightly
    /// aggregates, so the scrubber charts HR honestly and shows the others as nightly-average references,
    /// never fabricated overnight curves.
    @State private var overnightHR: [OvernightSample] = []

    private func latest<T>(_ key: (DailyMetric) -> T?) -> T? {
        for d in repo.days.reversed() { if let v = key(d) { return v } }
        return repo.today.flatMap(key)
    }
    private func mean(_ key: (DailyMetric) -> Double?) -> Double? {
        let xs = repo.days.suffix(30).compactMap(key)
        return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// `DailyMetric.efficiency` (like `CachedSleepSession.efficiency`) is stored as a FRACTION in [0,1]
    /// — see `SleepStageTotals.DailySleep`'s own doc ("efficiency is asleep / in-bed … in [0,1]") — not
    /// a 0-100 percentage. Treating it as already-percent here previously divided it by 100 a second
    /// time, which for `inBedMin` (dividing sleep minutes by a ~100x-too-small fraction) inflated "time
    /// in bed" into the hundreds of hours, and for the ring display rounded a value like 0.92 to "1".
    /// Normalized ONCE here — the same defensive `<= 1.0 ? *100 : as-is` conversion `SleepView.
    /// efficiencyPct` uses (some import paths already write 0-100) — so every consumer below works in
    /// one consistent 0-100 scale.
    private var efficiencyRaw: Double? { latest { $0.efficiency } }
    private var efficiencyPct: Double? { efficiencyRaw.map { $0 <= 1.0 ? $0 * 100 : $0 } }
    private var sleepMin: Double  { latest { $0.totalSleepMin } ?? 0 }
    private var deepMin: Double   { latest { $0.deepMin } ?? 0 }
    private var remMin: Double    { latest { $0.remMin } ?? 0 }
    private var lightMin: Double  { latest { $0.lightMin } ?? 0 }
    private var restorativeMin: Double { deepMin + remMin }
    private var inBedMin: Double {
        guard let e = efficiencyPct, e > 0 else { return sleepMin }
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
                    overnightCard
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

    /// The most recent night's real stage timeline: group sessions by the calendar day they END on
    /// (mirroring `SleepView.navDays`), take the newest day, pick its main-night session (the same
    /// learned-timing winner `SleepView` uses), and decode its stored segment JSON into the
    /// `Hypnogram`'s `[SleepInterval]` domain. Empty when the newest night has no time-resolved data
    /// (an imported night stores only stage minutes) — `hypnogramCard` hides itself in that case, and
    /// `breakdownCard`'s proportional lanes below still show the real per-stage minutes either way.
    private func loadHypnogram() async {
        let sessions = await repo.allSleepSessions()
        guard !sessions.isEmpty else {
            await MainActor.run { clearNight() }
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
            await MainActor.run { clearNight() }
            return
        }
        let intervals = SleepView.decodedIntervals(main.stagesJSON, sessionStart: main.effectiveStartTs) ?? []
        let start = Date(timeIntervalSince1970: TimeInterval(main.effectiveStartTs))
        let end = Date(timeIntervalSince1970: TimeInterval(main.endTs))
        // Real overnight heart rate across the main-night window, 2-minute buckets (aggregated in SQL so a
        // whole night never loads the raw ~1 Hz rows). Zero-bpm gaps are dropped so the line reflects only
        // recorded beats.
        let buckets = await repo.hrBuckets(from: main.effectiveStartTs, to: main.endTs, bucketSeconds: 120)
        let hr = buckets.compactMap { b -> OvernightSample? in
            guard b.bpm > 0 else { return nil }
            return OvernightSample(t: Date(timeIntervalSince1970: TimeInterval(b.ts)), bpm: b.bpm)
        }
        await MainActor.run {
            hypnogramIntervals = intervals
            hypnogramNightStart = intervals.isEmpty ? nil : start
            hypnogramNightEnd = intervals.isEmpty ? nil : end
            overnightHR = hr
        }
    }

    private func clearNight() {
        hypnogramIntervals = []; hypnogramNightStart = nil; hypnogramNightEnd = nil; overnightHR = []
        selectedStage = nil
    }

    // MARK: - Overnight physiology (synchronized scrubber)

    /// The interactive overnight panel: a scrubbable heart-rate line synchronized to the same night timeline
    /// as the hypnogram above, with a stage ribbon beneath it and nightly-average references for the signals
    /// NOOP only stores as aggregates. Shown only when the night has both a time-resolved stage timeline and
    /// real overnight HR.
    @ViewBuilder private var overnightCard: some View {
        if let start = hypnogramNightStart, let end = hypnogramNightEnd,
           overnightHR.count >= 3, end > start {
            VStack(alignment: .leading, spacing: 14) {
                Text("Overnight").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                StrandCard {
                    SleepOvernightPanel(samples: overnightHR, intervals: hypnogramIntervals,
                                        nightStart: start, nightEnd: end,
                                        restingHr: latest { $0.restingHr },
                                        nightlyHRV: latest { $0.avgHrv },
                                        nightlyResp: latest { $0.respRateBpm },
                                        nightlySpO2: latest { $0.spo2Pct })
                }
            }
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
        HStack(alignment: .center, spacing: 12) {
            BrandMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("LAST NIGHT").font(StrandFont.overline).tracking(1.4)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("Sleep").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Score hero ring

    /// Animated ring fill — draws in on appear/change, the same `StrandMotion.drawIn` curve
    /// `RecoveryRing` uses, instead of snapping straight to the target fraction.
    @State private var animatedRingFraction: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scoreHero: some View {
        let frac = min(1, max(0, (efficiencyPct ?? 0) / 100))
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
                    CountUpText(value: efficiencyPct ?? 0,
                                format: { efficiencyPct == nil ? "—" : "\(Int($0.rounded()))" },
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
                if let start = hypnogramNightStart, let end = hypnogramNightEnd,
                   !hypnogramIntervals.isEmpty, end > start {
                    // Real, time-resolved lanes: one full-width row per stage, a hatched track for the
                    // whole night, solid blocks exactly where that stage occurred — WHOOP's own sleep-
                    // detail layout, adapted from `SleepView.stageTimelineRow`. Tap a row to highlight it.
                    timeResolvedStages(start: start, end: end)
                } else {
                    // No time-resolved segment data for this night (e.g. an imported night that only
                    // stores stage minutes) — fall back to the proportional density lanes.
                    stageLane("Awake", awakeMin, StrandPalette.sleepAwake)
                    stageLane("Light", lightMin, StrandPalette.sleepLight)
                    stageLane("Deep", deepMin, StrandPalette.sleepDeep)
                    stageLane("REM", remMin, StrandPalette.sleepREM)
                    Text("Stage proportions from your recorded sleep · on-device")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    // MARK: Real time-resolved stage lanes (WHOOP sleep-detail style)

    private func timeResolvedStages(start: Date, end: Date) -> some View {
        let span = max(1, end.timeIntervalSince(start))
        let total = max(1, inBedMin)
        return VStack(alignment: .leading, spacing: 10) {
            timelineRow(.awake, minutes: awakeMin, total: total, span: span)
            timelineRow(.light, minutes: lightMin, total: total, span: span)
            timelineRow(.deep,  minutes: deepMin,  total: total, span: span)
            timelineRow(.rem,   minutes: remMin,   total: total, span: span)
            HStack {
                Text(clockText(start)).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                Spacer()
                Text(clockText(start.addingTimeInterval(span / 2))).font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                Spacer()
                Text(clockText(end)).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
            stageInsight
        }
    }

    /// One WHOOP-style stage lane: header (STAGE · coloured % · right-aligned duration) over a hatched
    /// night-long track with solid segments exactly where that stage occurred, positioned from the
    /// REAL decoded interval times (`iv.start`/`iv.end`, seconds from night start) — not a proportional
    /// fill. Tap toggles the highlight: the selected row keeps colour, the rest grey out.
    private func timelineRow(_ stage: SleepStage, minutes: Double, total: Double, span: Double) -> some View {
        let color = StrandPalette.sleepStageColor(stage)
        let isSelected = selectedStage == stage
        let dimmed = selectedStage != nil && !isSelected
        let percent = total > 0 ? Int((minutes / total * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(stage.label.uppercased()).font(StrandFont.overline).tracking(0.8)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("\(percent)%").font(StrandFont.captionNumber)
                    .foregroundStyle(dimmed ? StrandPalette.textTertiary : color)
                Spacer()
                Text(durText(minutes)).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    SleepHatchedTrack()
                    ForEach(hypnogramIntervals.filter { $0.stage == stage }) { iv in
                        let x0 = CGFloat(iv.start / span) * geo.size.width
                        let w = max(2, CGFloat((iv.end - iv.start) / span) * geo.size.width)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(dimmed ? StrandPalette.textTertiary.opacity(0.55) : color)
                            .frame(width: w, height: geo.size.height)
                            .offset(x: x0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(height: 20)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(StrandPalette.textPrimary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(isSelected ? StrandPalette.hairlineStrong : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(StrandMotion.fade) { selectedStage = isSelected ? nil : stage }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stage.label): \(durText(minutes)), \(percent) percent of the night")
        .accessibilityHint("Highlights this stage on the sleep chart")
        .accessibilityAddTraits(.isButton)
    }

    /// Tonight vs 30-day-typical for the tapped stage (Light/Deep/REM have a stored daily column to
    /// average; Awake doesn't, so it's shown without a typical rather than a derived estimate).
    @ViewBuilder private var stageInsight: some View {
        if let sel = selectedStage {
            let minutes = stageMinutes(sel)
            if let t = stageTypicalMinutes(sel) {
                let phrase = minutes > t * 1.15 ? "above your usual"
                           : minutes < t * 0.85 ? "below your usual" : "about your usual"
                Text("\(sel.label) \(durText(minutes)) tonight · typically \(durText(t)), \(phrase).")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            } else {
                Text("\(sel.label): \(durText(minutes)) tonight.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            }
        } else {
            Text("Tap a stage to compare with your 30-day typical.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
    }
    private func stageMinutes(_ stage: SleepStage) -> Double {
        switch stage {
        case .awake: return awakeMin
        case .light: return lightMin
        case .deep:  return deepMin
        case .rem:   return remMin
        }
    }
    private func stageTypicalMinutes(_ stage: SleepStage) -> Double? {
        switch stage {
        case .awake: return nil
        case .light: return mean { $0.lightMin }
        case .deep:  return mean { $0.deepMin }
        case .rem:   return mean { $0.remMin }
        }
    }
    private func clockText(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
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

/// The whole-night diagonal-hatched timeline track behind each stage lane's solid blocks — adapted
/// from `SleepView.StageHatchedTrack` (same visual language, private to that file so duplicated here
/// rather than exposed). Reads as "the whole night"; gaps (other stages) are implicit, nothing drawn.
private struct SleepHatchedTrack: View {
    var body: some View {
        ZStack {
            Rectangle().fill(StrandPalette.surfaceInset.opacity(0.9))
            Canvas { context, size in
                var path = Path()
                let step: CGFloat = 5
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += step
                }
                context.stroke(path, with: .color(StrandPalette.textTertiary.opacity(0.16)), lineWidth: 1)
            }
        }
    }
}

// MARK: - Overnight sample + synchronized scrubber

/// One real overnight heart-rate reading (bucketed mean) at a wall-clock time.
struct OvernightSample: Identifiable {
    let t: Date
    let bpm: Double
    var id: TimeInterval { t.timeIntervalSince1970 }
}

/// WHOOP-style interactive overnight panel. Draws the REAL overnight heart-rate curve on the same time
/// domain as the hypnogram, a stage ribbon beneath it, and a shared cursor the user taps/drags to read the
/// exact bpm, clock time and sleep stage at any moment. HRV / respiratory / SpO₂ are shown as the night's
/// AVERAGES (the only form NOOP stores for them) — labelled as averages, never drawn as invented curves.
private struct SleepOvernightPanel: View {
    let samples: [OvernightSample]
    let intervals: [SleepInterval]
    let nightStart: Date
    let nightEnd: Date
    let restingHr: Int?
    let nightlyHRV: Double?
    let nightlyResp: Double?
    let nightlySpO2: Double?

    /// Cursor position as a fraction of the night [0,1]; nil = not scrubbing (readout shows the average).
    @State private var cursorFrac: Double? = nil

    private var span: Double { max(1, nightEnd.timeIntervalSince(nightStart)) }
    private var bpms: [Double] { samples.map(\.bpm) }
    private var lo: Double { (bpms.min() ?? 40) - 4 }
    private var hi: Double { (bpms.max() ?? 120) + 4 }
    private var avgBpm: Double { bpms.isEmpty ? 0 : bpms.reduce(0, +) / Double(bpms.count) }

    private func fracOf(_ s: OvernightSample) -> Double { min(1, max(0, s.t.timeIntervalSince(nightStart) / span)) }
    private func stageAt(_ frac: Double) -> SleepStage? {
        let sec = frac * span
        return intervals.first { $0.start <= sec && sec < $0.end }?.stage
    }
    private func sampleAt(_ frac: Double) -> OvernightSample? {
        guard !samples.isEmpty else { return nil }
        return samples.min(by: { abs(fracOf($0) - frac) < abs(fracOf($1) - frac) })
    }
    private func stageColor(_ st: SleepStage) -> Color {
        switch st {
        case .awake: return StrandPalette.sleepAwake
        case .light: return StrandPalette.sleepLight
        case .deep:  return StrandPalette.sleepDeep
        case .rem:   return StrandPalette.sleepREM
        }
    }
    private let tint = StrandPalette.metricRose

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            readout
            GeometryReader { geo in
                let w = geo.size.width
                VStack(spacing: 6) {
                    hrChart.frame(height: 118)
                    ribbon.frame(height: 14)
                }
                .overlay(alignment: .leading) {
                    if let f = cursorFrac {
                        Rectangle().fill(StrandPalette.textSecondary.opacity(0.55))
                            .frame(width: 1).frame(maxHeight: .infinity)
                            .offset(x: w * CGFloat(f))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in cursorFrac = min(1, max(0, Double(v.location.x / max(1, w)))) }
                )
            }
            .frame(height: 118 + 6 + 14)
            axisRow
            referenceChips
        }
    }

    // MARK: Readout

    private var readout: some View {
        let bpm = cursorFrac.flatMap { sampleAt($0)?.bpm } ?? avgBpm
        let stage = cursorFrac.flatMap { stageAt($0) }
        let label = cursorFrac.map { timeLabel(at: $0) } ?? "AVG OVERNIGHT · TAP OR DRAG"
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(StrandFont.overline).tracking(1.2)
                    .foregroundStyle(StrandPalette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(bpm.rounded()))").font(.system(size: 30, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(tint)
                    Text("bpm").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    if let st = stage { stageChip(st) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                miniStat("AVG", avgBpm)
                miniStat("MIN", bpms.min() ?? 0)
                miniStat("MAX", bpms.max() ?? 0)
            }
        }
    }

    private func miniStat(_ label: String, _ v: Double) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(0.6)
                .foregroundStyle(StrandPalette.textTertiary)
            Text("\(Int(v.rounded()))").font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func stageChip(_ st: SleepStage) -> some View {
        Text(st.label).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(stageColor(st))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(stageColor(st).opacity(0.16)))
    }

    // MARK: HR chart (Canvas)

    private var hrChart: some View {
        Canvas { ctx, size in
            guard samples.count >= 2, hi > lo else { return }
            func pt(_ s: OvernightSample) -> CGPoint {
                let x = CGFloat(fracOf(s)) * size.width
                let y = CGFloat(1 - (s.bpm - lo) / (hi - lo)) * size.height
                return CGPoint(x: x, y: y)
            }
            let pts = samples.map(pt)
            var line = Path(); line.addLines(pts)
            var area = line
            area.addLine(to: CGPoint(x: pts.last!.x, y: size.height))
            area.addLine(to: CGPoint(x: pts.first!.x, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.30), tint.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(tint), lineWidth: 2)
            // Resting-HR baseline (real), dashed, when it's within the drawn range.
            if let rhr = restingHr, Double(rhr) >= lo, Double(rhr) <= hi {
                let y = CGFloat(1 - (Double(rhr) - lo) / (hi - lo)) * size.height
                var base = Path(); base.move(to: CGPoint(x: 0, y: y)); base.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(base, with: .color(StrandPalette.metricCyan.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            // Cursor dot on the line at the scrub position.
            if let f = cursorFrac, let s = sampleAt(f) {
                let p = pt(s)
                let r: CGFloat = 4.5
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(tint))
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(StrandPalette.surfaceBase), lineWidth: 1.5)
            }
        }
    }

    // MARK: Stage ribbon (synchronized)

    private var ribbon: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(StrandPalette.surfaceInset)
                ForEach(intervals) { iv in
                    let x0 = CGFloat(min(1, max(0, iv.start / span))) * geo.size.width
                    let x1 = CGFloat(min(1, max(0, iv.end / span))) * geo.size.width
                    Rectangle().fill(stageColor(iv.stage).opacity(0.9))
                        .frame(width: max(1, x1 - x0))
                        .offset(x: x0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    // MARK: Axis + references

    private var axisRow: some View {
        HStack {
            Text(clock(nightStart)).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Spacer()
            Text(clock(nightStart.addingTimeInterval(span / 2))).font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
            Spacer()
            Text(clock(nightEnd)).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private var referenceChips: some View {
        // Nightly AVERAGES for the signals NOOP stores only as aggregates — shown as reference values, not
        // fabricated overnight curves.
        let items: [(String, String, Color)] = [
            nightlyHRV.map { ("HRV", "\(Int($0.rounded())) ms", StrandPalette.metricCyan) },
            nightlyResp.map { ("Respiratory", String(format: "%.1f rpm", $0), StrandPalette.recoveryColor(80)) },
            nightlySpO2.map { ("SpO₂", "\(Int($0.rounded()))%", StrandPalette.metricPurple) },
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 8) {
            if !items.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                        HStack(spacing: 5) {
                            Circle().fill(it.2).frame(width: 7, height: 7)
                            Text("\(it.0) \(it.1)").font(.system(size: 11, weight: .medium))
                                .foregroundStyle(StrandPalette.textSecondary)
                            Text("avg").font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(StrandPalette.surfaceInset))
                    }
                }
            }
            Text("Heart rate is measured continuously overnight. HRV, respiratory rate and blood oxygen are stored as nightly averages, so they're shown as reference values — never as invented minute-by-minute curves.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Formatting

    private func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
    private func timeLabel(at frac: Double) -> String {
        clock(nightStart.addingTimeInterval(frac * span))
    }
}
#endif
