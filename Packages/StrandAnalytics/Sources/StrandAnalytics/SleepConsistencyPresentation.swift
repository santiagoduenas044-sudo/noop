import Foundation

// SleepConsistencyPresentation.swift — the framework-free presentation model for the
// "Sleep Consistency" card / detail view.
//
// PURELY ADDITIVE, and deliberately UI-FRAMEWORK-FREE: it takes a SleepRegularityResult and
// returns plain values (enums, Ints, Doubles, Bools) — NO SwiftUI/Color, NO localized copy.
// Colours and strings belong to the view layer; every DECISION (tone bucket, whether the
// onset/wake bars are trustworthy enough to show, the mid-sleep clock, the bar fill fractions)
// lives here so it is covered by `swift test` on the active swift-packages CI and mirrored
// byte-for-byte in Kotlin (SleepConsistencyPresentation.kt). The SwiftUI view stays a dumb
// renderer of these values — the part that isn't compiled by default CI carries no logic.
//
// PRODUCT NOTE (tone). Sleep-timing is a lifestyle wellness read, not a clinical one, so there
// is deliberately NO "critical/red/alarm" tone: an irregular week reads as `caution`, never as
// a failure. The four descriptive bands are distinguished by the view's HEADLINE wording (so the
// distinction survives colour-blindness and grayscale); tone only separates "steady" from "worth
// noticing" from "still building". This keeps the surface encouraging, never judgemental.

public struct SleepConsistencyPresentation: Equatable, Sendable, Codable {

    /// Semantic emphasis for the view to map to a design token — NOT a colour itself.
    /// `positive` → steady/good, `caution` → worth noticing (still gentle), `neutral` → building.
    public enum Tone: String, Sendable, Equatable, Codable {
        case positive
        case caution
        case neutral
    }

    /// The engine's descriptive band, passed through so the view can pick its (localized) copy.
    public let band: SleepRegularityLabel
    /// Emphasis bucket (see Tone).
    public let tone: Tone
    /// Whether the per-channel bedtime/wake bars are trustworthy enough to show — true ONLY on a
    /// SOLID-confidence read with both onset and wake spreads present (your #3: accuracy over
    /// showing more). The mid-sleep bar is always available on a readable result.
    public let showChannelBars: Bool
    /// Typical mid-sleep as a wall-clock hour (0…23), nil when the read is withheld.
    public let midpointClockHour: Int?
    /// Typical mid-sleep minute (0…59), nil when the read is withheld.
    public let midpointClockMinute: Int?
    /// Mid-sleep spread as a 0…1 bar fill (larger = more spread). nil when withheld. Always present
    /// on a readable result.
    public let midpointBarFraction: Double?
    /// Bedtime (onset) spread as a 0…1 bar fill. nil unless `showChannelBars`.
    public let onsetBarFraction: Double?
    /// Wake spread as a 0…1 bar fill. nil unless `showChannelBars`.
    public let wakeBarFraction: Double?

    public init(band: SleepRegularityLabel, tone: Tone, showChannelBars: Bool,
                midpointClockHour: Int?, midpointClockMinute: Int?,
                midpointBarFraction: Double?, onsetBarFraction: Double?, wakeBarFraction: Double?) {
        self.band = band
        self.tone = tone
        self.showChannelBars = showChannelBars
        self.midpointClockHour = midpointClockHour
        self.midpointClockMinute = midpointClockMinute
        self.midpointBarFraction = midpointBarFraction
        self.onsetBarFraction = onsetBarFraction
        self.wakeBarFraction = wakeBarFraction
    }

    /// Spread (minutes) that fills a per-channel bar completely. A 3 h spread is already "all over
    /// the place", so the bar saturates there; anything larger stays pinned full rather than
    /// running off. Same value on both platforms.
    public static let barFullScaleMin: Double = 180.0

    /// Derive the presentation from an engine result. Pure and total — never throws, never nil-crashes.
    public static func from(_ r: SleepRegularityResult) -> SleepConsistencyPresentation {
        let tone: Tone
        switch r.label {
        case .veryRegular, .regular: tone = .positive
        case .variable, .irregular:  tone = .caution
        case .unreadable:            tone = .neutral
        }

        guard r.isReadable else {
            return SleepConsistencyPresentation(
                band: r.label, tone: tone, showChannelBars: false,
                midpointClockHour: nil, midpointClockMinute: nil,
                midpointBarFraction: nil, onsetBarFraction: nil, wakeBarFraction: nil)
        }

        // Mid-sleep clock from the circular-mean minute-of-day.
        var hour: Int? = nil
        var minute: Int? = nil
        if let mid = r.meanMidpointMinOfDay {
            let m = ((mid % 1440) + 1440) % 1440
            hour = m / 60
            minute = m % 60
        }

        let midFrac = r.midpointSDMinutes.map { barFraction($0) }

        // Onset/wake bars only on a SOLID read with both spreads present.
        let bothChannels = (r.onsetSDMinutes != nil) && (r.wakeSDMinutes != nil)
        let showBars = (r.confidence == .solid) && bothChannels
        let onsetFrac = showBars ? r.onsetSDMinutes.map { barFraction($0) } : nil
        let wakeFrac = showBars ? r.wakeSDMinutes.map { barFraction($0) } : nil

        return SleepConsistencyPresentation(
            band: r.label, tone: tone, showChannelBars: showBars,
            midpointClockHour: hour, midpointClockMinute: minute,
            midpointBarFraction: midFrac, onsetBarFraction: onsetFrac, wakeBarFraction: wakeFrac)
    }

    /// Map a spread in minutes to a clamped 0…1 bar fill.
    static func barFraction(_ sdMin: Double) -> Double {
        let f = sdMin / barFullScaleMin
        return min(max(f, 0.0), 1.0)
    }
}
