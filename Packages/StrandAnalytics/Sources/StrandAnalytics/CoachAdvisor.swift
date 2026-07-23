import Foundation

// CoachAdvisor.swift — the decision core of NOOP's ON-DEVICE coach.
//
// NOOP already ships an optional, bring-your-own-key cloud chat. This is the opposite: an instant,
// private, network-free adviser that answers the everyday questions ("should I train today?") from the
// user's own scores — deterministic and honest, never a medical claim. This engine owns only the
// DECISION (the verdict); the app composes the words and the other answers reuse the existing engines
// (Charge drivers, correlations, weekly review). Pure, tested, framework-free. iPhone-first.

public enum CoachAdvisor {

    /// The training call for today.
    public enum Verdict: String, Sendable, Equatable, Codable {
        case push       // ready for real stress
        case maintain   // a moderate, train-to-feel day
        case easeIn     // keep it light, let the body catch up
        case rest       // recovery is the play
        case unknown    // not enough to say
    }

    /// Today's training verdict from the readiness band, with one real coaching nuance: even when the
    /// body reads primed, if tomorrow's outlook is a dip we counsel MAINTAIN rather than push — don't
    /// dig a hole right before a downswing.
    public static func trainingVerdict(band: ReadinessEngine.Level?,
                                       tomorrow: TomorrowOutlook.Direction?) -> Verdict {
        guard let band else { return .unknown }
        switch band {
        case .primed:       return tomorrow == .dip ? .maintain : .push
        case .balanced:     return .maintain
        case .strained:     return .easeIn
        case .rundown:      return .rest
        case .insufficient: return .unknown
        }
    }
}
