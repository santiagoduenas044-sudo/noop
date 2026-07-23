import Foundation

// TomorrowOutlook.swift — a hedged, CONDITIONAL forecast for tomorrow morning.
//
// A companion doesn't just say "tomorrow will be 74"; it tells you what you can DO about it. This engine
// runs the existing RecoveryForecaster TWICE — once assuming you get your usual night's sleep, once
// assuming a short night — so the outlook can honestly express the swing YOUR choice tonight creates
// ("keep your usual sleep and you're likely to hold ~75; a short night could pull it toward ~62").
// Direction (rebound / steady / dip) is relative to today, and everything is gated on the same
// confidence ladder as the forecast, so the copy hedges when the read is thin.
//
// PURELY additive, pure, DB-free, framework-free. The app owns the conditional wording. The forecast is
// APPROXIMATE and never a promise — the wording stays conditional by contract. iPhone-first; no Kotlin
// twin (the underlying RecoveryForecaster already has one).

public enum TomorrowOutlook {

    /// Where tomorrow morning is likely to sit relative to today.
    public enum Direction: String, Sendable, Equatable, Codable {
        case rebound   // meaningfully higher than today
        case steady    // about the same
        case dip       // meaningfully lower than today
        case unknown   // no "today" to compare against
    }

    /// A charge swing (points) at/above this is worth telling the user their sleep tonight matters.
    public static let meaningfulSwing: Int = 4
    /// The gap (points) from today that counts as a rebound / dip rather than steady.
    public static let directionMargin: Double = 5
    /// How many hours short of the personal need the "short night" scenario assumes.
    public static let shortNightHours: Double = 2.0

    public struct Outlook: Equatable, Sendable, Codable {
        public let hasForecast: Bool
        public let direction: Direction
        /// The "usual night's sleep" projection and its uncertainty band (rounded, 0…100).
        public let expected: Int
        public let expectedLow: Int
        public let expectedHigh: Int
        /// The "short night" projection — the cost of under-sleeping tonight (nil if not computable).
        public let ifShort: Int?
        /// expected − ifShort: how much tonight's sleep swings tomorrow. 0 when `ifShort` is nil.
        public let sleepSwing: Int
        public let confidence: ScoreConfidence

        /// The swing is large enough to be worth acting on.
        public var sleepMatters: Bool { sleepSwing >= TomorrowOutlook.meaningfulSwing }

        public init(hasForecast: Bool, direction: Direction, expected: Int, expectedLow: Int,
                    expectedHigh: Int, ifShort: Int?, sleepSwing: Int, confidence: ScoreConfidence) {
            self.hasForecast = hasForecast
            self.direction = direction
            self.expected = expected
            self.expectedLow = expectedLow
            self.expectedHigh = expectedHigh
            self.ifShort = ifShort
            self.sleepSwing = sleepSwing
            self.confidence = confidence
        }

        /// The withheld outlook (not enough history to forecast honestly).
        public static let none = Outlook(hasForecast: false, direction: .unknown, expected: 0,
                                         expectedLow: 0, expectedHigh: 0, ifShort: nil, sleepSwing: 0,
                                         confidence: .calibrating)
    }

    /// Build tomorrow's outlook from the same inputs the forecaster uses. `todayCharge` sets the
    /// direction; `needHours` is the personal sleep need the "usual night" scenario assumes.
    public static func build(recentCharge: [Double],
                             recentEffort: [Double] = [],
                             todayEffort: Double?,
                             todayCharge: Double?,
                             needHours: Double? = nil,
                             needNights: Int = 0,
                             shortfallHours: Double = shortNightHours) -> Outlook {
        let need = Swift.max(needHours ?? RecoveryForecaster.defaultNeedHours, 0.1)

        guard let good = RecoveryForecaster.forecast(recentCharge: recentCharge,
                                                     recentEffort: recentEffort, todayEffort: todayEffort,
                                                     plannedSleepHours: need, needHours: need,
                                                     needNights: needNights) else {
            return .none
        }
        let short = RecoveryForecaster.forecast(recentCharge: recentCharge, recentEffort: recentEffort,
                                                todayEffort: todayEffort,
                                                plannedSleepHours: Swift.max(need - shortfallHours, 0),
                                                needHours: need, needNights: needNights)

        let direction: Direction = {
            guard let today = todayCharge else { return .unknown }
            if good.charge >= today + directionMargin { return .rebound }
            if good.charge <= today - directionMargin { return .dip }
            return .steady
        }()

        let ifShort = short.map { Int($0.charge.rounded()) }
        let swing = ifShort.map { Swift.max(0, Int(good.charge.rounded()) - $0) } ?? 0

        return Outlook(hasForecast: true, direction: direction,
                       expected: Int(good.charge.rounded()),
                       expectedLow: Int(good.low.rounded()), expectedHigh: Int(good.high.rounded()),
                       ifShort: ifShort, sleepSwing: swing, confidence: good.confidence)
    }
}
