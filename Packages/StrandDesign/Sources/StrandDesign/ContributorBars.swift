import SwiftUI

// ContributorBars.swift — a diverging "what moved this score" bar chart. Each contributor is a
// signed point value; bars grow LEFT (pulled the score down) or RIGHT (pushed it up) from a centre
// axis, ordered biggest-mover first. An at-a-glance companion to a text breakdown — the reader sees
// the shape of a day's recovery (or any additive-ish score) without reading every row.
//
// Framework-neutral input (label + signed points) so this stays independent of the analytics layer:
// the app maps its own driver rows (e.g. ChargeDriver) into `Contributor`. Colours are the recovery
// ramp (up = green, down = red). Reduce-Motion aware; one combined VoiceOver element.

#if !os(watchOS)
public struct ContributorBars: View {

    public struct Contributor: Equatable, Sendable {
        public let label: String
        public let points: Int
        public init(label: String, points: Int) { self.label = label; self.points = points }
    }

    public var contributors: [Contributor]
    public var labelWidth: CGFloat
    public var rowHeight: CGFloat
    public var barThickness: CGFloat

    public init(contributors: [Contributor], labelWidth: CGFloat = 96,
                rowHeight: CGFloat = 26, barThickness: CGFloat = 12) {
        self.contributors = contributors
        self.labelWidth = labelWidth
        self.rowHeight = rowHeight
        self.barThickness = barThickness
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grow: CGFloat = 0

    private var maxAbs: Int { max(contributors.map { abs($0.points) }.max() ?? 1, 1) }

    private func color(_ points: Int) -> Color {
        points >= 0 ? StrandPalette.recoveryColor(100) : StrandPalette.recoveryColor(0)
    }

    public var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(contributors.enumerated()), id: \.offset) { _, c in
                row(c)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
        .onAppear {
            if reduceMotion { grow = 1 }
            else { withAnimation(.easeOut(duration: 0.55)) { grow = 1 } }
        }
    }

    private func row(_ c: Contributor) -> some View {
        HStack(spacing: 10) {
            Text(c.label)
                .font(StrandFont.caption)
                .foregroundColor(StrandPalette.textSecondary)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .trailing)

            GeometryReader { geo in
                let cx = geo.size.width / 2
                let frac = CGFloat(abs(c.points)) / CGFloat(maxAbs)
                let barW = frac * (cx - 6) * grow
                let midY = geo.size.height / 2
                ZStack(alignment: .topLeading) {
                    // centre axis
                    Rectangle()
                        .fill(StrandPalette.hairline)
                        .frame(width: 1, height: geo.size.height)
                        .offset(x: cx)
                    // the bar
                    RoundedRectangle(cornerRadius: barThickness / 2, style: .continuous)
                        .fill(color(c.points))
                        .frame(width: max(0, barW), height: barThickness)
                        .offset(x: c.points >= 0 ? cx : cx - barW,
                                y: midY - barThickness / 2)
                }
            }
            .frame(maxWidth: .infinity)

            Text(pointsText(c.points))
                .font(StrandFont.captionNumber)
                .foregroundColor(color(c.points))
                .frame(width: 46, alignment: .trailing)
        }
        .frame(height: rowHeight)
    }

    private func pointsText(_ p: Int) -> String {
        p > 0 ? "+\(p)" : "\(p)"   // the minus sign rides the value for negatives
    }

    private var accessibilitySummary: String {
        let parts = contributors.map { c in
            "\(c.label) \(c.points >= 0 ? "up" : "down") \(abs(c.points)) point\(abs(c.points) == 1 ? "" : "s")"
        }
        return "Score contributors: " + parts.joined(separator: ", ")
    }
}
#endif

#if DEBUG && !os(watchOS)
#Preview("ContributorBars") {
    ContributorBars(contributors: [
        .init(label: "HRV", points: 9),
        .init(label: "Resting HR", points: 5),
        .init(label: "Sleep", points: 3),
        .init(label: "Prior strain", points: -7),
        .init(label: "Skin temp", points: -2),
    ])
    .padding(24)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
