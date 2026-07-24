import Foundation

// Achievements.swift — earned milestone badges that celebrate real health habits.
//
// Momentum shows the single live streak; this is the collection you've BUILT over time — badges earned
// across behaviours (steady schedule, rested nights, recovery-ready) plus a couple of records (a Charge
// peak, days tracked). Each badge is earned when a personal best clears its tier; the engine also
// reports the next locked badge per category with progress, so there's always a next thing to reach.
// Honest: a badge is earned only from a real best, never granted. Pure, DB-free, framework-free, tested.
// Copy + visuals live in the app. iPhone-first; no Kotlin twin.

public enum Achievements {

    /// Day-count tiers shared by the three behaviour streaks.
    public static let streakTiers: [Int] = [7, 14, 30, 60, 100]
    /// Charge-peak tiers (reach this Charge at least once).
    public static let peakTiers: [Int] = [85, 90, 95, 100]
    /// Days-tracked tiers (cumulative days with a scored day).
    public static let trackedTiers: [Int] = [7, 30, 100, 365]

    public struct Badge: Equatable, Sendable, Codable, Identifiable {
        /// Stable id, e.g. "steadySchedule.30" or "peak.90".
        public var id: String { "\(category).\(tier)" }
        /// "steadySchedule" | "restedNights" | "recoveryReady" | "peak" | "tracked".
        public let category: String
        public let tier: Int
        public let earned: Bool
        /// 0…1 toward this tier (1 when earned). Meaningful for the next locked badge.
        public let progress: Double

        public init(category: String, tier: Int, earned: Bool, progress: Double) {
            self.category = category
            self.tier = tier
            self.earned = earned
            self.progress = progress
        }
    }

    public struct Report: Equatable, Sendable, Codable {
        /// Earned badges, most impressive first (largest tier, then category order).
        public let earned: [Badge]
        /// The next locked badge in each category that has one, with progress toward it.
        public let nextUp: [Badge]
        public let earnedCount: Int
        public let totalCount: Int

        public init(earned: [Badge], nextUp: [Badge], earnedCount: Int, totalCount: Int) {
            self.earned = earned
            self.nextUp = nextUp
            self.earnedCount = earnedCount
            self.totalCount = totalCount
        }
    }

    /// Evaluate the badge wall from the user's personal bests.
    public static func evaluate(scheduleBest: Int, restedBest: Int, recoveryBest: Int,
                                peakRecovery: Int, daysTracked: Int) -> Report {
        let categories: [(name: String, value: Int, tiers: [Int])] = [
            ("steadySchedule", scheduleBest, streakTiers),
            ("restedNights", restedBest, streakTiers),
            ("recoveryReady", recoveryBest, streakTiers),
            ("peak", peakRecovery, peakTiers),
            ("tracked", daysTracked, trackedTiers),
        ]

        var earned: [Badge] = []
        var nextUp: [Badge] = []
        var total = 0

        for c in categories {
            total += c.tiers.count
            for tier in c.tiers where c.value >= tier {
                earned.append(Badge(category: c.name, tier: tier, earned: true, progress: 1))
            }
            if let next = c.tiers.first(where: { $0 > c.value }) {
                let prog = next > 0 ? min(1, max(0, Double(c.value) / Double(next))) : 0
                nextUp.append(Badge(category: c.name, tier: next, earned: false, progress: prog))
            }
        }

        earned.sort { a, b in
            a.tier != b.tier ? a.tier > b.tier : categoryRank(a.category) < categoryRank(b.category)
        }
        // Nearest-to-complete next badges first (most motivating).
        nextUp.sort { $0.progress > $1.progress }

        return Report(earned: earned, nextUp: nextUp, earnedCount: earned.count, totalCount: total)
    }

    static func categoryRank(_ c: String) -> Int {
        switch c {
        case "recoveryReady":  return 0
        case "steadySchedule": return 1
        case "restedNights":   return 2
        case "peak":           return 3
        default:               return 4   // tracked
        }
    }
}
