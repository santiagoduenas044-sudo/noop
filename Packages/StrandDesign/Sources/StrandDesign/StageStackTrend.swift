import SwiftUI

// StageStackTrend.swift — a compact per-night STACKED stage-composition trend: one column per night,
// each column stacked (bottom→top) Deep · Core · REM · Awake and scaled so the longest night fills the
// chart. Answers "how has my sleep MIX moved over the last N nights?" — the trend companion to the
// single-night StageCompositionBar. Design-system colours; grows in from the baseline (Reduce-Motion
// safe); most-recent night on the right.

#if !os(watchOS)
public struct StageStackTrend: View {

    public struct Night: Equatable, Sendable {
        public var deep: Double, light: Double, rem: Double, awake: Double
        public init(deep: Double, light: Double, rem: Double, awake: Double) {
            self.deep = deep; self.light = light; self.rem = rem; self.awake = awake
        }
        var inBed: Double { max(0, deep) + max(0, light) + max(0, rem) + max(0, awake) }
    }

    public var nights: [Night]     // chronological, oldest → newest
    public var height: CGFloat
    public var barSpacing: CGFloat

    public init(nights: [Night], height: CGFloat = 132, barSpacing: CGFloat = 5) {
        self.nights = nights
        self.height = height
        self.barSpacing = barSpacing
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grow: CGFloat = 0

    private var maxInBed: CGFloat { CGFloat(max(nights.map { $0.inBed }.max() ?? 1, 1)) }

    public var body: some View {
        GeometryReader { geo in
            let n = max(nights.count, 1)
            let totalSpacing = barSpacing * CGFloat(n - 1)
            let barW = max(2, (geo.size.width - totalSpacing) / CGFloat(n))
            let scale = height / maxInBed
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(Array(nights.enumerated()), id: \.offset) { _, night in
                    column(night, width: barW, scale: scale)
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .bottom)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep stage trend over \(nights.count) nights"))
        .onAppear {
            if reduceMotion { grow = 1 }
            else { withAnimation(.easeOut(duration: 0.55)) { grow = 1 } }
        }
    }

    // One night's column: bottom→top Deep, Core, REM, Awake.
    private func column(_ night: Night, width: CGFloat, scale: CGFloat) -> some View {
        let segs: [(Double, Color)] = [
            (max(0, night.awake), StrandPalette.sleepAwake),   // top
            (max(0, night.rem),   StrandPalette.sleepREM),
            (max(0, night.light), StrandPalette.sleepLight),
            (max(0, night.deep),  StrandPalette.sleepDeep),    // bottom
        ]
        return VStack(spacing: 0) {
            ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                Rectangle()
                    .fill(seg.1)
                    .frame(width: width, height: CGFloat(seg.0) * scale * grow)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: min(width / 2, 3), style: .continuous))
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
#endif

#if DEBUG && !os(watchOS)
#Preview("StageStackTrend") {
    let rng: [StageStackTrend.Night] = (0..<14).map { i in
        let jitter = Double((i * 37) % 40) - 20
        return StageStackTrend.Night(deep: 95 + jitter, light: 240 + jitter, rem: 95 - jitter / 2, awake: 25 + abs(jitter) / 2)
    }
    return StageStackTrend(nights: rng)
        .padding(24)
        .frame(height: 180)
        .background(StrandPalette.surfaceBase)
        .preferredColorScheme(.dark)
}
#endif
