import SwiftUI

// LearnMoreDisclosure.swift — a premium, unobtrusive "learn about this metric" block. Collapsed by
// default to a single quiet affordance ("ⓘ About Recovery ⌄"); expands to a set of labeled sections
// (What it measures · Why it matters · Typical range · What influences it · How to improve). Generic
// and content-free — the app supplies the sections — so one component teaches every metric.
//
// Honesty is a first-class input: the `footnote` is meant to carry the "these are general-population
// ranges; compare to your own baseline and trend" disclaimer, rendered quietly at the bottom.

#if !os(watchOS)
public struct LearnMoreDisclosure: View {

    public struct Section: Equatable, Sendable {
        public let systemImage: String?
        public let heading: String
        public let body: String?
        public let bullets: [String]
        public init(systemImage: String? = nil, heading: String, body: String? = nil, bullets: [String] = []) {
            self.systemImage = systemImage
            self.heading = heading
            self.body = body
            self.bullets = bullets
        }
    }

    public var title: String
    public var tint: Color
    public var sections: [Section]
    public var footnote: String?

    public init(title: String, tint: Color = StrandPalette.accent,
                sections: [Section], footnote: String? = nil) {
        self.title = title
        self.tint = tint
        self.sections = sections
        self.footnote = footnote
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, s in
                        section(s)
                    }
                    if let footnote {
                        Text(footnote)
                            .font(StrandFont.footnote)
                            .foregroundColor(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 14)
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        Button {
            if reduceMotion { expanded.toggle() }
            else { withAnimation(.easeInOut(duration: 0.26)) { expanded.toggle() } }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundColor(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(StrandPalette.textTertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(expanded ? "Collapse" : "Expand"))
    }

    private func section(_ s: Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon = s.systemImage {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundColor(tint)
                }
                Text(s.heading)
                    .font(StrandFont.caption)
                    .foregroundColor(tint)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            if let body = s.body {
                Text(body)
                    .font(StrandFont.subhead)
                    .foregroundColor(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !s.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(s.bullets.enumerated()), id: \.offset) { _, b in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(tint).frame(width: 5, height: 5).offset(y: 1)
                            Text(b)
                                .font(StrandFont.subhead)
                                .foregroundColor(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
#endif

#if DEBUG && !os(watchOS)
#Preview("LearnMoreDisclosure") {
    ScrollView {
        LearnMoreDisclosure(
            title: "About Recovery",
            tint: StrandPalette.chargeColor,
            sections: [
                .init(systemImage: "questionmark.circle", heading: "What it measures",
                      body: "How ready your body is today, from overnight heart-rate variability, resting heart rate, sleep and recent strain."),
                .init(systemImage: "chart.bar", heading: "Typical range",
                      body: "As a rough guide: 0–33 low, 34–66 moderate, 67–100 high. These are general ranges — your own baseline matters more."),
                .init(systemImage: "arrow.up.forward", heading: "How to improve",
                      bullets: ["Keep a consistent sleep schedule", "Ease training after hard days", "Limit late alcohol and caffeine"]),
            ],
            footnote: "Ranges are general guidance, not medical advice. NOOP compares today to your own baseline and trend.")
            .padding(16)
    }
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
