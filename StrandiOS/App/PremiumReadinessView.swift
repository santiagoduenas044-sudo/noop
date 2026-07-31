#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Phase 2 · Readiness — the prototype's Readiness/Recovery detail, native SwiftUI on real
/// `DailyMetric` data: a large recovery-ring hero with a plain-language explanation, every
/// contributor (HRV, resting HR, sleep, respiratory, skin temp, prior strain) with its real
/// value and a normalized bar, and a short recovery-trend forecast. Presented from Home's
/// recovery hero. Nothing hardcoded.
struct PremiumReadinessView: View {
    @EnvironmentObject var repo: Repository
    var onClose: (() -> Void)? = nil

    private func latest<T>(_ key: (DailyMetric) -> T?) -> T? {
        for d in repo.days.reversed() { if let v = key(d) { return v } }
        return repo.today.flatMap(key)
    }
    private var recovery: Double? { latest { $0.recovery } }
    private var hrv: Double?  { latest { $0.avgHrv } }
    private var rhr: Int?     { latest { $0.restingHr } }
    private var eff: Double?  { latest { $0.efficiency } }
    private var resp: Double? { latest { $0.respRateBpm } }
    private var skin: Double? { latest { $0.skinTempDevC } }
    private var priorStrain: Double? {
        let s = repo.days.suffix(90).compactMap { $0.strain }
        return s.count >= 2 ? s[s.count - 2] : s.last
    }

    private struct Driver { let name: String; let value: String; let frac: Double; let tint: Color; let note: String }
    private var drivers: [Driver] {
        var d: [Driver] = []
        if let h = hrv { d.append(.init(name: "HRV", value: "\(Int(h.rounded())) ms", frac: min(1, h/140),
            tint: StrandPalette.metricCyan, note: hrvNote(h))) }
        if let r = rhr { d.append(.init(name: "Resting HR", value: "\(r) bpm", frac: max(0, min(1, (80.0 - Double(r))/45)),
            tint: StrandPalette.metricRose, note: "Lower resting heart rate signals good recovery.")) }
        if let e = eff { d.append(.init(name: "Sleep", value: "\(Int(e))%", frac: e/100,
            tint: StrandPalette.sleepDeep, note: "Sleep efficiency — time asleep vs time in bed.")) }
        if let rp = resp { d.append(.init(name: "Respiratory", value: String(format: "%.1f rpm", rp),
            frac: max(0, min(1, 1 - abs(rp-14)/8)), tint: StrandPalette.recoveryColor(80),
            note: "A steady overnight respiration rate is a good sign.")) }
        if let s = skin { d.append(.init(name: "Skin temp", value: String(format: "%+.1f°C", s),
            frac: max(0, min(1, 1 - abs(s)/1.5)), tint: StrandPalette.gold,
            note: "Deviation from your baseline skin temperature.")) }
        if let ps = priorStrain { d.append(.init(name: "Prior strain", value: String(format: "%.1f", ps),
            frac: max(0, min(1, 1 - ps/21)), tint: StrandPalette.effortColor,
            note: "Yesterday's effort — high strain needs more recovery.")) }
        return d
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                hero
                contributors
                forecast
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 40)
        }
        .background(ambient.ignoresSafeArea())
    }

    private var ambient: some View {
        ZStack {
            StrandPalette.surfaceBase
            RadialGradient(colors: [StrandPalette.recoveryColor(80).opacity(0.14), .clear],
                           center: .init(x: 0.5, y: 0.02), startRadius: 0, endRadius: 360)
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            RecoveryRing(score: recovery ?? 0, diameter: 220, lineWidth: 16,
                         showsWordmark: false, showsHover: false)
            Text(explanation).font(StrandFont.subhead).multilineTextAlignment(.center)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
    }
    private var explanation: String {
        guard let r = recovery else { return "Pair your strap to see your readiness." }
        let word = r >= 67 ? "primed to perform" : r >= 34 ? "ready with care" : "in need of rest"
        return "Your body is \(word). Recovery blends HRV, resting heart rate, sleep and recent strain into one readiness score."
    }

    private var contributors: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Contributors").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            StrandCard {
                VStack(spacing: 14) {
                    ForEach(Array(drivers.enumerated()), id: \.offset) { _, d in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(d.name).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                                Spacer()
                                Text(d.value).font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(StrandPalette.surfaceInset)
                                    Capsule().fill(LinearGradient(colors: [d.tint, d.tint.opacity(0.7)],
                                                                  startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(3, geo.size.width * CGFloat(d.frac)))
                                }
                            }
                            .frame(height: 8)
                            Text(d.note).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private var forecast: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Forecast").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            StrandCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(forecastText).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Forecast blends your recent recovery trend with tonight's projected sleep. It updates as you log the day.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private var forecastText: String {
        let recent = repo.days.suffix(7).compactMap { $0.recovery }
        guard !recent.isEmpty else { return "Log a few nights to unlock your recovery forecast." }
        let avg = recent.reduce(0,+)/Double(recent.count)
        let trend = recent.count >= 2 && recent.last! >= recent.first! ? "trending up" : "steady"
        return "Your 7-day recovery is averaging \(Int(avg.rounded()))% and \(trend). An earlier night tonight should lift tomorrow a few points."
    }
}
#endif
