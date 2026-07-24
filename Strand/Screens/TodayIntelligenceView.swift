import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// TodayIntelligenceView.swift — NOOP's "much more than a dashboard" intelligence, as ONE reusable block.
//
// This is the adaptive-Home narrative the prototypes promised: the Morning Briefing story, the leading-domain
// Focus Hero, the ranked "what matters today" feed, Tomorrow's Outlook, the on-device Coach, then the
// zoom-out reads — Your Week, Health Streaks + Momentum, Achievements, the Weekly Review, the Monthly Story,
// and What Moves Your Recovery. Every piece self-gates: with too little history it renders nothing, so a cold
// start stays quiet and a data-rich install lights up.
//
// It computes ENTIRELY from `repo` plus the readiness band and Rest score the host Today screen already
// resolved — no day navigation, no live-HR coupling — so BOTH the liquid Today (the default) and the classic
// Today can drop it in and show the SAME intelligence. The heavy lifting lives in the pure StrandAnalytics
// engines (the single source of truth); this view is the thin marshalling from `repo` into those engines and
// on into the dumb SwiftUI renderers. Today-only by contract — the host gates it on the selected day being today.

struct TodayIntelligenceView: View {
    @EnvironmentObject var repo: Repository

    /// The readiness band the host already resolved (drives the recovery insight + coach verdict), so the
    /// hero here can never disagree with the host's Push / Maintain / Rest read.
    let readinessLevel: ReadinessEngine.Level
    /// The merged Rest (sleep_performance) score the host's Rest ring reads — feeds the Charge driver
    /// breakdown's rest-quality term so a driver can never describe a term the ring's number didn't use.
    let restScore: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            todayInsightsSection()
            weekGlanceSection()
            streaksSection()
            achievementsSection()
            weeklyReviewSection()
            monthlyStorySection()
            recoveryFactorsSection()
        }
    }

    // MARK: - Today's Charge row + driver breakdown (today-scoped carry)

    /// Today's logical-day key (the day every read-out here keys on).
    private var todayKey: String { repo.today?.day ?? Repository.logicalDayKey(Date()) }

    /// The row whose recovery + vitals feed the recovery insight and the driver breakdown. Today's own row
    /// when it's scored; otherwise the freshest strictly-prior scored night (the #543 carry), so right after
    /// the 04:00 rollover — before tonight's sleep scores — the narrative still reads from last night rather
    /// than blanking. Never selects a future-dated row (lexicographic `< todayKey` guard).
    private var chargeRow: DailyMetric? {
        if repo.today?.recovery != nil { return repo.today }
        return repo.days.last(where: { $0.recovery != nil && $0.day < todayKey }) ?? repo.today
    }

    /// The ordered "What shaped it" Charge drivers for the displayed Charge, folded from the SAME HRV / RHR /
    /// respiratory baselines `AnalyticsEngine` scored with. nil for a calibrating / cold-start night (no usable
    /// HRV baseline), so the feed falls back to the recovery band alone. Mirrors `TodayView.chargeBreakdown`.
    private func chargeBreakdown() -> (drivers: [ChargeDriver], confidence: ScoreConfidence)? {
        guard let row = chargeRow, let hrv = row.avgHrv, let rhr = row.restingHr else { return nil }
        let hrvBase = Baselines.foldHistory(repo.days.map(\.avgHrv), cfg: Baselines.hrvCfg)
        guard hrvBase.usable else { return nil }
        let rhrBase = Baselines.foldHistory(repo.days.map { $0.restingHr.map(Double.init) },
                                            cfg: Baselines.restingHRCfg)
        let respBase = Baselines.foldHistory(repo.days.map(\.respRateBpm), cfg: Baselines.respCfg)
        let sleepPerf = restScore.map { $0 / 100.0 }
        let drivers = RecoveryScorer.chargeDrivers(
            hrv: hrv, rhr: Double(rhr), resp: row.respRateBpm,
            hrvBaseline: hrvBase,
            rhrBaseline: rhrBase.usable ? rhrBase : nil,
            respBaseline: respBase.usable ? respBase : nil,
            sleepPerf: sleepPerf, skinTempDev: row.skinTempDevC)
        return (drivers, ScoreConfidence.charge(recovery: row.recovery, hrvBaseline: hrvBase))
    }

    // MARK: - Today's Insights feed (briefing + focus hero + ranked feed + outlook + coach)

    /// Tonight's sleep-stage report vs the recent baseline, reusing the SAME producer as the Sleep tab.
    private func todayStageReport() -> SleepStageInsights.Report? {
        let recent = repo.sleeps.sorted { $0.effectiveStartTs < $1.effectiveStartTs }.suffix(31)
        let allMins = recent.compactMap { SleepStageTotals.minutes(fromStagesJSON: $0.stagesJSON) }
        guard let tonight = allMins.last else { return nil }
        return SleepStageInsights.analyze(tonight: tonight, baseline: Array(allMins.dropLast()))
    }

    /// The trailing-window sleep-timing regularity read, reusing the Sleep tab's producer.
    private func todayTimingResult() -> SleepRegularityResult {
        let nights = repo.sleeps
            .sorted { $0.effectiveStartTs < $1.effectiveStartTs }
            .map { SleepTimingNight.from(onsetEpoch: $0.effectiveStartTs, wakeEpoch: $0.endTs) }
        return SleepRegularity.assess(nights: nights)
    }

    @ViewBuilder
    private func todayInsightsSection() -> some View {
        let recoverySignal: TodayInsightsBuilder.RecoverySignal? = chargeRow?.recovery
            .map { TodayInsightsBuilder.RecoverySignal(score: Int($0.rounded()), band: readinessLevel) }
        let stageReport = todayStageReport()
        let timing = todayTimingResult()
        let ranked = TodayInsightsBuilder.build(recovery: recoverySignal,
                                                sleepStages: stageReport,
                                                sleepTiming: timing,
                                                max: 4)
        if !ranked.insights.isEmpty {
            let drivers = chargeBreakdown()?.drivers ?? []
            let cards = ranked.insights.map {
                TodayInsightCard.make(for: $0, drivers: drivers,
                                      stageReport: stageReport, timing: timing)
            }
            let cardsByKind = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let focus = HomeFocusResolver.resolve(ranked: ranked)
            let part = MorningBriefing.partOfDay(hour: Calendar.current.component(.hour, from: Date()))
            let streak = bestCurrentStreak()
            let script = MorningBriefingPlanner.plan(part: part, focus: focus, ranked: ranked,
                                                     streakDays: streak)
            let outlook = TomorrowOutlook.build(recentCharge: repo.days.compactMap { $0.recovery },
                                                todayEffort: nil,
                                                todayCharge: chargeRow?.recovery)
            let coachContext = CoachContext(
                verdict: CoachAdvisor.trainingVerdict(band: readinessLevel,
                                                      tomorrow: outlook.hasForecast ? outlook.direction : nil),
                recoveryScore: recoverySignal?.score,
                topDriver: drivers.first,
                outlook: outlook,
                topFactor: recoveryFactorsReport().factors.first,
                weekly: weeklyReview())
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                MorningBriefingView(script: script, name: "", cardsByKind: cardsByKind, streakDays: streak)
                if let heroModel = focusHeroModel(focus: focus, recovery: recoverySignal, drivers: drivers,
                                                  stageReport: stageReport, headlineCard: cards.first) {
                    FocusHero(model: heroModel)
                }
                TodayInsightsFeed(cards: cards, dayTone: ranked.dayTone,
                                  attentionCount: ranked.attentionCount)
                if outlook.hasForecast { TomorrowOutlookView(outlook: outlook) }
                OnDeviceCoachView(context: coachContext)
            }
        }
    }

    /// Build the Adaptive Home focus hero for the resolved focus domain, or nil when there isn't enough to
    /// show. Reuses the SAME domain outputs the feed uses, so the hero can never disagree with the cards below.
    private func focusHeroModel(focus: HomeFocusResult,
                                recovery: TodayInsightsBuilder.RecoverySignal?,
                                drivers: [ChargeDriver],
                                stageReport: SleepStageInsights.Report?,
                                headlineCard: TodayInsightCard?) -> FocusHeroModel? {
        switch focus.domain {
        case .recovery:
            guard let rec = recovery else { return nil }
            let score = Double(rec.score)
            let accent = StrandPalette.recoveryColor(score)
            let titleActionIcon: (LocalizedStringKey, String, String) = {
                switch rec.band {
                case .primed:
                    return ("You're primed today",
                            String(localized: "It's a good day to train harder if you've been meaning to."),
                            "bolt.heart.fill")
                case .strained:
                    return ("Ease off today",
                            String(localized: "Keep it light — gentle movement, hydration, and an early night usually bring it back."),
                            "leaf.fill")
                case .rundown:
                    return ("Your body needs recovery",
                            String(localized: "Prioritise rest today — light movement at most, and an early night."),
                            "leaf.fill")
                default:
                    return ("A balanced day",
                            String(localized: "Nothing stands out — train to how you feel."),
                            "equal.circle.fill")
                }
            }()
            let heroDrivers = drivers.prefix(3).map {
                FocusDriver(label: $0.label, value: $0.valueText, positive: $0.deltaPoints >= 0)
            }
            let explanation: String = {
                if let d = drivers.first {
                    return String(format: String(localized: "Charge %ld. %@ — %@"),
                                  rec.score, d.valueText.isEmpty ? d.label : d.valueText, d.verdict)
                }
                return String(format: String(localized: "Charge %ld."), rec.score)
            }()
            return FocusHeroModel(domain: .recovery, mode: focus.mode, accent: accent,
                                  title: titleActionIcon.0, explanation: explanation,
                                  action: titleActionIcon.1, actionIcon: titleActionIcon.2,
                                  recoveryScore: score, recoveryDrivers: Array(heroDrivers))

        case .sleep:
            guard let report = stageReport else { return nil }
            let c = report.composition
            let mins = c.asleepMin
            let duration = String(format: String(localized: "%ldh %02ldm"), Int(mins) / 60, Int(mins) % 60)
            let eff = String(format: String(localized: "%ld%% efficiency"), Int((c.efficiency * 100).rounded()))
            let hasCaution = report.insights.contains { $0.tone == .caution }
            let title: LocalizedStringKey = hasCaution ? "Last night is worth a look" : "Last night's sleep"
            let explanation = headlineCard?.subtitle
                ?? String(localized: "Here's how the night broke down across stages.")
            let action = hasCaution
                ? String(localized: "Aim for a consistent, slightly earlier bedtime tonight.")
                : String(localized: "A steady bedtime keeps nights like this consistent.")
            return FocusHeroModel(domain: .sleep, mode: focus.mode, accent: StrandPalette.sleepDeep,
                                  title: title, explanation: explanation, action: action,
                                  actionIcon: "moon.zzz.fill",
                                  sleep: FocusSleep(deep: c.deepMin, light: c.lightMin, rem: c.remMin,
                                                    awake: c.awakeMin, duration: duration, efficiency: eff))

        case .trends:
            let series = repo.days.suffix(21).compactMap { $0.recovery }
            let action = String(localized: "A steady stretch like this is a great time to build on your habits.")
            guard series.count >= 3 else {
                return FocusHeroModel(domain: .trends, mode: .optimization, accent: StrandPalette.chargeColor,
                                      title: "You're in a good rhythm",
                                      explanation: String(localized: "Everything's near your personal baseline today."),
                                      action: action, actionIcon: "chart.line.uptrend.xyaxis")
            }
            let headline = trendsHeadline(series)
            return FocusHeroModel(domain: .trends, mode: .optimization, accent: StrandPalette.chargeColor,
                                  title: headline.0, explanation: headline.1, action: action,
                                  actionIcon: "chart.line.uptrend.xyaxis", trendValues: series)

        case .strain:
            return nil   // strain focus needs the standout-load signal (a later milestone)
        }
    }

    /// A tiny, honest trend read over the recovery series for the trends focus hero.
    private func trendsHeadline(_ series: [Double]) -> (LocalizedStringKey, String) {
        let n = series.count
        let third = Swift.max(1, n / 3)
        let firstMean = series.prefix(third).reduce(0, +) / Double(third)
        let lastMean = series.suffix(third).reduce(0, +) / Double(third)
        let delta = lastMean - firstMean
        if delta >= 4 {
            let pct = firstMean > 0 ? Int((delta / firstMean * 100).rounded()) : 0
            return ("Trending up — a chance to build",
                    String(format: String(localized: "Your recovery is up about %ld%% over the last couple of weeks."), pct))
        } else if delta <= -4 {
            return ("Holding steady",
                    String(localized: "Your recovery has eased a little lately, but nothing needs attention today."))
        }
        return ("Steady and strong",
                String(localized: "Your recovery has held near your personal baseline for two weeks."))
    }

    // MARK: - Health streaks (meaningful, self-adapting behaviour streaks)

    private func streakSummaries() -> [StreakSummary] {
        var out: [StreakSummary] = []

        let sleeps = Array(repo.sleeps.sorted { $0.effectiveStartTs < $1.effectiveStartTs }.suffix(60))
        if sleeps.count >= HealthStreaks.scheduleMinBaseline + 1 {
            let keys = sleeps.indices.map { "n\($0)" }
            let asleep = sleeps.map { Double(Swift.max(0, $0.endTs - $0.effectiveStartTs)) / 60.0 }
            let mids = sleeps.map {
                SleepTimingNight.from(onsetEpoch: $0.effectiveStartTs, wakeEpoch: $0.endTs).midpointMinOfDay
            }
            let steady = HealthStreaks.steadyFlags(days: keys, midpointsMinOfDay: mids)
            out.append(streakSummary(.steadySchedule, "Steady schedule", "clock.arrow.circlepath",
                                     StrandPalette.metricPurple, unit: "night streak", flags: steady,
                                     target: String(localized: "Within ±60 min of your usual")))

            let rested = HealthStreaks.restedFlags(days: keys, asleepMins: asleep)
            let tgt = Int(HealthStreaks.restedTargetMin(asleep).rounded())
            out.append(streakSummary(.restedNights, "Rested nights", "bed.double.fill",
                                     StrandPalette.restColor, unit: "night streak", flags: rested,
                                     target: String(format: String(localized: "≈ your usual %ldh %02ldm"),
                                                     tgt / 60, tgt % 60)))
        }

        let recDays = Array(repo.days.suffix(60))
        if recDays.filter({ $0.recovery != nil }).count >= 4 {
            let recFlags = HealthStreaks.recoveryFlags(days: recDays.map { $0.day },
                                                       recoveries: recDays.map { $0.recovery ?? 0 })
            let floor = Int(HealthStreaks.recoveryFloor(recDays.compactMap { $0.recovery }).rounded())
            out.append(streakSummary(.recoveryReady, "Recovery-ready", "bolt.heart.fill",
                                     StrandPalette.chargeColor, unit: "day streak", flags: recFlags,
                                     target: String(format: String(localized: "Charge %ld or higher"), floor)))
        }
        return out
    }

    private func streakSummary(_ kind: HealthStreaks.Kind, _ title: LocalizedStringKey, _ symbol: String,
                               _ accent: Color, unit: LocalizedStringKey,
                               flags: [StreakEngine.DayFlag], target: String) -> StreakSummary {
        StreakSummary(id: kind, title: title, symbol: symbol, accent: accent, unit: unit,
                      result: StreakEngine.assess(days: flags),
                      recentFlags: flags.suffix(7).map { $0.met }, targetText: target)
    }

    /// The best current run across all streaks, for the briefing's closer (nil when none is long enough).
    private func bestCurrentStreak() -> Int? {
        let best = streakSummaries().map { $0.result.current }.max() ?? 0
        return best >= MorningBriefingPlanner.streakCloserMinDays ? best : nil
    }

    @ViewBuilder
    private func streaksSection() -> some View {
        let summaries = streakSummaries()
        if !summaries.isEmpty {
            let mom = Momentum.summarize(summaries.map {
                Momentum.Streak(kind: $0.id, current: $0.result.current, best: $0.result.best)
            })
            StreaksSection(summaries: summaries, momentum: momentumBundle(mom))
        }
    }

    /// Resolve the Momentum ember's colour + proud copy from the featured habit.
    private func momentumBundle(_ mom: Momentum.Summary) -> MomentumBundle {
        guard let kind = mom.featuredKind else {
            return MomentumBundle(summary: mom, accent: StrandPalette.restColor, title: nil,
                                  message: String(localized: "A rested night or a steady bedtime starts a new streak."))
        }
        let accent: Color
        let title: LocalizedStringKey
        let noun: String
        switch kind {
        case .steadySchedule:
            accent = StrandPalette.metricPurple; title = "Steady schedule"
            noun = String(localized: "nights on a steady schedule")
        case .restedNights:
            accent = StrandPalette.restColor; title = "Rested nights"
            noun = String(localized: "nights of solid rest")
        case .recoveryReady:
            accent = StrandPalette.chargeColor; title = "Recovery-ready"
            noun = String(localized: "days starting recovered")
        }
        let tail = mom.isRecord ? String(localized: " — your best run yet.")
                                : String(localized: ", and counting.")
        let message = String(format: String(localized: "%ld %@%@"), mom.current, noun, tail)
        return MomentumBundle(summary: mom, accent: accent, title: title, message: message)
    }

    // MARK: - Weekly Review (the week-scale story)

    private func weekStats(chargeDays: ArraySlice<DailyMetric>,
                           nights: ArraySlice<CachedSleepSession>) -> WeeklyReview.WeekStats {
        let charges = chargeDays.compactMap { $0.recovery }
        let avgCharge = charges.isEmpty ? nil : charges.reduce(0, +) / Double(charges.count)
        let hours = nights.map { Double(Swift.max(0, $0.endTs - $0.effectiveStartTs)) / 3600.0 }
        let avgSleep = hours.isEmpty ? nil : hours.reduce(0, +) / Double(hours.count)
        let timing = nights.map { SleepTimingNight.from(onsetEpoch: $0.effectiveStartTs, wakeEpoch: $0.endTs) }
        let sd = SleepRegularity.assess(nights: Array(timing)).midpointSDMinutes
        return WeeklyReview.WeekStats(avgCharge: avgCharge, avgSleepHours: avgSleep, avgEffort: nil,
                                      scheduleSDMin: sd, daysWithData: charges.count,
                                      totalDays: chargeDays.count)
    }

    private func weeklyReview() -> WeeklyReview.Review {
        let days = repo.days
        let sleeps = repo.sleeps.sorted { $0.effectiveStartTs < $1.effectiveStartTs }
        return WeeklyReview.build(
            this: weekStats(chargeDays: days.suffix(7), nights: sleeps.suffix(7)),
            prior: weekStats(chargeDays: days.dropLast(7).suffix(7),
                             nights: sleeps.dropLast(7).suffix(7)))
    }

    @ViewBuilder
    private func weeklyReviewSection() -> some View {
        let review = weeklyReview()
        if review.hasEnoughData { WeeklyReviewView(review: review) }
    }

    // MARK: - Monthly Story (long-term trend read)

    private func monthlyStory() -> MonthlyStory.Story {
        let days = repo.days.suffix(28)
        let sleeps = Array(repo.sleeps.sorted { $0.effectiveStartTs < $1.effectiveStartTs }.suffix(28))
        let hours = sleeps.map { Double(Swift.max(0, $0.endTs - $0.effectiveStartTs)) / 3600.0 }
        let timing = sleeps.map { SleepTimingNight.from(onsetEpoch: $0.effectiveStartTs, wakeEpoch: $0.endTs) }
        let sd = SleepRegularity.assess(nights: Array(timing)).midpointSDMinutes
        let recs = days.compactMap { $0.recovery }
        return MonthlyStory.build(.init(recoveries: recs, sleepHours: hours, scheduleSDMin: sd,
                                        daysWithData: recs.count, totalDays: days.count))
    }

    @ViewBuilder
    private func monthlyStorySection() -> some View {
        let story = monthlyStory()
        if story.hasEnough { MonthlyStoryView(story: story) }
    }

    // MARK: - Achievements (earned milestone badges)

    private func achievementsReport() -> Achievements.Report {
        let summaries = streakSummaries()
        func best(_ k: HealthStreaks.Kind) -> Int { summaries.first { $0.id == k }?.result.best ?? 0 }
        let peak = repo.days.compactMap { $0.recovery }.max().map { Int($0.rounded()) } ?? 0
        let tracked = repo.days.filter { $0.recovery != nil }.count
        return Achievements.evaluate(scheduleBest: best(.steadySchedule), restedBest: best(.restedNights),
                                     recoveryBest: best(.recoveryReady), peakRecovery: peak, daysTracked: tracked)
    }

    @ViewBuilder
    private func achievementsSection() -> some View {
        let report = achievementsReport()
        if report.earnedCount > 0 { AchievementsView(report: report) }
    }

    // MARK: - Your week (at-a-glance dashboard)

    private static let weekGlanceParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let weekGlanceWeekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEEE")   // narrow weekday (single letter)
        return f
    }()
    private static func weekdayInitial(_ dayKey: String) -> String {
        guard let d = weekGlanceParser.date(from: dayKey) else { return "" }
        return weekGlanceWeekday.string(from: d)
    }

    private func weekGlanceDays() -> [WeekGlanceDay] {
        var hoursByDay: [String: Double] = [:]
        for s in repo.sleeps {
            let d = SleepTimingNight.from(onsetEpoch: s.effectiveStartTs, wakeEpoch: s.endTs).day
            hoursByDay[d] = Double(Swift.max(0, s.endTs - s.effectiveStartTs)) / 3600.0
        }
        let todayKey = Repository.logicalDayKey(Date())
        return repo.days.suffix(7).map { m in
            WeekGlanceDay(id: m.day, label: Self.weekdayInitial(m.day), recovery: m.recovery,
                          sleepHours: hoursByDay[m.day], isToday: m.day == todayKey)
        }
    }

    @ViewBuilder
    private func weekGlanceSection() -> some View {
        let days = weekGlanceDays()
        if days.contains(where: { $0.recovery != nil }) { WeekGlanceView(days: days) }
    }

    // MARK: - What moves your recovery (personal correlations)

    private func recoveryFactorsReport() -> PersonalCorrelations.Report {
        let target: [(day: String, value: Double)] = repo.days.compactMap {
            guard let r = $0.recovery else { return nil }
            return (day: $0.day, value: r)
        }
        var duration: [(day: String, value: Double)] = []
        var efficiency: [(day: String, value: Double)] = []
        var restorative: [(day: String, value: Double)] = []
        var awake: [(day: String, value: Double)] = []
        for s in repo.sleeps {
            let day = SleepTimingNight.from(onsetEpoch: s.effectiveStartTs, wakeEpoch: s.endTs).day
            duration.append((day: day, value: Double(Swift.max(0, s.endTs - s.effectiveStartTs)) / 3600.0))
            if let e = s.efficiency { efficiency.append((day: day, value: e)) }
            if let m = SleepStageTotals.minutes(fromStagesJSON: s.stagesJSON) {
                restorative.append((day: day, value: m.deep + m.rem))
                awake.append((day: day, value: m.awake))
            }
        }
        return PersonalCorrelations.analyze(target: target, factors: [
            ("sleepDuration", duration), ("sleepEfficiency", efficiency),
            ("restorative", restorative), ("awake", awake),
        ])
    }

    @ViewBuilder
    private func recoveryFactorsSection() -> some View {
        let report = recoveryFactorsReport()
        if report.hasEnough { RecoveryFactorsView(report: report) }
    }
}
