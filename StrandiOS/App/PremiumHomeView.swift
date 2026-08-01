#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Phase 2 · Home — the approved Premium UI prototype's flagship dashboard, rebuilt
/// natively in SwiftUI on the REAL app data (`Repository` → `DailyMetric`): a
/// recovery-ring hero with day-strain + sleep, an AI "Today's Story", a per-signal
/// live-vitals grid, a sleep summary, recovery drivers and a recommendation.
///
/// Every value is read from `repo.today` / `repo.days` (most-recent-non-nil carry for
/// metrics an unscored today hasn't filled yet) — nothing is hardcoded. It reuses the
/// shipping `StrandDesign` components (`RecoveryRing`, `StrandCard`, `Sparkline`), so it
/// inherits the Phase-1 re-skinned palette automatically. Compiled into the app module
/// alongside `Strand/**`, so `Repository`/`NavRouter`/`scrollToTopSignal` are all visible.
struct PremiumHomeView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var router: NavRouter
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal
    @State private var showReadiness = false

    // MARK: Data helpers (real Repository data)

    /// Most-recent non-nil value of a metric across banked days (mirrors how the
    /// existing Today view carries prior-night vitals into an unscored today).
    private func latest<T>(_ key: (DailyMetric) -> T?) -> T? {
        for d in repo.days.reversed() { if let v = key(d) { return v } }
        return repo.today.flatMap(key)
    }
    /// Last `n` non-nil samples of a Double metric, oldest→newest, for a sparkline.
    private func series(_ key: (DailyMetric) -> Double?, _ n: Int = 14) -> [Double] {
        Array(repo.days.suffix(90).compactMap(key).suffix(n))
    }

    private var recovery: Double? { latest { $0.recovery } }
    private var strain: Double?   { latest { $0.strain } }
    private var hrv: Double?      { latest { $0.avgHrv } }
    private var rhr: Int?         { latest { $0.restingHr } }
    private var resp: Double?     { latest { $0.respRateBpm } }
    private var spo2: Double?     { latest { $0.spo2Pct } }
    private var skinTemp: Double? { latest { $0.skinTempDevC } }
    /// `DailyMetric.efficiency` is stored as a FRACTION in [0,1] (see `SleepStageTotals.DailySleep`'s
    /// own doc), not a 0-100 percentage — normalized here (same defensive `<= 1.0 ? *100 : as-is`
    /// conversion `SleepView.efficiencyPct` uses) so a raw 0.92 reads "92%", not "1%".
    private var efficiencyRaw: Double? { latest { $0.efficiency } }
    private var efficiency: Double? { efficiencyRaw.map { $0 <= 1.0 ? $0 * 100 : $0 } }
    private var sleepMin: Double? { latest { $0.totalSleepMin } }
    private var deepMin: Double  { latest { $0.deepMin } ?? 0 }
    private var remMin: Double   { latest { $0.remMin } ?? 0 }
    private var lightMin: Double { latest { $0.lightMin } ?? 0 }

    // MARK: Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 1).id("top")
                    header
                    hero.contentShape(Rectangle()).onTapGesture { showReadiness = true }
                    storyCard
                    vitalsSection
                    sleepCard
                    driversCard
                    recommendationCard
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 96)   // clear the floating tab bar
            }
            .background(ambient.ignoresSafeArea())
            .onChange(of: scrollToTopSignal) { _, _ in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
            }
            .sheet(isPresented: $showReadiness) {
                NavigationStack {
                    PremiumReadinessView()
                        .navigationTitle("Readiness")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showReadiness = false }
                                    .foregroundStyle(StrandPalette.accent)
                            }
                        }
                }
            }
        }
    }

    // MARK: Ambient background (prototype's living glow)

    private var ambient: some View {
        ZStack {
            StrandPalette.surfaceBase
            RadialGradient(colors: [StrandPalette.effortColor.opacity(0.12), .clear],
                           center: .init(x: 0.1, y: 0.02), startRadius: 0, endRadius: 340)
            RadialGradient(colors: [StrandPalette.sleepDeep.opacity(0.12), .clear],
                           center: .init(x: 1.0, y: 0.0), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [StrandPalette.recoveryColor(80).opacity(0.07), .clear],
                           center: .init(x: 0.5, y: 1.0), startRadius: 0, endRadius: 380)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateEyebrow).font(StrandFont.overline).tracking(1.4)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("Today").font(StrandFont.title1)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer()
            Circle()
                .fill(AngularGradient(gradient: StrandPalette.goldGradient, center: .center))
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .overlay(Image(systemName: "person.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StrandPalette.surfaceBase))
        }
    }

    // MARK: Hero — recovery ring + strain + sleep

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            RecoveryRing(score: recovery ?? 0, diameter: 168, lineWidth: 13,
                         showsWordmark: false, showsHover: false)
            VStack(alignment: .leading, spacing: 18) {
                heroStat(label: "Day Strain", value: strain,
                         format: { strain == nil ? "—" : String(format: "%.1f", $0) },
                         fraction: (strain ?? 0) / 21.0,
                         tint: StrandPalette.effortColor, sub: "of 21")
                heroStat(label: "Sleep", value: efficiency,
                         format: { efficiency == nil ? "—" : "\(Int($0))%" },
                         fraction: (efficiency ?? 0) / 100.0,
                         tint: StrandPalette.sleepDeep, sub: sleepHoursText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func heroStat(label: String, value: Double?, format: @escaping (Double) -> String,
                          fraction: Double, tint: Color, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(StrandFont.overline).tracking(1.2)
                .foregroundStyle(StrandPalette.textTertiary)
            CountUpText(value: value ?? 0, format: format,
                        font: .system(size: 30, weight: .heavy, design: .default),
                        color: StrandPalette.textPrimary)
                .monospacedDigit()
            MiniBar(fraction: fraction, tint: tint)
            Text(sub).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
    }

    // MARK: AI story

    private var storyCard: some View {
        StrandCard(tint: StrandPalette.gold) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle().fill(AngularGradient(gradient: StrandPalette.goldGradient, center: .center))
                        .frame(width: 26, height: 26)
                    Text("TODAY'S STORY").font(StrandFont.overline).tracking(1.4)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Text(storyText).font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
    }

    private var storyText: String {
        guard let rec = recovery else { return "Pair your strap to see today's story and recovery." }
        let band = rec >= 67 ? "recovered and ready" : rec >= 34 ? "moderately recovered" : "under-recovered"
        var s = "You're \(band) at \(Int(rec.rounded()))%."
        if let h = hrv { s += " HRV is \(Int(h.rounded())) ms" }
        if let r = rhr { s += ", resting heart rate \(r) bpm." } else { s += "." }
        if rec >= 67 { s += " Your body can absorb a solid session today." }
        else if rec >= 34 { s += " Train with intent, but leave a little in the tank." }
        else { s += " Prioritise rest and recovery today." }
        return s
    }

    // MARK: Live vitals grid

    private var vitalsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Live vitals")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14)], spacing: 14) {
                vitalCard(icon: "heart.fill", tint: StrandPalette.metricRose, label: "Resting HR",
                          value: rhr.map(String.init) ?? "—", unit: "bpm",
                          spark: series { $0.restingHr.map(Double.init) })
                vitalCard(icon: "waveform.path.ecg", tint: StrandPalette.metricCyan, label: "HRV",
                          value: hrv.map { String(Int($0.rounded())) } ?? "—", unit: "ms",
                          spark: series { $0.avgHrv })
                vitalCard(icon: "lungs.fill", tint: StrandPalette.recoveryColor(80), label: "Respiratory",
                          value: resp.map { String(format: "%.1f", $0) } ?? "—", unit: "rpm",
                          spark: series { $0.respRateBpm })
                vitalCard(icon: "drop.fill", tint: StrandPalette.metricPurple, label: "Blood oxygen",
                          value: spo2.map { String(Int($0.rounded())) } ?? "—", unit: "%",
                          spark: series { $0.spo2Pct })
            }
        }
    }

    private func vitalCard(icon: String, tint: Color, label: String, value: String, unit: String, spark: [Double]) -> some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 8) {
                iconTile(icon, tint: tint)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 28, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                if spark.count >= 2 {
                    Sparkline(values: spark,
                              gradient: Gradient(colors: [tint, tint.opacity(0.55)]),
                              lineWidth: 2, showsArea: true, showsHead: true, showsHover: false)
                        .frame(height: 34)
                } else {
                    Color.clear.frame(height: 34)
                }
            }
        }
    }

    // MARK: Sleep summary

    /// Sleep-score ring fill — draws in on appear/change, the same `StrandMotion.drawIn` curve the
    /// Sleep tab's own hero ring uses (matches the HTML's Home sleep-row ring, previously text-only here).
    @State private var animatedSleepRingFraction: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Sleep")
            StrandCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 18) {
                        sleepRing
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sleepHoursText).font(.system(size: 22, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(StrandPalette.textPrimary)
                            stageKey("Deep", StrandPalette.sleepDeep, deepMin)
                            stageKey("REM", StrandPalette.sleepREM, remMin)
                            stageKey("Light", StrandPalette.sleepLight, lightMin)
                        }
                        Spacer(minLength: 0)
                    }
                    stageBar
                }
            }
        }
    }

    private var sleepRing: some View {
        let frac = min(1, max(0, (efficiency ?? 0) / 100))
        return ZStack {
            Circle().stroke(StrandPalette.surfaceInset, lineWidth: 10)
            Circle().trim(from: 0, to: animatedSleepRingFraction)
                .stroke(LinearGradient(colors: [StrandPalette.sleepREM, StrandPalette.sleepDeep],
                                       startPoint: .topTrailing, endPoint: .bottomLeading),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: StrandPalette.sleepDeep.opacity(0.4), radius: 6)
            VStack(spacing: 0) {
                CountUpText(value: efficiency ?? 0,
                            format: { efficiency == nil ? "—" : "\(Int($0))" },
                            font: .system(size: 26, weight: .heavy),
                            color: StrandPalette.textPrimary)
                    .monospacedDigit()
                Text("SCORE").font(.system(size: 8, weight: .bold)).tracking(0.6)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .frame(width: 96, height: 96)
        .onAppear { withAnimation(StrandMotion.drawIn(reduced: reduceMotion)) { animatedSleepRingFraction = frac } }
        .onChange(of: frac) { _, new in
            withAnimation(StrandMotion.drawIn(reduced: reduceMotion)) { animatedSleepRingFraction = new }
        }
    }

    private var stageBar: some View {
        let total = max(1, deepMin + remMin + lightMin)
        return GeometryReader { geo in
            HStack(spacing: 3) {
                segment(deepMin / total, geo.size.width, StrandPalette.sleepDeep)
                segment(remMin / total, geo.size.width, StrandPalette.sleepREM)
                segment(lightMin / total, geo.size.width, StrandPalette.sleepLight)
            }
        }
        .frame(height: 12)
    }

    private func segment(_ frac: Double, _ width: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: max(2, width * CGFloat(frac)))
    }

    private func stageKey(_ name: String, _ color: Color, _ minutes: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text(durText(minutes)).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textTertiary)
        }
    }

    // MARK: Recovery drivers

    private var driversCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Recovery drivers")
            StrandCard {
                VStack(spacing: 0) {
                    driverRow("HRV", hrv.map { "\(Int($0.rounded())) ms" } ?? "—",
                              frac: (hrv ?? 0) / 140.0, tint: StrandPalette.metricCyan)
                    hairlineRule
                    driverRow("Resting HR", rhr.map { "\($0) bpm" } ?? "—",
                              frac: rhr.map { max(0, min(1, (80.0 - Double($0)) / 45.0)) } ?? 0,
                              tint: StrandPalette.metricRose)
                    hairlineRule
                    driverRow("Sleep", efficiency.map { "\(Int($0))%" } ?? "—",
                              frac: (efficiency ?? 0) / 100.0, tint: StrandPalette.sleepDeep)
                    hairlineRule
                    driverRow("Respiratory", resp.map { String(format: "%.1f rpm", $0) } ?? "—",
                              frac: resp.map { max(0, min(1, 1 - abs($0 - 14) / 8)) } ?? 0,
                              tint: StrandPalette.recoveryColor(80))
                    if let st = skinTemp {
                        hairlineRule
                        driverRow("Skin temp", String(format: "%+.1f°C", st),
                                  frac: max(0, min(1, 1 - abs(st) / 1.5)), tint: StrandPalette.gold)
                    }
                }
            }
        }
    }

    private func driverRow(_ name: String, _ value: String, frac: Double, tint: Color) -> some View {
        HStack(spacing: 12) {
            Text(name).font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 92, alignment: .leading)
            MiniBar(fraction: frac, tint: tint)
            Text(value).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 11)
    }

    // MARK: Recommendation

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Recommended today")
            StrandCard(tint: StrandPalette.accent) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        iconTile("flame.fill", tint: StrandPalette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recTitle).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                            Text(recSub).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    Button {
                        router.requestQuickActions()
                    } label: {
                        Text("Start activity")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.goldDeepText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(StrandPalette.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recTitle: String {
        guard let rec = recovery else { return "Ease in gently" }
        return rec >= 67 ? "Push · build the base" : rec >= 34 ? "Moderate effort" : "Recover & restore"
    }
    private var recSub: String {
        guard let rec = recovery else { return "Not enough data yet — a light day is a safe default." }
        if rec >= 67 { return "You can handle a strong session — aim for a strain of 14–16 without denting tomorrow." }
        if rec >= 34 { return "Keep it aerobic today; save the intensity for a greener day." }
        return "Low recovery — favour rest, mobility and an early night."
    }

    // MARK: Small shared pieces

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
    }
    private var hairlineRule: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
    }
    private func iconTile(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(tint.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }

    // MARK: Formatting

    private var dateEyebrow: String {
        let f = DateFormatter(); f.dateFormat = "EEEE · MMM d"
        return f.string(from: Date()).uppercased()
    }
    private var sleepHoursText: String {
        guard let m = sleepMin, m > 0 else { return "—" }
        return durText(m)
    }
    private func durText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded()); let h = m / 60, mm = m % 60
        return h > 0 ? "\(h)h \(mm)m" : "\(mm)m"
    }
}

// MARK: - Mini progress bar

private struct MiniBar: View {
    let fraction: Double
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.surfaceInset)
                Capsule().fill(LinearGradient(colors: [tint, tint.opacity(0.7)],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 7)
    }
}
#endif
