#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Phase 2 · Blood Oxygen (SpO₂) — native rebuild of the prototype's `spo2.js`. Shows a REAL calibrated
/// SpO₂ percentage ONLY when the banked data carries one (`DailyMetric.spo2Pct`, present on imported rows).
/// The on-device WHOOP 4.0 engine banks only the RAW red/IR PPG ADC means (`spo2Red`/`spo2Ir`), not a
/// calibrated percentage — that needs WHOOP's proprietary curve — so for most users there is no honest
/// number to show, and this screen renders an explicit empty state rather than inventing one. "NOOP never
/// invents a measurement" is the whole point of this screen.
struct PremiumBloodOxygenView: View {
    @EnvironmentObject var repo: Repository

    /// Real nightly SpO₂ percentages, oldest→newest, nil-free.
    private var series: [Double] { repo.days.compactMap { $0.spo2Pct } }
    private var latest: Double? { series.last }
    private var baseline: Double? {
        let recent = series.suffix(30)
        guard recent.count >= 3 else { return nil }
        return recent.reduce(0, +) / Double(recent.count)
    }
    private let tint = StrandPalette.metricPurple

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if series.isEmpty {
                    emptyState
                } else {
                    hero
                    statsRow
                    trendCard
                    rangeCard
                }
                explanationCard
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 96)
        }
        .background(ambient.ignoresSafeArea())
        .navigationTitle("Blood Oxygen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ambient: some View {
        ZStack {
            StrandPalette.surfaceBase
            RadialGradient(colors: [tint.opacity(0.14), .clear],
                           center: .init(x: 0.5, y: 0.05), startRadius: 0, endRadius: 320)
        }
    }

    private var hero: some View {
        StrandCard(tint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    iconTile("drop.fill", tint: tint)
                    Text("BLOOD OXYGEN · LAST NIGHT").font(StrandFont.overline).tracking(1.4)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountUpText(value: latest ?? 0, format: { "\(Int($0.rounded()))" },
                                font: .system(size: 46, weight: .heavy), color: StrandPalette.textPrimary)
                        .monospacedDigit()
                    Text("%").font(StrandFont.headline).foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                    if let b = baseline {
                        Text("baseline \(Int(b.rounded()))%")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(StrandPalette.textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(StrandPalette.surfaceInset))
                    }
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile("AVG", baseline.map { "\(Int($0.rounded()))" } ?? "—", "%")
            statTile("LOW", series.min().map { "\(Int($0.rounded()))" } ?? "—", "%")
            statTile("HIGH", series.max().map { "\(Int($0.rounded()))" } ?? "—", "%")
        }
    }
    private func statTile(_ label: String, _ value: String, _ unit: String) -> some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(StrandFont.overline).tracking(1.2).foregroundStyle(StrandPalette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var trendCard: some View {
        let recent = Array(series.suffix(30))
        if recent.count >= 2 {
            StrandCard {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Nightly trend · last \(recent.count)")
                    Sparkline(values: recent,
                              gradient: Gradient(colors: [tint, tint.opacity(0.55)]),
                              lineWidth: 2.5, showsArea: true, showsHead: true, showsHover: true,
                              valueFormat: { "\(Int($0.rounded()))%" })
                        .frame(height: 130)
                }
            }
        }
    }

    @ViewBuilder private var rangeCard: some View {
        let lo = series.min() ?? 90, hi = series.max() ?? 100
        let now = latest ?? lo
        let frac = hi > lo ? (now - lo) / (hi - lo) : 0.5
        StrandCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Where last night sits")
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(StrandPalette.surfaceInset).frame(height: 8)
                        Capsule().fill(LinearGradient(colors: [tint.opacity(0.5), tint],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * CGFloat(min(1, max(0, frac)))), height: 8)
                        Circle().fill(tint).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(StrandPalette.surfaceBase, lineWidth: 2))
                            .offset(x: max(0, min(geo.size.width - 16, geo.size.width * CGFloat(min(1, max(0, frac))) - 8)))
                    }
                }
                .frame(height: 18)
                HStack {
                    Text("\(Int(lo.rounded()))%").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                    Text("\(Int(hi.rounded()))%").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    private var explanationCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("About blood oxygen")
                Text("SpO₂ is the percentage of your blood's oxygen-carrying capacity in use, measured overnight from the strap's optical sensor. Most nights sit in the mid-to-high 90s. NOOP shows a percentage only when it has a calibrated reading — the raw optical signal alone isn't a blood-oxygen number, so it's never presented as one.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
        }
    }

    private var emptyState: some View {
        StrandCard {
            VStack(spacing: 12) {
                iconTile("drop.fill", tint: tint)
                Text("No calibrated SpO₂ yet").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text("Your WHOOP 4.0 records raw optical signal overnight, but a blood-oxygen percentage needs a calibrated conversion NOOP doesn't have on-device. When a calibrated reading is available (e.g. from an import) it will appear here. NOOP won't show a number it can't stand behind.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
        }
    }

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
