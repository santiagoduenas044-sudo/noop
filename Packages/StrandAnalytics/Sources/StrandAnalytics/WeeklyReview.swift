import Foundation

// WeeklyReview.swift — the week-scale health story: wins, setbacks, and one thing to try.
//
// Where the Morning Briefing zooms into today, this zooms out to seven days and compares them to the
// week before. It turns week-over-week deltas in the core signals (Charge, sleep duration, schedule
// consistency, training load) into ranked FINDINGS, splits them into wins and setbacks, names the
// biggest mover as the headline, and derives ONE actionable recommendation from the top setback (or a
// "keep it up" when the week was clean). Copy-free (kinds only — the app owns the prose); pure, DB-free,
// framework-free, tested. iPhone-first; no Kotlin twin.

public enum WeeklyReview {

    // Notability thresholds (a change smaller than this isn't worth a line).
    public static let chargeNotable: Double = 4        // avg Charge points, week over week
    public static let sleepNotableHours: Double = 0.5
    public static let effortNotable: Double = 6        // avg Effort points
    public static let scheduleSteadySD: Double = 50    // midpoint SD (min) at/under → steady
    public static let scheduleDriftSD: Double = 90     // …over → drifting

    public enum FindingKind: String, Sendable, Equatable, Codable {
        case recoveryUp, recoveryDown
        case sleptMore, sleptLess
        case steadySchedule, driftingSchedule
        case trainedMore, trainedLess
        case buildingWeek
    }

    public enum Tone: String, Sendable, Equatable, Codable { case positive, caution, neutral }

    public struct Finding: Equatable, Sendable, Codable {
        public let kind: FindingKind
        public let tone: Tone
        /// 0…1 importance, for ranking + the headline.
        public let magnitude: Double
        /// The signed change behind this finding, in its own units (Charge pts, hours, SD min…), when one
        /// applies — so the app can render "+6 pts", "−0.8 h" without recomputing.
        public let delta: Double?

        public init(kind: FindingKind, tone: Tone, magnitude: Double, delta: Double? = nil) {
            self.kind = kind
            self.tone = tone
            self.magnitude = magnitude
            self.delta = delta
        }
    }

    /// One week's aggregates (the app computes these from repo history).
    public struct WeekStats: Equatable, Sendable {
        public let avgCharge: Double?
        public let avgSleepHours: Double?
        public let avgEffort: Double?
        public let scheduleSDMin: Double?
        public let daysWithData: Int
        public let totalDays: Int

        public init(avgCharge: Double?, avgSleepHours: Double?, avgEffort: Double?,
                    scheduleSDMin: Double?, daysWithData: Int, totalDays: Int) {
            self.avgCharge = avgCharge
            self.avgSleepHours = avgSleepHours
            self.avgEffort = avgEffort
            self.scheduleSDMin = scheduleSDMin
            self.daysWithData = daysWithData
            self.totalDays = totalDays
        }
    }

    public struct Review: Equatable, Sendable, Codable {
        public let wins: [Finding]
        public let setbacks: [Finding]
        public let neutrals: [Finding]
        /// The single biggest mover (win or setback), or nil on a flat/empty week.
        public let headline: Finding?
        /// A recommendation key for the app to render ("rec.protectRecovery", …).
        public let recommendation: String
        /// Fraction of the week with data.
        public let completeness: Double
        public let hasEnoughData: Bool

        public init(wins: [Finding], setbacks: [Finding], neutrals: [Finding], headline: Finding?,
                    recommendation: String, completeness: Double, hasEnoughData: Bool) {
            self.wins = wins
            self.setbacks = setbacks
            self.neutrals = neutrals
            self.headline = headline
            self.recommendation = recommendation
            self.completeness = completeness
            self.hasEnoughData = hasEnoughData
        }
    }

    /// Minimum days with data before a review is worth showing.
    public static let minDaysWithData: Int = 3

    public static func build(this current: WeekStats, prior: WeekStats) -> Review {
        var findings: [Finding] = []

        // Recovery, week over week.
        if let a = current.avgCharge, let b = prior.avgCharge {
            let d = a - b
            if abs(d) >= chargeNotable {
                findings.append(Finding(kind: d > 0 ? .recoveryUp : .recoveryDown,
                                        tone: d > 0 ? .positive : .caution,
                                        magnitude: min(1, abs(d) / 15), delta: d))
            }
        }

        // Sleep duration, week over week.
        if let a = current.avgSleepHours, let b = prior.avgSleepHours {
            let d = a - b
            if abs(d) >= sleepNotableHours {
                findings.append(Finding(kind: d > 0 ? .sleptMore : .sleptLess,
                                        tone: d > 0 ? .positive : .caution,
                                        magnitude: min(1, abs(d) / 2), delta: d))
            }
        }

        // Schedule consistency (absolute band — a steady week is a win regardless of last week).
        if let sd = current.scheduleSDMin {
            if sd <= scheduleSteadySD {
                findings.append(Finding(kind: .steadySchedule, tone: .positive,
                                        magnitude: min(1, (scheduleSteadySD - sd) / scheduleSteadySD + 0.4),
                                        delta: sd))
            } else if sd >= scheduleDriftSD {
                findings.append(Finding(kind: .driftingSchedule, tone: .caution,
                                        magnitude: min(1, (sd - scheduleDriftSD) / 120 + 0.4), delta: sd))
            }
        }

        // Training load, week over week (neutral — more/less isn't inherently good or bad).
        if let a = current.avgEffort, let b = prior.avgEffort {
            let d = a - b
            if abs(d) >= effortNotable {
                findings.append(Finding(kind: d > 0 ? .trainedMore : .trainedLess, tone: .neutral,
                                        magnitude: min(1, abs(d) / 20), delta: d))
            }
        }

        let wins = findings.filter { $0.tone == .positive }.sorted { $0.magnitude > $1.magnitude }
        let setbacks = findings.filter { $0.tone == .caution }.sorted { $0.magnitude > $1.magnitude }
        let neutrals = findings.filter { $0.tone == .neutral }.sorted { $0.magnitude > $1.magnitude }

        let headline = (wins + setbacks).max { $0.magnitude < $1.magnitude }
        let completeness = current.totalDays > 0
            ? Double(current.daysWithData) / Double(current.totalDays) : 0
        let enough = current.daysWithData >= minDaysWithData

        return Review(wins: wins, setbacks: setbacks, neutrals: neutrals, headline: headline,
                      recommendation: recommendation(topSetback: setbacks.first, hasWins: !wins.isEmpty),
                      completeness: completeness, hasEnoughData: enough)
    }

    /// One recommendation, from the most pressing setback (or encouragement when the week was clean).
    static func recommendation(topSetback: Finding?, hasWins: Bool) -> String {
        guard let s = topSetback else { return "rec.keepGoing" }
        switch s.kind {
        case .recoveryDown:     return "rec.protectRecovery"
        case .sleptLess:        return "rec.prioritizeSleep"
        case .driftingSchedule: return "rec.steadyBedtime"
        default:                return hasWins ? "rec.keepGoing" : "rec.steadyWeek"
        }
    }
}
