import Foundation

// Momentum.swift — the emotional centrepiece of NOOP's streaks: one number to feel proud of.
//
// The streak CARDS answer "how am I doing on each habit"; Momentum answers "what am I building right
// now" with a single featured streak, a milestone to climb toward, and an intensity the UI turns into a
// glowing ember (rendered in the COLOUR of the habit itself — NOOP's own take on the streak flame, not
// a copied orange fire). Deterministic, pure, framework-free, tested. iPhone-first; no Kotlin twin.

public enum Momentum {

    /// The milestone ladder a streak climbs. Rungs get sparser as they grow so early wins feel close and
    /// long runs still have a next target.
    public static let ladder: [Int] = [3, 7, 14, 21, 30, 45, 60, 100, 150, 200, 300, 365]

    /// The full-intensity point: at this many days the ember burns as bright as it gets.
    public static let intensityFullDays: Double = 30

    /// One behaviour's streak state, as fed in by the app.
    public struct Streak: Equatable, Sendable {
        public let kind: HealthStreaks.Kind
        public let current: Int
        public let best: Int
        public init(kind: HealthStreaks.Kind, current: Int, best: Int) {
            self.kind = kind
            self.current = current
            self.best = best
        }
    }

    public struct Summary: Equatable, Sendable, Codable {
        /// The habit being celebrated (the strongest active run), or nil when nothing is active.
        public let featuredKind: HealthStreaks.Kind?
        public let current: Int
        public let best: Int
        /// The next ladder rung above `current`, or nil when past the top of the ladder.
        public let nextMilestone: Int?
        /// Days from `current` to `nextMilestone` (nil past the top).
        public let daysToNext: Int?
        /// The highest ladder rung already reached (0 if none), for a progress bar's start.
        public let prevMilestone: Int
        /// 0…1 for the ember's brightness/size.
        public let intensity: Double
        /// The featured run is at or above its all-time best right now — a live personal record.
        public let isRecord: Bool
        public var hasActiveStreak: Bool { current > 0 }

        public init(featuredKind: HealthStreaks.Kind?, current: Int, best: Int, nextMilestone: Int?,
                    daysToNext: Int?, prevMilestone: Int, intensity: Double, isRecord: Bool) {
            self.featuredKind = featuredKind
            self.current = current
            self.best = best
            self.nextMilestone = nextMilestone
            self.daysToNext = daysToNext
            self.prevMilestone = prevMilestone
            self.intensity = intensity
            self.isRecord = isRecord
        }
    }

    /// Feature the strongest active run (ties broken by the larger all-time best), and derive its
    /// milestone context + ember intensity.
    public static func summarize(_ streaks: [Streak]) -> Summary {
        let featured = streaks
            .filter { $0.current > 0 }
            .max { a, b in a.current != b.current ? a.current < b.current : a.best < b.best }

        guard let f = featured else {
            return Summary(featuredKind: nil, current: 0, best: streaks.map(\.best).max() ?? 0,
                           nextMilestone: ladder.first, daysToNext: ladder.first,
                           prevMilestone: 0, intensity: 0, isRecord: false)
        }

        let next = ladder.first { $0 > f.current }
        let prev = ladder.last { $0 <= f.current } ?? 0
        let intensity = min(1, 0.2 + 0.8 * Double(f.current) / intensityFullDays)

        return Summary(featuredKind: f.kind, current: f.current, best: f.best,
                       nextMilestone: next, daysToNext: next.map { $0 - f.current },
                       prevMilestone: prev, intensity: intensity,
                       isRecord: f.current >= f.best)
    }
}
