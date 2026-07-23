import SwiftUI
import StrandDesign
import StrandAnalytics

// RecoveryFactorsView.swift — "What moves your recovery", from the user's own history.
//
// The pure PersonalCorrelations engine finds which lifestyle factors genuinely track with Charge for
// THIS user; this renders them as a short, honest list. Copy says "tends to" / "tracks with" — never
// "causes" — and a footnote makes the association-not-proof point explicit. Design-system only.
// iPhone-first.

enum RecoveryFactorsCopy {

    /// A plain-language, direction-aware line for a correlated factor. `direction` is the sign of the
    /// correlation with Charge (positive = more of this, higher Charge).
    static func line(_ f: PersonalCorrelations.Factor) -> String {
        let pos = f.direction == .positive
        switch f.key {
        case "sleepDuration":
            return pos ? String(localized: "You tend to recover better after more sleep.")
                       : String(localized: "Longer nights tend to go with lower recovery for you.")
        case "sleepEfficiency":
            return pos ? String(localized: "Higher sleep efficiency tends to go with better recovery.")
                       : String(localized: "Lower sleep efficiency tends to go with better recovery.")
        case "restorative":
            return pos ? String(localized: "More deep + REM sleep tends to go with better recovery.")
                       : String(localized: "Less deep + REM sleep tends to go with better recovery.")
        case "awake":
            return pos ? String(localized: "More time awake in bed tends to go with higher recovery.")
                       : String(localized: "More time awake in bed tends to go with lower recovery.")
        default:
            return pos ? String(localized: "This tends to go with better recovery.")
                       : String(localized: "This tends to go with lower recovery.")
        }
    }

    static func strengthText(_ s: PersonalCorrelations.Strength) -> LocalizedStringKey {
        switch s {
        case .strong: return "Strong pattern"
        case .clear:  return "Clear pattern"
        case .mild:   return "Mild pattern"
        }
    }

    /// A better-recovery association is encouraging (green); a worse-recovery one is a caution (amber).
    static func tint(_ f: PersonalCorrelations.Factor) -> Color {
        let helpsRecovery: Bool = {
            switch f.key {
            case "awake": return f.direction == .negative     // less awake time helps
            default:      return f.direction == .positive      // more sleep/efficiency/restorative helps
            }
        }()
        return helpsRecovery ? StrandPalette.statusPositive : StrandPalette.statusWarning
    }

    static func symbol(_ f: PersonalCorrelations.Factor) -> String {
        f.direction == .positive ? "arrow.up.right" : "arrow.down.right"
    }
}

struct RecoveryFactorsView: View {
    let report: PersonalCorrelations.Report

    var body: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: 7) {
                    Image(systemName: "link")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(StrandPalette.chargeColor)
                    Text("What moves your recovery")
                        .font(StrandFont.caption.weight(.bold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(report.factors.enumerated()), id: \.offset) { _, f in
                        row(f)
                    }
                }

                Text("Patterns from your own history — associations, not proof of cause.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ f: PersonalCorrelations.Factor) -> some View {
        let tint = RecoveryFactorsCopy.tint(f)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: RecoveryFactorsCopy.symbol(f))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(RecoveryFactorsCopy.line(f))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(RecoveryFactorsCopy.strengthText(f.strength))
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(tint.opacity(0.14)))
            }
        }
    }
}

#if DEBUG
#Preview("What moves recovery") {
    let report = PersonalCorrelations.Report(factors: [
        .init(key: "sleepDuration", r: 0.58, n: 24, direction: .positive, strength: .strong),
        .init(key: "awake", r: -0.41, n: 22, direction: .negative, strength: .clear),
        .init(key: "restorative", r: 0.33, n: 20, direction: .positive, strength: .mild),
    ])
    return ScrollView { RecoveryFactorsView(report: report).padding() }
        .background(StrandPalette.surfaceBase)
}
#endif
