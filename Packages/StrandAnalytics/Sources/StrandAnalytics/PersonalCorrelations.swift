import Foundation

// PersonalCorrelations.swift — "what actually moves YOUR recovery", from your own history.
//
// A companion should help you understand your body, not just chart it. This engine correlates a target
// signal (Charge) against candidate lifestyle factors you control (sleep duration, efficiency,
// restorative minutes, time awake) over the user's own history, and surfaces only the links that are
// both statistically real (enough days, low p) and worth mentioning (a real effect size). It NEVER
// claims causation — the app copy says "tends to" / "tracks with", never "causes". Ranked strongest
// first, capped. Pure wrapper over CorrelationEngine; DB-free, framework-free, tested.
//
// iPhone-first; no Kotlin twin (the underlying CorrelationEngine already mirrors).

public enum PersonalCorrelations {

    /// Minimum overlapping days before a correlation is trustworthy enough to show.
    public static let minN: Int = 14
    /// Two-sided significance cutoff.
    public static let alpha: Double = 0.05
    /// Minimum |r| worth mentioning even when significant (a real, not hair-thin, effect).
    public static let minEffect: Double = 0.25
    /// Cap on how many links to surface.
    public static let maxFactors: Int = 3

    public enum Strength: String, Sendable, Equatable, Codable { case strong, clear, mild }
    public enum Direction: String, Sendable, Equatable, Codable { case positive, negative }

    public struct Factor: Equatable, Sendable, Codable {
        public let key: String
        public let r: Double
        public let n: Int
        public let direction: Direction
        public let strength: Strength

        public init(key: String, r: Double, n: Int, direction: Direction, strength: Strength) {
            self.key = key
            self.r = r
            self.n = n
            self.direction = direction
            self.strength = strength
        }
    }

    public struct Report: Equatable, Sendable, Codable {
        public let factors: [Factor]
        public var hasEnough: Bool { !factors.isEmpty }
        public init(factors: [Factor]) { self.factors = factors }
    }

    public static func strength(_ absR: Double) -> Strength {
        if absR >= 0.5 { return .strong }
        if absR >= 0.35 { return .clear }
        return .mild
    }

    /// Correlate `target` against each named factor series (all day-keyed), keeping only the significant,
    /// meaningful links, ranked by |r| descending and capped.
    public static func analyze(target: [(day: String, value: Double)],
                               factors: [(key: String, series: [(day: String, value: Double)])],
                               minN: Int = minN, alpha: Double = alpha,
                               minEffect: Double = minEffect, maxFactors: Int = maxFactors) -> Report {
        var out: [Factor] = []
        for f in factors {
            let pairs = CorrelationEngine.alignByDay(target, f.series)
            guard let c = CorrelationEngine.pearson(pairs),
                  c.n >= minN, c.pApprox <= alpha, abs(c.r) >= minEffect else { continue }
            out.append(Factor(key: f.key, r: c.r, n: c.n,
                              direction: c.r >= 0 ? .positive : .negative,
                              strength: strength(abs(c.r))))
        }
        out.sort { abs($0.r) > abs($1.r) }
        return Report(factors: Array(out.prefix(Swift.max(0, maxFactors))))
    }
}
