import SwiftUI
import StrandDesign
import StrandAnalytics

// MorningBriefingView.swift — NOOP's natural-language "health story" at the top of Today.
//
// The narrative SHAPE (which sentences, in what order) comes from the pure MorningBriefingPlanner; this
// file owns the WORDS. Each planned line maps to a briefing-voice sentence; headline / support lines
// borrow the SAME specific subtitle the insight feed shows (a plain String), so the story never invents
// a number or diverges from the cards below it. Copy is warm, plain, and non-clinical by contract — it
// recommends, it never diagnoses.
//
// Design-system only. iPhone-first surface (compiles for the shared macOS app too).

/// Turns a planned briefing line into a briefing-voice sentence. Pure String composition so the whole
/// story can be assembled and (if needed) read aloud as one paragraph.
enum MorningBriefingCopy {

    static func sentence(_ line: MorningBriefing.Line, name: String,
                         cardsByKind: [String: TodayInsightCard], streakDays: Int?) -> String? {
        switch line.role {
        case .greeting: return greeting(line.kind, name: name)
        case .headline: return headline(line, cardsByKind: cardsByKind)
        case .support:  return support(line, cardsByKind: cardsByKind)
        case .action:   return action(line.kind)
        case .closer:   return closer(line.kind, streakDays: streakDays)
        }
    }

    private static func greeting(_ kind: String, name: String) -> String {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        switch kind {
        case "greeting.morning":
            return hasName ? String(format: String(localized: "Good morning, %@."), name)
                           : String(localized: "Good morning.")
        case "greeting.afternoon":
            return hasName ? String(format: String(localized: "Good afternoon, %@."), name)
                           : String(localized: "Good afternoon.")
        case "greeting.evening":
            return hasName ? String(format: String(localized: "Good evening, %@."), name)
                           : String(localized: "Good evening.")
        default:
            return hasName ? String(format: String(localized: "Hello, %@."), name)
                           : String(localized: "Hello.")
        }
    }

    private static func headline(_ line: MorningBriefing.Line,
                                 cardsByKind: [String: TodayInsightCard]) -> String {
        let opener: String
        switch line.kind {
        case "headline.attention.recovery":
            opener = String(localized: "Your recovery is the main thing to know today.")
        case "headline.attention.sleep":
            opener = String(localized: "Last night's sleep is what stands out this morning.")
        case "headline.attention.strain":
            opener = String(localized: "Yesterday's training load is today's story.")
        case "headline.optimization.recovery":
            opener = String(localized: "You're well recovered — a chance to make the most of today.")
        case "headline.optimization.trends":
            opener = String(localized: "Nothing needs your attention today, so let's look at the bigger picture.")
        default:
            opener = String(localized: "Here's what matters most today.")
        }
        // Borrow the feed's specific reason when this line speaks to an insight.
        if let k = line.insightKind, let sub = cardsByKind[k]?.subtitle, !sub.isEmpty {
            return opener + " " + sub
        }
        return opener
    }

    private static func support(_ line: MorningBriefing.Line,
                                cardsByKind: [String: TodayInsightCard]) -> String? {
        guard let k = line.insightKind, let sub = cardsByKind[k]?.subtitle, !sub.isEmpty else { return nil }
        return String(format: String(localized: "Also worth noting: %@"), sub)
    }

    private static func action(_ kind: String) -> String {
        switch kind {
        case "action.attention.recovery":
            return String(localized: "Keep today easy — light movement, hydration and an early night usually bring it back.")
        case "action.attention.sleep":
            return String(localized: "Aim for a consistent, slightly earlier bedtime tonight.")
        case "action.attention.strain":
            return String(localized: "Prioritise recovery today — protein, hydration, and an easy session at most.")
        case "action.optimization.recovery":
            return String(localized: "It's a good day to train harder if you've been meaning to.")
        case "action.optimization.trends":
            return String(localized: "A steady stretch like this is a great time to build on your habits.")
        default:
            return String(localized: "Small, steady choices today set up tomorrow.")
        }
    }

    private static func closer(_ kind: String, streakDays: Int?) -> String? {
        switch kind {
        case "closer.streak":
            guard let s = streakDays else { return nil }
            return String(format: String(localized: "And you're on a %ld-day streak — nicely done."), s)
        case "closer.optimization":
            return String(localized: "Keep doing what you're doing.")
        default: // closer.attention
            return String(localized: "Check back tonight and we'll see how it went.")
        }
    }

    /// A short part-of-day label for the eyebrow.
    static func eyebrow(for script: MorningBriefing.Script) -> LocalizedStringKey {
        switch script.lines.first?.kind {
        case "greeting.morning":   return "Morning briefing"
        case "greeting.afternoon": return "Afternoon briefing"
        case "greeting.evening":   return "Evening briefing"
        default:                   return "Your briefing"
        }
    }
}

/// The briefing card: an eyebrow, the greeting as a heading, the story as a flowing paragraph, and a
/// gentle closer. Reads like a few honest sentences from a companion, not a dashboard.
struct MorningBriefingView: View {
    let script: MorningBriefing.Script
    let name: String
    let cardsByKind: [String: TodayInsightCard]
    let streakDays: Int?

    private var greetingLine: String {
        script.lines.first { $0.role == .greeting }
            .flatMap { MorningBriefingCopy.sentence($0, name: name, cardsByKind: cardsByKind, streakDays: streakDays) }
            ?? ""
    }

    /// headline + support + action, joined into one paragraph.
    private var bodyParagraph: String {
        script.lines
            .filter { $0.role == .headline || $0.role == .support || $0.role == .action }
            .compactMap { MorningBriefingCopy.sentence($0, name: name, cardsByKind: cardsByKind, streakDays: streakDays) }
            .joined(separator: " ")
    }

    private var closerLine: String? {
        script.lines.first { $0.role == .closer }
            .flatMap { MorningBriefingCopy.sentence($0, name: name, cardsByKind: cardsByKind, streakDays: streakDays) }
    }

    var body: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.chargeColor)
                    Text(MorningBriefingCopy.eyebrow(for: script))
                        .font(StrandFont.caption.weight(.bold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer(minLength: 6)
                    Text("On-device")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                if !greetingLine.isEmpty {
                    Text(greetingLine)
                        .font(StrandFont.title2.weight(.bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(bodyParagraph)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let closer = closerLine {
                    Text(closer)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Morning briefing") {
    let cards: [String: TodayInsightCard] = [
        "recovery.strained": TodayInsightCard(id: "recovery.strained", symbol: "bolt.heart",
            title: "Recovery is running low",
            subtitle: "HRV 44 ms — below baseline, suppressing recovery",
            tint: StrandPalette.statusWarning, tone: .caution),
        "sleepStages.fragmented": TodayInsightCard(id: "sleepStages.fragmented", symbol: "wave.3.right",
            title: "A restless night", subtitle: "More time awake than usual — sleep was broken up.",
            tint: StrandPalette.restColor, tone: .caution),
    ]
    let script = MorningBriefing.Script(lines: [
        .init(role: .greeting, kind: "greeting.morning"),
        .init(role: .headline, kind: "headline.attention.recovery", insightKind: "recovery.strained"),
        .init(role: .support, kind: "support.caution", insightKind: "sleepStages.fragmented"),
        .init(role: .action, kind: "action.attention.recovery"),
        .init(role: .closer, kind: "closer.attention"),
    ])
    return ScrollView {
        MorningBriefingView(script: script, name: "Santiago", cardsByKind: cards, streakDays: nil)
            .padding()
    }
    .background(StrandPalette.surfaceBase)
}
#endif
