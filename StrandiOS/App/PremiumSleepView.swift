#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// Phase 3 · Sleep — a real sleep-analysis dashboard on the user's own recorded nights.
///
/// The centrepiece is `SleepNightPanel`: last night's stage timeline and overnight heart rate are
/// ONE connected instrument rather than two cards repeating each other. Tapping a stage isolates it
/// everywhere at once — the ribbon dims every other stage and the heart-rate chart shades exactly
/// the windows that stage occupied — while the HR curve itself stays fully drawn so physiology
/// remains comparable across stages. Dragging anywhere on the chart reads out the precise time,
/// heart rate and stage at that moment.
///
/// Around it sit the analyses that make a night interpretable rather than merely described:
/// continuity (WASO, awakenings, longest wake), regularity (a timing map plus bed/wake/midpoint
/// variability), timing trends against personal baselines, sleep balance versus personal need, and
/// overnight vitals each compared to their own 30-day baseline.
///
/// All sleep intelligence comes from `PremiumSleepIntel`, shared with the Coach context so the
/// screen and the Coach can never disagree. Every figure is real: nights with impossible windows
/// are rejected upstream, and any section without enough history says so instead of estimating.
struct PremiumSleepView: View {
    @EnvironmentObject var repo: Repository
    /// Needed to re-score the day after a sleep-window edit / nap add, so the dashboard aggregates
    /// (Rest, recovery) honour the change rather than only this screen's session view.
    @EnvironmentObject var intelligence: IntelligenceEngine
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal

    @State private var intel = PremiumSleepIntel(nights: [], latestIntervals: [], latestBed: nil,
                                                 latestWake: nil, overnightHR: [],
                                                 latestMainBlock: nil, latestDayNaps: [])
    @State private var selectedStage: SleepStage?
    @State private var findings: [PremiumFinding] = []
    /// Sleep-duration relationships, strongest first (computed in `load()`).
    @State private var sleepRelationships: [SleepRelationship] = []
    @State private var selectedSleepRelationship: String?

    // MARK: Real per-day values

    private func latest<T>(_ key: (DailyMetric) -> T?) -> T? {
        for d in repo.days.reversed() { if let v = key(d) { return v } }
        return repo.today.flatMap(key)
    }
    private func mean(_ key: (DailyMetric) -> Double?) -> Double? {
        PremiumAnalysis.mean(repo.days.suffix(30).compactMap(key))
    }

    private var efficiencyPct: Double? {
        latest { $0.efficiency }.map { $0 <= 1.0 ? $0 * 100 : $0 }
    }
    private var asleepMin: Double? { latest { $0.totalSleepMin } }
    private var inBedMin: Double? {
        // Prefer the REAL recorded window; fall back to deriving it from efficiency only when the
        // night has no session row. Never let a bad efficiency produce an absurd time-in-bed.
        if let n = intel.nights.last, n.inBedMin > 0 { return n.inBedMin }
        guard let asleep = asleepMin, let e = efficiencyPct, e > 20, e <= 100 else { return asleepMin }
        return asleep / (e / 100.0)
    }
    private var deepMin: Double { latest { $0.deepMin } ?? 0 }
    private var remMin: Double { latest { $0.remMin } ?? 0 }
    private var lightMin: Double { latest { $0.lightMin } ?? 0 }
    private var restorativeMin: Double { deepMin + remMin }
    private var sleepNeedMin: Double { max(450, mean { $0.totalSleepMin } ?? 450) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 1).id("top")
                    header
                    scoreHero
                    nightPanelSection
                    napsSection
                    findingsSection
                    continuitySection
                    scheduleSection
                    balanceSection
                    overnightVitalsSection
                    historySection
                    distributionSection
                    relationshipsSection
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
        .task(id: repo.refreshSeq) { await load() }
        // Manually add a missed nap (#508). Presents the SAME `SleepTimeEditor` the classic tab uses, so
        // every guard (future bed clamp, wake-date derived from bed) applies identically here.
        .sheet(item: $addNapSeed) { seed in
            SleepTimeEditor(bedTs: seed.bedTs, wakeTs: seed.wakeTs,
                            title: "Add a nap",
                            blurb: "Pick when the nap started and ended. NOOP stages it from your data as its own session, separate from the night's sleep.",
                            bedLabel: "Nap started", wakeLabel: "Nap ended") { startTs, endTs in
                await repo.addManualNap(startTs: startTs, endTs: endTs)
                // Re-score so the day's aggregates (Rest, recovery) pick up the new session, then refresh
                // the read cache — exactly the classic tab's order.
                await intelligence.analyzeRecent()
                await repo.refresh()
            }
        }
        // Correct or delete an existing block — a nap row, or the night's main sleep.
        .sheet(item: $sleepEdit) { edit in
            let coverageLo = min(edit.detectedStartTs, edit.bedTs)
            SleepTimeEditor(bedTs: edit.bedTs, wakeTs: edit.wakeTs,
                            title: edit.isNap ? "Edit nap times" : "Edit sleep times",
                            bedLabel: edit.isNap ? "Nap started" : "Asleep",
                            wakeLabel: edit.isNap ? "Nap ended" : "Woke",
                            deleteLabel: edit.isNap ? "Delete this nap" : "Delete this sleep",
                            coverage: coverageLo...max(edit.wakeTs, coverageLo + 1),
                            // A nap row is always manually added / hand-edited, so its delete writes NO
                            // re-detection tombstone — the confirm copy must not promise suppression (#65).
                            suppressesReDetection: !edit.userEdited,
                            onSave: { newBedTs, newWakeTs in
                await repo.editSleepTimes(detectedStartTs: edit.detectedStartTs, oldEndTs: edit.wakeTs,
                                          storedStagesJSON: edit.stagesJSON,
                                          newStartTs: newBedTs, newEndTs: newWakeTs)
                await intelligence.analyzeRecent()
                await repo.refresh()
            }, onDelete: {
                _ = await repo.deleteSleepSession(detectedStartTs: edit.detectedStartTs, endTs: edit.wakeTs)
                await intelligence.analyzeRecent()
                await repo.refresh()
            })
        }
    }

    // MARK: Naps + sleep-window corrections (#508 on iOS)

    /// Non-nil while the "Add a nap" picker is open; carries the seeded window.
    @State private var addNapSeed: PremiumNapSeed?
    /// Non-nil while an existing block's editor is open.
    @State private var sleepEdit: PremiumSleepEdit?

    /// The window the "Add a nap" picker opens on. Anchors an hour after the night's wake — the natural
    /// place to look for a missed afternoon nap — but only when that half-hour has already PASSED;
    /// otherwise it seeds the half-hour that just ended, which is always a valid, in-the-past window.
    /// (`SleepEditGuard` rejects a future end outright, so a seed must never be ahead of the clock.)
    private var napSeed: PremiumNapSeed {
        let w = SleepEditGuard.napSeedWindow(lastWakeTs: intel.latestMainBlock?.endTs,
                                             now: Int(Date().timeIntervalSince1970))
        return PremiumNapSeed(bedTs: w.start, wakeTs: w.end)
    }

    /// Naps — the day's sleep OUTSIDE the main night, each editable and deletable, plus the "Add nap"
    /// affordance that had no iOS home at all: it lives on the classic `SleepView`, which the iOS tab
    /// shell never presents (the Sleep tab is this screen), so there was no way to record a nap on
    /// iPhone. The split and the write path are the shared ones (`SleepView.mainNightGroup`,
    /// `Repository.addManualNap`), so a nap logged here reads identically everywhere else.
    ///
    /// The card is ALWAYS present, even with nothing recorded — an empty naps list is exactly when the
    /// user needs the add button, and the previous screen's silence is what made the feature look absent.
    @ViewBuilder private var napsSection: some View {
        let naps = intel.latestDayNaps
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PremiumSectionHeader(title: "Naps")
                Spacer()
                PremiumExplainer(
                    title: String(localized: "Naps"),
                    items: [
                        PremiumExplainerItem(question: String(localized: "What counts as a nap?"),
                                             answer: String(localized: "Any sleep recorded on this day other than your main night. A night briefly interrupted by a wake-up stays one night — its fragments are bridged, not split into naps.")),
                        PremiumExplainerItem(question: String(localized: "Why add one by hand?"),
                                             answer: String(localized: "If you slept without the strap, or it did not detect a short daytime sleep, adding the window lets NOOP count that rest toward the day.")),
                    ],
                    methodology: String(localized: "A nap you add is staged from your own recorded data over the window you pick and stored as its own session — never folded into the night's sleep. If the strap has no dense data there yet, it is stored as a single unstaged block and re-staged automatically once the raw data syncs."))
            }
            StrandCard {
                VStack(alignment: .leading, spacing: 14) {
                    if naps.isEmpty {
                        Text("No naps recorded for this day.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                    } else {
                        napSummaryRow(naps)
                        ForEach(naps, id: \.startTs) { nap in
                            Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                            napRow(nap)
                        }
                    }
                    Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                    HStack(spacing: 12) {
                        Button { addNapSeed = napSeed } label: {
                            Label("Add nap", systemImage: "plus.circle.fill")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.restColor)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add a nap")
                        Spacer(minLength: 8)
                        // Correcting the night's own window has the same problem as adding a nap: the
                        // affordance only existed on a screen iOS never shows.
                        if let main = intel.latestMainBlock {
                            Button {
                                sleepEdit = PremiumSleepEdit(detectedStartTs: main.startTs,
                                                             bedTs: main.effectiveStartTs,
                                                             wakeTs: main.endTs,
                                                             stagesJSON: main.stagesJSON,
                                                             userEdited: main.userEdited,
                                                             isNap: false)
                            } label: {
                                Label("Edit sleep times", systemImage: "pencil.circle")
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit last night's sleep times")
                        }
                    }
                }
            }
        }
    }

    /// Main / Naps / Total for a day that has at least one nap, so what drives the day's rest total stays
    /// explainable. Main is the bridged main-night group's real recorded span.
    @ViewBuilder private func napSummaryRow(_ naps: [CachedSleepSession]) -> some View {
        // Main comes from `latestMainBlock`, which is the SAME day as the naps by construction — reading
        // `nights.last` instead could straddle two days when the newest night was rejected as impossible.
        let mainMin = intel.latestMainBlock.map { Double($0.endTs - $0.effectiveStartTs) / 60.0 } ?? 0
        let napMin = naps.reduce(0.0) { $0 + Double($1.endTs - $1.effectiveStartTs) / 60.0 }
        HStack(spacing: 14) {
            if mainMin > 0 {
                statBlock("Main sleep", PremiumAnalysis.durText(mainMin), StrandPalette.sleepDeep)
            }
            statBlock("Naps", PremiumAnalysis.durText(napMin), StrandPalette.sleepREM)
            statBlock("Total", PremiumAnalysis.durText(mainMin + napMin), StrandPalette.restColor)
        }
    }

    private func napRow(_ nap: CachedSleepSession) -> some View {
        Button {
            sleepEdit = PremiumSleepEdit(detectedStartTs: nap.startTs,
                                         bedTs: nap.effectiveStartTs,
                                         wakeTs: nap.endTs,
                                         stagesJSON: nap.stagesJSON,
                                         // A nap row is manually added / hand-edited: never re-detected,
                                         // so its delete writes no tombstone.
                                         userEdited: true,
                                         isNap: true)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "powersleep")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.restColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.napWindowText(nap))
                        .font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                    Text(PremiumAnalysis.durText(Double(nap.endTs - nap.effectiveStartTs) / 60.0))
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "pencil.circle")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.restColor)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: String(localized: "Edit nap %@"), Self.napWindowText(nap)))
    }

    /// "9:20 PM – 9:55 PM" for a nap row, in the device's own 12-/24-hour setting.
    private static let napClockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
    private static func napWindowText(_ nap: CachedSleepSession) -> String {
        let start = napClockFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(nap.effectiveStartTs)))
        let end = napClockFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(nap.endTs)))
        return "\(start) – \(end)"
    }

    private func load() async {
        intel = await PremiumSleepIntel.load(repo: repo)
        var out: [PremiumFinding] = []
        // Bedtime drift: this week's nights against the week before.
        let bed = intel.bedtimeSeries(window: 30)
        if bed.count >= 10 {
            let recent = Array(bed.suffix(7))
            let prior = Array(bed.dropLast(7).suffix(7))
            if let f = PremiumAnalysis.timingFinding(id: "sleep.bedtime.drift", label: "bedtime",
                                                     recent: recent, prior: prior,
                                                     tint: StrandPalette.sleepDeep) {
                out.append(f)
            }
        }
        // Duration against its own baseline.
        let durA = PremiumMetricCatalog.analysis(.sleepDuration, repo: repo)
        if let f = PremiumAnalysis.baselineFinding(durA, name: "sleep duration", unit: "",
                                                   tint: StrandPalette.sleepREM) {
            out.append(f)
        }
        // Does sleep duration track next-day recovery for this person?
        let dur = PremiumMetricCatalog.series(.sleepDuration, repo: repo)
        let rec = PremiumMetricCatalog.series(.recovery, repo: repo)
        if let best = PremiumAnalysis.bestRelationship(dur, rec),
           let f = PremiumAnalysis.relationshipFinding(id: "sleep.rel.recovery",
                                                       aName: "Sleep duration", bName: "Recovery",
                                                       correlation: best.correlation,
                                                       lagDays: best.lagDays,
                                                       tint: StrandPalette.sleepDeep) {
            out.append(f)
        }
        findings = out.sorted { $0.confidence > $1.confidence }

        let rels = computeSleepRelationships()
        sleepRelationships = rels
        if let sel = selectedSleepRelationship, !rels.contains(where: { $0.id == sel }) {
            selectedSleepRelationship = nil
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

    // MARK: Score hero

    @State private var ringFraction: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scoreHero: some View {
        let frac: Double = min(1, max(0, (efficiencyPct ?? 0) / 100))
        return VStack(spacing: 12) {
            ZStack {
                Circle().stroke(StrandPalette.surfaceInset, lineWidth: 14)
                Circle().trim(from: 0, to: ringFraction)
                    .stroke(LinearGradient(colors: [StrandPalette.sleepREM, StrandPalette.sleepDeep],
                                           startPoint: .topTrailing, endPoint: .bottomLeading),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: StrandPalette.sleepDeep.opacity(0.5), radius: 10)
                VStack(spacing: 2) {
                    CountUpText(value: efficiencyPct ?? 0,
                                format: { self.efficiencyPct == nil ? "—" : "\(Int($0.rounded()))" },
                                font: .system(size: 58, weight: .heavy),
                                color: StrandPalette.textPrimary)
                        .monospacedDigit()
                    Text("EFFICIENCY", comment: "Sleep hero ring label").font(StrandFont.overline).tracking(1.4)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .frame(width: 208, height: 208)
            .onAppear { withAnimation(StrandMotion.drawIn(reduced: reduceMotion)) { ringFraction = frac } }
            .onChange(of: frac) { _, new in
                withAnimation(StrandMotion.drawIn(reduced: reduceMotion)) { ringFraction = new }
            }
            Text(heroSubtitle)
                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var heroSubtitle: String {
        guard let a = asleepMin, a > 0 else { return "No sleep recorded yet" }
        var s = "\(PremiumAnalysis.durText(a)) asleep"
        if let b = inBedMin, b > 0 { s += " · \(PremiumAnalysis.durText(b)) in bed" }
        return s
    }

    // MARK: The unified night panel (stages ↔ overnight heart rate)

    @ViewBuilder private var nightPanelSection: some View {
        if let bed = intel.latestBed, let wake = intel.latestWake,
           !intel.latestIntervals.isEmpty, wake > bed {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    PremiumSectionHeader(title: "Last night")
                    Spacer()
                    ProvenanceChip(provenance: .estimated)
                }
                StrandCard {
                    SleepNightPanel(intervals: intel.latestIntervals,
                                    hr: intel.overnightHR,
                                    nightStart: bed, nightEnd: wake,
                                    selected: $selectedStage,
                                    typicalMinutes: typicalStageMinutes)
                }
            }
        } else if intel.nights.isEmpty {
            StrandCard {
                PremiumEmptyState(icon: "bed.double",
                                  title: "No sleep recorded yet",
                                  message: "Wear your strap overnight and NOOP will build your sleep picture here.")
            }
        } else {
            StrandCard {
                MetricUnavailable(name: "Stage timeline",
                                  reason: "Last night has no minute-level stage data — an imported night stores only stage totals.")
            }
        }
    }

    /// 30-day typical minutes per stage, used for the "vs typical" comparison inside the panel.
    /// `nil` for a stage without a stored daily column (awake) so the panel omits the comparison
    /// rather than deriving a fake typical.
    private var typicalStageMinutes: [SleepStage: Double] {
        var out: [SleepStage: Double] = [:]
        if let d = mean({ $0.deepMin }) { out[.deep] = d }
        if let r = mean({ $0.remMin }) { out[.rem] = r }
        if let l = mean({ $0.lightMin }) { out[.light] = l }
        return out
    }

    // MARK: Findings

    @ViewBuilder private var findingsSection: some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "What changed")
                StrandCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(findings) { f in PremiumFindingRow(finding: f) }
                    }
                }
            }
        }
    }

    // MARK: Continuity

    @ViewBuilder private var continuitySection: some View {
        if !intel.latestIntervals.isEmpty {
            let waso: Double = intel.wasoMin
            let longest: Double = intel.longestAwakeMin
            let count: Int = intel.awakeningCount
            let effTypical: Double? = mean { $0.efficiency }.map { $0 <= 1 ? $0 * 100 : $0 }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    PremiumSectionHeader(title: "Continuity")
                    Spacer()
                    ProvenanceChip(provenance: .calculated)
                }
                StrandCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            statBlock("Awake in bed", PremiumAnalysis.durText(waso),
                                      StrandPalette.sleepAwake)
                            statBlock("Longest wake", PremiumAnalysis.durText(longest),
                                      StrandPalette.sleepAwake)
                            statBlock("Awakenings", "\(count)", StrandPalette.sleepLight)
                        }
                        if let e = efficiencyPct {
                            Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                            efficiencyRow(e, typical: effTypical)
                        }
                        Text("Time awake after first falling asleep, from your real decoded stage timeline. Sleep-onset latency is excluded — it isn't an awakening.", comment: "Sleep continuity footnote")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func efficiencyRow(_ value: Double, typical: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Efficiency").font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                Spacer()
                Text("\(Int(value.rounded()))%")
                    .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.sleepDeep)
                if let t = typical {
                    Text(String(format: String(localized: "typ %d%%"), Int(t.rounded())))
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            PremiumBar(fraction: value / 100, tint: StrandPalette.sleepDeep, height: 8)
        }
    }

    private func statBlock(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 20, weight: .heavy)).monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label.uppercased()).font(StrandFont.overline).tracking(1.0)
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Schedule (regularity + timing, merged)

    /// Your body clock as ONE section. Regularity and Timing used to be two sections that both
    /// described bed/wake/midpoint — one as ± variability stats, the other as three stacked line
    /// charts. Merged here: the score and the timing map give the shape, the ± row gives the
    /// numbers, and a SINGLE drift chart (re-aimable between bedtime, wake and midpoint) replaces
    /// the three near-identical charts.
    private enum ScheduleSeries: Hashable { case bedtime, wake, midpoint }
    @State private var scheduleSeries: ScheduleSeries = .bedtime

    @ViewBuilder private var scheduleSection: some View {
        if intel.nights.count >= 4 {
            let nights: [PremiumSleepIntel.Night] = Array(intel.nights.suffix(14))
            let score: Double? = intel.regularityScore()
            let values: [Double] = scheduleValues
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    PremiumSectionHeader(title: "Your schedule")
                    Spacer()
                    ProvenanceChip(provenance: .calculated)
                }
                StrandCard {
                    VStack(alignment: .leading, spacing: 16) {
                        if let s = score {
                            MetricValueHeader(value: "\(Int(s.rounded()))", unit: "/ 100",
                                              deltaText: nil, deltaGood: nil,
                                              caption: regularityCaption(s),
                                              tint: StrandPalette.metricCyan)
                        }
                        SleepTimingMap(nights: nights)
                        HStack(spacing: 14) {
                            statBlock("Bedtime ±", variabilityText(intel.bedtimeVariability()),
                                      StrandPalette.sleepDeep)
                            statBlock("Wake ±", variabilityText(intel.wakeVariability()),
                                      StrandPalette.metricAmber)
                            statBlock("Midpoint ±", variabilityText(intel.midpointVariability()),
                                      StrandPalette.metricCyan)
                        }
                        Text("Each bar is one night, positioned by clock time. The tighter they line up, the steadier your body clock.", comment: "Sleep timing map caption")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                        PremiumChipPicker<ScheduleSeries>(options: [
                            PremiumChipPicker<ScheduleSeries>.Option(
                                value: .bedtime, label: String(localized: "Bedtime"),
                                tint: StrandPalette.sleepDeep),
                            PremiumChipPicker<ScheduleSeries>.Option(
                                value: .wake, label: String(localized: "Wake time"),
                                tint: StrandPalette.metricAmber),
                            PremiumChipPicker<ScheduleSeries>.Option(
                                value: .midpoint, label: String(localized: "Midpoint"),
                                tint: StrandPalette.metricCyan),
                        ], selection: $scheduleSeries)
                        driftChart(values)
                        if let shift = intel.weekendShiftMinutes(), abs(shift) >= 10 {
                            Text(String(format: shift > 0
                                        ? String(localized: "Weekend bedtime runs %@ later than your weekdays.")
                                        : String(localized: "Weekend bedtime runs %@ earlier than your weekdays."),
                                      PremiumAnalysis.durText(abs(shift))))
                                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var scheduleValues: [Double] {
        switch scheduleSeries {
        case .bedtime:  return intel.bedtimeSeries(window: 30)
        case .wake:     return intel.wakeSeries(window: 30)
        case .midpoint: return intel.midpointSeries(window: 30)
        }
    }
    private var scheduleTint: Color {
        switch scheduleSeries {
        case .bedtime:  return StrandPalette.sleepDeep
        case .wake:     return StrandPalette.metricAmber
        case .midpoint: return StrandPalette.metricCyan
        }
    }

    /// The selected timing series against its own personal band, plus how far the last week has
    /// drifted from the weeks before it — so the chart states whether the schedule is moving, not
    /// just what it looks like.
    private func driftChart(_ values: [Double]) -> some View {
        let base: Double? = PremiumAnalysis.mean(values)
        let sd: Double? = PremiumAnalysis.stdev(values)
        let tint: Color = scheduleTint
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let b = base {
                    Text(String(format: String(localized: "typ %@"), PremiumSleepIntel.clockText(b)))
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer()
                if let drift = scheduleDrift(values) {
                    Text(drift).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            if values.count >= 2 {
                BaselineBandChart(values: values, baseline: base, spread: sd, tint: tint, height: 100,
                                  valueFormat: { PremiumSleepIntel.clockText($0) })
            } else {
                MetricUnavailable(name: String(localized: "Timing"),
                                  reason: "Need at least two nights.")
            }
        }
    }

    /// "38m later than the fortnight before" — the last 7 nights against the 7 before them.
    /// `nil` until both windows are full, and below a 10-minute floor that is just schedule noise.
    private func scheduleDrift(_ values: [Double]) -> String? {
        guard values.count >= 14 else { return nil }
        let recent = Array(values.suffix(7))
        let prior = Array(values.dropLast(7).suffix(7))
        guard let a = PremiumAnalysis.mean(recent), let b = PremiumAnalysis.mean(prior) else { return nil }
        let delta = a - b
        guard abs(delta) >= 10 else { return String(localized: "steady vs last week") }
        return String(format: delta > 0
                      ? String(localized: "%@ later than last week")
                      : String(localized: "%@ earlier than last week"),
                      PremiumAnalysis.durText(abs(delta)))
    }

    private func regularityCaption(_ score: Double) -> String {
        let band: String
        if score >= 80 { band = "Very consistent" }
        else if score >= 60 { band = "Fairly consistent" }
        else if score >= 40 { band = "Variable" }
        else { band = "Highly variable" }
        return "\(band) — how tightly your sleep midpoint clusters across your last \(min(14, intel.nights.count)) nights."
    }
    private func variabilityText(_ minutes: Double?) -> String {
        guard let m = minutes else { return "—" }
        return PremiumAnalysis.durText(m)
    }

    // MARK: Balance

    @ViewBuilder private var balanceSection: some View {
        let durations: [PremiumSample] = PremiumMetricCatalog.series(.sleepDuration, repo: repo)
        let last7: [PremiumSample] = Array(durations.suffix(7))
        if last7.count >= 3 {
            let need: Double = sleepNeedMin
            let deltas: [Double] = last7.map { $0.value - need }
            let above: Int = deltas.filter { $0 >= 0 }.count
            let avg: Double = PremiumAnalysis.mean(last7.map(\.value)) ?? need
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    PremiumSectionHeader(title: "Balance")
                    Spacer()
                    ProvenanceChip(provenance: .calculated)
                }
                StrandCard {
                    VStack(alignment: .leading, spacing: 16) {
                        MetricValueHeader(
                            value: (avg - need >= 0 ? "+" : "") + PremiumAnalysis.durText(avg - need),
                            unit: "avg / night",
                            deltaText: nil, deltaGood: nil,
                            caption: "Against your \(PremiumAnalysis.durText(need)) personal sleep need, across your last \(last7.count) nights.",
                            tint: avg >= need ? StrandPalette.recoveryColor(85) : StrandPalette.metricRose)
                        DeviationBars(deltas: deltas, height: 84,
                                      labels: last7.map { Self.weekdayLetter($0.day) })
                        HStack(spacing: 14) {
                            statBlock("Target", PremiumAnalysis.durText(need), StrandPalette.textSecondary)
                            statBlock("Above", "\(above)", StrandPalette.recoveryColor(85))
                            statBlock("Below", "\(last7.count - above)", StrandPalette.metricRose)
                        }
                        Text("Your sleep need is the greater of 7h 30m and your own 30-day average — the same rule the rest of NOOP uses.", comment: "Sleep balance footnote")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private static func weekdayLetter(_ dayKey: String) -> String {
        guard let d = PremiumAnalysis.dayParser.date(from: dayKey) else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEE"
        return String(f.string(from: d).prefix(1))
    }

    // MARK: Overnight vitals

    private var overnightVitalsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PremiumSectionHeader(title: "Overnight vitals", trailing: "vs your baseline")
            StrandCard {
                VStack(spacing: 0) {
                    vitalRow(.restingHr)
                    vitalRow(.hrv)
                    vitalRow(.respiratory)
                    vitalRow(.spo2)
                    vitalRow(.skinTemp)
                    Text("Heart rate is measured continuously overnight — see the chart above. These are stored as one value per night, so they're shown as nightly figures rather than invented minute-by-minute curves.", comment: "Overnight vitals footnote")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
            }
        }
    }

    /// One overnight signal with its value, its own 30-day baseline and a signed deviation. Renders
    /// nothing at all when the signal has never been recorded, so the card never shows an empty row.
    @ViewBuilder private func vitalRow(_ id: PremiumMetricID) -> some View {
        let a: PremiumMetricAnalysis = PremiumMetricCatalog.analysis(id, repo: repo)
        if let v = a.latest {
            let d: PremiumMetricDef = PremiumMetricCatalog.def(id)
            NavigationLink(value: PremiumRoute.catalogMetric(id)) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        PremiumIconTile(system: d.icon, tint: d.tint, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.shortName).font(StrandFont.body)
                                .foregroundStyle(StrandPalette.textPrimary)
                            if let b = a.baseline {
                                Text(String(format: String(localized: "baseline %@"), d.format(b)))
                                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            } else {
                                Text("no baseline yet", comment: "Shown when a metric lacks enough history")
                                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            }
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(d.format(v, withUnit: false))
                                .font(StrandFont.captionNumber).foregroundStyle(d.tint)
                            if let devText = PremiumMetricCatalog.deviationText(id, a) {
                                Text(devText)
                                    .font(StrandFont.footnote)
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    .padding(.vertical, 10)
                    Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: History

    private var historySection: some View {
        let a: PremiumMetricAnalysis = PremiumMetricCatalog.analysis(.sleepDuration, repo: repo)
        let values: [Double] = Array(a.series.suffix(30).map(\.value))
        return VStack(alignment: .leading, spacing: 14) {
            PremiumSectionHeader(title: "Sleep history", trailing: "30 nights")
            StrandCard {
                VStack(alignment: .leading, spacing: 12) {
                    if values.count >= 2 {
                        BaselineBandChart(values: values, baseline: a.baseline, spread: a.spread,
                                          tint: StrandPalette.sleepREM, height: 150,
                                          valueFormat: { PremiumAnalysis.durText($0) })
                        HStack(spacing: 14) {
                            changeBlock("7 days", a.change7)
                            changeBlock("30 days", a.change30)
                            changeBlock("90 days", a.change90)
                        }
                    } else {
                        MetricUnavailable(name: "Sleep history",
                                          reason: "Need at least two recorded nights.")
                    }
                }
            }
        }
    }

    private func changeBlock(_ label: String, _ pct: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let p = pct {
                Text(PremiumAnalysis.signedPct(p))
                    .font(.system(size: 17, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(p >= 0 ? StrandPalette.recoveryColor(85) : StrandPalette.metricRose)
            } else {
                Text("—").font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Text(label.uppercased()).font(StrandFont.overline).tracking(1.0)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Distribution — where does a typical night actually land?

    @ViewBuilder private var distributionSection: some View {
        let a: PremiumMetricAnalysis = PremiumMetricCatalog.analysis(.sleepDuration, repo: repo)
        if a.series.count >= 10 {
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "Sleep duration distribution")
                StrandCard {
                    VStack(alignment: .leading, spacing: 10) {
                        DistributionHistogram(values: a.series.map(\.value), buckets: 12,
                                              tint: StrandPalette.sleepREM,
                                              highlight: a.latest, height: 110)
                        if a.byWeekday.count >= 3 {
                            Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                            Text("BY DAY OF WEEK", comment: "Section label above a weekday pattern chart").font(StrandFont.overline).tracking(1.2)
                                .foregroundStyle(StrandPalette.textTertiary)
                            WeekdayPatternChart(byWeekday: a.byWeekday,
                                                tint: StrandPalette.sleepREM,
                                                format: { PremiumAnalysis.durText($0) })
                        }
                        Text("How your recorded nights actually spread out, not just their average.", comment: "Sleep distribution caption")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Relationships — ONE card, strongest first, re-aimable.

    struct SleepRelationship: Identifiable {
        let partner: PremiumMetricID
        let correlation: Correlation
        let points: [CGPoint]
        var id: String { partner.rawValue }
    }

    /// "What does my sleep actually move with?" — one card leading with the STRONGEST association,
    /// the rest a tap away, rather than a stack of scatters the user has to compare by eye.
    @ViewBuilder private var relationshipsSection: some View {
        if !sleepRelationships.isEmpty {
            let shown: SleepRelationship = sleepRelationships.first { $0.id == selectedSleepRelationship }
                ?? sleepRelationships[0]
            let d: PremiumMetricDef = PremiumMetricCatalog.def(shown.partner)
            let confidence: PremiumConfidence = PremiumConfidence.from(n: shown.correlation.n,
                                                                        strength: shown.correlation.r)
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "What your sleep moves with")
                if sleepRelationships.count > 1 {
                    PremiumChipPicker<String>(
                        options: sleepRelationships.map { rel in
                            PremiumChipPicker<String>.Option(
                                value: rel.id,
                                label: PremiumMetricCatalog.def(rel.partner).shortName,
                                tint: PremiumMetricCatalog.def(rel.partner).tint)
                        },
                        selection: selectedSleepRelationshipBinding)
                }
                StrandCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Self.sleepRelationshipSentence(partner: d.shortName,
                                                            r: shown.correlation.r))
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        CorrelationScatter(points: shown.points, tint: d.tint, height: 140)
                        HStack {
                            Text(confidence.label).font(StrandFont.footnote).foregroundStyle(confidence.tint)
                            Spacer()
                            Text(String(format: String(localized: "r = %1$@ · %2$d nights"),
                                        String(format: "%.2f", shown.correlation.r), shown.correlation.n))
                                .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
                        }
                        Text(String(format: String(localized: "Each dot is one night: your sleep duration against that day's %@. An association in your own data, not a cause."), d.shortName.lowercased()))
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private static func sleepRelationshipSentence(partner: String, r: Double) -> String {
        let mag: Double = abs(r)
        let strength: String = mag >= 0.6 ? String(localized: "a strong")
            : (mag >= 0.3 ? String(localized: "a moderate") : String(localized: "a weak"))
        let template: String = r >= 0
            ? String(localized: "Nights you sleep longer tend to come with higher %1$@ — %2$@ association.")
            : String(localized: "Nights you sleep longer tend to come with lower %1$@ — %2$@ association.")
        return String(format: template, partner.lowercased(), strength)
    }

    private var selectedSleepRelationshipBinding: Binding<String> {
        Binding(get: { selectedSleepRelationship ?? sleepRelationships.first?.id ?? "" },
                set: { selectedSleepRelationship = $0 })
    }

    /// Ranks sleep duration against each candidate partner. Computed in `load()` so the alignment
    /// and correlation work stays off the body-evaluation path.
    private func computeSleepRelationships() -> [SleepRelationship] {
        let durSeries = PremiumMetricCatalog.series(.sleepDuration, repo: repo)
            .map { (day: $0.day, value: $0.value) }
        var out: [SleepRelationship] = []
        for partner in [PremiumMetricID.recovery, .hrv, .restingHr, .respiratory] {
            let ps = PremiumMetricCatalog.series(partner, repo: repo)
                .map { (day: $0.day, value: $0.value) }
            let aligned = CorrelationEngine.alignByDay(durSeries, ps)
            guard aligned.count >= PremiumAnalysis.minCorrelationSamples,
                  let corr = CorrelationEngine.pearson(aligned) else { continue }
            let xs = aligned.map(\.0), ys = aligned.map(\.1)
            let xlo = xs.min() ?? 0, xhi = xs.max() ?? 1
            let ylo = ys.min() ?? 0, yhi = ys.max() ?? 1
            let xspan = max(xhi - xlo, 0.0001), yspan = max(yhi - ylo, 0.0001)
            out.append(SleepRelationship(
                partner: partner, correlation: corr,
                points: Self.normalisedScatter(xs: xs, ys: ys, xlo: xlo, xspan: xspan,
                                               ylo: ylo, yspan: yspan)))
        }
        return out.sorted { abs($0.correlation.r) > abs($1.correlation.r) }
    }

    /// Normalises aligned pairs into the unit square. Kept as a static helper (not inline
    /// arithmetic) per the SwiftUI type-checker guidance elsewhere in this file's siblings.
    private static func normalisedScatter(xs: [Double], ys: [Double], xlo: Double, xspan: Double,
                                          ylo: Double, yspan: Double) -> [CGPoint] {
        var pts: [CGPoint] = []
        pts.reserveCapacity(xs.count)
        for i in 0..<xs.count {
            let nx: Double = (xs[i] - xlo) / xspan
            let ny: Double = 1 - (ys[i] - ylo) / yspan
            pts.append(CGPoint(x: CGFloat(nx), y: CGFloat(ny)))
        }
        return pts
    }
}

// MARK: - The unified night panel

/// Last night's stages and heart rate as ONE instrument.
///
/// Selecting a stage (by tapping its row, or its legend chip) isolates it everywhere simultaneously:
/// the ribbon dims every other stage, and the heart-rate chart shades exactly the time windows that
/// stage occupied. The HR curve itself is never dimmed — the point of the interaction is to compare
/// physiology BETWEEN stages, which requires the curve to stay legible throughout.
///
/// Dragging the chart scrubs: the readout reports the precise clock time, the heart rate at that
/// moment and which stage the user was in.
private struct SleepNightPanel: View {
    let intervals: [SleepInterval]
    let hr: [(t: Date, bpm: Double)]
    let nightStart: Date
    let nightEnd: Date
    @Binding var selected: SleepStage?
    /// 30-day typical minutes per stage, for the "vs typical" line. Missing stages omit it.
    let typicalMinutes: [SleepStage: Double]

    @State private var scrubFraction: Double?

    private var span: Double { max(1, nightEnd.timeIntervalSince(nightStart)) }
    private var bpmValues: [Double] { hr.map(\.bpm) }

    /// Stage order top-to-bottom in the legend and rows: the conventional hypnogram ordering.
    private static let order: [SleepStage] = [.awake, .rem, .light, .deep]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            readout
            legend
            chartStack
            axis
            Rectangle().fill(StrandPalette.hairline).frame(height: 1)
            stageRows
            footnote
        }
    }

    // MARK: Readout

    private var readout: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scrubFraction == nil
                     ? String(localized: "OVERNIGHT AVERAGE")
                     : String(format: String(localized: "AT %@"), timeText(scrubFraction ?? 0)))
                    .font(StrandFont.overline).tracking(1.2)
                    .foregroundStyle(StrandPalette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(bpmText)
                        .font(.system(size: 30, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(StrandPalette.metricRose)
                    Text("bpm").font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                    if let stage = scrubbedStage {
                        stageChip(stage)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                miniStat("MIN", bpmValues.min())
                miniStat("MAX", bpmValues.max())
            }
        }
    }

    private var bpmText: String {
        if let f = scrubFraction, let s = sample(at: f) { return "\(Int(s.bpm.rounded()))" }
        guard let avg = PremiumAnalysis.mean(bpmValues) else { return "—" }
        return "\(Int(avg.rounded()))"
    }
    private var scrubbedStage: SleepStage? {
        guard let f = scrubFraction else { return nil }
        return stage(at: f)
    }
    private func miniStat(_ label: String, _ v: Double?) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(0.6)
                .foregroundStyle(StrandPalette.textTertiary)
            Text(v.map { "\(Int($0.rounded()))" } ?? "—")
                .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
        }
    }
    private func stageChip(_ s: SleepStage) -> some View {
        Text(s.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(StrandPalette.sleepStageColor(s))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(StrandPalette.sleepStageColor(s).opacity(0.18)))
    }

    // MARK: Legend (doubles as the stage selector)

    private var legend: some View {
        HStack(spacing: 8) {
            ForEach(Self.order, id: \.self) { stage in
                let isOn: Bool = selected == stage
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selected = isOn ? nil : stage
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(StrandPalette.sleepStageColor(stage))
                            .frame(width: 7, height: 7)
                        Text(stage.label).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(isOn ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(isOn
                        ? StrandPalette.sleepStageColor(stage).opacity(0.20)
                        : StrandPalette.surfaceInset))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: isOn
                                    ? String(localized: "%@ stage, selected")
                                    : String(localized: "%@ stage, not selected"), stage.label))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Chart + ribbon (the shared time domain)

    private var chartStack: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            VStack(spacing: 8) {
                hrChart.frame(height: 130)
                StageRibbon(blocks: ribbonBlocks, selected: selected?.rawValue, height: 16)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard w > 0 else { return }
                        scrubFraction = Double(min(max(0, g.location.x / w), 1))
                    }
                    .onEnded { _ in scrubFraction = nil }
            )
        }
        .frame(height: 130 + 8 + 16)
    }

    /// Ribbon blocks in normalised [0,1] time, tagged by stage so `StageRibbon` can dim the
    /// unselected ones.
    private var ribbonBlocks: [StageRibbon.Block] {
        intervals.enumerated().map { idx, iv in
            StageRibbon.Block(id: idx,
                              start: iv.start / span,
                              end: iv.end / span,
                              category: iv.stage.rawValue,
                              tint: StrandPalette.sleepStageColor(iv.stage))
        }
    }

    /// The heart-rate curve. When a stage is selected its time windows are shaded behind the line,
    /// which is what visually connects "REM" in the stage list to *when* REM happened overnight.
    private var hrChart: some View {
        Canvas { ctx, size in
            guard hr.count >= 2 else { return }
            let values: [Double] = bpmValues
            let r = PremiumCharts.range(values: values)
            let h: CGFloat = size.height
            let w: CGFloat = size.width

            // 1. Selected-stage windows, shaded across the full chart height.
            if let sel = selected {
                for iv in intervals where iv.stage == sel {
                    let x0: CGFloat = w * CGFloat(min(max(iv.start / span, 0), 1))
                    let x1: CGFloat = w * CGFloat(min(max(iv.end / span, 0), 1))
                    let rect = CGRect(x: x0, y: 0, width: max(1, x1 - x0), height: h)
                    ctx.fill(Path(rect), with: .color(StrandPalette.sleepStageColor(sel).opacity(0.22)))
                }
            }

            // 2. The heart-rate line — never dimmed, so stages stay comparable.
            var pts: [CGPoint] = []
            pts.reserveCapacity(hr.count)
            for s in hr {
                let frac: Double = min(max(s.t.timeIntervalSince(nightStart) / span, 0), 1)
                let px: CGFloat = w * CGFloat(frac)
                let py: CGFloat = PremiumCharts.y(s.bpm, lo: r.lo, hi: r.hi, height: h)
                pts.append(CGPoint(x: px, y: py))
            }
            var line = Path()
            line.addLines(pts)
            var area = line
            area.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h))
            area.addLine(to: CGPoint(x: pts[0].x, y: h))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [StrandPalette.metricRose.opacity(0.26),
                                  StrandPalette.metricRose.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(line, with: .color(StrandPalette.metricRose), lineWidth: 2)

            // 3. Scrub cursor.
            if let f = scrubFraction {
                let cx: CGFloat = w * CGFloat(f)
                var v = Path()
                v.move(to: CGPoint(x: cx, y: 0))
                v.addLine(to: CGPoint(x: cx, y: h))
                ctx.stroke(v, with: .color(StrandPalette.textSecondary.opacity(0.55)), lineWidth: 1)
                if let s = sample(at: f) {
                    let py: CGFloat = PremiumCharts.y(s.bpm, lo: r.lo, hi: r.hi, height: h)
                    let dot = CGRect(x: cx - 5, y: py - 5, width: 10, height: 10)
                    ctx.fill(Path(ellipseIn: dot), with: .color(StrandPalette.metricRose))
                    ctx.stroke(Path(ellipseIn: dot), with: .color(StrandPalette.surfaceBase), lineWidth: 2)
                }
            }
        }
    }

    private var axis: some View {
        HStack {
            Text(clock(nightStart))
            Spacer()
            Text(clock(nightStart.addingTimeInterval(span / 2)))
            Spacer()
            Text(clock(nightEnd))
        }
        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
    }

    // MARK: Stage rows (the other half of the selection)

    private var stageRows: some View {
        VStack(spacing: 8) {
            ForEach(Self.order, id: \.self) { stage in
                stageRow(stage)
            }
        }
    }

    private func stageRow(_ stage: SleepStage) -> some View {
        let minutes: Double = stageMinutes(stage)
        let totalMin: Double = span / 60
        let pct: Int = totalMin > 0 ? Int((minutes / totalMin * 100).rounded()) : 0
        let isSelected: Bool = selected == stage
        let isDimmed: Bool = selected != nil && !isSelected
        let color: Color = StrandPalette.sleepStageColor(stage)

        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                selected = isSelected ? nil : stage
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(stage.label).font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("\(pct)%").font(StrandFont.captionNumber)
                        .foregroundStyle(isDimmed ? StrandPalette.textTertiary : color)
                    Spacer()
                    Text(PremiumAnalysis.durText(minutes))
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if isSelected, let comparison = typicalComparison(stage, minutes: minutes) {
                    Text(comparison)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? color.opacity(0.12) : StrandPalette.textPrimary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1))
            .opacity(isDimmed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.label): \(PremiumAnalysis.durText(minutes)), \(pct) percent of the night")
        .accessibilityHint("Highlights this stage on the overnight chart")
    }

    /// "1h 22m · typically 1h 05m (+17m)". Omitted for stages with no stored typical (awake), so
    /// the app never invents a comparison it can't support.
    private func typicalComparison(_ stage: SleepStage, minutes: Double) -> String? {
        guard let typical = typicalMinutes[stage], typical > 0 else {
            return "No 30-day typical stored for this stage yet."
        }
        let delta: Double = minutes - typical
        let sign: String = delta >= 0 ? "+" : "−"
        return "Typically \(PremiumAnalysis.durText(typical)) · \(sign)\(PremiumAnalysis.durText(abs(delta))) vs typical"
    }

    private var footnote: some View {
        Text("Tap a stage to highlight exactly when it happened overnight. Drag the chart to read any moment. Sleep stages are estimated on-device from motion and heart rate — not a clinical measurement.", comment: "Sleep night panel footnote")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Lookups

    private func stageMinutes(_ stage: SleepStage) -> Double {
        intervals.filter { $0.stage == stage }
            .reduce(0.0) { $0 + ($1.end - $1.start) } / 60
    }
    private func stage(at fraction: Double) -> SleepStage? {
        let sec: Double = fraction * span
        return intervals.first { $0.start <= sec && sec < $0.end }?.stage
    }
    private func sample(at fraction: Double) -> (t: Date, bpm: Double)? {
        guard !hr.isEmpty else { return nil }
        let target: Double = fraction * span
        return hr.min { a, b in
            abs(a.t.timeIntervalSince(nightStart) - target) < abs(b.t.timeIntervalSince(nightStart) - target)
        }
    }
    private func timeText(_ fraction: Double) -> String {
        clock(nightStart.addingTimeInterval(fraction * span))
    }
    private func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Timing map

/// One row per night, each a bar spanning bedtime→wake on a shared clock axis. A regular schedule
/// visibly lines up into a column; a drifting one staggers. Far more legible than three separate
/// lines of bed/wake/midpoint numbers.
private struct SleepTimingMap: View {
    let nights: [PremiumSleepIntel.Night]

    var body: some View {
        // `bedMinutes` and `wakeMinutes` are already on one continuous noon-anchored scale
        // (`PremiumSleepIntel.minutesSinceNoon` wraps a post-midnight wake time onto it itself) —
        // adding another 1440 here double-wrapped the wake side and pushed the midpoint label
        // shown below by 12 hours (the "2:30 PM" instead of "2:30 AM" bug).
        let beds: [Double] = nights.map(\.bedMinutes)
        let wakes: [Double] = nights.map(\.wakeMinutes)
        let winStart: Double = (beds.min() ?? 0) - 20
        let winEnd: Double = (wakes.max() ?? 1440) + 20
        let span: Double = max(1, winEnd - winStart)
        let rowH: CGFloat = 11
        let gap: CGFloat = 3

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(nights.enumerated()), id: \.offset) { i, night in
                        let x0: CGFloat = geo.size.width * CGFloat((night.bedMinutes - winStart) / span)
                        let x1: CGFloat = geo.size.width * CGFloat((night.wakeMinutes - winStart) / span)
                        let opacity: Double = 0.45 + 0.55 * Double(i) / Double(max(1, nights.count - 1))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(StrandPalette.sleepDeep.opacity(opacity))
                            .frame(width: max(2, x1 - x0), height: rowH)
                            .offset(x: x0, y: CGFloat(i) * (rowH + gap))
                    }
                }
            }
            .frame(height: CGFloat(nights.count) * (rowH + gap))
            HStack {
                Text(PremiumSleepIntel.clockText(winStart))
                Spacer()
                Text(PremiumSleepIntel.clockText((winStart + winEnd) / 2))
                Spacer()
                Text(PremiumSleepIntel.clockText(winEnd))
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(StrandPalette.textTertiary)
        }
    }
}

// MARK: - Sleep-editing sheet payloads

/// Seeds the "Add a nap" picker. Identity is the seed start so `.sheet(item:)` presents once per request.
struct PremiumNapSeed: Identifiable {
    let bedTs: Int
    let wakeTs: Int
    var id: Int { bedTs }
}

/// One in-flight sleep-window edit. `detectedStartTs` is the IMMUTABLE detected key the write targets
/// (`Repository.editSleepTimes` / `deleteSleepSession` match on it), while `bedTs` is the currently
/// EFFECTIVE onset shown to the user — they differ once an onset has been hand-corrected, and conflating
/// them is what spawns duplicate rows.
struct PremiumSleepEdit: Identifiable {
    let detectedStartTs: Int
    let bedTs: Int
    let wakeTs: Int
    let stagesJSON: String?
    /// True for a hand-edited / manually-added block: deleting it writes no re-detection tombstone, so
    /// the confirm copy must not promise suppression.
    let userEdited: Bool
    let isNap: Bool
    var id: Int { detectedStartTs }
}
#endif
