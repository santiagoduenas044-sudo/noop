#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// Phase 2 · Strain / Activity — native rebuild of the prototype's Strain screen on REAL data: the day's
/// strain (0–21) with a recovery-informed suggested range, real activity tiles (active energy, steps,
/// workouts), the day heart-rate timeline from `repo.hrBuckets`, real time-in-zone from a personalized
/// `HRZoneSet` (Tanaka), and a weekly strain trend from `repo.days`.
struct PremiumStrainView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var profile: ProfileStore

    @State private var dayHR: [HRBucket] = []
    @State private var zoneSet: HRZoneSet?
    @State private var timeInZone: TimeInZone?

    private func latest<T>(_ key: (DailyMetric) -> T?) -> T? {
        for d in repo.days.reversed() { if let v = key(d) { return v } }
        return repo.today.flatMap(key)
    }
    private var strain: Double? { latest { $0.strain } }
    private var recovery: Double? { latest { $0.recovery } }
    private var activeKcal: Double? { latest { $0.activeKcalEst } }
    private var steps: Int? { latest { $0.steps } }
    private var workouts: Int? { latest { $0.exerciseCount } }
    private var bpmValues: [Double] { dayHR.map(\.bpm).filter { $0 > 0 } }

    /// Suggested strain ceiling from today's recovery: greener → more room to push (WHOOP's own idea, our
    /// own simple mapping). A range around that target, clamped to the 0–21 scale.
    private var suggested: (lo: Double, hi: Double)? {
        guard let r = recovery else { return nil }
        let target = 6 + (r / 100) * 12       // 6 at 0% recovery → 18 at 100%
        return (max(0, target - 2), min(21, target + 2))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                heroRing
                if suggested != nil { suggestedCard }
                activityTiles
                if bpmValues.count >= 2 { dayHRCard }
                if zoneSet != nil { zonesCard }
                weeklyStrainCard
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 96)
        }
        .background(ambient.ignoresSafeArea())
        .navigationTitle("Strain")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: repo.refreshSeq) {
            let start = Calendar.current.startOfDay(for: Date())
            let from = Int(start.timeIntervalSince1970), to = Int(Date().timeIntervalSince1970)
            dayHR = await repo.hrBuckets(from: from, to: to, bucketSeconds: 300)
            let samples = await repo.hrSamples(from: from, to: to)
            let set = HRZones.zones(age: profile.age > 0 ? Double(profile.age) : 30)
            zoneSet = set
            timeInZone = samples.isEmpty ? nil : HRZones.timeInZone(samples, zoneSet: set)
        }
    }

    private var ambient: some View {
        ZStack {
            StrandPalette.surfaceBase
            RadialGradient(colors: [StrandPalette.effortColor.opacity(0.15), .clear],
                           center: .init(x: 0.5, y: 0.05), startRadius: 0, endRadius: 340)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TODAY'S EFFORT").font(StrandFont.overline).tracking(1.4)
                .foregroundStyle(StrandPalette.textTertiary)
            Text("Strain").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Hero ring

    private var heroRing: some View {
        let frac = min(1, max(0, (strain ?? 0) / 21))
        return ZStack {
            Circle().stroke(StrandPalette.surfaceInset, lineWidth: 14)
            Circle().trim(from: 0, to: frac)
                .stroke(LinearGradient(colors: [StrandPalette.effortColor, StrandPalette.effortColor.opacity(0.7)],
                                       startPoint: .topTrailing, endPoint: .bottomLeading),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: StrandPalette.effortColor.opacity(0.4), radius: 8)
            VStack(spacing: 2) {
                CountUpText(value: strain ?? 0, format: { strain == nil ? "—" : String(format: "%.1f", $0) },
                            font: .system(size: 44, weight: .heavy), color: StrandPalette.textPrimary)
                    .monospacedDigit()
                Text("OF 21").font(.system(size: 9, weight: .bold)).tracking(1)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .frame(width: 176, height: 176)
        .frame(maxWidth: .infinity)
    }

    // MARK: Suggested range

    @ViewBuilder private var suggestedCard: some View {
        if let s = suggested {
            StrandCard {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Suggested range · from today's recovery")
                    GeometryReader { geo in
                        let w = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(StrandPalette.surfaceInset).frame(height: 10)
                            Capsule().fill(StrandPalette.effortColor.opacity(0.35))
                                .frame(width: w * CGFloat((s.hi - s.lo) / 21), height: 10)
                                .offset(x: w * CGFloat(s.lo / 21))
                            if let st = strain {
                                Circle().fill(StrandPalette.effortColor).frame(width: 16, height: 16)
                                    .overlay(Circle().strokeBorder(StrandPalette.surfaceBase, lineWidth: 2))
                                    .offset(x: max(0, min(w - 16, w * CGFloat(st / 21) - 8)))
                            }
                        }
                    }
                    .frame(height: 18)
                    Text("Aim for a strain of \(String(format: "%.0f", s.lo))–\(String(format: "%.0f", s.hi)) today. Greener recovery leaves more room to push; a lower score suggests holding back.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Activity tiles

    private var activityTiles: some View {
        HStack(spacing: 12) {
            tile("flame.fill", StrandPalette.metricAmber, "Active", activeKcal.map { "\(Int($0.rounded()))" } ?? "—", "kcal")
            tile("figure.walk", StrandPalette.recoveryColor(80), "Steps", steps.map(String.init) ?? "—", "")
            tile("figure.run", StrandPalette.effortColor, "Workouts", workouts.map(String.init) ?? "0", "")
        }
    }
    private func tile(_ icon: String, _ tint: Color, _ label: String, _ value: String, _ unit: String) -> some View {
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

    // MARK: Day HR timeline

    private var dayHRCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Heart rate · today")
                Sparkline(values: bpmValues,
                          gradient: Gradient(colors: [StrandPalette.metricRose, StrandPalette.metricRose.opacity(0.55)]),
                          lineWidth: 2, showsArea: true, showsHead: true, showsHover: true,
                          valueFormat: { "\(Int($0.rounded())) bpm" })
                    .frame(height: 130)
                HStack {
                    Text("12a"); Spacer(); Text("6a"); Spacer(); Text("12p"); Spacer(); Text("6p"); Spacer(); Text("now")
                }
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    // MARK: Zones

    @ViewBuilder private var zonesCard: some View {
        if let set = zoneSet, let tiz = timeInZone {
            let rows = zoneRows(set: set, tiz: tiz)
            let maxMin = max(1, rows.map(\.minutes).max() ?? 1)
            StrandCard {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Time in zone · today")
                    ForEach(rows) { z in
                        HStack(spacing: 12) {
                            Text(z.name).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                                .frame(width: 72, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(StrandPalette.surfaceInset)
                                    Capsule().fill(z.tint)
                                        .frame(width: max(3, geo.size.width * CGFloat(z.minutes / maxMin)))
                                }
                            }
                            .frame(height: 10)
                            Text(durText(z.minutes)).font(StrandFont.captionNumber)
                                .foregroundStyle(StrandPalette.textSecondary).frame(width: 46, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private struct ZoneRow: Identifiable {
        let name: String; let tint: Color; let minutes: Double
        var id: String { name }
    }
    private func zoneRows(set: HRZoneSet, tiz: TimeInZone) -> [ZoneRow] {
        func mins(_ z: Int, includeBelow: Bool = false) -> Double {
            (tiz.seconds(inZone: z) + (includeBelow ? tiz.belowZone1 : 0)) / 60.0
        }
        return [
            ZoneRow(name: "Peak", tint: StrandPalette.metricRose, minutes: mins(5)),
            ZoneRow(name: "Cardio", tint: StrandPalette.effortColor, minutes: mins(4)),
            ZoneRow(name: "Aerobic", tint: StrandPalette.gold, minutes: mins(3)),
            ZoneRow(name: "Fat burn", tint: StrandPalette.recoveryColor(80), minutes: mins(2)),
            ZoneRow(name: "Resting", tint: StrandPalette.metricCyan, minutes: mins(1, includeBelow: true)),
        ]
    }

    // MARK: Weekly strain

    @ViewBuilder private var weeklyStrainCard: some View {
        let recent = Array(repo.days.suffix(90).compactMap { $0.strain }.suffix(7))
        if recent.count >= 2 {
            let maxV = max(1, recent.max() ?? 1)
            StrandCard {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("Strain · last \(recent.count) days")
                    GeometryReader { geo in
                        let barW = (geo.size.width - CGFloat(recent.count - 1) * 8) / CGFloat(recent.count)
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(Array(recent.enumerated()), id: \.offset) { _, v in
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(LinearGradient(colors: [StrandPalette.effortColor,
                                                                  StrandPalette.effortColor.opacity(0.6)],
                                                         startPoint: .top, endPoint: .bottom))
                                    .frame(width: barW, height: max(4, geo.size.height * CGFloat(v / maxV)))
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: 110)
                }
            }
        }
    }

    // MARK: Shared

    private func sectionLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(StrandFont.overline).tracking(1.3).foregroundStyle(StrandPalette.textTertiary)
    }
    private func iconTile(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }
    private func durText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded()); let h = m / 60, mm = m % 60
        return h > 0 ? "\(h)h \(mm)m" : "\(mm)m"
    }
}
#endif
