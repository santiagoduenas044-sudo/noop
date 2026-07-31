#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Phase 2 · Heart — the prototype's Heart screen, native SwiftUI on real data:
/// a live BPM hero with a pulsing heart (from `LiveState.heartRate`, the same source
/// the live strap feeds), the real day heart-rate curve loaded from `repo.hrBuckets`,
/// resting / average / max, real time-in-zone, and a resting-HR trend from `repo.days`.
///
/// Note: WHOOP straps report heart rate, not an ECG waveform, so the hero is an honest
/// live-pulse visualization — not a fabricated medical trace.
struct PremiumHeartView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState

    @State private var dayHR: [HRBucket] = []
    @State private var beat = false

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
            dayHR = await repo.hrBuckets(from: Int(start.timeIntervalSince1970),
                                         to: Int(Date().timeIntervalSince1970), bucketSeconds: 300)
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
                    Text(value.map(String.init) ?? "—").font(.system(size: 24, weight: .heavy))
                        .monospacedDigit().foregroundStyle(StrandPalette.textPrimary)
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Day HR chart

    private var dayChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            StrandCard {
                VStack(alignment: .leading, spacing: 8) {
                    if bpmValues.count >= 2 {
                        Sparkline(values: bpmValues,
                                  gradient: Gradient(colors: [StrandPalette.metricRose,
                                                              StrandPalette.metricRose.opacity(0.55)]),
                                  lineWidth: 2, showsArea: true, showsHead: true, showsHover: true,
                                  valueFormat: { "\(Int($0.rounded())) bpm" })
                            .frame(height: 150)
                        HStack {
                            Text("12a"); Spacer(); Text("6a"); Spacer(); Text("12p")
                            Spacer(); Text("6p"); Spacer(); Text("now")
                        }
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    } else {
                        Text("No heart-rate recorded yet today")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 150)
                    }
                }
            }
        }
    }

    // MARK: Zones

    private struct Zone { let name: String; let lo: Int; let hi: Int; let tint: Color }
    private var zones: [Zone] {
        [Zone(name: "Peak", lo: 171, hi: 999, tint: StrandPalette.metricRose),
         Zone(name: "Cardio", lo: 152, hi: 170, tint: StrandPalette.effortColor),
         Zone(name: "Aerobic", lo: 133, hi: 151, tint: StrandPalette.gold),
         Zone(name: "Fat burn", lo: 114, hi: 132, tint: StrandPalette.recoveryColor(80)),
         Zone(name: "Resting", lo: 0, hi: 113, tint: StrandPalette.metricCyan)]
    }
    private func zoneMinutes(_ z: Zone) -> Int {
        dayHR.filter { let b = Int($0.bpm.rounded()); return b >= z.lo && b <= z.hi }.count * 5
    }

    private var zonesCard: some View {
        let maxMin = max(1, zones.map(zoneMinutes).max() ?? 1)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Zones today").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            StrandCard {
                VStack(spacing: 12) {
                    ForEach(zones, id: \.name) { z in
                        let mins = zoneMinutes(z)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(z.name).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                                Text(z.hi >= 999 ? "\(z.lo)+" : "\(z.lo)–\(z.hi)")
                                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            }
                            .frame(width: 76, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(StrandPalette.surfaceInset)
                                    Capsule().fill(z.tint)
                                        .frame(width: max(3, geo.size.width * CGFloat(Double(mins) / Double(maxMin))))
                                }
                            }
                            .frame(height: 10)
                            Text(durText(Double(mins))).font(StrandFont.captionNumber)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .frame(width: 46, alignment: .trailing)
                        }
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
