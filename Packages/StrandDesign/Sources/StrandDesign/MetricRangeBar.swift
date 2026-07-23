import SwiftUI

// MetricRangeBar.swift — a range band that shows where a value sits within GENERAL-POPULATION zones,
// with the reader's own value ("You") and personal baseline marked separately. The honest companion to
// LearnMoreDisclosure: it makes the general-vs-personal distinction visible instead of asserting a
// single "good" number.
//
// Two modes:
//   • Zones: contiguous coloured bands (e.g. Low / Moderate / High) — used only where population ranges
//     are scientifically supported.
//   • Personal (zones empty): a neutral track with a soft band around the baseline — used where the
//     metric varies too much between people to give a population verdict (e.g. HRV).

#if !os(watchOS)
public struct MetricRangeBar: View {

    public enum Tone: Sendable { case low, caution, good, best, neutral }

    public struct Zone: Equatable, Sendable {
        public let label: String
        public let lower: Double
        public let upper: Double
        public let tone: Tone
        public init(label: String, lower: Double, upper: Double, tone: Tone) {
            self.label = label; self.lower = lower; self.upper = upper; self.tone = tone
        }
        public static func == (a: Zone, b: Zone) -> Bool {
            a.label == b.label && a.lower == b.lower && a.upper == b.upper
        }
    }

    public var zones: [Zone]
    public var lowerBound: Double
    public var upperBound: Double
    public var value: Double?
    public var baseline: Double?
    public var tint: Color
    public var showsZoneLabels: Bool

    public init(zones: [Zone], lowerBound: Double, upperBound: Double,
                value: Double?, baseline: Double?, tint: Color = StrandPalette.accent,
                showsZoneLabels: Bool = true) {
        self.zones = zones
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.value = value
        self.baseline = baseline
        self.tint = tint
        self.showsZoneLabels = showsZoneLabels
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear: CGFloat = 0

    private let barHeight: CGFloat = 12

    private func toneColor(_ t: Tone) -> Color {
        switch t {
        case .low:     return StrandPalette.recoveryColor(6)
        case .caution: return StrandPalette.recoveryColor(50)
        case .good:    return StrandPalette.recoveryColor(78)
        case .best:    return StrandPalette.recoveryColor(100)
        case .neutral: return StrandPalette.surfaceInset
        }
    }

    private func frac(_ v: Double) -> CGFloat {
        let span = upperBound - lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((v - lowerBound) / span, 0), 1))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    band(width: w)
                    if showsZoneLabels && !zones.isEmpty {
                        zoneLabels(width: w).offset(y: barHeight + 4)
                    }
                    markers(width: w)
                        .offset(y: barHeight + (showsZoneLabels && !zones.isEmpty ? 16 : 4))
                }
            }
            .frame(height: barHeight + (showsZoneLabels && !zones.isEmpty ? 40 : 30))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
        .onAppear {
            if reduceMotion { appear = 1 } else { withAnimation(.easeOut(duration: 0.5)) { appear = 1 } }
        }
    }

    @ViewBuilder private func band(width w: CGFloat) -> some View {
        if zones.isEmpty {
            // Personal mode: neutral track + a soft band around the baseline.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous)
                    .fill(StrandPalette.surfaceInset)
                    .frame(width: w, height: barHeight)
                if let baseline {
                    let bw = w * 0.34
                    let cx = frac(baseline) * w
                    RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous)
                        .fill(tint.opacity(0.28))
                        .frame(width: bw, height: barHeight)
                        .offset(x: min(max(cx - bw / 2, 0), w - bw))
                }
            }
        } else {
            HStack(spacing: 1.5) {
                ForEach(Array(zones.enumerated()), id: \.offset) { _, z in
                    Rectangle()
                        .fill(toneColor(z.tone).opacity(0.85))
                        .frame(width: max(0, w * CGFloat((z.upper - z.lower) / (upperBound - lowerBound))))
                }
            }
            .frame(width: w, height: barHeight)
            .clipShape(RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous))
        }
    }

    private func zoneLabels(width w: CGFloat) -> some View {
        HStack(spacing: 1.5) {
            ForEach(Array(zones.enumerated()), id: \.offset) { _, z in
                Text(z.label)
                    .font(StrandFont.footnote)
                    .foregroundColor(StrandPalette.textTertiary)
                    .lineLimit(1)
                    .frame(width: max(0, w * CGFloat((z.upper - z.lower) / (upperBound - lowerBound))), alignment: .center)
            }
        }
    }

    private func markers(width w: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let baseline { marker(at: frac(baseline) * w, label: "Baseline",
                                     color: StrandPalette.textTertiary, width: w) }
            if let value { marker(at: frac(value) * w, label: "You", color: tint, width: w) }
        }
    }

    private func marker(at x: CGFloat, label: String, color: Color, width w: CGFloat) -> some View {
        VStack(spacing: 2) {
            Capsule().fill(color).frame(width: 2, height: 12)
            Text(label).font(StrandFont.overline).foregroundColor(color)
        }
        .fixedSize()
        .opacity(Double(appear))
        // Clamp so the label doesn't run off either edge.
        .offset(x: min(max(x - 18, 0), w - 36))
    }

    private var accessibilitySummary: String {
        var s = ""
        if let value { s += "You: \(Int(value.rounded()))" }
        if let baseline { s += (s.isEmpty ? "" : ". ") + "Your baseline: \(Int(baseline.rounded()))" }
        if zones.isEmpty { s += ". This metric varies by person; watch your own trend." }
        return s.isEmpty ? "Range bar" : s
    }
}
#endif

#if DEBUG && !os(watchOS)
#Preview("MetricRangeBar") {
    VStack(alignment: .leading, spacing: 30) {
        MetricRangeBar(
            zones: [.init(label: "Low", lower: 0, upper: 33, tone: .low),
                    .init(label: "Moderate", lower: 33, upper: 66, tone: .caution),
                    .init(label: "High", lower: 66, upper: 100, tone: .best)],
            lowerBound: 0, upperBound: 100, value: 86, baseline: 72,
            tint: StrandPalette.chargeColor)
        MetricRangeBar(
            zones: [], lowerBound: 38, upperBound: 88, value: 68, baseline: 59,
            tint: StrandPalette.metricCyan)
    }
    .padding(24)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
