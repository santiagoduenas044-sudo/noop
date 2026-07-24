import SwiftUI
import StrandDesign
import StrandAnalytics

// LiveHeartRateCard.swift — NOOP's real-time heart-rate monitor.
//
// A heart that PULSES at the actual rate (period = 60/bpm, a lub-dub envelope), the big live bpm and its
// HR zone (from the pure `HRZones` engine), a five-band zone ladder with the active band lit, a rolling
// beat-by-beat trace, and live min/avg/max. Falls back to today's banked 5-minute trace when idle. An
// isolated `LiveState` leaf so the ~1 Hz HR notifies re-render only this card, never the whole Today.
// Design-system only; the beat-line reuses the shared HR thread renderer.

/// A copy-owning map from an HR-zone number (0 = resting … 5 = peak) to its display name + accent. The pure
/// `HRZones` engine owns the boundaries; this owns the words + design tokens. Colours run a cool→warm ramp
/// (rest blue → peak rose) so the zone reads at a glance.
enum HRZoneStyle {
    static func name(_ z: Int) -> String {
        switch z {
        case 1: return String(localized: "Warm up")
        case 2: return String(localized: "Light")
        case 3: return String(localized: "Moderate")
        case 4: return String(localized: "Hard")
        case 5: return String(localized: "Peak")
        default: return String(localized: "Resting")
        }
    }
    static func color(_ z: Int) -> Color {
        switch z {
        case 1: return StrandPalette.restColor
        case 2: return StrandPalette.chargeColor
        case 3: return StrandPalette.metricAmber
        case 4: return StrandPalette.effortColor
        case 5: return StrandPalette.metricRose
        default: return StrandPalette.textTertiary
        }
    }
}

struct LiveHeartRateCard: View {
    var tint: Color
    var fallback: [Double]        // today's banked 5-minute buckets — shown when there's no live stream
    var animated: Bool
    var zoneSet: HRZoneSet

    @EnvironmentObject private var live: LiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var samples: [Double] = []
    private let maxSamples = 120   // ~2 min of 1 Hz live HR, enough to read the shape

    /// A fresh live beat is streaming right now (drives the pulsing heart + the LIVE pill).
    private var liveBpm: Int? {
        guard live.connected, let hr = live.heartRate, hr > 0 else { return nil }
        return hr
    }
    private var isStreaming: Bool { liveBpm != nil }
    /// The number the hero shows — the live beat, else today's most recent banked value.
    private var currentBpm: Int? { liveBpm ?? fallback.last.map { Int($0.rounded()) } }
    private var currentZone: Int? { currentBpm.map { zoneSet.zoneNumber(forBPM: Double($0)) } }
    /// The trace series: the live rolling buffer once it has shape, else today's banked buckets.
    private var series: [Double] { samples.count >= 2 ? samples : fallback }
    private var animateHeart: Bool { isStreaming && animated && !reduceMotion }

    private var statusText: String {
        if !live.connected { return String(localized: "Strap not connected") }
        if live.worn == false { return String(localized: "Strap is off your wrist") }
        if isStreaming { return String(localized: "Live · beat by beat") }
        if fallback.count >= 2 { return String(localized: "5-min average · since midnight") }
        return String(localized: "Waiting for the strap") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            heroRow
            if currentZone != nil { zoneLadder }
            if series.count >= 2 {
                LiquidThread(bpm: series, tint: tint, height: 84, animated: animated)
                statsRow
            } else if !isStreaming {
                Text(live.connected ? "Waiting for a live heartbeat…" : "Connect your strap to see live heart rate")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            }
        }
        .onAppear { if samples.isEmpty, let hr = liveBpm { samples = [Double(hr)] } }
        .onChangeCompat(of: live.heartRate) { hr in
            guard let hr, hr > 0, live.connected else { return }
            samples.append(Double(hr))
            if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
        }
    }

    // MARK: header (title + status + LIVE pill)

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HEART RATE").font(StrandFont.overline).tracking(1.6)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(statusText).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer()
            if isStreaming { livePill }
        }
    }

    private var livePill: some View {
        HStack(spacing: 5) {
            PulsingLiveDot(color: tint, animate: animated && !reduceMotion)
            Text("LIVE").font(StrandFont.overlineScaled(9)).tracking(1.4)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.14))
            .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 1)))
    }

    // MARK: hero (pulsing heart + big bpm + zone)

    private var heroRow: some View {
        HStack(alignment: .center, spacing: 14) {
            heart
            VStack(alignment: .leading, spacing: 1) {
                if let hr = currentBpm {
                    (Text("\(hr)").font(StrandFont.rounded(42)).monospacedDigit()
                        .foregroundColor(StrandPalette.textPrimary)
                        + Text(" bpm").font(StrandFont.body).foregroundColor(StrandPalette.textTertiary))
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.25), value: hr)
                } else {
                    Text("––").font(StrandFont.rounded(42)).foregroundStyle(StrandPalette.textTertiary)
                }
                if let z = currentZone {
                    (Text(z >= 1 ? String(format: String(localized: "Zone %ld · "), z) : "")
                        .font(StrandFont.caption).foregroundColor(StrandPalette.textTertiary)
                     + Text(HRZoneStyle.name(z))
                        .font(StrandFont.caption.weight(.semibold)).foregroundColor(HRZoneStyle.color(z)))
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The pulsing heart. When a live beat is streaming it beats at the real rate (period = 60/bpm) with a
    /// lub-dub envelope, driven by an animation TimelineView inside this isolated leaf; otherwise it rests.
    @ViewBuilder private var heart: some View {
        let color = currentZone.map { HRZoneStyle.color($0) } ?? tint
        if animateHeart, let bpm = liveBpm {
            TimelineView(.animation) { tl in
                let s = Self.heartScale(bpm: bpm, at: tl.date)
                heartGlyph(color: color, scale: s)
            }
        } else {
            heartGlyph(color: color, scale: 1)
        }
    }

    private func heartGlyph(color: Color, scale: CGFloat) -> some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 34))
            .foregroundStyle(color)
            .scaleEffect(scale)
            .shadow(color: color.opacity(0.55), radius: 10 * max(0, scale - 0.98))
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)
    }

    /// Heartbeat scale at a given instant: a double-bump (lub-dub) envelope over one beat period.
    static func heartScale(bpm: Int, at date: Date) -> CGFloat {
        let bps = Swift.max(0.3, Double(bpm) / 60.0)
        let phase = (date.timeIntervalSinceReferenceDate * bps).truncatingRemainder(dividingBy: 1)
        func bump(_ x: Double, _ c: Double, _ w: Double) -> Double { exp(-pow((x - c) / w, 2)) }
        // "lub" at the start of the beat (wrapped at 1.0), a smaller "dub" shortly after.
        let lub = bump(phase, 0.0, 0.06) + bump(phase, 1.0, 0.06)
        let dub = 0.5 * bump(phase, 0.17, 0.05)
        return 1.0 + 0.22 * CGFloat(Swift.min(1.0, lub + dub))
    }

    // MARK: zone ladder (5 bands, active one lit)

    private var zoneLadder: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(1...5, id: \.self) { z in
                let on = currentZone == z
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(on ? HRZoneStyle.color(z) : HRZoneStyle.color(z).opacity(0.16))
                    .frame(height: on ? 10 : 6)
                    .animation(.easeOut(duration: 0.3), value: on)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(currentZone.map { Text(HRZoneStyle.name($0)) } ?? Text("Resting"))
    }

    // MARK: live stats

    private var statsRow: some View {
        HStack {
            stat(String(localized: "Min"), series.min())
            Spacer()
            stat(String(localized: "Avg"), series.reduce(0, +) / Double(series.count))
            Spacer()
            stat(String(localized: "Max"), series.max())
        }
    }

    private func stat(_ label: String, _ v: Double?) -> some View {
        HStack(spacing: 5) {
            Text(label).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            Text(v.map { String(Int($0.rounded())) } ?? "–")
                .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
        }
    }
}

/// A small dot that softly pulses to signal a live stream (the LIVE pill). Its own TimelineView so it
/// animates independently of the beat-synced heart, and rests as a static dot when motion is reduced.
struct PulsingLiveDot: View {
    var color: Color
    var animate: Bool
    var body: some View {
        if animate {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let p = 0.5 + 0.5 * sin(t * 3.0)   // ~0.5 Hz gentle breathe
                Circle().fill(color).frame(width: 7, height: 7)
                    .scaleEffect(0.8 + 0.3 * CGFloat(p))
                    .opacity(0.5 + 0.5 * p)
            }
        } else {
            Circle().fill(color).frame(width: 7, height: 7)
        }
    }
}
