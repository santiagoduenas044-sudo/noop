import Foundation

// HealthStreaks.swift — NOOP's meaningful, self-adapting health streaks.
//
// Three behaviours worth rewarding, each judged against the USER'S OWN baseline rather than a generic
// target (smart goals, not fixed ones):
//   • steadySchedule — you kept a consistent sleep midpoint (within tolerance of your recent norm).
//   • restedNights   — you got close to your typical night's sleep (personal median, with grace).
//   • recoveryReady  — you started the day recovered (Charge at/above your personal floor).
//
// Each builder turns raw per-day values into StreakEngine.DayFlag[] using an adaptive threshold derived
// from the user's history; StreakEngine then produces the current/best/at-risk run. Pure, DB-free,
// framework-free, fully testable. The copy + visuals live in the app. iPhone-first; no Kotlin twin.

public enum HealthStreaks {

    public enum Kind: String, Sendable, Equatable, Codable, CaseIterable {
        case steadySchedule
        case restedNights
        case recoveryReady
    }

    // MARK: Rested nights (adaptive to your typical sleep)

    /// Grace below your personal median that still counts as a rested night.
    public static let restedGraceMin: Double = 30
    public static let restedFloorMin: Double = 360   // never demand less credit than 6 h
    public static let restedCapMin: Double = 540     // never demand more than 9 h

    /// Adaptive target: your median night's sleep minus a small grace, clamped to a sane band.
    public static func restedTargetMin(_ asleepMins: [Double]) -> Double {
        let m = median(asleepMins.filter { $0 > 0 }) ?? restedFloorMin
        return min(max(m - restedGraceMin, restedFloorMin), restedCapMin)
    }

    public static func restedFlags(days: [String], asleepMins: [Double]) -> [StreakEngine.DayFlag] {
        let target = restedTargetMin(asleepMins)
        return zip(days, asleepMins).map { StreakEngine.DayFlag(day: $0.0, met: $0.1 >= target) }
    }

    // MARK: Steady schedule (consistent sleep timing)

    /// How far the night's midpoint may sit from your recent mean and still count as steady.
    public static let scheduleToleranceMin: Double = 60
    /// Nights of history needed before we can judge consistency (earlier nights are "building").
    public static let scheduleMinBaseline: Int = 3
    /// Trailing window the personal mean is taken over.
    public static let scheduleWindow: Int = 14

    /// A night is steady when its sleep midpoint is within tolerance of the circular mean of the
    /// preceding window. The first few nights (no baseline yet) are not-met (nothing to compare to).
    public static func steadyFlags(days: [String], midpointsMinOfDay: [Double]) -> [StreakEngine.DayFlag] {
        var flags: [StreakEngine.DayFlag] = []
        for i in days.indices {
            let start = Swift.max(0, i - scheduleWindow)
            let prior = Array(midpointsMinOfDay[start..<i])
            guard prior.count >= scheduleMinBaseline else {
                flags.append(StreakEngine.DayFlag(day: days[i], met: false)); continue
            }
            let dev = circularDiffMinutes(midpointsMinOfDay[i], circularMeanMinutes(prior))
            flags.append(StreakEngine.DayFlag(day: days[i], met: dev <= scheduleToleranceMin))
        }
        return flags
    }

    // MARK: Recovery ready (started the day recovered, relative to you)

    public static let recoveryMarginPts: Double = 12
    public static let recoveryFloorPts: Double = 34   // never call a genuinely red day "ready"
    public static let recoveryCapPts: Double = 67     // never demand a peak day to count

    /// Adaptive floor: your median Charge minus a margin, clamped so it's neither trivially easy nor
    /// impossibly high.
    public static func recoveryFloor(_ recoveries: [Double]) -> Double {
        let m = median(recoveries.filter { $0 > 0 }) ?? 50
        return min(max(m - recoveryMarginPts, recoveryFloorPts), recoveryCapPts)
    }

    public static func recoveryFlags(days: [String], recoveries: [Double]) -> [StreakEngine.DayFlag] {
        let floor = recoveryFloor(recoveries)
        return zip(days, recoveries).map { StreakEngine.DayFlag(day: $0.0, met: $0.1 >= floor) }
    }
}

// MARK: - Pure helpers

/// Median of a sample (nil when empty).
private func median(_ xs: [Double]) -> Double? {
    let s = xs.sorted()
    guard !s.isEmpty else { return nil }
    let n = s.count
    return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
}

/// Circular mean of minute-of-day values (handles the midnight wrap), returned in 0..<1440.
private func circularMeanMinutes(_ mins: [Double]) -> Double {
    guard !mins.isEmpty else { return 0 }
    let twoPi = 2 * Double.pi
    var s = 0.0, c = 0.0
    for m in mins {
        let a = m / 1440 * twoPi
        s += sin(a); c += cos(a)
    }
    var mean = atan2(s, c)
    if mean < 0 { mean += twoPi }
    return mean / twoPi * 1440
}

/// Smallest circular distance (minutes) between two minute-of-day values.
private func circularDiffMinutes(_ a: Double, _ b: Double) -> Double {
    let d = abs(a - b).truncatingRemainder(dividingBy: 1440)
    return min(d, 1440 - d)
}
