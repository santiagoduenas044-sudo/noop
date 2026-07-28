import SwiftUI

// MARK: - Hex Color Helper

public extension Color {
    /// Parse a hex string ("#0B0D12" / "0B0D12" RGB, or "#AARRGGBB"/"RRGGBBAA" RGBA) to sRGB
    /// components in 0...1. Shared by `Color(hex:)` and the dynamic `Color(light:dark:)` provider.
    static func sRGBComponents(hex: String) -> (r: Double, g: Double, b: Double, a: Double) {
        let raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&int)
        switch raw.count {
        case 8: // RRGGBBAA
            return (Double((int >> 24) & 0xFF) / 255.0, Double((int >> 16) & 0xFF) / 255.0,
                    Double((int >> 8) & 0xFF) / 255.0, Double(int & 0xFF) / 255.0)
        default: // RRGGBB (6) and any fallback
            return (Double((int >> 16) & 0xFF) / 255.0, Double((int >> 8) & 0xFF) / 255.0,
                    Double(int & 0xFF) / 255.0, 1.0)
        }
    }

    /// Create a Color from a hex string like "#0B0D12" or "0B0D12" (RGB) or "#AARRGGBB" / "RRGGBBAA".
    /// Supported lengths: 6 (RGB), 8 (RGBA).
    init(hex: String) {
        let c = Color.sRGBComponents(hex: hex)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    /// A colour that resolves to `light` or `dark` (both hex strings) per the active appearance.
    /// Backed by a `UIColor`/`NSColor` dynamic provider, so a single token automatically re-resolves
    /// at every one of its call sites when the colour scheme flips — no per-view environment plumbing.
    /// This is the whole light-theme strategy: only the token definitions change, never the call sites.
    init(light: String, dark: String) {
        #if os(watchOS)
        // watchOS has no UITraitCollection / dynamic-provider UIColor, and our watch app is effectively
        // always dark, so a token resolves straight to its dark hex. No per-scheme plumbing on the wrist.
        self.init(hex: dark)
        #elseif canImport(UIKit)
        self.init(UIColor { trait in
            let c = Color.sRGBComponents(hex: trait.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a))
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = Color.sRGBComponents(hex: isDark ? dark : light)
            return NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a))
        })
        #else
        self.init(hex: dark)
        #endif
    }
}

// MARK: - Strand Palette
//
// "Clinical Premium": an editorial, minimalist dark theme — deep near-black canvas,
// flat cards with a single hairline border, and ONE quiet accent colour per metric
// (sage = good / recovery, blue-grey = rest / sleep / HRV, terracotta = alert / low /
// high). No gamification, no glassmorphism, no liquid gradients. Every gauge/chart
// reads as a calm health report, not a game HUD.
//
// PUBLIC API IS FROZEN: every property name below is depended on by screens across
// macOS / iOS, so the names never change — only the VALUES were re-themed. The Clinical
// Premium tokens (gold ramp, titanium ramp, gradients, etc.) reuse the SAME frozen names
// so nothing downstream needs a call-site change.

public enum StrandPalette {

    // MARK: Surfaces — near-black canvas, flat cards, single hairline border.
    public static let surfaceBase    = Color(light: "#F7F6F3", dark: "#0A0A0B") // background base
    public static let surfaceRaised  = Color(light: "#FFFFFF", dark: "#151517") // card surface
    public static let surfaceOverlay = Color(light: "#FFFFFF", dark: "#1A1A1C") // popovers / sheets / tooltips
    public static let surfaceInset   = Color(light: "#ECEAE5", dark: "#1E1E20") // wells / ring track / segmented track
    public static let hairline       = Color(light: "#E4E2DD", dark: "#242426") // card border, 1px
    public static let hairlineStrong = Color(light: "#D3D0C8", dark: "#333335") // hover / emphasis border

    // MARK: Text — deep ink on paper / warm off-white on near-black.
    public static let textPrimary    = Color(light: "#17171A", dark: "#F2F1EE")
    public static let textSecondary  = Color(light: "#6B6B6E", dark: "#8A8A8D")
    public static let textTertiary   = Color(light: "#98989A", dark: "#5C5C5F")

    // MARK: Text ON a permanently-dark surface (scheme-invariant)
    // Use these — NOT textPrimary/Secondary/Tertiary — for labels/pills drawn over a fill that is pinned
    // dark in BOTH themes. The regular text tokens FLIP to dark ink in Light mode, so on a fixed-dark card
    // they render dark-on-near-black and vanish. These hold the light-on-dark values in BOTH
    // schemes, so a label always reads on the card. (Same hex as the *.dark side of the text tokens.)
    public static let onDarkPrimary   = Color(hex: "#F2F1EE")
    public static let onDarkSecondary = Color(hex: "#8A8A8D")
    public static let onDarkTertiary  = Color(hex: "#5C5C5F")

    // MARK: Glow — a barely-there ambient wash behind heroes (2–3% opacity per the Clinical Premium
    // spec — this is a near-invisible presence, never a bloom).
    public static let glowAmbient    = Color(light: "#EEF2ED", dark: "#141B15")

    // MARK: Accent — chrome anchor (links, selection, focus, generic accent). Clinical Premium's
    // "accent primary (good)" — the sage green — carries the generic accent role on BOTH schemes,
    // deepened slightly on light for contrast against paper.
    public static let accent         = Color(light: "#4F8F49", dark: "#8FBF8A")
    public static let accentHover    = Color(light: "#3E7239", dark: "#A5CC9F")
    public static let accentMuted    = Color(light: "#E9F1E8", dark: "#141F16")
    /// Focus ring color (sage on both schemes).
    public static let focusRing      = Color(light: "#4F8F49", dark: "#8FBF8A")
    /// Opacity for dimmed/disabled sections (shared so screens don't invent their own value).
    public static let disabledOpacity: Double = 0.45

    // MARK: - Chart style (data-viz colour mode) — Clinical (brand) or Classic (throwback)
    //
    // Set from `@AppStorage(ChartStyle.storageKey)` at the app root. The DATA-RAMP accessors below
    // (recoveryStops, strainStops, hrZones, sleepStageColor, stress gradient, status, metric, and the
    // DomainTheme worlds) branch on this — so flipping it re-colours every gauge/chart/scale to the
    // classic red→green readiness scale, in BOTH light and dark, with NO call-site changes. Chrome
    // (surfaces, text, accent) is never touched.
    public static var chartStyle: ChartStyle = .titanium
    @inline(__always) static var isClassic: Bool { chartStyle == .classic }

    // MARK: Classic (throwback) data ramps — the recognizable health-app scale, unchanged by the
    // Clinical Premium re-skin (opt-in legacy mode). Light/dark tuned.
    // Recovery: red → orange → amber → lime → green.
    static let cRecovery000 = Color(light: "#CB3A2F", dark: "#E5483B")
    static let cRecovery030 = Color(light: "#D87328", dark: "#EE8B3C")
    static let cRecovery055 = Color(light: "#CFA528", dark: "#F2C53D")
    static let cRecovery078 = Color(light: "#74A53A", dark: "#A6D04E")
    static let cRecovery100 = Color(light: "#2E9E4F", dark: "#46B45A")
    static let cRecoveryStops: [Gradient.Stop] = [
        .init(color: cRecovery000, location: 0.00), .init(color: cRecovery030, location: 0.30),
        .init(color: cRecovery055, location: 0.55), .init(color: cRecovery078, location: 0.78),
        .init(color: cRecovery100, location: 1.00),
    ]
    // Strain: the classic light→deep blue cardiovascular ramp.
    static let cStrain000 = Color(light: "#5E92D6", dark: "#7FB2E8")
    static let cStrain033 = Color(light: "#3A74C4", dark: "#4A90E2")
    static let cStrain066 = Color(light: "#284F9C", dark: "#2F6FCB")
    static let cStrain100 = Color(light: "#1C3E80", dark: "#1E4FA0")
    static let cStrainStops: [Gradient.Stop] = [
        .init(color: cStrain000, location: 0.00), .init(color: cStrain033, location: 0.33),
        .init(color: cStrain066, location: 0.66), .init(color: cStrain100, location: 1.00),
    ]
    // Sleep: grey awake, blue light, deep indigo, purple REM.
    static let cSleepAwake = Color(light: "#8C95A3", dark: "#C9CCD6")
    static let cSleepLight = Color(light: "#3A80D6", dark: "#6FA8E8")
    static let cSleepDeep  = Color(light: "#203E73", dark: "#2A4C8F")
    static let cSleepREM   = Color(light: "#6A4FC0", dark: "#8E6FD6")
    // HR zones: grey → green → yellow → orange → red.
    static let cZone1 = Color(light: "#828D9B", dark: "#9AA7B5")
    static let cZone2 = Color(light: "#2E9E4F", dark: "#46B45A")
    static let cZone3 = Color(light: "#CFA528", dark: "#F2C53D")
    static let cZone4 = Color(light: "#D87328", dark: "#EE8B3C")
    static let cZone5 = Color(light: "#CB3A2F", dark: "#E5483B")
    // Stress: calm green → amber → red.
    static let cStressStops: [Gradient.Stop] = [
        .init(color: Color(light: "#2E9E4F", dark: "#46B45A"), location: 0.0),
        .init(color: Color(light: "#CFA528", dark: "#F2C53D"), location: 0.5),
        .init(color: Color(light: "#CB3A2F", dark: "#E5483B"), location: 1.0),
    ]

    // MARK: Recovery / Charge ramp — the sage "good" world, fading through the neutral
    // blue-grey to the terracotta "alert" low end. Clinical Premium reads a metric by ONE
    // dominant colour (sage = good), not a rainbow scale; the ring itself paints FLAT with
    // the colour sampled at the current score rather than stroking this ramp as a gradient.
    public static let recovery000 = Color(light: "#A85A42", dark: "#C97B63") // depleted — terracotta (alert)
    public static let recovery030 = Color(light: "#AF6852", dark: "#CE8B75") // low
    public static let recovery055 = Color(light: "#6C7C88", dark: "#7A94A8") // moderate — neutral blue-grey
    public static let recovery078 = Color(light: "#5F8F5A", dark: "#7FAE7A") // primed — sage-leaning
    public static let recovery100 = Color(light: "#4F8F49", dark: "#8FBF8A") // peak — sage (good)

    /// Ordered gradient stops for the recovery scale (Clinical terracotta→sage ramp, or the Classic red→green).
    public static var recoveryStops: [Gradient.Stop] {
        isClassic ? cRecoveryStops : [
            .init(color: recovery000, location: 0.00),
            .init(color: recovery030, location: 0.30),
            .init(color: recovery055, location: 0.55),
            .init(color: recovery078, location: 0.78),
            .init(color: recovery100, location: 1.00),
        ]
    }

    /// The signature recovery gradient (terracotta → sage, or Classic red→green).
    public static var recoveryGradient: Gradient { Gradient(stops: recoveryStops) }

    // MARK: Strain / Effort ramp — the terracotta "Effort" colour world: a single warm output
    // hue from deep ember to a soft bright peak, never crossing into the sage/blue-grey worlds.
    public static let strain000 = Color(light: "#7A4130", dark: "#8C4A36") // deep ember
    public static let strain033 = Color(light: "#93503C", dark: "#A85A42") // warm terracotta
    public static let strain066 = Color(light: "#AD6248", dark: "#C97B63") // bright terracotta
    public static let strain100 = Color(light: "#C68268", dark: "#D99B85") // soft peak

    public static var strainStops: [Gradient.Stop] {
        isClassic ? cStrainStops : [
            .init(color: strain000, location: 0.00),
            .init(color: strain033, location: 0.33),
            .init(color: strain066, location: 0.66),
            .init(color: strain100, location: 1.00),
        ]
    }

    /// The strain gradient (terracotta output/heat, or the Classic blue ramp).
    public static var strainGradient: Gradient { Gradient(stops: strainStops) }

    // MARK: Sleep stages — the blue-grey "Rest" colour world (Clinical); Classic adds a purple REM.
    // Four restrained, desaturated tones — no bright hues — so the hypnogram reads as quiet, editorial
    // bands rather than a game palette. Light-mode variants are the same hues darkened for contrast.
    public static var sleepAwake: Color { isClassic ? cSleepAwake : Color(light: "#8E8E90", dark: "#8A8A8D") }
    public static var sleepLight: Color { isClassic ? cSleepLight : Color(light: "#7C93A4", dark: "#93A9BA") }
    public static var sleepDeep:  Color { isClassic ? cSleepDeep  : Color(light: "#3F5568", dark: "#5A7488") }
    public static var sleepREM:   Color { isClassic ? cSleepREM   : Color(light: "#5C6883", dark: "#7C88A6") }

    // MARK: HR zones — Clinical cool (blue-grey) → warm (terracotta), or the Classic grey→green→yellow→orange→red.
    public static var zone1: Color { isClassic ? cZone1 : Color(light: "#7A94A8", dark: "#7A94A8") }
    public static var zone2: Color { isClassic ? cZone2 : Color(light: "#6C86A0", dark: "#6C86A0") }
    public static var zone3: Color { isClassic ? cZone3 : Color(light: "#A88F72", dark: "#A88F72") }
    public static var zone4: Color { isClassic ? cZone4 : Color(light: "#BD8564", dark: "#BD8564") }
    public static var zone5: Color { isClassic ? cZone5 : Color(light: "#C97B63", dark: "#C97B63") }

    /// HR zones indexed 1...5; index 0 mirrors zone1 for convenience.
    public static var hrZones: [Color] { [zone1, zone1, zone2, zone3, zone4, zone5] }

    // MARK: Status — Clinical sage/neutral/terracotta, or the Classic green/amber/red.
    public static var statusPositive: Color { isClassic ? Color(light: "#2E9E4F", dark: "#46B45A") : Color(light: "#4F8F49", dark: "#8FBF8A") }
    public static var statusWarning:  Color { isClassic ? Color(light: "#CFA528", dark: "#F2C53D") : Color(light: "#A88F72", dark: "#B99C79") }
    public static var statusCritical: Color { isClassic ? Color(light: "#CB3A2F", dark: "#E5483B") : Color(light: "#A85A42", dark: "#C97B63") }

    // MARK: Per-metric accents — HRV / SpO₂ / energy / risk, drawn from the same restrained trio.
    public static var metricCyan:   Color { isClassic ? Color(light: "#2E92B4", dark: "#3FA9C9") : Color(light: "#6C86A0", dark: "#7A94A8") }
    public static var metricPurple: Color { isClassic ? Color(light: "#6A4FC0", dark: "#8E6FD6") : Color(light: "#5C6883", dark: "#7C88A6") }
    public static var metricAmber:  Color { isClassic ? Color(light: "#CFA528", dark: "#F2C53D") : Color(light: "#A88F72", dark: "#B99C79") }
    public static var metricRose:   Color { isClassic ? Color(light: "#CB3A2F", dark: "#E5483B") : Color(light: "#A85A42", dark: "#C97B63") }

    // MARK: - Domain "colour worlds"
    //
    // Each daily score owns a two-stop accent gradient (deep → bright) plus a glow.
    // Charge (recovery) owns sage; Effort (strain) owns terracotta; Rest (sleep) owns
    // blue-grey — matching Clinical Premium's "one colour per metric" rule.

    // Each domain's accent / glow follows the chart style: Clinical (sage/terracotta/blue-grey) or
    // Classic (Charge=green, Effort=blue, Rest=indigo, Stress=amber) so card tints + gauge tips + glows
    // match the data scale.

    /// Charge (recovery) — sage world / Classic green.
    public static var chargeColor: Color  { isClassic ? Color(light: "#2E9E4F", dark: "#46B45A") : Color(light: "#4F8F49", dark: "#8FBF8A") }
    public static var chargeDeep: Color    { isClassic ? Color(light: "#207A3C", dark: "#2E9E4F") : Color(light: "#3E7239", dark: "#6E9E69") }
    public static var chargeBright: Color  { isClassic ? Color(light: "#5FBE6E", dark: "#86D98E") : Color(light: "#6DA867", dark: "#A5CC9F") }
    public static var chargeGlow: Color    { isClassic ? Color(light: "#2E9E4F", dark: "#46B45A") : Color(light: "#4F8F49", dark: "#8FBF8A") }
    /// Diagonal accent pair for the Charge card wash + gauge stroke (deep → bright).
    public static var chargeGradient: Gradient { Gradient(colors: [chargeDeep, chargeBright]) }

    /// Effort (strain) — terracotta world / Classic blue.
    public static var effortColor: Color   { isClassic ? Color(light: "#3A74C4", dark: "#4A90E2") : Color(light: "#A85A42", dark: "#C97B63") }
    public static var effortDeep: Color    { isClassic ? Color(light: "#284F9C", dark: "#2F6FCB") : Color(light: "#7A4130", dark: "#8C4A36") }
    public static var effortBright: Color  { isClassic ? Color(light: "#5E92D6", dark: "#7FB2E8") : Color(light: "#C68268", dark: "#D99B85") }
    public static var effortGlow: Color    { isClassic ? Color(light: "#3A74C4", dark: "#4A90E2") : Color(light: "#A85A42", dark: "#C97B63") }
    public static var effortGradient: Gradient { Gradient(colors: [effortDeep, effortBright]) }

    /// Rest (sleep) — blue-grey world / Classic indigo.
    public static var restColor: Color     { isClassic ? Color(light: "#3A80D6", dark: "#6FA8E8") : Color(light: "#4C6478", dark: "#7A94A8") }
    public static var restDeep: Color      { isClassic ? Color(light: "#203E73", dark: "#2A4C8F") : Color(light: "#3F5568", dark: "#5A7488") }
    public static var restBright: Color    { isClassic ? Color(light: "#6A4FC0", dark: "#8E6FD6") : Color(light: "#7C93A4", dark: "#93A9BA") }
    public static var restGlow: Color      { isClassic ? Color(light: "#3A80D6", dark: "#6FA8E8") : Color(light: "#4C6478", dark: "#7A94A8") }
    public static var restGradient: Gradient { Gradient(colors: [restDeep, restBright]) }

    /// Stress — blue-grey→terracotta world / Classic green→amber→red.
    public static var stressColor: Color   { isClassic ? Color(light: "#CFA528", dark: "#F2C53D") : Color(light: "#A88F72", dark: "#B99C79") }
    public static var stressDeep: Color    { isClassic ? Color(light: "#2E9E4F", dark: "#46B45A") : Color(light: "#4C6478", dark: "#7A94A8") }
    public static var stressBright: Color  { isClassic ? Color(light: "#CB3A2F", dark: "#E5483B") : Color(light: "#A85A42", dark: "#C97B63") }
    public static var stressGlow: Color    { isClassic ? Color(light: "#CFA528", dark: "#F2C53D") : Color(light: "#A88F72", dark: "#B99C79") }
    /// 3-stop gauge ramp: calm → balanced → high.
    public static var stressGradient: Gradient { Gradient(colors: [stressDeep, stressColor, stressBright]) }

    // MARK: Scenic background — detail-screen hero backdrop, now a flat near-black wash matching
    // the base canvas (no starfield glow; Clinical Premium drops the "scenic" bloom entirely).
    /// Radial canvas: lit center → deep edge. Used by `ScenicHeroBackground`.
    public static let scenicCenter     = Color(light: "#F7F6F3", dark: "#151517")
    public static let scenicEdge       = Color(light: "#EDEBE6", dark: "#0A0A0B")
    /// Star tint for the scenic starfield (kept for API stability; the field no longer renders — see
    /// `ScenicHeroBackground`).
    public static let scenicStar       = Color(light: "#D8D5CD", dark: "#3A3A3C")

    /// Frosted-card tint endpoints (now flat — same top/bottom so any lingering wash reads as a solid fill).
    public static let cardFillTop      = Color(light: "#FFFFFF", dark: "#151517")
    public static let cardFillBottom   = Color(light: "#FAF9F6", dark: "#0F0F10")

    // MARK: - Core accent + neutral ramps
    //
    // The primary accent ramp (buttons, ring fills, FAB, active chrome) now runs sage green
    // instead of gold; the neutral "titanium" ramp (tiles, avatars, icon plates) runs a quiet
    // near-black grey. Same names on Android so Apple and Android match byte-for-byte.

    /// Brand accent — primary CTA fill. Sage on both schemes (deepened a hair on light for contrast).
    public static let gold          = Color(light: "#4F8F49", dark: "#8FBF8A")
    /// Bright sage — accent highlight / hover.
    public static let goldLight     = Color(light: "#6DA867", dark: "#A5CC9F")
    /// Deep sage — accent low stop.
    public static let goldDeep      = Color(light: "#3E7239", dark: "#6E9E69")
    /// Near-black ink for text/icons placed ON accent-filled surfaces (scheme-invariant; sage fills
    /// stay sage — a dark ink reads cleanly on the muted green in both themes).
    public static let goldDeepText  = Color(hex: "#0A0A0B")
    /// The bright core dot at a gauge arc tip / sparkline head — flips to a dark ink on light so it
    /// still reads as a crisp centre against a light-mode accent, and stays warm off-white on dark.
    public static let tipCore       = Color(light: "#17171A", dark: "#F2F1EE")
    /// Sparing emphasis (badges / alerts) — reuses the terracotta alert hue rather than a separate yellow.
    public static let signalYellow  = Color(light: "#A85A42", dark: "#C97B63")
    /// 135–155° accent ramp for buttons, ring fills, FAB (light → sage → deep).
    public static let goldGradient  = Gradient(colors: [goldLight, gold, goldDeep])

    /// Neutral ramp (top highlight → mid body → low → deep) for tiles, avatars and icon plates.
    /// A quiet near-black/grey ramp on dark; a light grey ramp on light so tiles stay visible on paper.
    public static let titaniumTop   = Color(light: "#E4E2DD", dark: "#2C2C2E")
    public static let titaniumMid   = Color(light: "#C9C7C1", dark: "#242426")
    public static let titaniumLow   = Color(light: "#ADABA5", dark: "#1C1C1E")
    public static let titaniumDeep  = Color(hex: "#141416")
    /// 150° neutral ramp for tiles / avatars / icon plates.
    public static let titaniumGradient = Gradient(colors: [titaniumTop, titaniumMid, titaniumLow, titaniumDeep])

    // MARK: - Sampling helpers

    /// Sample the recovery gradient (terracotta → sage) at a recovery score 0...100.
    /// Returns the exact interpolated color used everywhere recovery is tinted.
    public static func recoveryColor(_ score: Double) -> Color {
        sample(stops: recoveryStops, at: score / 100.0)
    }

    /// Sample the strain ("Effort") gradient at a value on NOOP's 0...100 Effort scale.
    public static func strainColor(_ strain: Double) -> Color {
        sample(stops: strainStops, at: strain / 100.0)
    }

    /// Effort tint sampled by a 0...1 fraction (e.g. value/scaleMax), spreading the full ember→bright
    /// terracotta ramp. Prefer this for gauge tips / value-tinted accents so a high Effort reads as bright
    /// terracotta rather than ember. `strainColor(_:)` stays for callers holding a 0...100 value.
    public static func effortTint(fraction: Double) -> Color {
        sample(stops: strainStops, at: min(max(fraction, 0), 1))
    }

    /// The state word for a recovery score, per spec §9.3.
    /// DEPLETED · LOW · MODERATE · PRIMED · PEAK
    public static func recoveryState(_ score: Double) -> String {
        switch score {
        case ..<25:  return String(localized: "DEPLETED", bundle: .module)
        case ..<50:  return String(localized: "LOW", bundle: .module)
        case ..<70:  return String(localized: "MODERATE", bundle: .module)
        case ..<88:  return String(localized: "PRIMED", bundle: .module)
        default:     return String(localized: "PEAK", bundle: .module)
        }
    }

    /// HR-zone color for a 0...5 zone index (clamped).
    public static func hrZoneColor(_ zone: Int) -> Color {
        let z = max(1, min(5, zone))
        return hrZones[z]
    }

    /// Color for a sleep stage by canonical name (awake/light/deep/rem).
    public static func sleepStageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: return sleepAwake
        case .light: return sleepLight
        case .deep:  return sleepDeep
        case .rem:   return sleepREM
        }
    }

    // MARK: - Linear gradient stop interpolation

    /// Interpolate a set of gradient stops at a normalized position 0...1.
    /// Clamps out-of-range positions to the end stops.
    public static func sample(stops: [Gradient.Stop], at position: Double) -> Color {
        guard let first = stops.first else { return .clear }
        guard stops.count > 1 else { return first.color }
        let t = min(max(position, 0.0), 1.0)

        // Find the bracketing pair.
        var lower = stops[0]
        var upper = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) {
            let a = stops[i]
            let b = stops[i + 1]
            if t >= a.location && t <= b.location {
                lower = a
                upper = b
                break
            }
        }
        let span = upper.location - lower.location
        let localT = span > 0 ? (t - lower.location) / span : 0
        return interpolate(lower.color, upper.color, localT)
    }

    /// Linear-interpolate two colors in sRGB space.
    static func interpolate(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ca = ColorComponentCache.components(of: a)
        let cb = ColorComponentCache.components(of: b)
        let tt = min(max(t, 0.0), 1.0)
        return Color(
            .sRGB,
            red:   ca.r + (cb.r - ca.r) * tt,
            green: ca.g + (cb.g - ca.g) * tt,
            blue:  ca.b + (cb.b - ca.b) * tt,
            opacity: ca.a + (cb.a - ca.a) * tt
        )
    }
}

// MARK: - Resolved-component memo cache
//
// PERF: `interpolate(_:_:_:)` is the leaf of ALL gradient sampling — every sparkline point, every pip
// segment, every gauge tip, every heat-strip cell calls `sample(stops:at:)` → `interpolate`, which used
// to build a fresh UIColor/NSColor and run `getRed()` on BOTH endpoints on every single call. The stop
// colours are a tiny fixed set of static `let`s, so resolving them over and over dominated the draw.
//
// This memoizes the resolved sRGB components per Color. Crucially the cache is keyed on the CURRENT
// resolved appearance as well as the Color, because the palette tokens are dynamic `Color(light:dark:)`
// providers that resolve to DIFFERENT components per light/dark — so a bare Color key would return a
// stale, wrong-scheme value after an appearance flip. Including the appearance token in the key makes
// the cache miss (and re-resolve) exactly when the scheme changes, so the output stays byte-identical to
// calling `rgbaComponents` directly. Bounded so a pathological caller can't grow it without limit.
enum ColorComponentCache {
    private static var store: [Key: (r: Double, g: Double, b: Double, a: Double)] = [:]
    private static let lock = NSLock()

    private struct Key: Hashable {
        let color: Color
        let appearance: Int
    }

    /// A small integer identifying the current resolved appearance (light vs dark), matching the trait
    /// that `UIColor(color)` / `NSColor(color)` resolves against at this call site.
    private static var appearanceToken: Int {
        #if os(watchOS)
        // No UITraitCollection on watchOS; the watch app is always dark, so the cache key is constant.
        return 1
        #elseif canImport(UIKit)
        return UITraitCollection.current.userInterfaceStyle == .dark ? 1 : 0
        #elseif canImport(AppKit)
        let match = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? 1 : 0
        #else
        return 0
        #endif
    }

    static func components(of color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        let key = Key(color: color, appearance: appearanceToken)
        lock.lock()
        if let hit = store[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let resolved = color.rgbaComponents
        lock.lock()
        // Cap the cache so an adversarial stream of unique colours can't grow it unboundedly; the real
        // working set is the handful of static palette stops, so this ceiling is never hit in practice.
        if store.count > 512 { store.removeAll(keepingCapacity: true) }
        store[key] = resolved
        lock.unlock()
        return resolved
    }
}

// MARK: - Sleep stage enum (shared with Hypnogram)

public enum SleepStage: String, CaseIterable, Sendable {
    case awake
    case light
    case deep
    case rem

    /// Display label.
    public var label: String {
        switch self {
        case .awake: return String(localized: "Awake", bundle: .module)
        case .light: return String(localized: "Light", bundle: .module)
        case .deep:  return String(localized: "Deep", bundle: .module)
        case .rem:   return "REM"
        }
    }

    /// Vertical band order (top = awake, bottom = deep) for hypnogram layout.
    public var bandRank: Int {
        switch self {
        case .awake: return 0
        case .rem:   return 1
        case .light: return 2
        case .deep:  return 3
        }
    }
}

// MARK: - Color component extraction

extension Color {
    /// Resolve to sRGB RGBA components in 0...1. Works on macOS 13+ via platform color bridge.
    var rgbaComponents: (r: Double, g: Double, b: Double, a: Double) {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #elseif canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #else
        return (0, 0, 0, 1)
        #endif
    }
}

#if DEBUG
#Preview("Palette") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            swatchRow("Surfaces", [
                ("base", StrandPalette.surfaceBase),
                ("raised", StrandPalette.surfaceRaised),
                ("overlay", StrandPalette.surfaceOverlay),
                ("inset", StrandPalette.surfaceInset),
                ("hairline", StrandPalette.hairline),
                ("hairline.strong", StrandPalette.hairlineStrong),
            ])
            swatchRow("Text", [
                ("primary", StrandPalette.textPrimary),
                ("secondary", StrandPalette.textSecondary),
                ("tertiary", StrandPalette.textTertiary),
            ])
            swatchRow("Accent", [
                ("accent", StrandPalette.accent),
                ("hover", StrandPalette.accentHover),
                ("muted", StrandPalette.accentMuted),
            ])
            swatchRow("Sage / accent", [
                ("gold", StrandPalette.gold),
                ("light", StrandPalette.goldLight),
                ("deep", StrandPalette.goldDeep),
                ("deepText", StrandPalette.goldDeepText),
                ("signal", StrandPalette.signalYellow),
            ])
            swatchRow("Titanium (neutral)", [
                ("top", StrandPalette.titaniumTop),
                ("mid", StrandPalette.titaniumMid),
                ("low", StrandPalette.titaniumLow),
                ("deep", StrandPalette.titaniumDeep),
            ])
            VStack(alignment: .leading, spacing: 8) {
                Text("RECOVERY GRADIENT").font(.caption).foregroundStyle(StrandPalette.textTertiary)
                LinearGradient(gradient: StrandPalette.recoveryGradient, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("STRAIN RAMP").font(.caption).foregroundStyle(StrandPalette.textTertiary)
                LinearGradient(gradient: StrandPalette.strainGradient, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            swatchRow("Sleep stages", [
                ("awake", StrandPalette.sleepAwake),
                ("light", StrandPalette.sleepLight),
                ("deep", StrandPalette.sleepDeep),
                ("REM", StrandPalette.sleepREM),
            ])
            swatchRow("HR zones", [
                ("Z1", StrandPalette.zone1), ("Z2", StrandPalette.zone2),
                ("Z3", StrandPalette.zone3), ("Z4", StrandPalette.zone4),
                ("Z5", StrandPalette.zone5),
            ])
        }
        .padding(24)
    }
    .frame(width: 520, height: 760)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}

@ViewBuilder
private func swatchRow(_ title: String, _ items: [(String, Color)]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title.uppercased())
            .font(.caption)
            .foregroundStyle(StrandPalette.textTertiary)
        HStack(spacing: 10) {
            ForEach(items, id: \.0) { name, color in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color)
                        .frame(width: 64, height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(StrandPalette.hairline, lineWidth: 1))
                    Text(name).font(.system(size: 9)).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }
}
#endif
