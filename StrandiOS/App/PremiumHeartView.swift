#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// Phase 3 · Heart — a full cardiovascular dashboard on the user's real recorded data.
///
/// Rather than one line chart repeated at different time scales, each section answers a distinct
/// question: what is my heart doing *now*, how wide did today range, where does my resting heart
/// rate and HRV sit against my own baselines, how did today distribute across real personalised
/// zones, what does my week look like by weekday, how did my heart behave overnight, and do these
/// signals actually relate to my recovery?
///
/// Two honesty constraints shape it. WHOOP straps report PPG-derived heart rate, not an ECG, so the
/// hero is a live-pulse readout rather than a fabricated cardiac trace. And the "physiological
/// load" view is derived only where the data genuinely supports it — it is computed from real time
/// spent above the user's own resting baseline, labelled as an estimate, and hidden entirely when
/// the day has too few samples to characterise.
struct PremiumHeartView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var profile: ProfileStore

    @State private var dayHR: [HRBucket] = []
    @State private var beat = false
    @State private var zoneSet: HRZoneSet?
    @State private var timeInZone: TimeInZone?
    /// Per-day min / max / mean from the last 14 days of stored heart rate, for the range chart.
    @State private var dailyRanges: [DailyHRRange] = []
    @State private var overnight: [(t: Date, bpm: Double)] = []
    @State private var findings: [PremiumFinding] = []
    @State private var journalFindings: [PremiumFinding] = []
    /// Candidate relationships, strongest first. Computed in `load()` rather than in a computed
    /// property so the day-alignment and correlation work doesn't rerun on every body evaluation.
    @State private var relationships: [HeartRelationship] = []
    @State private var selectedRelationship: String?
    /// Which signal the distribution card is currently aimed at.
    @State private var distributionMetric: PremiumMetricID = .restingHr

    struct DailyHRRange: Identifiable {
        let id: Int
        let dayKey: String
        let lo: Double
        let hi: Double
        let mean: Double
        let label: String
    }

    // MARK: Derived values

    private func latest<T>(_ key: (DailyMetric) -> T?) -> T? {
        for d in repo.days.reversed() { if let v = key(d) { return v } }
        return repo.today.flatMap(key)
    }
    private var bpmValues: [Double] { dayHR.map(\.bpm).filter { $0 > 0 } }
    private var restingHR: Int? { latest { $0.restingHr } }
    private var liveBPM: Int? {
        if let h = live.heartRate, h > 0 { return h }
        if let last = bpmValues.last { return Int(last.rounded()) }
        return restingHR
    }
    private var avgHR: Int? { PremiumAnalysis.mean(bpmValues).map { Int($0.rounded()) } }
    private var maxHR: Int? { bpmValues.max().map { Int($0.rounded()) } }
    private var minHR: Int? { bpmValues.min().map { Int($0.rounded()) } }

    private var rhrAnalysis: PremiumMetricAnalysis { PremiumMetricCatalog.analysis(.restingHr, repo: repo) }
    private var hrvAnalysis: PremiumMetricAnalysis { PremiumMetricCatalog.analysis(.hrv, repo: repo) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                liveHero
                todayRangeCard
                findingsSection
                baselinesSection
                dayChartCard
                zonesCard
                loadSection
                overnightSection
                weekdaySection
                distributionSection
                relationshipSection
                journalRelationshipsSection
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 96)
        }
        .background(ambient.ignoresSafeArea())
        .task(id: repo.refreshSeq) { await load() }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { beat = true }
        }
    }

    // MARK: Loading

    private func load() async {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        let from = Int(startToday.timeIntervalSince1970)
        let to = Int(Date().timeIntervalSince1970)

        dayHR = await repo.hrBuckets(from: from, to: to, bucketSeconds: 300)
        let samples = await repo.hrSamples(from: from, to: to)
        let set = HRZones.zones(age: profile.age > 0 ? Double(profile.age) : 30)
        zoneSet = set
        timeInZone = samples.isEmpty ? nil : HRZones.timeInZone(samples, zoneSet: set)

        // Daily ranges across the last 14 days — one bucketed read per day, coarse buckets so a
        // fortnight of history stays cheap.
        var ranges: [DailyHRRange] = []
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"
        for back in stride(from: 13, through: 0, by: -1) {
            guard let dayStart = cal.date(byAdding: .day, value: -back, to: startToday) else { continue }
            let dayEnd = min(Date(), cal.date(byAdding: .day, value: 1, to: dayStart) ?? Date())
            guard dayEnd > dayStart else { continue }
            let buckets = await repo.hrBuckets(from: Int(dayStart.timeIntervalSince1970),
                                               to: Int(dayEnd.timeIntervalSince1970),
                                               bucketSeconds: 900)
            let vals = buckets.map(\.bpm).filter { $0 > 0 && $0 < 250 }
            guard let lo = vals.min(), let hi = vals.max(), let m = PremiumAnalysis.mean(vals) else { continue }
            ranges.append(DailyHRRange(id: ranges.count,
                                       dayKey: Repository.localDayKey(dayStart),
                                       lo: lo, hi: hi, mean: m,
                                       label: String(fmt.string(from: dayStart).prefix(1))))
        }
        dailyRanges = ranges

        // Overnight curve — reuse the shared sleep intelligence so Heart and Sleep agree.
        let intel = await PremiumSleepIntel.load(repo: repo, window: 3)
        overnight = intel.overnightHR

        // Findings for the cardiovascular signals.
        var out: [PremiumFinding] = []
        for id in [PremiumMetricID.hrv, .restingHr] {
            let a = PremiumMetricCatalog.analysis(id, repo: repo)
            let d = PremiumMetricCatalog.def(id)
            if let f = PremiumAnalysis.baselineFinding(a, name: d.shortName, unit: d.unit, tint: d.tint) {
                out.append(f)
            }
        }
        let hrvSeries = PremiumMetricCatalog.series(.hrv, repo: repo)
        let recSeries = PremiumMetricCatalog.series(.recovery, repo: repo)
        if let best = PremiumAnalysis.bestRelationship(hrvSeries, recSeries),
           let f = PremiumAnalysis.relationshipFinding(id: "heart.rel.hrv.recovery",
                                                       aName: "HRV", bName: "Recovery",
                                                       correlation: best.correlation,
                                                       lagDays: best.lagDays,
                                                       tint: StrandPalette.metricCyan) {
            out.append(f)
        }
        findings = out.sorted { $0.confidence > $1.confidence }

        // Journal → HRV / RHR associations, using the same mechanism and thresholds as the Journal
        // screen's own "what your logs line up with" — the engine, not the presentation, decides
        // what counts as a real association.
        let entries = await repo.journalEntries()
        var behaviorDays: [String: Set<String>] = [:]
        for e in entries where e.answeredYes {
            behaviorDays[e.question, default: []].insert(e.day)
        }
        var journalOut: [PremiumFinding] = []
        let heartOutcomes: [(PremiumMetricID, Color)] = [
            (.hrv, StrandPalette.metricCyan), (.restingHr, StrandPalette.metricRose),
        ]
        for (behavior, days) in behaviorDays {
            for (id, tint) in heartOutcomes {
                let series = PremiumMetricCatalog.series(id, repo: repo)
                let name = PremiumMetricCatalog.def(id).shortName
                guard let assoc = PremiumAnalysis.behaviorAssociation(
                    behaviorDays: days, behaviorName: behavior,
                    outcome: series, outcomeName: name) else { continue }
                if let f = PremiumAnalysis.behaviorFinding(effect: assoc.effect,
                                                           lagDays: assoc.lagDays, tint: tint) {
                    journalOut.append(f)
                }
            }
        }
        journalOut.sort { $0.confidence > $1.confidence }
        journalFindings = Array(journalOut.prefix(5))

        // Candidate relationships, ranked by strength so the card leads with the one that actually
        // matters for this user rather than a fixed editorial order.
        let candidates: [(PremiumMetricID, PremiumMetricID)] = [
            (.hrv, .recovery), (.hrv, .sleepDuration), (.hrv, .sleepEfficiency),
            (.restingHr, .recovery), (.restingHr, .sleepDuration),
        ]
        var rels: [HeartRelationship] = []
        for (a, b) in candidates {
            let sa = PremiumMetricCatalog.series(a, repo: repo).map { (day: $0.day, value: $0.value) }
            let sb = PremiumMetricCatalog.series(b, repo: repo).map { (day: $0.day, value: $0.value) }
            let aligned = CorrelationEngine.alignByDay(sa, sb)
            guard aligned.count >= PremiumAnalysis.minCorrelationSamples,
                  let c = CorrelationEngine.pearson(aligned) else { continue }
            rels.append(HeartRelationship(a: a, b: b, correlation: c,
                                          points: Self.normalise(aligned)))
        }
        rels.sort { abs($0.correlation.r) > abs($1.correlation.r) }
        relationships = rels
        // Drop a stale selection if its pair no longer clears the sample-count gate.
        if let sel = selectedRelationship, !rels.contains(where: { $0.id == sel }) {
            selectedRelationship = nil
        }
    }

    // MARK: Chrome

    private var ambient: some View {
        ZStack {
            StrandPalette.surfaceBase
            RadialGradient(colors: [StrandPalette.metricRose.opacity(0.16), .clear],
                           center: .init(x: 0.5, y: 0.06), startRadius: 0, endRadius: 340)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(restingHR.map { String(format: String(localized: "LIVE · RESTING %d BPM"), $0) }
                    ?? String(localized: "LIVE"))
                    .font(StrandFont.overline).tracking(1.4)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("Heart").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Live hero

    private var liveHero: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(StrandPalette.metricRose.opacity(0.5), lineWidth: 2)
                    .frame(width: 92, height: 92)
                    .scaleEffect(beat ? 1.35 : 0.9).opacity(beat ? 0 : 0.6)
                Image(systemName: "heart.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(StrandPalette.metricRose)
                    .scaleEffect(beat ? 1.12 : 1.0)
                    .shadow(color: StrandPalette.metricRose.opacity(0.6), radius: 16)
            }
            .frame(height: 104)
            Text(liveBPM.map(String.init) ?? "—")
                .font(.system(size: 58, weight: .heavy)).monospacedDigit()
                .foregroundStyle(StrandPalette.metricRose)
            HStack(spacing: 6) {
                Text("BPM").font(StrandFont.overline).tracking(1.4)
                    .foregroundStyle(StrandPalette.textTertiary)
                ProvenanceChip(provenance: .measured)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Today's range

    private var todayRangeCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Today's range", comment: "Heart screen section title").font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let lo = minHR, let hi = maxHR, let avg = avgHR {
                    HStack(spacing: 14) {
                        rangeStat("LOW", lo, StrandPalette.metricCyan)
                        rangeStat("AVERAGE", avg, StrandPalette.gold)
                        rangeStat("HIGH", hi, StrandPalette.metricRose)
                    }
                    rangeBar(lo: Double(lo), hi: Double(hi), avg: Double(avg))
                } else {
                    MetricUnavailable(name: "Today's heart rate",
                                      reason: "No readings recorded yet today.")
                }
            }
        }
    }

    private func rangeStat(_ label: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)").font(.system(size: 22, weight: .heavy)).monospacedDigit()
                .foregroundStyle(tint)
            Text(label).font(StrandFont.overline).tracking(1.0)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A single horizontal span from the day's low to its high, with the average marked — the
    /// day's cardiovascular envelope in one glance.
    private func rangeBar(lo: Double, hi: Double, avg: Double) -> some View {
        GeometryReader { geo in
            let span: Double = max(1, hi - lo)
            let markerX: CGFloat = geo.size.width * CGFloat((avg - lo) / span)
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(
                    colors: [StrandPalette.metricCyan, StrandPalette.gold, StrandPalette.metricRose],
                    startPoint: .leading, endPoint: .trailing))
                    .frame(height: 10)
                Circle().fill(StrandPalette.textPrimary)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(StrandPalette.surfaceBase, lineWidth: 2))
                    .offset(x: max(0, min(geo.size.width - 10, markerX - 5)))
            }
        }
        .frame(height: 14)
    }

    // MARK: Findings

    @ViewBuilder private var findingsSection: some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "What your heart shows")
                StrandCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(findings) { f in PremiumFindingRow(finding: f) }
                    }
                }
            }
        }
    }

    // MARK: Baselines (RHR + HRV vs personal normal)

    private var baselinesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PremiumSectionHeader(title: "Against your baseline")
            baselineCard(.restingHr, analysis: rhrAnalysis)
            baselineCard(.hrv, analysis: hrvAnalysis)
        }
    }

    private func baselineCard(_ id: PremiumMetricID, analysis a: PremiumMetricAnalysis) -> some View {
        let d: PremiumMetricDef = PremiumMetricCatalog.def(id)
        let values: [Double] = Array(a.series.suffix(30).map(\.value))
        return NavigationLink(value: PremiumRoute.catalogMetric(id)) {
            StrandCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        PremiumIconTile(system: d.icon, tint: d.tint, size: 30)
                        Text(d.name).font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    if values.count >= 2 {
                        MetricValueHeader(
                            value: a.latest.map { d.format($0, withUnit: false) } ?? "—",
                            unit: d.unit,
                            deltaText: baselineDelta(id, a),
                            deltaGood: baselineGood(id, a),
                            caption: baselineCaption(a, def: d),
                            tint: d.tint)
                        BaselineBandChart(values: values, baseline: a.baseline, spread: a.spread,
                                          tint: d.tint, height: 96,
                                          valueFormat: { d.format($0, withUnit: false) })
                        // Range + period change live INSIDE the baseline card rather than in a
                        // separate section: "what is it now, what's normal for me, how wide does it
                        // swing, and is it improving" is one question, so it gets one card.
                        if let lo = values.min(), let hi = values.max() {
                            Text(String(format: String(localized: "Ranged %1$@–%2$@ over these %3$d readings"),
                                        d.format(lo, withUnit: false), d.format(hi, withUnit: false),
                                        values.count))
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        }
                        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                        HStack(spacing: 14) {
                            changeStat("7D", PremiumMetricCatalog.changeText(id, pct: a.change7, abs: a.change7Abs),
                                      PremiumMetricCatalog.changeGood(id, pct: a.change7, abs: a.change7Abs))
                            changeStat("30D", PremiumMetricCatalog.changeText(id, pct: a.change30, abs: a.change30Abs),
                                      PremiumMetricCatalog.changeGood(id, pct: a.change30, abs: a.change30Abs))
                            changeStat("90D", PremiumMetricCatalog.changeText(id, pct: a.change90, abs: a.change90Abs),
                                      PremiumMetricCatalog.changeGood(id, pct: a.change90, abs: a.change90Abs))
                        }
                    } else {
                        MetricUnavailable(name: d.shortName,
                                          reason: "Not enough readings recorded yet.")
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func baselineDelta(_ id: PremiumMetricID, _ a: PremiumMetricAnalysis) -> String? {
        PremiumMetricCatalog.deviationText(id, a)
    }
    private func baselineGood(_ id: PremiumMetricID, _ a: PremiumMetricAnalysis) -> Bool? {
        PremiumMetricCatalog.deviationGood(id, a)
    }
    private func baselineCaption(_ a: PremiumMetricAnalysis, def d: PremiumMetricDef) -> String? {
        guard let b = a.baseline else {
            return "Not enough history for a baseline yet — \(a.series.count) readings so far."
        }
        var s = "Your \(a.baselineN)-day baseline is \(d.format(b))"
        if a.runLength >= 3 { s += " · \(a.runLength) days \(a.runBelow ? "below" : "above")" }
        return s + "."
    }

    /// One 7/30/90-day change figure, using the same absolute-vs-percent display logic as the
    /// catalog detail screen so a metric flagged `usesAbsoluteDeviation` never shows a misleading
    /// percentage. Rendered inside `baselineCard`, not as its own section.
    private func changeStat(_ label: String, _ text: String?, _ good: Bool?) -> some View {
        let tint: Color = good == nil
            ? StrandPalette.textSecondary
            : (good! ? StrandPalette.recoveryColor(85) : StrandPalette.metricRose)
        return VStack(alignment: .leading, spacing: 3) {
            Text(text ?? "—").font(.system(size: 17, weight: .heavy)).monospacedDigit()
                .foregroundStyle(text == nil ? StrandPalette.textTertiary : tint)
            Text(label).font(StrandFont.overline).tracking(1.0)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Today's curve (zone-shaded)

    private var chartRange: ClosedRange<Double>? {
        guard let set = zoneSet else { return nil }
        let dataLo = bpmValues.min() ?? set.zones[0].lower
        let dataHi = bpmValues.max() ?? set.maxHR
        let lo = min(dataLo, set.zones[0].lower) - 4
        let hi = max(dataHi, set.maxHR) + 4
        return lo < hi ? lo...hi : nil
    }

    private var dayChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PremiumSectionHeader(title: "Through today")
            StrandCard {
                VStack(alignment: .leading, spacing: 10) {
                    if bpmValues.count >= 2, let range = chartRange, let set = zoneSet {
                        ZStack {
                            zoneRibbon(zoneRows(set: set, tiz: timeInZone), range: range)
                            Sparkline(values: bpmValues,
                                      gradient: Gradient(colors: [StrandPalette.metricRose,
                                                                  StrandPalette.metricRose.opacity(0.85)]),
                                      range: range,
                                      lineWidth: 2.5, showsArea: false, showsHead: true, showsHover: true,
                                      valueFormat: { "\(Int($0.rounded())) bpm" })
                        }
                        .frame(height: 150)
                        HStack {
                            Text("12a"); Spacer(); Text("6a"); Spacer(); Text("12p")
                            Spacer(); Text("6p"); Spacer(); Text("now")
                        }
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        Text(String(format: String(localized: "Shaded by your real zones · Tanaka max-HR, age %d"), profile.age))
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    } else {
                        MetricUnavailable(name: "Today's curve",
                                          reason: "No heart rate recorded yet today.")
                    }
                }
            }
        }
    }

    private func zoneRibbon(_ rows: [ZoneRow], range: ClosedRange<Double>) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ForEach(rows) { row in
                    let yTop: CGFloat = yFor(row.hi, range: range, height: geo.size.height)
                    let yBot: CGFloat = yFor(row.lo, range: range, height: geo.size.height)
                    Rectangle()
                        .fill(row.tint.opacity(0.14))
                        .frame(height: max(0, yBot - yTop))
                        .offset(y: yTop)
                }
            }
        }
    }

    private func yFor(_ value: Double, range: ClosedRange<Double>, height: CGFloat) -> CGFloat {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let frac = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        return height * CGFloat(1 - frac)
    }

    // MARK: Zones

    struct ZoneRow: Identifiable {
        let name: String; let lo: Double; let hi: Double; let tint: Color; let minutes: Double
        var id: String { name }
    }

    private func zoneRows(set: HRZoneSet, tiz: TimeInZone?) -> [ZoneRow] {
        func mins(_ zoneNumbers: [Int], includeBelow: Bool = false) -> Double {
            guard let tiz else { return 0 }
            let z = zoneNumbers.reduce(0.0) { $0 + tiz.seconds(inZone: $1) }
            return (z + (includeBelow ? tiz.belowZone1 : 0)) / 60.0
        }
        let z1 = set.zones[0], z2 = set.zones[1], z3 = set.zones[2], z4 = set.zones[3], z5 = set.zones[4]
        return [
            ZoneRow(name: "Peak", lo: z5.lower, hi: 999, tint: StrandPalette.metricRose, minutes: mins([5])),
            ZoneRow(name: "Cardio", lo: z4.lower, hi: z4.upper, tint: StrandPalette.effortColor, minutes: mins([4])),
            ZoneRow(name: "Aerobic", lo: z3.lower, hi: z3.upper, tint: StrandPalette.gold, minutes: mins([3])),
            ZoneRow(name: "Fat burn", lo: z2.lower, hi: z2.upper, tint: StrandPalette.recoveryColor(80), minutes: mins([2])),
            ZoneRow(name: "Resting", lo: 0, hi: z1.upper, tint: StrandPalette.metricCyan,
                    minutes: mins([1], includeBelow: true)),
        ]
    }

    @ViewBuilder private var zonesCard: some View {
        if let set = zoneSet {
            let rows: [ZoneRow] = zoneRows(set: set, tiz: timeInZone)
            let total: Double = max(1, rows.reduce(0.0) { $0 + $1.minutes })
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "Time in zone", trailing: "today")
                StrandCard {
                    VStack(alignment: .leading, spacing: 14) {
                        zoneStackBar(rows: rows, total: total)
                        VStack(spacing: 10) {
                            ForEach(rows) { z in zoneRowView(z, total: total) }
                        }
                        Text(String(format: String(localized: "Zones from your Tanaka max-HR (208 − 0.7 × age, age %d) — personal, not generic thresholds."), profile.age))
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// A single stacked bar showing how the whole day divided across zones — the proportional view
    /// that per-zone bars alone can't give.
    private func zoneStackBar(rows: [ZoneRow], total: Double) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(rows.reversed()) { z in
                    let frac: Double = z.minutes / total
                    if frac > 0.001 {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(z.tint)
                            .frame(width: max(2, geo.size.width * CGFloat(frac)))
                    }
                }
            }
        }
        .frame(height: 14)
    }

    private func zoneRowView(_ z: ZoneRow, total: Double) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(z.name).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                Text(z.hi >= 999 ? "\(Int(z.lo.rounded()))+" : "\(Int(z.lo.rounded()))–\(Int(z.hi.rounded()))")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
            .frame(width: 76, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset)
                    Capsule().fill(z.tint)
                        .frame(width: max(3, geo.size.width * CGFloat(z.minutes / total)))
                }
            }
            .frame(height: 10)
            Text(PremiumAnalysis.durText(z.minutes))
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: Physiological load (derived only where the data supports it)

    /// An estimate of daytime cardiovascular load: the share of today's recorded time spent
    /// meaningfully above the user's own resting baseline, plus how far above.
    ///
    /// This is deliberately conservative. It is computed ONLY from real recorded samples against a
    /// real personal resting baseline, it is labelled an estimate, and it is hidden entirely when
    /// the day has too few readings or no baseline — rather than presenting a number that would
    /// look authoritative without support. It is not a stress diagnosis.
    @ViewBuilder private var loadSection: some View {
        let rhrBase: Double? = rhrAnalysis.baseline
        if let base = rhrBase, bpmValues.count >= 24 {
            let elevated: [Double] = bpmValues.filter { $0 > base * 1.15 }
            let elevatedPct: Double = Double(elevated.count) / Double(bpmValues.count) * 100
            let restfulPct: Double = 100 - elevatedPct
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    PremiumSectionHeader(title: "Physiological load")
                    Spacer()
                    ProvenanceChip(provenance: .calculated)
                }
                StrandCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            loadStat("Restful", restfulPct, StrandPalette.recoveryColor(85))
                            loadStat("Elevated", elevatedPct, StrandPalette.metricRose)
                        }
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(StrandPalette.recoveryColor(85))
                                    .frame(width: max(2, geo.size.width * CGFloat(restfulPct / 100)))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(StrandPalette.metricRose)
                            }
                        }
                        .frame(height: 12)
                        Text(String(format: String(localized: "The share of today's recorded readings sitting more than 15%% above your %d bpm resting baseline. An estimate of cardiovascular load from real samples — not a stress score or a medical assessment."), Int(base.rounded())))
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func loadStat(_ label: String, _ pct: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(Int(pct.rounded()))%")
                .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                .foregroundStyle(tint)
            Text(label.uppercased()).font(StrandFont.overline).tracking(1.0)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Overnight

    /// Shared clock formatter for the overnight readout — a stored static rather than one built
    /// inside the `@ViewBuilder`, so no object is allocated per body evaluation.
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    @ViewBuilder private var overnightSection: some View {
        if overnight.count >= 4 {
            let values: [Double] = overnight.map(\.bpm)
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "Overnight", trailing: "last night")
                StrandCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ScrubbableChart(
                            values: values,
                            tint: StrandPalette.sleepDeep,
                            height: 130,
                            reference: restingHR.map(Double.init),
                            referenceTint: StrandPalette.metricCyan,
                            readout: { idx, v in
                                let t = self.overnight[min(idx, self.overnight.count - 1)].t
                                return "\(Self.clockFormatter.string(from: t)) · \(Int(v.rounded())) bpm"
                            },
                            idleLabel: "Drag to read any moment overnight")
                        if let lo = values.min(), let m = PremiumAnalysis.mean(values) {
                            Text(String(format: String(localized: "Dipped to %1$d bpm, averaging %2$d bpm. The dashed line is your resting heart rate."), Int(lo.rounded()), Int(m.rounded())))
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: Weekly pattern

    @ViewBuilder private var weekdaySection: some View {
        if !dailyRanges.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "Daily range", trailing: "14 days")
                StrandCard {
                    VStack(alignment: .leading, spacing: 10) {
                        RangeColumnChart(
                            columns: dailyRanges.map { r in
                                RangeColumnChart.Column(id: r.id, lo: r.lo, hi: r.hi,
                                                        marker: r.mean, label: r.label)
                            },
                            tint: StrandPalette.metricRose,
                            markerTint: StrandPalette.textPrimary,
                            height: 140)
                        Text("Each column spans that day's lowest to highest recorded heart rate; the dot marks the day's average.", comment: "Heart daily-range chart caption")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Distribution — ONE card, re-aimable between RHR and HRV.

    /// "How unusual is today?" for whichever signal the user points it at. Previously this was two
    /// stacked cards (four charts) asking the same question of two metrics; a selector gives both
    /// signals equal prominence without doubling the screen's length.
    @ViewBuilder private var distributionSection: some View {
        let a: PremiumMetricAnalysis = distributionMetric == .hrv ? hrvAnalysis : rhrAnalysis
        if a.series.count >= 10 {
            let d: PremiumMetricDef = PremiumMetricCatalog.def(distributionMetric)
            let tint: Color = d.tint
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "How unusual is today?")
                PremiumChipPicker<PremiumMetricID>(options: [
                    PremiumChipPicker<PremiumMetricID>.Option(
                        value: .restingHr,
                        label: PremiumMetricCatalog.def(.restingHr).shortName,
                        tint: PremiumMetricCatalog.def(.restingHr).tint),
                    PremiumChipPicker<PremiumMetricID>.Option(
                        value: .hrv,
                        label: PremiumMetricCatalog.def(.hrv).shortName,
                        tint: PremiumMetricCatalog.def(.hrv).tint),
                ], selection: $distributionMetric)
                StrandCard {
                    VStack(alignment: .leading, spacing: 10) {
                        DistributionHistogram(values: a.series.map(\.value), buckets: 12,
                                              tint: tint,
                                              highlight: a.latest, height: 110)
                        Text(distributionCaption(d, a))
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        if a.byWeekday.count >= 3 {
                            Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                            Text("BY DAY OF WEEK", comment: "Section label above a weekday pattern chart").font(StrandFont.overline).tracking(1.2)
                                .foregroundStyle(StrandPalette.textTertiary)
                            WeekdayPatternChart(byWeekday: a.byWeekday,
                                                tint: tint,
                                                format: { d.format($0, withUnit: false) })
                        }
                    }
                }
            }
        }
    }

    /// Places today's reading inside its own distribution — a percentile, so the histogram states
    /// how unusual today is rather than leaving the user to eyeball the marker.
    private func distributionCaption(_ d: PremiumMetricDef, _ a: PremiumMetricAnalysis) -> String {
        let values: [Double] = a.series.map(\.value)
        guard let latest = a.latest, values.count >= 10 else {
            return String(localized: "Your recorded readings, bucketed.")
        }
        let below: Int = values.filter { $0 < latest }.count
        let pct: Int = Int((Double(below) / Double(values.count) * 100).rounded())
        return String(format: String(localized: "Today's %1$@ sits higher than %2$d%% of your last %3$d readings."),
                      d.format(latest, withUnit: false), pct, values.count)
    }

    // MARK: Relationships — ONE card, ranked strongest-first, re-aimable.

    /// One computed relationship between two of the user's real signals.
    struct HeartRelationship: Identifiable {
        let a: PremiumMetricID
        let b: PremiumMetricID
        let correlation: Correlation
        let points: [CGPoint]
        var id: String { "\(a.rawValue).\(b.rawValue)" }
    }

    /// "What else moves with my heart signals?" — as ONE card showing the STRONGEST relationship
    /// first, with the others a tap away. Three stacked scatters said the same thing three times and
    /// left the user to work out which mattered; ranking answers that directly.
    @ViewBuilder private var relationshipSection: some View {
        if !relationships.isEmpty {
            let shown: HeartRelationship = relationships.first { $0.id == selectedRelationship }
                ?? relationships[0]
            let aName: String = PremiumMetricCatalog.def(shown.a).shortName
            let bName: String = PremiumMetricCatalog.def(shown.b).shortName
            let tint: Color = PremiumMetricCatalog.def(shown.a).tint
            let confidence: PremiumConfidence = PremiumConfidence.from(n: shown.correlation.n,
                                                                       strength: shown.correlation.r)
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "What moves with your heart")
                if relationships.count > 1 {
                    PremiumChipPicker<String>(
                        options: relationships.map { rel in
                            PremiumChipPicker<String>.Option(
                                value: rel.id,
                                label: String(format: String(localized: "%1$@ · %2$@"),
                                              PremiumMetricCatalog.def(rel.a).shortName,
                                              PremiumMetricCatalog.def(rel.b).shortName),
                                tint: PremiumMetricCatalog.def(rel.a).tint)
                        },
                        selection: selectedRelationshipBinding)
                }
                StrandCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Self.relationshipSentence(aName: aName, bName: bName,
                                                       r: shown.correlation.r))
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        CorrelationScatter(points: shown.points, tint: tint, height: 150)
                        HStack {
                            Text(String(format: String(localized: "%1$@ → %2$@"), aName, bName))
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textTertiary)
                            Spacer()
                            Text(String(format: String(localized: "r = %1$@ · %2$d days"),
                                        String(format: "%.2f", shown.correlation.r), shown.correlation.n))
                                .font(StrandFont.captionNumber)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        HStack {
                            Text(confidence.label).font(StrandFont.footnote)
                                .foregroundStyle(confidence.tint)
                            Spacer()
                            Text("association, not cause", comment: "Correlation disclaimer")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }
            }
        }
    }

    /// Non-causal plain-language read of the coefficient, so the scatter states its own conclusion
    /// instead of leaving the user to interpret a dot cloud.
    private static func relationshipSentence(aName: String, bName: String, r: Double) -> String {
        let mag: Double = abs(r)
        let strength: String = mag >= 0.6 ? String(localized: "strongly")
            : (mag >= 0.3 ? String(localized: "moderately") : String(localized: "weakly"))
        let template: String = r >= 0
            ? String(localized: "Your %1$@ and %2$@ have %3$@ risen and fallen together.")
            : String(localized: "Your %1$@ and %2$@ have %3$@ moved in opposite directions.")
        return String(format: template, aName, bName, strength)
    }

    /// Selection binding that falls back to the strongest relationship when nothing is chosen yet.
    private var selectedRelationshipBinding: Binding<String> {
        Binding(get: { selectedRelationship ?? relationships.first?.id ?? "" },
                set: { selectedRelationship = $0 })
    }

    // MARK: Journal relationships — do logged behaviours line up with HRV or RHR?

    @ViewBuilder private var journalRelationshipsSection: some View {
        if !journalFindings.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "Journal")
                StrandCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(journalFindings) { f in PremiumFindingRow(finding: f) }
                        Text("Associations from your own logged history — not proven causes.", comment: "Heart journal-associations disclaimer")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Normalises aligned pairs into the unit square the scatter plots in. Pulled out of the view
    /// body deliberately — inlining this arithmetic inside a `@ViewBuilder` is what previously
    /// exhausted the type-checker's budget.
    private static func normalise(_ pairs: [(Double, Double)]) -> [CGPoint] {
        guard !pairs.isEmpty else { return [] }
        let xs: [Double] = pairs.map(\.0)
        let ys: [Double] = pairs.map(\.1)
        let xlo: Double = xs.min() ?? 0, xhi: Double = xs.max() ?? 1
        let ylo: Double = ys.min() ?? 0, yhi: Double = ys.max() ?? 1
        let xspan: Double = max(xhi - xlo, 0.0001)
        let yspan: Double = max(yhi - ylo, 0.0001)
        var out: [CGPoint] = []
        out.reserveCapacity(pairs.count)
        for i in 0..<pairs.count {
            let nx: Double = (xs[i] - xlo) / xspan
            let ny: Double = (ys[i] - ylo) / yspan
            out.append(CGPoint(x: CGFloat(nx), y: CGFloat(ny)))
        }
        return out
    }
}
#endif
