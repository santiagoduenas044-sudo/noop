#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Phase 2 · Energy / Calories — native rebuild of the prototype's Energy screen on REAL data. Active
/// energy is the strap's on-device HR-only estimate (`DailyMetric.activeKcalEst`); resting energy is a
/// clearly-labelled Mifflin–St Jeor BMR estimate from the user's profile (age / sex / weight / height) —
/// a standard formula, not a measurement NOOP claims to have taken. If active energy was never recorded the
/// screen says so instead of inventing a number.
struct PremiumEnergyView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var profile: ProfileStore

    private func latest<T>(_ key: (DailyMetric) -> T?) -> T? {
        for d in repo.days.reversed() { if let v = key(d) { return v } }
        return repo.today.flatMap(key)
    }
    /// Real daily active-energy series (kcal), oldest→newest, nil-free.
    private var activeSeries: [Double] { repo.days.compactMap { $0.activeKcalEst } }
    private var activeToday: Double? { latest { $0.activeKcalEst } }
    private var stepsToday: Int? { latest { $0.steps } }

    /// Resting energy for a full day via Mifflin–St Jeor BMR (kcal/day). An ESTIMATE from profile, always
    /// labelled as such — never presented as a strap measurement.
    private var restingKcal: Double? {
        let w = profile.weightKg, h = profile.heightCm, a = Double(profile.age)
        guard w > 0, h > 0, a > 0 else { return nil }
        let constant: Double
        switch profile.sex.lowercased() {
        case "male": constant = 5
        case "female": constant = -161
        default: constant = -78   // neutral midpoint for non-binary / unspecified
        }
        return 10 * w + 6.25 * h - 5 * a + constant
    }
    private var totalToday: Double? {
        switch (activeToday, restingKcal) {
        case let (a?, r?): return a + r
        case let (a?, nil): return a
        case let (nil, r?): return r
        default: return nil
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if activeToday == nil && restingKcal == nil {
                    emptyState
                } else {
                    hero
                    splitCard
                    statsRow
                    weeklyCard
                }
                explanationCard
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 96)
        }
        .background(ambient.ignoresSafeArea())
        .navigationTitle("Energy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ambient: some View {
        ZStack {
            StrandPalette.surfaceBase
            RadialGradient(colors: [StrandPalette.metricAmber.opacity(0.14), .clear],
                           center: .init(x: 0.5, y: 0.05), startRadius: 0, endRadius: 320)
        }
    }

    // MARK: Hero — total energy today

    private var hero: some View {
        StrandCard(tint: StrandPalette.metricAmber) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    iconTile("flame.fill", tint: StrandPalette.metricAmber)
                    Text("TOTAL ENERGY · TODAY").font(StrandFont.overline).tracking(1.4)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountUpText(value: totalToday ?? 0, format: { "\(Int($0.rounded()))" },
                                font: .system(size: 46, weight: .heavy), color: StrandPalette.textPrimary)
                        .monospacedDigit()
                    Text("kcal").font(StrandFont.headline).foregroundStyle(StrandPalette.textTertiary)
                }
                Text(heroSub).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
    private var heroSub: String {
        var parts: [String] = []
        if let a = activeToday { parts.append("\(Int(a.rounded())) active") }
        if let r = restingKcal { parts.append("\(Int(r.rounded())) resting (est.)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " + ")
    }

    // MARK: Active / resting split

    @ViewBuilder private var splitCard: some View {
        if let a = activeToday, let r = restingKcal {
            let total = max(1, a + r)
            StrandCard {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("Active vs resting")
                    GeometryReader { geo in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 5).fill(StrandPalette.metricAmber)
                                .frame(width: max(4, geo.size.width * CGFloat(a / total)))
                            RoundedRectangle(cornerRadius: 5).fill(StrandPalette.restColor)
                                .frame(width: max(4, geo.size.width * CGFloat(r / total)))
                        }
                    }
                    .frame(height: 14)
                    HStack(spacing: 18) {
                        legendDot("Active", StrandPalette.metricAmber, "\(Int(a.rounded())) kcal")
                        legendDot("Resting (est.)", StrandPalette.restColor, "\(Int(r.rounded())) kcal")
                        Spacer()
                    }
                }
            }
        }
    }

    private func legendDot(_ name: String, _ color: Color, _ value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text(value).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
            }
        }
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile("ACTIVE", activeToday.map { "\(Int($0.rounded()))" } ?? "—", "kcal", StrandPalette.metricAmber)
            statTile("STEPS", stepsToday.map(String.init) ?? "—", "", StrandPalette.recoveryColor(80))
            statTile("RESTING", restingKcal.map { "\(Int($0.rounded()))" } ?? "—", "est.", StrandPalette.restColor)
        }
    }

    private func statTile(_ label: String, _ value: String, _ unit: String, _ tint: Color) -> some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(StrandFont.overline).tracking(1.2).foregroundStyle(StrandPalette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 21, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                    if !unit.isEmpty {
                        Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Weekly active energy

    @ViewBuilder private var weeklyCard: some View {
        let recent = Array(activeSeries.suffix(7))
        if recent.count >= 2 {
            let maxV = max(1, recent.max() ?? 1)
            StrandCard {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("Active energy · last \(recent.count) days")
                    GeometryReader { geo in
                        let barW = (geo.size.width - CGFloat(recent.count - 1) * 8) / CGFloat(recent.count)
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(Array(recent.enumerated()), id: \.offset) { _, v in
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(LinearGradient(colors: [StrandPalette.metricAmber,
                                                                  StrandPalette.metricAmber.opacity(0.6)],
                                                         startPoint: .top, endPoint: .bottom))
                                    .frame(width: barW, height: max(4, geo.size.height * CGFloat(v / maxV)))
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: 120)
                }
            }
        }
    }

    // MARK: Explanation

    private var explanationCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("How this is calculated")
                Text("Active energy is estimated on-device from your heart rate through the day — a rough figure, best read as a trend. Resting energy is a Mifflin–St Jeor BMR estimate from your profile (age, sex, weight, height), not a measurement your strap took. NOOP never sends this off your device.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
        }
    }

    private var emptyState: some View {
        StrandCard {
            VStack(spacing: 12) {
                iconTile("flame.fill", tint: StrandPalette.metricAmber)
                Text("No energy recorded yet").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text("Wear your strap through the day and add your body metrics in Settings to see active and resting energy.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
        }
    }

    // MARK: Shared

    private func sectionLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(StrandFont.overline).tracking(1.3).foregroundStyle(StrandPalette.textTertiary)
    }
    private func iconTile(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }
}
#endif
