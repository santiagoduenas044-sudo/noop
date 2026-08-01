#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// Phase 2 · Heart — the prototype's Heart screen, native SwiftUI on real data:
/// a live BPM hero with a pulsing heart (from `LiveState.heartRate`, the same source
/// the live strap feeds), the real day heart-rate curve loaded from `repo.hrBuckets`
/// with a real, age-personalized zone-shaded ribbon behind it, resting / average / max,
/// real time-in-zone (Tanaka-formula `HRZones`, the same engine `workoutZoneMinutes`
/// uses), and a resting-HR trend from `repo.days`.
///
/// Note: WHOOP straps report heart rate, not an ECG waveform, so the hero is an honest
/// live-pulse visualization — not a fabricated medical trace. The prototype's "ECG"
/// canvas is a synthetic animation with no real cardiac-electrical data behind it (WHOOP
/// straps use PPG, not ECG electrodes), so it's intentionally not reproduced here.
struct PremiumHeartView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var profile: ProfileStore

    @State private var dayHR: [HRBucket] = []
    @State private var beat = false
    /// Real, age-personalized zones (Tanaka HRmax formula) — same engine `Repository.workoutZoneMinutes`
    /// uses — replacing any fixed/guessed bpm thresholds.
    @State private var zoneSet: HRZoneSet?
    @State private var timeInZone: TimeInZone?

    private func latest<T>(_ key: (DailyMetric) -> T?) -> T? {
        for d in repo.days.reversed() { if let v = key(d) { return v } }
        return repo.today.flatMap(key)
    }
    private var restingHR: Int? { latest { $0.restingHr } }
    private var bpmValues: [Double] { dayHR.map { $0.bpm }.filter { $0 > 0 } }
    private var liveBPM: Int? {
        if let h = live.heartRate, h > 0 { return h }
        if let last = bpmValues.last { return Int(last.rounded()) }
        return restingHR
    }
    private var avgHR: Int? { bpmValues.isEmpty ? nil : Int((bpmValues.reduce(0,+) / Double(bpmValues.count)).rounded()) }
    private var maxHR: Int? { bpmValues.max().map { Int($0.rounded()) } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                liveHero
                statsRow
                dayChartCard
                zonesCard
                rhrTrendCard
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 96)
        }
        .background(ambient.ignoresSafeArea())
        .task(id: repo.refreshSeq) {
            let start = Calendar.current.startOfDay(for: Date())
            let from = Int(start.timeIntervalSince1970), to = Int(Date().timeIntervalSince1970)
            dayHR = await repo.hrBuckets(from: from, to: to, bucketSeconds: 300)
            let samples = await repo.hrSamples(from: from, to: to)
            let set = HRZones.zones(age: profile.age > 0 ? Double(profile.age) : 30)
            zoneSet = set
            timeInZone = samples.isEmpty ? nil : HRZones.timeInZone(samples, zoneSet: set)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { beat = true }
        }
    }

    private var ambient: some View {
        ZStack {
            StrandPalette.surfaceBase
            RadialGradient(colors: [StrandPalette.metricRose.opacity(0.16), .clear],
                           center: .init(x: 0.5, y: 0.06), startRadius: 0, endRadius: 340)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(restingHR.map { "LIVE · RESTING \($0) BPM" } ?? "LIVE")
                .font(StrandFont.overline).tracking(1.4).foregroundStyle(StrandPalette.textTertiary)
            Text("Heart").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Live hero

    private var liveHero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(StrandPalette.metricRose.opacity(0.5), lineWidth: 2)
                    .frame(width: 92, height: 92)
                    .scaleEffect(beat ? 1.35 : 0.9).opacity(beat ? 0 : 0.6)
                Image(systemName: "heart.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(StrandPalette.metricRose)
                    .scaleEffect(beat ? 1.12 : 1.0)
                    .shadow(color: StrandPalette.metricRose.opacity(0.6), radius: 16)
            }
            .frame(height: 110)
            Text(liveBPM.map(String.init) ?? "—")
                .font(.system(size: 62, weight: .heavy)).monospacedDigit()
                .foregroundStyle(StrandPalette.metricRose)
            Text("BPM · LIVE").font(StrandFont.overline).tracking(1.4)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            stat("Resting", restingHR, "bpm", StrandPalette.metricCyan)
            stat("Average", avgHR, "bpm", StrandPalette.gold)
            stat("Max", maxHR, "bpm", StrandPalette.metricRose)
        }
    }
    private func stat(_ label: String, _ value: Int?, _ unit: String, _ tint: Color) -> some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    CountUpText(value: value.map(Double.init) ?? 0,
                                format: { value == nil ? "—" : "\(Int($0.rounded()))" },
                                font: .system(size: 24, weight: .heavy),
                                color: StrandPalette.textPrimary)
                        .monospacedDigit()
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Day HR chart (zone-shaded ribbon)

    /// The chart's vertical bpm range: wide enough to cover both today's actual readings and the
    /// full real zone spread, so the zone-shaded bands and the line always share one scale.
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
            Text("Today").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            StrandCard {
                VStack(alignment: .leading, spacing: 8) {
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
                    } else if bpmValues.count >= 2 {
                        Sparkline(values: bpmValues,
                                  gradient: Gradient(colors: [StrandPalette.metricRose,
                                                              StrandPalette.metricRose.opacity(0.55)]),
                                  lineWidth: 2, showsArea: true, showsHead: true, showsHover: true,
                                  valueFormat: { "\(Int($0.rounded())) bpm" })
                            .frame(height: 150)
                    } else {
                        Text("No heart-rate recorded yet today")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 150)
                    }
                }
            }
        }
    }

    /// Horizontal zone bands drawn behind the HR line, in the SAME value range as the Sparkline
    /// above it, so the line visibly crosses real zone boundaries as it moves through the day.
    private func zoneRibbon(_ rows: [ZoneRow], range: ClosedRange<Double>) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ForEach(rows) { row in
                    let yTop = yFor(row.hi, range: range, height: geo.size.height)
                    let yBot = yFor(row.lo, range: range, height: geo.size.height)
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

    // MARK: Zones (real: Tanaka age-predicted max HR + HRZones.timeInZone)

    private struct ZoneRow: Identifiable {
        let name: String; let lo: Double; let hi: Double; let tint: Color; let minutes: Double
        var id: String { name }
    }

    /// The 5 real zone rows built from a personalized `HRZoneSet` (Tanaka HRmax from age) and real
    /// time-in-zone. "Resting" merges Zone 1 with below-Zone-1 time, matching the 5-row layout the
    /// prototype's fixed thresholds used — only the BOUNDS and MINUTES are now real, not guessed.
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
            let rows = zoneRows(set: set, tiz: timeInZone)
            let maxMin = max(1, rows.map(\.minutes).max() ?? 1)
            VStack(alignment: .leading, spacing: 14) {
                Text("Zones today").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                StrandCard {
                    VStack(spacing: 12) {
                        ForEach(rows) { z in
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
                                            .frame(width: max(3, geo.size.width * CGFloat(z.minutes / maxMin)))
                                    }
                                }
                                .frame(height: 10)
                                Text(durText(z.minutes)).font(StrandFont.captionNumber)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .frame(width: 46, alignment: .trailing)
                            }
                        }
                        Text("Zones from your Tanaka max-HR (208 − 0.7 × age, age \(profile.age)) · on-device")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: Resting-HR trend

    private var rhrTrendCard: some View {
        let series = Array(repo.days.suffix(90).compactMap { $0.restingHr.map(Double.init) }.suffix(14))
        return VStack(alignment: .leading, spacing: 14) {
            Text("Resting HR · last 14 days").font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            StrandCard {
                if series.count >= 2 {
                    Sparkline(values: series,
                              gradient: Gradient(colors: [StrandPalette.metricCyan,
                                                          StrandPalette.metricCyan.opacity(0.55)]),
                              lineWidth: 2.5, showsArea: true, showsHead: true, showsHover: true,
                              valueFormat: { "\(Int($0.rounded())) bpm" })
                        .frame(height: 110)
                } else {
                    Text("Not enough days yet").font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 110)
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
