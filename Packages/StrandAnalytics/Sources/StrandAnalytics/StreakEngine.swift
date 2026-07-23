import Foundation

// StreakEngine.swift — the generic "consecutive healthy days" core.
//
// NOOP's streaks reward real health BEHAVIOURS (a steady sleep schedule, enough rest, starting the day
// recovered) — never just opening the app. This engine is the domain-neutral core: given an ordered
// per-day met/not-met series, it returns the current run, the best run in the window, and whether the
// streak is "at risk" (yesterday extended a run but the latest day hasn't met it yet). The specific,
// adaptive behaviours live in HealthStreaks; the copy + visuals live in the app.
//
// Honest by construction: a day with no data BREAKS a run (you can't credit a behaviour that wasn't
// measured), and `current` counts only the unbroken trailing run of met days. Deterministic, pure,
// DB-free, framework-free, fully testable. iPhone-first; no Kotlin twin.

public enum StreakEngine {

    /// One day's verdict for a behaviour. `day` is a yyyy-MM-dd key (for ordering / display only).
    public struct DayFlag: Equatable, Sendable {
        public let day: String
        public let met: Bool
        public init(day: String, met: Bool) {
            self.day = day
            self.met = met
        }
    }

    public struct Result: Equatable, Sendable, Codable {
        /// Length of the unbroken run of met days ending at the most recent day (0 if it isn't met).
        public let current: Int
        /// Longest run of met days anywhere in the window.
        public let best: Int
        /// Total met days in the window.
        public let metCount: Int
        /// Days considered.
        public let total: Int
        /// The run that ended just before the latest day, when the latest day itself isn't met — i.e. a
        /// live streak you'd extend by doing the behaviour today. 0 when the latest day already met it
        /// (the run is `current`, not at risk) or when there was no prior run.
        public let atRisk: Int

        public var isActive: Bool { current > 0 }

        public init(current: Int, best: Int, metCount: Int, total: Int, atRisk: Int) {
            self.current = current
            self.best = best
            self.metCount = metCount
            self.total = total
            self.atRisk = atRisk
        }
    }

    /// Assess an ordered (oldest → newest) per-day series.
    public static func assess(days: [DayFlag]) -> Result {
        guard !days.isEmpty else { return Result(current: 0, best: 0, metCount: 0, total: 0, atRisk: 0) }

        var best = 0, run = 0, metCount = 0
        for f in days {
            if f.met { run += 1; metCount += 1; best = Swift.max(best, run) }
            else { run = 0 }
        }

        // Current = trailing run of met days.
        var current = 0
        for f in days.reversed() {
            if f.met { current += 1 } else { break }
        }

        // At risk: latest day not met, but the run immediately before it was non-zero.
        var atRisk = 0
        if let last = days.last, !last.met {
            var r = 0
            for f in days.dropLast().reversed() {
                if f.met { r += 1 } else { break }
            }
            atRisk = r
        }

        return Result(current: current, best: best, metCount: metCount, total: days.count, atRisk: atRisk)
    }
}
