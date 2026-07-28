import SwiftUI

// MARK: - Strand Typography (§9.2) — "Clinical Premium"
//
// Hero numerals (recovery %, HR, strain, etc.) use New York — Apple's native serif
// design — for a high-contrast, editorial read: the number dominates, everything else
// stays quiet. Labels and body copy stay on the system SF Pro face at regular/medium
// weight. Both roles go through `Font.system(size:weight:design:)`, which — unlike a
// named `.custom(_:size:)` font — scales automatically with Dynamic Type, so no manual
// `relativeTo:` plumbing is needed for either family.
//
// All numeric styles use `.monospacedDigit()` so live values don't reflow.

public enum StrandFont {

    // MARK: Family

    /// A New York serif at a given size/weight — the house numeral face for hero/dominant
    /// values (gauge centers, tile values). `Font.system(design:)` scales with Dynamic Type.
    private static func serif(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// SF Pro (system default) at a given size/weight — the house face for every label,
    /// caption and body role.
    private static func sfPro(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: Scale (§9.2)

    /// Display 64–80 / Bold — the gauge score number. New York serif, tight-but-not-crushed
    /// tracking, tabular digits so a changing value never reflows.
    public static func display(_ size: CGFloat = 72) -> Font {
        serif(size, weight: .bold).monospacedDigit()
    }

    /// The tracking for big serif display numbers (light, ≈ -0.015em — serif faces don't want
    /// the aggressive negative tracking a grotesque does). Apply alongside `display(_:)` at the
    /// use site, e.g. `.tracking(StrandFont.displayTracking(72))`.
    public static func displayTracking(_ size: CGFloat = 72) -> CGFloat {
        -size * 0.015
    }

    /// A New York serif numeral style at an arbitrary size/weight — the house dominant
    /// numeral. Tabular so live values align. Use anywhere a score/number is the hero of its
    /// container (gauge centers, tile values).
    public static func rounded(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        serif(size, weight: weight).monospacedDigit()
    }

    /// Title1 28 / Bold. SF Pro. Scales with Dynamic Type.
    public static let title1 = sfPro(28, weight: .bold)

    /// Title2 22 / Semibold. SF Pro. Scales with Dynamic Type.
    public static let title2 = sfPro(22, weight: .semibold)

    /// Headline 17 / Semibold. SF Pro. Scales with Dynamic Type.
    public static let headline = sfPro(17, weight: .semibold)

    /// Body 15 / Regular. SF Pro. Scales with Dynamic Type.
    public static let body = sfPro(15, weight: .regular)

    /// Subhead 13. SF Pro. Scales with Dynamic Type.
    public static let subhead = sfPro(13, weight: .regular)

    /// Caption 12. SF Pro. Scales with Dynamic Type.
    public static let caption = sfPro(12, weight: .regular)

    /// Footnote 11. SF Pro. Scales with Dynamic Type.
    public static let footnote = sfPro(11, weight: .regular)

    /// Overline 11 / Bold, +1.2 tracking (apply `.tracking(1.2)` at use site;
    /// `overlineText(_:)` does it for you). Small-caps ALL-CAPS labels ("RECOVERY", "STRAIN").
    /// SF Pro. Scales with Dynamic Type.
    public static let overline = sfPro(11, weight: .bold)

    /// `overline` at a custom point size — same SF Pro face/weight, just smaller. Passing 11
    /// returns exactly `.overline`. Lets a caller shrink an ALL-CAPS label to fit a small
    /// container without losing Dynamic-Type text-scaling.
    public static func overlineScaled(_ size: CGFloat) -> Font {
        sfPro(size, weight: .bold)
    }

    /// Mono 13 (SF Mono) — raw / log views. Tabular by nature.
    public static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)

    // MARK: Numeric variants (tabular digits)

    /// A New York serif numeral at an arbitrary size/weight, for a dominant live value (tile
    /// values, metric read-outs). Tabular digits.
    public static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        serif(size, weight: weight).monospacedDigit()
    }

    /// SF Pro body number — for inline live values mixed with label text (so numeral and label
    /// share one family at small sizes). Tabular, scales with Dynamic Type alongside its
    /// sibling `body`/`caption` labels.
    public static let bodyNumber = sfPro(15, weight: .medium).monospacedDigit()

    /// SF Pro caption number — for small inline live values (sparklines, chips). Tabular,
    /// scales with Dynamic Type.
    public static let captionNumber = sfPro(12, weight: .medium).monospacedDigit()

    /// Mono at an arbitrary size.
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// The recommended tracking for overline text (small-caps ALL-CAPS labels, ≈ +1.2 letter-spacing).
    public static let overlineTracking: CGFloat = 1.2
}

// MARK: - Text helpers

public extension Text {
    /// Style as an overline label: ALL-CAPS, bold, +1.2 tracking, tertiary text.
    func strandOverline() -> some View {
        self.font(StrandFont.overline)
            .tracking(StrandFont.overlineTracking)
            .textCase(.uppercase)
            .foregroundStyle(StrandPalette.textSecondary)
    }
}

public extension View {
    /// Convenience: an overline-styled label string.
    static func strandOverline(_ string: String) -> some View {
        Text(string).strandOverline()
    }
}

#if DEBUG
#Preview("Typography") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("88").font(StrandFont.display(72)).tracking(StrandFont.displayTracking(72)).foregroundStyle(StrandPalette.textPrimary)
            Text("Title 1 / Bold 28").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            Text("Title 2 / Semibold 22").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            Text("Headline / Semibold 17").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
            Text("Body / Regular 15 — the thread of you, read in full.")
                .font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
            Text("Subhead 13").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Text("Caption 12").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text("Footnote 11").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Text("Overline").strandOverline()
            Text("0xAA 41 00 1c crc32=f3a1  mono 13").font(StrandFont.mono).foregroundStyle(StrandPalette.textSecondary)
            HStack(spacing: 4) {
                Text("HRV").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("62").font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
                Text("ms").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 520, height: 620)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
