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
    @EnvironmentObject var profile: ProfileStore
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal
    @State private var showReadiness = false
    @State private var showSettings = false
    /// The user's Home dashboard configuration — which metric cards show, in what order, and
    /// whether the grid renders compact. Persisted in `UserDefaults` by the store itself.
    @StateObject private var layout = PremiumHomeLayoutStore()
    @State private var showEditHome = false
    /// Deterministic findings (baseline deviations, trends, associations) computed from the user's
    /// own history by `PremiumAnalysis` — never model-generated.
    @State private var findings: [PremiumFinding] = []
    @State private var journalStreak: Int = 0
    @State private var journalLoggedToday = false
    /// Distinct factors logged today — drives the "N factors recorded" line on the Journal card.
    @State private var journalTodayCount = 0

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
    private var activeKcal: Double? { latest { $0.activeKcalEst } }
    private var steps: Int?         { latest { $0.steps } }
    private var workouts: Int?      { latest { $0.exerciseCount } }
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
                    hero
                    quickStatsRow
                    storyCard
                    journalQuickCard
                    insightsCard
                    weekOverviewCard
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
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    PremiumSettingsView()
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showSettings = false }
                                    .foregroundStyle(StrandPalette.accent)
                            }
                        }
                }
            }
            .sheet(isPresented: $showEditHome) {
                NavigationStack {
                    PremiumEditHomeView(layout: layout)
                        .navigationTitle(Text("Edit Home", comment: "Home customisation sheet title"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showEditHome = false }
                                    .foregroundStyle(StrandPalette.accent)
                            }
                        }
                }
            }
            .task(id: repo.refreshSeq) { await loadInsights() }
        }
    }

    /// Computes the personal findings and journal status. Runs off the main actor for the heavy
    /// correlation work, then publishes the results.
    private func loadInsights() async {
        let entries = await repo.journalEntries()
        let loggedDays = Set(entries.filter(\.answeredYes).map(\.day))
        let streak = PremiumCoachContext.streak(days: loggedDays)
        let todayKey = Repository.localDayKey(Date())
        let today = loggedDays.contains(todayKey)
        // Distinct factors recorded today — the card states what's actually logged rather than
        // just "done", so a partially-filled day is visible at a glance.
        let todayCount = Set(entries.filter { $0.day == todayKey && $0.answeredYes }
                                    .map(\.question)).count

        // Baseline + relationship findings across the headline signals.
        var out: [PremiumFinding] = []
        for id in [PremiumMetricID.hrv, .restingHr, .recovery, .sleepDuration] {
            let a = PremiumMetricCatalog.analysis(id, repo: repo)
            let d = PremiumMetricCatalog.def(id)
            if let f = PremiumAnalysis.baselineFinding(a, name: d.shortName, unit: d.unit, tint: d.tint) {
                out.append(f)
            }
        }
        let sleepSeries = PremiumMetricCatalog.series(.sleepDuration, repo: repo)
        let recoverySeries = PremiumMetricCatalog.series(.recovery, repo: repo)
        if let best = PremiumAnalysis.bestRelationship(sleepSeries, recoverySeries),
           let f = PremiumAnalysis.relationshipFinding(
            id: "home.rel.sleep.recovery", aName: "Sleep duration", bName: "Recovery",
            correlation: best.correlation, lagDays: best.lagDays, tint: StrandPalette.sleepDeep) {
            out.append(f)
        }
        out.sort { $0.confidence > $1.confidence }

        findings = out
        journalStreak = streak
        journalLoggedToday = today
        journalTodayCount = todayCount
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
        HStack(alignment: .center, spacing: 12) {
            BrandMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(dateEyebrow).font(StrandFont.overline).tracking(1.4)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("Today").font(StrandFont.title1)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer()
            // The profile/settings shortcut — previously a static, non-functional placeholder;
            // now opens the real Settings screen, matching the prototype's avatar-taps-to-Settings.
            Button { showSettings = true } label: {
                Circle()
                    .fill(AngularGradient(gradient: StrandPalette.goldGradient, center: .center))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .overlay(Image(systemName: "person.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StrandPalette.surfaceBase))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    // MARK: Hero — recovery ring + strain + sleep

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            // Tapping the recovery ring opens the Readiness detail sheet (unchanged); the strain stat
            // deep-links into the native Strain screen so each hero element has its own destination.
            RecoveryRing(score: recovery ?? 0, diameter: 168, lineWidth: 13,
                         showsWordmark: false, showsHover: false)
                .contentShape(Circle())
                .onTapGesture { showReadiness = true }
            VStack(alignment: .leading, spacing: 18) {
                NavigationLink(value: PremiumRoute.strain) {
                    heroStat(label: "Day Strain", value: strain,
                             format: { strain == nil ? "—" : String(format: "%.1f", $0) },
                             fraction: (strain ?? 0) / 21.0,
                             tint: StrandPalette.effortColor, sub: "of 21", showsChevron: true)
                }
                .buttonStyle(.plain)
                heroStat(label: "Sleep", value: efficiency,
                         format: { efficiency == nil ? "—" : "\(Int($0))%" },
                         fraction: (efficiency ?? 0) / 100.0,
                         tint: StrandPalette.sleepDeep, sub: sleepHoursText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func heroStat(label: String, value: Double?, format: @escaping (Double) -> String,
                          fraction: Double, tint: Color, sub: String, showsChevron: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(label.uppercased()).font(StrandFont.overline).tracking(1.2)
                    .foregroundStyle(StrandPalette.textTertiary)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            CountUpText(value: value ?? 0, format: format,
                        font: .system(size: 30, weight: .heavy, design: .default),
                        color: StrandPalette.textPrimary)
                .monospacedDigit()
            MiniBar(fraction: fraction, tint: tint)
            Text(sub).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
    }

    // MARK: Quick stats — real signals not otherwise surfaced as their own tile on Home

    private var quickStatsRow: some View {
        HStack(spacing: 12) {
            quickStat(icon: "figure.run", tint: StrandPalette.effortColor, label: "Workouts",
                      value: workouts.map(String.init) ?? "0", unit: "")
            quickStat(icon: "bed.double.fill", tint: StrandPalette.sleepDeep, label: "Time asleep",
                      value: sleepMin.map { durText($0) } ?? "—", unit: "")
            quickStat(icon: "thermometer.medium", tint: StrandPalette.gold, label: "Skin temp",
                      value: skinTemp.map { String(format: "%+.1f", $0) } ?? "—",
                      unit: skinTemp == nil ? "" : "°C")
        }
    }
    private func quickStat(icon: String, tint: Color, label: String, value: String, unit: String) -> some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 8) {
                iconTile(icon, tint: tint)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).font(.system(size: 20, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                    if !unit.isEmpty {
                        Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: AI story

    private var storyCard: some View {
        StrandCard(tint: StrandPalette.gold) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle().fill(AngularGradient(gradient: StrandPalette.goldGradient, center: .center))
                        .frame(width: 26, height: 26)
                    Text("TODAY'S STORY", comment: "Home narrative card label").font(StrandFont.overline).tracking(1.4)
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

    // MARK: Journal quick check-in (fast access — one tap from Home)

    /// A prominent Home shortcut into the Journal, so logging is never buried in a menu. Shows
    /// today's status and the current streak, and opens the journal sheet directly.
    private var journalQuickCard: some View {
        Button {
            router.openJournal()
        } label: {
            StrandCard(tint: journalLoggedToday ? StrandPalette.recoveryColor(85) : StrandPalette.gold) {
                HStack(spacing: 14) {
                    iconTile(journalLoggedToday ? "checkmark.seal.fill" : "square.and.pencil",
                             tint: journalLoggedToday ? StrandPalette.recoveryColor(85) : StrandPalette.gold)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(journalLoggedToday ? String(localized: "Logged today") : String(localized: "Log today's check-in"))
                            .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        Text(journalSubtitle)
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(journalLoggedToday ? String(localized: "Journal, logged today") : String(localized: "Log today's journal check-in"))
    }

    private var journalSubtitle: String {
        // State the concrete thing that's true today first — "3 factors recorded" is more useful
        // than a generic nudge, and makes a half-finished check-in visible.
        if journalTodayCount > 0 {
            let recorded = String(format: String(localized: "%1$d factor(s) recorded"), journalTodayCount)
            return journalStreak >= 2
                ? recorded + " · " + String(format: String(localized: "%1$d-day streak"), journalStreak)
                : recorded
        }
        if journalStreak >= 2 {
            return String(format: String(localized: "%1$d-day streak · a few taps"), journalStreak)
        }
        return "Takes a few taps — powers your personal patterns"
    }

    // MARK: Personal insights (deterministic — computed, never model-generated)

    /// The top computed findings from `PremiumAnalysis`: baseline deviations, sustained trends and
    /// journal associations, each carrying its own confidence label. This is also exactly what the
    /// future Coach is handed, so what the user reads here and what the Coach explains agree.
    @ViewBuilder private var insightsCard: some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Your patterns")
                StrandCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(findings.prefix(3))) { f in
                            PremiumFindingRow(finding: f)
                        }
                        Text("Computed on-device from your own history. Associations, not causes.", comment: "Findings disclaimer")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: This week — recovery/strain/sleep at a glance

    /// A 7-day mini bar chart for recovery, strain and sleep, real `repo.days` history scaled to
    /// each metric's own natural range (0–100 for recovery/sleep, 0–21 for strain — the same WHOOP
    /// strain scale used everywhere else) rather than a per-week min/max, so a bar's height is
    /// comparable day to day. A day with no recorded value draws a faint placeholder, never a
    /// fabricated bar.
    private var weekOverviewCard: some View {
        let days = Array(repo.days.suffix(7))
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("This week")
            StrandCard {
                VStack(alignment: .leading, spacing: 14) {
                    weekRow("Recovery", tint: StrandPalette.recoveryColor(80), days: days,
                            key: { $0.recovery }, span: 100)
                    weekRow("Strain", tint: StrandPalette.effortColor, days: days,
                            key: { $0.strain }, span: 21)
                    weekRow("Sleep", tint: StrandPalette.sleepDeep, days: days,
                            key: { $0.efficiency.map { $0 <= 1.0 ? $0 * 100 : $0 } }, span: 100)
                    weekDayLabels(days)
                }
            }
        }
    }
    private func weekRow(_ label: String, tint: Color, days: [DailyMetric],
                         key: @escaping (DailyMetric) -> Double?, span: Double) -> some View {
        HStack(spacing: 10) {
            Text(label).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                .frame(width: 64, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    let v = key(d)
                    VStack {
                        Spacer(minLength: 0)
                        Capsule().fill(v == nil ? StrandPalette.surfaceInset : tint)
                            .frame(height: v.map { 3 + CGFloat(max(0, min(1, $0 / span))) * 20 } ?? 3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 26)
        }
    }
    private func weekDayLabels(_ days: [DailyMetric]) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 64)
            HStack(spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    Text(dayAbbrev(d.day)).font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
    private func dayAbbrev(_ key: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: key) else { return "" }
        let out = DateFormatter(); out.dateFormat = "EEE"
        return String(out.string(from: date).prefix(1))
    }

    // MARK: Live vitals grid

    /// The customisable metric grid. Driven entirely by `PremiumHomeLayoutStore` over the full
    /// `PremiumMetricCatalog`, so the user chooses which of the ~24 available signals appear, in
    /// what order, and whether cards render compact (value only) or expanded (value + trend).
    /// Metrics the device has never recorded are filtered out rather than shown empty.
    private var vitalsSection: some View {
        let ids: [PremiumMetricID] = layout.visible.filter { id in
            PremiumMetricCatalog.def(id).isDerived || !PremiumMetricCatalog.series(id, repo: repo).isEmpty
        }
        let columns: [GridItem] = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Your metrics")
                Spacer()
                Button { showEditHome = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .semibold))
                        Text("Edit").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(StrandPalette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Edit Home metrics", comment: "Accessibility label for the Edit Home button"))
            }
            if ids.isEmpty {
                StrandCard {
                    PremiumEmptyState(icon: "square.grid.2x2",
                                      title: "No metrics on Home",
                                      message: "Tap Edit to choose which health metrics appear here.")
                }
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ids) { id in
                        metricCard(id)
                    }
                }
            }
        }
    }

    /// One tappable metric tile, rendered from the catalog. Every card deep-links to a real detail
    /// screen; derived metrics (live HR, regularity…) route to the screen that owns them so a tap
    /// always lands somewhere useful.
    private func metricCard(_ id: PremiumMetricID) -> some View {
        let d: PremiumMetricDef = PremiumMetricCatalog.def(id)
        let value: Double? = metricValue(id)
        let spark: [Double] = layout.compact ? [] : Array(
            PremiumMetricCatalog.series(id, repo: repo).suffix(14).map(\.value))
        return NavigationLink(value: route(for: id)) {
            StrandCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        iconTile(d.icon, tint: d.tint)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value.map { d.format($0, withUnit: false) } ?? "—")
                            .font(.system(size: 26, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        if !d.unit.isEmpty && value != nil {
                            Text(d.unit).font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                    Text(d.shortName).font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineLimit(1)
                    if !layout.compact {
                        if spark.count >= 2 {
                            Sparkline(values: spark,
                                      gradient: Gradient(colors: [d.tint, d.tint.opacity(0.55)]),
                                      lineWidth: 2, showsArea: true, showsHead: true, showsHover: false)
                                .frame(height: 34)
                        } else {
                            Color.clear.frame(height: 34)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Current value for a catalog metric. Derived metrics that Home can resolve cheaply (energy
    /// totals, sleep balance) are computed here; the rest report nil and their card shows "—".
    private func metricValue(_ id: PremiumMetricID) -> Double? {
        switch id {
        case .liveHeartRate:
            return nil                                    // live-only; the Heart tab owns it
        case .restingEnergy:
            return restingKcalEstimate
        case .totalEnergy:
            guard let a = activeKcal, let r = restingKcalEstimate else { return nil }
            return a + r
        case .journalStatus:
            return Double(journalStreak)
        case .sleepRegularity, .sleepBalance, .bedtime, .wakeTime, .stressLoad:
            return nil                                    // owned by the Sleep / Heart screens
        default:
            return PremiumMetricCatalog.latest(id, repo: repo)
        }
    }

    /// Resting energy is not a stored column — it is a Mifflin–St Jeor BMR estimate from the
    /// user's profile, the SAME formula `PremiumEnergyView.restingKcal` uses so the two screens
    /// can never disagree. Returns nil when the profile lacks weight/height/age, so the card shows
    /// "—" rather than a fabricated figure.
    private var restingKcalEstimate: Double? {
        let w = profile.weightKg, h = profile.heightCm, a = Double(profile.age)
        guard w > 0, h > 0, a > 0 else { return nil }
        let constant: Double
        switch profile.sex.lowercased() {
        case "male":   constant = 5
        case "female": constant = -161
        default:       constant = -78   // neutral midpoint for non-binary / unspecified
        }
        return 10 * w + 6.25 * h - 5 * a + constant
    }

    private func route(for id: PremiumMetricID) -> PremiumRoute {
        switch id {
        case .spo2:                       return .bloodOxygen
        case .activeEnergy, .totalEnergy, .restingEnergy: return .energy
        case .strain, .workouts:          return .strain
        default:                          return .catalogMetric(id)
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
                Text("SCORE", comment: "Sleep ring label on Home").font(.system(size: 8, weight: .bold)).tracking(0.6)
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
                        Text("Start activity", comment: "Home recommendation button")
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
