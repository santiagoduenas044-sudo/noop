import Foundation

// MonthlyStory.swift — the month-scale health story / long-term trend read.
//
// Completes the day → week → month arc (Morning Briefing → Weekly Review → this). Where the weekly
// review compares two weeks, this looks at the whole ~4-week shape: is Charge trending up, holding, or
// slipping, how much sleep you've averaged, and whether your schedule stayed consistent. The trend is a
// least-squares slope over the month expressed in points-per-week, so "improving" means a real,
// measured climb, not a vibe. Copy-free (kinds/numbers only; the app owns prose). Pure, DB-free,
// framework-free, tested. iPhone-first; no Kotlin twin.

public enum MonthlyStory {

    /// Minimum days with data before a monthly read is honest.
    public static let minDaysWithData: Int = 14
    /// A Charge slope at/beyond this (points per week) reads as a real trend rather than noise.
    public static let trendSlopePerWeek: Double = 2.0
    /// Midpoint SD (min) at/under which the month's schedule reads as consistent.
    public static let consistentScheduleSD: Double = 55

    public enum Trend: String, Sendable, Equatable, Codable {
        case improving, steady, declining, unknown
    }

    public struct Input: Equatable, Sendable {
        public let recoveries: [Double]     // chronological (oldest→newest), non-nil Charge values
        public let sleepHours: [Double]     // chronological nightly hours
        public let scheduleSDMin: Double?   // month's sleep-midpoint SD
        public let daysWithData: Int
        public let totalDays: Int

        public init(recoveries: [Double], sleepHours: [Double], scheduleSDMin: Double?,
                    daysWithData: Int, totalDays: Int) {
            self.recoveries = recoveries
            self.sleepHours = sleepHours
            self.scheduleSDMin = scheduleSDMin
            self.daysWithData = daysWithData
            self.totalDays = totalDays
        }
    }

    public struct Story: Equatable, Sendable, Codable {
        public let hasEnough: Bool
        public let trend: Trend
        public let avgRecovery: Int?
        /// Charge change per week over the month (rounded to 0.1), signed.
        public let recoverySlopePerWeek: Double
        public let avgSleepHours: Double?
        public let consistentSchedule: Bool
        public let completeness: Double

        public init(hasEnough: Bool, trend: Trend, avgRecovery: Int?, recoverySlopePerWeek: Double,
                    avgSleepHours: Double?, consistentSchedule: Bool, completeness: Double) {
            self.hasEnough = hasEnough
            self.trend = trend
            self.avgRecovery = avgRecovery
            self.recoverySlopePerWeek = recoverySlopePerWeek
            self.avgSleepHours = avgSleepHours
            self.consistentSchedule = consistentSchedule
            self.completeness = completeness
        }
    }

    public static func build(_ i: Input) -> Story {
        let charges = i.recoveries.filter { $0 > 0 }
        let enough = i.daysWithData >= minDaysWithData && charges.count >= 8

        let avgRec = charges.isEmpty ? nil : charges.reduce(0, +) / Double(charges.count)
        let slopePerDay = charges.count >= 4 ? olsSlope(charges) : 0
        let slopePerWeek = slopePerDay * 7

        let trend: Trend = {
            guard enough else { return .unknown }
            if slopePerWeek >= trendSlopePerWeek { return .improving }
            if slopePerWeek <= -trendSlopePerWeek { return .declining }
            return .steady
        }()

        let hours = i.sleepHours.filter { $0 > 0 }
        let avgSleep = hours.isEmpty ? nil : hours.reduce(0, +) / Double(hours.count)
        let consistent = (i.scheduleSDMin ?? .greatestFiniteMagnitude) <= consistentScheduleSD
        let completeness = i.totalDays > 0 ? Double(i.daysWithData) / Double(i.totalDays) : 0

        return Story(hasEnough: enough, trend: trend,
                     avgRecovery: avgRec.map { Int($0.rounded()) },
                     recoverySlopePerWeek: (slopePerWeek * 10).rounded() / 10,
                     avgSleepHours: avgSleep.map { ($0 * 10).rounded() / 10 },
                     consistentSchedule: consistent, completeness: completeness)
    }

    /// Ordinary-least-squares slope of `y` against its index (0,1,2,…), in units of y per step.
    /// Returns 0 when x has no variance.
    static func olsSlope(_ y: [Double]) -> Double {
        let n = y.count
        guard n >= 2 else { return 0 }
        let nD = Double(n)
        let meanX = Double(n - 1) / 2
        let meanY = y.reduce(0, +) / nD
        var sxy = 0.0, sxx = 0.0
        for (i, v) in y.enumerated() {
            let dx = Double(i) - meanX
            sxy += dx * (v - meanY)
            sxx += dx * dx
        }
        return sxx > 0 ? sxy / sxx : 0
    }
}
