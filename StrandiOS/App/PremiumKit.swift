#if os(iOS)
import SwiftUI
import StrandDesign

/// PremiumKit — the shared native design-system layer for the premium redesign.
/// It builds ON TOP of `StrandDesign` (the app's frozen token source, re-skinned to the
/// prototype identity) rather than duplicating it: these are the reusable compositions the
/// premium screens repeat — an ambient glow background, section headers, badges, stat
/// bars, icon tiles, a version-row and empty/loading/error states — so new screens assemble
/// from one vocabulary instead of copy-pasting. Existing premium screens adopt these
/// incrementally; new screens (What's New, Journal, Settings) use them throughout.
enum PremiumKit {}

// MARK: - Ambient background (the prototype's living glow)

struct PremiumAmbient: View {
    var tints: [Color] = [StrandPalette.gold]
    var body: some View {
        ZStack {
            StrandPalette.surfaceBase
            if tints.count > 0 {
                RadialGradient(colors: [tints[0].opacity(0.14), .clear],
                               center: .init(x: 0.16, y: 0.02), startRadius: 0, endRadius: 340)
            }
            if tints.count > 1 {
                RadialGradient(colors: [tints[1].opacity(0.11), .clear],
                               center: .init(x: 1.0, y: 0.04), startRadius: 0, endRadius: 300)
            }
        }
    }
}

// MARK: - Section header

struct PremiumSectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            if let t = trailing {
                Text(t).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Badge / pill

struct PremiumBadge: View {
    let text: String
    var tint: Color = StrandPalette.gold
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold)).tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.15)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1))
    }
}

// MARK: - Icon tile

struct PremiumIconTile: View {
    let system: String
    var tint: Color = StrandPalette.gold
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: system)
            .font(.system(size: size * 0.47, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(tint.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }
}

// MARK: - Progress / stat bar

struct PremiumBar: View {
    let fraction: Double
    var tint: Color = StrandPalette.gold
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.surfaceInset)
                Capsule().fill(LinearGradient(colors: [tint, tint.opacity(0.7)],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Key/value row (version info, diagnostics)

struct PremiumInfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }
}

// MARK: - Explanation (ⓘ)

/// One question-and-answer pair in a `PremiumExplainer`.
struct PremiumExplainerItem: Identifiable {
    let question: String
    let answer: String
    var id: String { question }
}

/// The reusable ⓘ affordance: a small info button that opens a plain-language explanation of what a
/// figure means, where it came from, and how it was derived.
///
/// Two deliberate rules:
/// * **Plain language first, methodology last.** Raw derivation lives under a separate "How this was
///   calculated" block so the everyday reading stays readable, per the product direction.
/// * **Never diagnostic.** These explain what NOOP measured and how; they must not tell the user
///   what a value means for their health.
struct PremiumExplainer: View {
    let title: String
    let items: [PremiumExplainerItem]
    /// Methodology / derivation. Shown under its own heading, below the plain-language items.
    var methodology: String?

    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: String(localized: "About %1$@"), title))
        .sheet(isPresented: $showing) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.question).font(StrandFont.headline)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Text(item.answer).font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(3)
                            }
                        }
                        if let m = methodology {
                            Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("How this was calculated").font(StrandFont.headline)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Text(m).font(StrandFont.footnote)
                                    .foregroundStyle(StrandPalette.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(2)
                            }
                        }
                    }
                    .padding(20)
                }
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showing = false }
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
            }
        }
    }
}

// MARK: - Chip selector

/// A horizontal row of selectable chips. Exists so a screen can offer ONE high-information chart
/// with a selector instead of stacking a near-identical chart per option — the difference between
/// "four charts answering the same question" and "one chart you can re-aim".
struct PremiumChipPicker<T: Hashable>: View {
    struct Option: Identifiable {
        let value: T
        let label: String
        let tint: Color
        var id: String { "\(value)" }
    }

    let options: [Option]
    @Binding var selection: T

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { opt in
                    let on: Bool = opt.value == selection
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { selection = opt.value }
                    } label: {
                        Text(opt.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(on ? StrandPalette.surfaceBase : StrandPalette.textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(on ? opt.tint : StrandPalette.surfaceInset))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

// MARK: - Empty / loading / error states

struct PremiumEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil
    var tint: Color = StrandPalette.textTertiary
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .regular)).foregroundStyle(tint)
            Text(title).font(StrandFont.headline).foregroundStyle(StrandPalette.textSecondary)
            if let m = message {
                Text(m).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}

struct PremiumLoadingState: View {
    var label: String = "Loading…"
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().tint(StrandPalette.accent)
            Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}
#endif
