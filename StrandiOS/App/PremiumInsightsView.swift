#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Phase 2 · Insights — the prototype's "why, explained" cards, native SwiftUI computed
/// from real `repo.days` history: HRV vs baseline, the recovery trend, sleep-efficiency
/// movement and skin-temperature deviation, each turned into a plain-language insight with
/// tags. No hardcoded numbers — every figure is derived from DailyMetric history.
struct PremiumInsightsView: View {
    @EnvironmentObject var repo: Repository

    private func latest<T>(_ key: (DailyMetric) -> T?) -> T? {
        for d in repo.days.reversed() { if let v = key(d) { return v } }
        return repo.today.flatMap(key)
    }
    private func mean(_ key: (DailyMetric) -> Double?, _ n: Int = 30) -> Double? {
        let xs = repo.days.suffix(n).compactMap(key)
        return xs.isEmpty ? nil : xs.reduce(0,+)/Double(xs.count)
    }

    private struct Insight: Identifiable { let id = UUID(); let icon: String; let tint: Color
        let title: String; let body: String; let tags: [String] }

    private var insights: [Insight] {
        var out: [Insight] = []
        if let h = latest({ $0.avgHrv }), let base = mean({ $0.avgHrv }) {
            let pct = Int(((h - base) / base * 100).rounded())
            let dir = pct >= 0 ? "above" : "below"
            out.append(.init(icon: "waveform.path.ecg", tint: StrandPalette.metricCyan,
                title: pct >= 0 ? "HRV is holding strong" : "HRV dipped below baseline",
                body: "Your HRV is \(Int(h.rounded())) ms — about \(abs(pct))% \(dir) your 30-day baseline of \(Int(base.rounded())) ms. Consistent sleep timing is the strongest lever.",
                tags: ["HRV", "Recovery"]))
        }
        let rec = repo.days.suffix(14).compactMap { $0.recovery }
        if rec.count >= 4 {
            let half = rec.count/2
            let a = rec.prefix(half).reduce(0,+)/Double(half)
            let b = rec.suffix(rec.count-half).reduce(0,+)/Double(rec.count-half)
            let up = b >= a
            out.append(.init(icon: up ? "arrow.up.forward" : "arrow.down.forward",
                tint: StrandPalette.recoveryColor(80),
                title: up ? "Recovery is trending up" : "Recovery has eased",
                body: "Your recovery moved from about \(Int(a.rounded()))% to \(Int(b.rounded()))% over the last two weeks. \(up ? "Whatever you're doing is working — keep it steady." : "Look at sleep debt and recent strain to bring it back up.")",
                tags: ["Recovery", "14-day"]))
        }
        // DailyMetric.efficiency is a FRACTION in [0,1] (see SleepStageTotals.DailySleep's doc), not a
        // 0-100 percentage — normalize both before use, same defensive `<= 1.0 ? *100 : as-is` guard
        // SleepView.efficiencyPct uses, or "efficiency was 92%" would read "was 0%".
        if let eRaw = latest({ $0.efficiency }), let baseRaw = mean({ $0.efficiency }) {
            let e = eRaw <= 1.0 ? eRaw * 100 : eRaw
            let base = baseRaw <= 1.0 ? baseRaw * 100 : baseRaw
            let diff = Int((e - base).rounded())
            out.append(.init(icon: "moon.zzz.fill", tint: StrandPalette.sleepDeep,
                title: diff >= 0 ? "Sleep efficiency is solid" : "Restless nights lately",
                body: "Last night's sleep efficiency was \(Int(e))%, \(abs(diff)) points \(diff >= 0 ? "above" : "below") your recent average. A cooler, darker room is the highest-yield fix.",
                tags: ["Sleep", "Efficiency"]))
        }
        if let s = latest({ $0.skinTempDevC }) {
            out.append(.init(icon: "thermometer.medium", tint: StrandPalette.gold,
                title: abs(s) < 0.3 ? "Skin temp is stable" : "Skin temp nudged \(s >= 0 ? "up" : "down")",
                body: "Overnight skin temperature was \(String(format: "%+.1f", s))°C versus your baseline. \(abs(s) < 0.3 ? "Right in your normal range." : "Often tied to a warm room or a late meal — worth a glance if it persists.")",
                tags: ["Temperature"]))
        }
        return out
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                summaryCard
                if insights.isEmpty {
                    StrandCard {
                        Text("Keep logging — a few more days of history unlock personalized insights.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(insights) { card($0) }
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 40)
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WHY, EXPLAINED").font(StrandFont.overline).tracking(1.4)
                .foregroundStyle(StrandPalette.textTertiary)
            Text("Insights").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCard: some View {
        StrandCard(tint: StrandPalette.gold) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(StrandPalette.gold)
                Text(summaryText).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var summaryText: String {
        guard let r = latest({ $0.recovery }) else { return "Log a few days to see what's moving your recovery." }
        return r >= 67 ? "Your signals are aligned — recovery is strong and the fundamentals are working."
                       : "A few levers can move your recovery up; the cards below explain what and why."
    }

    private func card(_ ins: Insight) -> some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: ins.icon).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ins.tint)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(ins.tint.opacity(0.16)))
                    Text(ins.title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 0)
                }
                Text(ins.body).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(ins.tags, id: \.self) { t in
                        Text(t.uppercased()).font(StrandFont.overline).tracking(0.6)
                            .foregroundStyle(ins.tint)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ins.tint.opacity(0.14)))
                    }
                }
            }
        }
    }
}
#endif
