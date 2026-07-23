import SwiftUI

// StageCompositionBar.swift — a single, elegant horizontal bar showing how a night was spent across
// the four sleep stages, plus an optional legend with per-stage durations.
//
// Distinct from the Hypnogram (which is the moment-to-moment TIMELINE): this answers "what was the
// MIX?" at a glance. Segments run left→right in a restorative gradient — Deep, Core, REM, Awake — so
// the most restorative time leads and wake trails. Design-system-owned colours (StrandPalette sleep
// stages); reveals with a left-to-right wipe on appear (Reduce-Motion safe). One VoiceOver element.

#if !os(watchOS)
public struct StageCompositionBar: View {

    public var deepMin: Double
    public var lightMin: Double   // "Core"
    public var remMin: Double
    public var awakeMin: Double
    public var height: CGFloat
    public var showsLegend: Bool

    public init(deepMin: Double, lightMin: Double, remMin: Double, awakeMin: Double,
                height: CGFloat = 16, showsLegend: Bool = true) {
        self.deepMin = deepMin
        self.lightMin = lightMin
        self.remMin = remMin
        self.awakeMin = awakeMin
        self.height = height
        self.showsLegend = showsLegend
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: CGFloat = 0

    private struct Seg { let label: String; let minutes: Double; let color: Color }
    private var segments: [Seg] {
        [ Seg(label: "Deep",  minutes: max(0, deepMin),  color: StrandPalette.sleepDeep),
          Seg(label: "Core",  minutes: max(0, lightMin), color: StrandPalette.sleepLight),
          Seg(label: "REM",   minutes: max(0, remMin),   color: StrandPalette.sleepREM),
          Seg(label: "Awake", minutes: max(0, awakeMin), color: StrandPalette.sleepAwake) ]
    }
    private var total: Double { max(segments.reduce(0) { $0 + $1.minutes }, 1) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                        Rectangle()
                            .fill(s.color)
                            .frame(width: max(0, geo.size.width * CGFloat(s.minutes / total)))
                    }
                }
                .frame(width: geo.size.width, height: height, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
                // Left-to-right wipe reveal.
                .mask(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .frame(width: geo.size.width * reveal)
                }
            }
            .frame(height: height)

            if showsLegend { legend }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
        .onAppear {
            if reduceMotion { reveal = 1 }
            else { withAnimation(.easeOut(duration: 0.6)) { reveal = 1 } }
        }
    }

    private var legend: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, s in
                HStack(spacing: 6) {
                    Circle().fill(s.color).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.label)   // static stage name — verbatim String initialiser
                            .font(StrandFont.caption)
                            .foregroundColor(StrandPalette.textSecondary)
                        Text(durationText(s.minutes))
                            .font(StrandFont.captionNumber)
                            .foregroundColor(StrandPalette.textPrimary)
                    }
                }
                if idx < segments.count - 1 { Spacer(minLength: 6) }
            }
        }
    }

    private func durationText(_ minutes: Double) -> String {
        let t = Int(minutes.rounded())
        let h = t / 60, m = t % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var accessibilitySummary: String {
        let parts = segments.map { "\($0.label) \(durationText($0.minutes))" }
        return "Sleep stages: " + parts.joined(separator: ", ")
    }
}
#endif

#if DEBUG && !os(watchOS)
#Preview("StageCompositionBar") {
    VStack(spacing: 28) {
        StageCompositionBar(deepMin: 110, lightMin: 240, remMin: 100, awakeMin: 20)
        StageCompositionBar(deepMin: 40, lightMin: 300, remMin: 55, awakeMin: 95)
        StageCompositionBar(deepMin: 110, lightMin: 240, remMin: 100, awakeMin: 20, height: 10, showsLegend: false)
    }
    .padding(24)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
