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
                Text(restingHR.map { "LIVE · RESTING \($0) BPM" } ?? "LIVE")
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
                Text("Today's range").font(StrandFont.headline)
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
                            deltaText: baselineDelta(a),
                            deltaGood: baselineGood(a, def: d),
                            caption: baselineCaption(a, def: d),
                            tint: d.tint)
                        BaselineBandChart(values: values, baseline: a.baseline, spread: a.spread,
                                          tint: d.tint, height: 96,
                                          valueFormat: { d.format($0, withUnit: false) })
                    } else {
                        MetricUnavailable(name: d.shortName,
                                          reason: "Not enough readings recorded yet.")
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func baselineDelta(_ a: PremiumMetricAnalysis) -> String? {
        guard a.hasBaseline, let pct = a.deviationPct else { return nil }
        return PremiumAnalysis.signedPct(pct)
    }
    private func baselineGood(_ a: PremiumMetricAnalysis, def d: PremiumMetricDef) -> Bool? {
        guard let hb = d.higherBetter, let pct = a.deviationPct, a.hasBaseline else { return nil }
        return hb ? pct >= 0 : pct <= 0
    }
    private func baselineCaption(_ a: PremiumMetricAnalysis, def d: PremiumMetricDef) -> String? {
        guard let b = a.baseline else {
            return "Not enough history for a baseline yet — \(a.series.count) readings so far."
        }
        var s = "Your \(a.baselineN)-day baseline is \(d.format(b))"
        if a.runLength >= 3 { s += " · \(a.runLength) days \(a.runBelow ? "below" : "above")" }
        return s + "."
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
                        Text("Shaded by your real zones · Tanaka max-HR, age \(profile.age)")
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
                        Text("Zones from your Tanaka max-HR (208 − 0.7 × age, age \(profile.age)) — personal, not generic thresholds.")
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
                        Text("The share of today's recorded readings sitting more than 15% above your \(Int(base.rounded())) bpm resting baseline. An estimate of cardiovascular load from real samples — not a stress score or a medical assessment.")
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
                            Text("Dipped to \(Int(lo.rounded())) bpm, averaging \(Int(m.rounded())) bpm. The dashed line is your resting heart rate.")
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
                        Text("Each column spans that day's lowest to highest recorded heart rate; the dot marks the day's average.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Distribution

    @ViewBuilder private var distributionSection: some View {
        let a: PremiumMetricAnalysis = rhrAnalysis
        if a.series.count >= 10 {
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "Resting HR distribution")
                StrandCard {
                    VStack(alignment: .leading, spacing: 10) {
                        DistributionHistogram(values: a.series.map(\.value), buckets: 12,
                                              tint: StrandPalette.metricCyan,
                                              highlight: a.latest, height: 110)
                        if a.byWeekday.count >= 3 {
                            Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                            Text("BY DAY OF WEEK").font(StrandFont.overline).tracking(1.2)
                                .foregroundStyle(StrandPalette.textTertiary)
                            WeekdayPatternChart(byWeekday: a.byWeekday,
                                                tint: StrandPalette.metricCyan,
                                                format: { "\(Int($0.rounded())) bpm" })
                        }
                    }
                }
            }
        }
    }

    // MARK: Relationship to recovery

    @ViewBuilder private var relationshipSection: some View {
        let hrvSeries: [PremiumSample] = PremiumMetricCatalog.series(.hrv, repo: repo)
        let recSeries: [PremiumSample] = PremiumMetricCatalog.series(.recovery, repo: repo)
        if let best = PremiumAnalysis.bestRelationship(hrvSeries, recSeries) {
            let pairs = CorrelationEngine.alignByDay(hrvSeries.map { (day: $0.day, value: $0.value) },
                                                     recSeries.map { (day: $0.day, value: $0.value) })
            let points: [CGPoint] = Self.normalise(pairs)
            VStack(alignment: .leading, spacing: 14) {
                PremiumSectionHeader(title: "HRV and recovery")
                StrandCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CorrelationScatter(points: points, tint: StrandPalette.metricCyan, height: 150)
                        HStack {
                            Text("HRV →").font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textTertiary)
                            Spacer()
                            Text("r = \(String(format: "%.2f", best.correlation.r)) · \(best.correlation.n) days")
                                .font(StrandFont.captionNumber)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        Text("Each dot is one day: your HRV against that day's recovery. This is an association measured in your own data, not a cause.")
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
