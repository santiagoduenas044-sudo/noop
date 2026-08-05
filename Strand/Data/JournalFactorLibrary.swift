import Foundation

/// One entry in the searchable factor library — a SUGGESTION the user can add to their own journal
/// catalog (`JournalCatalogStore.addFromLibrary`), not something logged directly. This file is pure
/// data, deliberately kept out of any SwiftUI view: the "Add factor" screen renders whatever this
/// array contains rather than hardcoding questions into the view layer, so growing the library is a
/// data change, never a UI change.
struct JournalFactorTemplate: Identifiable {
    /// The exact string that becomes the item's `canonical` key once added — same stability rule as
    /// every other journal key: the effects engine and history join on this verbatim.
    let canonical: String
    let kind: JournalKind
    let group: JournalGroup
    /// One short line shown in the library browser explaining why this might be worth tracking.
    /// Deliberately not diagnostic — states what the factor is, not what it means for the user.
    let blurb: String

    var id: String { canonical }
}

/// The factor library: everything `PremiumJournalView`'s "Add factor" search can offer, organised by
/// the same `JournalGroup` categories the daily log renders in.
///
/// Deliberately does NOT duplicate anything already in `JournalCatalogStore.starterQuestions` —
/// screen-in-bed, shared bed, read-before-bed, sauna, late caffeine, late meal (eat close to
/// bedtime) and "felt stressed" (yes/no) are already starters; this library complements them with
/// factors starters don't cover, plus richer response types (scale/quantity/time/duration) for
/// concepts a plain yes/no can't capture (e.g. a stress SCALE alongside the starter's stress
/// yes/no — different questions, kept distinct rather than merged, since collapsing them would
/// discard whichever history was already logged under the other shape).
///
/// Mood is deliberately absent: it already has a dedicated first-class feature (`MoodStore`, the
/// 1–5 face picker on the Journal header) — duplicating it here as a journal factor would split one
/// concept across two storage paths for no benefit.
enum JournalFactorLibrary {
    static let all: [JournalFactorTemplate] = sleepHabits + nutrition + caffeine + supplements
        + activity + recovery + lifestyle + environment + subjective

    static let sleepHabits: [JournalFactorTemplate] = [
        .init(canonical: "Went to bed later than usual", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "A later-than-usual bedtime, tracked separately from your actual recorded bedtime drift.")),
        .init(canonical: "Alarm woke you before you were ready", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "Waking to an alarm mid-cycle can leave you feeling groggier than the same total sleep uninterrupted.")),
        .init(canonical: "Wore a sleep mask", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "Blocking light is one of the more common sleep-hygiene changes people try.")),
        .init(canonical: "Wore earplugs", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "Blocking noise, tracked separately from a noisy room itself.")),
        .init(canonical: "Nap length", kind: .duration(unitLabel: String(localized: "min")), group: .sleepHabits,
              blurb: String(localized: "Daytime naps can shift how much pressure builds for the following night's sleep.")),
    ]

    static let nutrition: [JournalFactorTemplate] = [
        .init(canonical: "Ate a heavy meal", kind: .bool, group: .nutrition,
              blurb: String(localized: "A larger-than-usual meal, independent of timing.")),
        .init(canonical: "Had a high-sugar meal or snack", kind: .bool, group: .nutrition,
              blurb: String(localized: "Tracks high-sugar intake separately from meal size or timing.")),
        .init(canonical: "Had a high-protein meal", kind: .bool, group: .nutrition,
              blurb: String(localized: "Some people track protein intake against recovery or sleep.")),
        .init(canonical: "Stayed well hydrated", kind: .bool, group: .nutrition,
              blurb: String(localized: "A self-reported hydration check-in, since NOOP has no way to measure hydration directly.")),
        .init(canonical: "Fasted for part of the day", kind: .bool, group: .nutrition,
              blurb: String(localized: "Any intentional fasting window, regardless of length or protocol.")),
        .init(canonical: "Ate at a restaurant", kind: .bool, group: .nutrition,
              blurb: String(localized: "Restaurant meals often differ from home cooking in sodium, portion size and timing.")),
    ]

    static let caffeine: [JournalFactorTemplate] = [
        .init(canonical: "Had coffee", kind: .bool, group: .caffeine,
              blurb: String(localized: "Coffee specifically, separate from other caffeine sources.")),
        .init(canonical: "Had tea", kind: .bool, group: .caffeine,
              blurb: String(localized: "Tea specifically, separate from other caffeine sources.")),
        .init(canonical: "Had an energy drink", kind: .bool, group: .caffeine,
              blurb: String(localized: "Energy drinks often carry more caffeine, and other stimulants, than coffee or tea.")),
        .init(canonical: "Caffeine intake", kind: .quantity(unitLabel: String(localized: "mg")), group: .caffeine,
              blurb: String(localized: "A rough total in milligrams, if you want more detail than a yes/no gives you.")),
        .init(canonical: "Last caffeine", kind: .time, group: .caffeine,
              blurb: String(localized: "The time of your last caffeine, distinct from the starter's yes/no 'late in the day' question.")),
    ]

    /// Deliberately short and generic — supplements are the one category the brief explicitly asks
    /// to be user-configurable rather than assumed. These are common starting suggestions; anyone
    /// can add their own via "Create a custom factor", which uses the exact same storage.
    static let supplements: [JournalFactorTemplate] = [
        .init(canonical: "Took melatonin", kind: .bool, group: .supplements,
              blurb: String(localized: "One of the most commonly tracked sleep supplements.")),
        .init(canonical: "Took vitamin D", kind: .bool, group: .supplements,
              blurb: String(localized: "Commonly taken; some people track it against mood or energy.")),
        .init(canonical: "Took zinc", kind: .bool, group: .supplements,
              blurb: String(localized: "Often paired with magnesium in a bedtime stack.")),
        .init(canonical: "Took ashwagandha", kind: .bool, group: .supplements,
              blurb: String(localized: "A commonly tracked adaptogen supplement.")),
        .init(canonical: "Took creatine", kind: .bool, group: .supplements,
              blurb: String(localized: "Usually tracked against training and recovery rather than sleep.")),
    ]

    static let activity: [JournalFactorTemplate] = [
        .init(canonical: "Did strength training", kind: .bool, group: .activity,
              blurb: String(localized: "Resistance training specifically, separate from cardio or a WHOOP-logged workout.")),
        .init(canonical: "Did cardio", kind: .bool, group: .activity,
              blurb: String(localized: "Aerobic exercise specifically, separate from strength training.")),
        .init(canonical: "Went for a walk", kind: .bool, group: .activity,
              blurb: String(localized: "Lower-intensity movement that a strap's strain score may barely register.")),
        .init(canonical: "Stretched", kind: .bool, group: .activity,
              blurb: String(localized: "Flexibility work, tracked separately from a structured workout.")),
        .init(canonical: "Had an unusually hard workout", kind: .bool, group: .activity,
              blurb: String(localized: "A session that felt harder than your normal training.")),
        .init(canonical: "Took a rest day", kind: .bool, group: .activity,
              blurb: String(localized: "A deliberate day off training.")),
    ]

    static let recovery: [JournalFactorTemplate] = [
        .init(canonical: "Had cold exposure", kind: .bool, group: .recovery,
              blurb: String(localized: "Cold plunge, ice bath or a cold shower used deliberately for recovery.")),
        .init(canonical: "Got a massage", kind: .bool, group: .recovery,
              blurb: String(localized: "Manual or device-assisted (e.g. massage gun) recovery work.")),
        .init(canonical: "Meditated", kind: .bool, group: .recovery,
              blurb: String(localized: "Any seated meditation or breathwork practice.")),
    ]

    static let lifestyle: [JournalFactorTemplate] = [
        .init(canonical: "Traveled", kind: .bool, group: .lifestyle,
              blurb: String(localized: "Any travel day, regardless of distance — see Environment for a different bed or time zone specifically.")),
        .init(canonical: "Had an unusual schedule", kind: .bool, group: .lifestyle,
              blurb: String(localized: "A day that broke from your normal routine, for any reason.")),
        .init(canonical: "Had long screen time", kind: .bool, group: .lifestyle,
              blurb: String(localized: "Extended screen use during the day, separate from the starter's evening-specific screen question.")),
        .init(canonical: "Spent time outdoors", kind: .bool, group: .lifestyle,
              blurb: String(localized: "Daylight and outdoor time are commonly tracked against sleep timing.")),
        .init(canonical: "Attended a social event", kind: .bool, group: .lifestyle,
              blurb: String(localized: "Social occasions often come with later nights or different eating/drinking patterns.")),
    ]

    static let environment: [JournalFactorTemplate] = [
        .init(canonical: "Room felt too warm", kind: .bool, group: .environment,
              blurb: String(localized: "Self-reported room temperature, since NOOP has no ambient-temperature sensor.")),
        .init(canonical: "Room felt too cold", kind: .bool, group: .environment,
              blurb: String(localized: "Self-reported room temperature, since NOOP has no ambient-temperature sensor.")),
        .init(canonical: "Noise disrupted sleep", kind: .bool, group: .environment,
              blurb: String(localized: "Traffic, a partner, pets, or anything else audibly disruptive.")),
        .init(canonical: "Slept in a different bed", kind: .bool, group: .environment,
              blurb: String(localized: "A hotel, a guest room, or anywhere other than your usual bed.")),
        .init(canonical: "Slept at a notably different altitude", kind: .bool, group: .environment,
              blurb: String(localized: "Self-reported, since NOOP has no altitude sensor — only log this where you genuinely know it changed.")),
    ]

    /// Scales default to 1–5 to match the app's existing mood scale, so the same mental model
    /// ("1 low, 5 high") applies everywhere in Journal.
    static let subjective: [JournalFactorTemplate] = [
        .init(canonical: "Energy level", kind: .scale(range: 1...5), group: .subjective,
              blurb: String(localized: "Your own sense of energy for the day, on a 1–5 scale.")),
        .init(canonical: "Stress level", kind: .scale(range: 1...5), group: .subjective,
              blurb: String(localized: "How stressed you felt, on a 1–5 scale — a finer-grained companion to the starter's yes/no stress question.")),
        .init(canonical: "Soreness", kind: .scale(range: 1...5), group: .subjective,
              blurb: String(localized: "Muscle soreness, on a 1–5 scale.")),
        .init(canonical: "Fatigue", kind: .scale(range: 1...5), group: .subjective,
              blurb: String(localized: "How fatigued you felt independent of how much you slept, on a 1–5 scale.")),
        .init(canonical: "Sleep quality (how it felt)", kind: .scale(range: 1...5), group: .subjective,
              blurb: String(localized: "Your own sense of how well you slept, on a 1–5 scale — distinct from NOOP's computed sleep score, which is measured, not felt.")),
    ]
}
