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
/// discard whichever history was already logged under the other shape). Every entry's `canonical`
/// is checked for exact duplicates against every other entry and against the starters by
/// `JournalFactorLibraryTests` — see that file before adding more.
///
/// Mood is deliberately absent: it already has a dedicated first-class feature (`MoodStore`, the
/// 1–5 face picker on the Journal header) — duplicating it here as a journal factor would split one
/// concept across two storage paths for no benefit.
enum JournalFactorLibrary {
    static let all: [JournalFactorTemplate] = sleepHabits + nutrition + caffeine + supplements
        + activity + recovery + lifestyle + environment + subjective + work + social

    static let sleepHabits: [JournalFactorTemplate] = [
        .init(canonical: "Went to bed later than usual", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "A later-than-usual bedtime, tracked separately from your actual recorded bedtime drift.")),
        .init(canonical: "Went to bed earlier than usual", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "An earlier-than-usual bedtime, tracked separately from your actual recorded bedtime drift.")),
        .init(canonical: "Alarm woke you before you were ready", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "Waking to an alarm mid-cycle can leave you feeling groggier than the same total sleep uninterrupted.")),
        .init(canonical: "Woke up without an alarm", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "Waking naturally, before or without an alarm.")),
        .init(canonical: "Took longer than usual to fall asleep", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "A self-reported sense of sleep-onset difficulty, alongside whatever NOOP can measure.")),
        .init(canonical: "Fell asleep quickly", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "The opposite of the above — fell asleep unusually fast.")),
        .init(canonical: "Woke up during the night", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "A self-reported awakening, alongside NOOP's own decoded WASO/awakening count.")),
        .init(canonical: "Wore a sleep mask", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "Blocking light is one of the more common sleep-hygiene changes people try.")),
        .init(canonical: "Wore earplugs", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "Blocking noise, tracked separately from a noisy room itself.")),
        .init(canonical: "Used a white noise machine", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "Background noise used deliberately to mask disruptions.")),
        .init(canonical: "Used a weighted blanket", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "A commonly tried sleep-hygiene change.")),
        .init(canonical: "Changed sleep position", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "Slept in a notably different position than usual.")),
        .init(canonical: "Watched TV or a screen to fall asleep", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "Distinct from the starter's general 'screen in bed' question — specifically using one to fall asleep.")),
        .init(canonical: "Listened to a podcast or audiobook to fall asleep", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "A common wind-down habit, separate from screen use.")),
        .init(canonical: "Co-slept with a child", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "Distinct from the starter's general 'shared your bed' question.")),
        .init(canonical: "Pet slept in the bed", kind: .bool, group: .sleepHabits,
              blurb: String(localized: "Distinct from the starter's general 'shared your bed' question.")),
        .init(canonical: "Nap length", kind: .duration(unitLabel: String(localized: "min")), group: .sleepHabits,
              blurb: String(localized: "Daytime naps can shift how much pressure builds for the following night's sleep.")),
        .init(canonical: "Number of naps", kind: .quantity(unitLabel: String(localized: "naps")), group: .sleepHabits,
              blurb: String(localized: "How many separate naps, if more than one.")),
    ]

    static let nutrition: [JournalFactorTemplate] = [
        .init(canonical: "Ate a heavy meal", kind: .bool, group: .nutrition,
              blurb: String(localized: "A larger-than-usual meal, independent of timing.")),
        .init(canonical: "Had a high-sugar meal or snack", kind: .bool, group: .nutrition,
              blurb: String(localized: "Tracks high-sugar intake separately from meal size or timing.")),
        .init(canonical: "Had a high-protein meal", kind: .bool, group: .nutrition,
              blurb: String(localized: "Some people track protein intake against recovery or sleep.")),
        .init(canonical: "Had a high-carb meal", kind: .bool, group: .nutrition,
              blurb: String(localized: "Tracks high-carbohydrate intake separately from sugar specifically.")),
        .init(canonical: "Ate spicy food", kind: .bool, group: .nutrition,
              blurb: String(localized: "Some people find spicy food affects sleep or resting heart rate.")),
        .init(canonical: "Had dairy in the evening", kind: .bool, group: .nutrition,
              blurb: String(localized: "A commonly suspected sleep-quality factor for some people.")),
        .init(canonical: "Stayed well hydrated", kind: .bool, group: .nutrition,
              blurb: String(localized: "A self-reported hydration check-in, since NOOP has no way to measure hydration directly.")),
        .init(canonical: "Drank very little water", kind: .bool, group: .nutrition,
              blurb: String(localized: "The opposite of the above, tracked separately rather than as a single two-way scale.")),
        .init(canonical: "Fasted for part of the day", kind: .bool, group: .nutrition,
              blurb: String(localized: "Any intentional fasting window, regardless of length or protocol.")),
        .init(canonical: "Skipped a meal", kind: .bool, group: .nutrition,
              blurb: String(localized: "Unintentionally missing a meal, distinct from a deliberate fast.")),
        .init(canonical: "Had a late-night snack", kind: .bool, group: .nutrition,
              blurb: String(localized: "Distinct from the starter's 'ate close to bedtime' question — specifically a snack, not a meal.")),
        .init(canonical: "Ate at a restaurant", kind: .bool, group: .nutrition,
              blurb: String(localized: "Restaurant meals often differ from home cooking in sodium, portion size and timing.")),
        .init(canonical: "Had dessert", kind: .bool, group: .nutrition,
              blurb: String(localized: "Tracked separately from general high-sugar intake, if you want the distinction.")),
        .init(canonical: "Number of alcoholic drinks", kind: .quantity(unitLabel: String(localized: "drinks")), group: .nutrition,
              blurb: String(localized: "A count alongside the starter's yes/no alcohol question, for anyone who wants the detail.")),
        .init(canonical: "Last meal", kind: .time, group: .nutrition,
              blurb: String(localized: "The time of your last meal, distinct from the starter's yes/no 'ate close to bedtime' question.")),
    ]

    static let caffeine: [JournalFactorTemplate] = [
        .init(canonical: "Had coffee", kind: .bool, group: .caffeine,
              blurb: String(localized: "Coffee specifically, separate from other caffeine sources.")),
        .init(canonical: "Had tea", kind: .bool, group: .caffeine,
              blurb: String(localized: "Tea specifically, separate from other caffeine sources.")),
        .init(canonical: "Had an energy drink", kind: .bool, group: .caffeine,
              blurb: String(localized: "Energy drinks often carry more caffeine, and other stimulants, than coffee or tea.")),
        .init(canonical: "Had decaf", kind: .bool, group: .caffeine,
              blurb: String(localized: "Useful if you want to distinguish decaf days from real caffeine days.")),
        .init(canonical: "Had a pre-workout supplement", kind: .bool, group: .caffeine,
              blurb: String(localized: "Pre-workout products are often a concentrated, easy-to-forget caffeine source.")),
        .init(canonical: "Had caffeine after 2pm", kind: .bool, group: .caffeine,
              blurb: String(localized: "A fixed-cutoff framing, distinct from the starter's general 'late in the day' question.")),
        .init(canonical: "Number of caffeinated drinks", kind: .quantity(unitLabel: String(localized: "drinks")), group: .caffeine,
              blurb: String(localized: "A simple count, if milligrams feels like more precision than you want to track.")),
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
        .init(canonical: "Took a multivitamin", kind: .bool, group: .supplements,
              blurb: String(localized: "A common daily baseline supplement.")),
        .init(canonical: "Took fish oil / omega-3", kind: .bool, group: .supplements,
              blurb: String(localized: "Commonly tracked against general recovery.")),
        .init(canonical: "Took probiotics", kind: .bool, group: .supplements,
              blurb: String(localized: "Commonly tracked against digestion and general wellbeing.")),
        .init(canonical: "Took zinc", kind: .bool, group: .supplements,
              blurb: String(localized: "Often paired with magnesium in a bedtime stack.")),
        .init(canonical: "Took L-theanine", kind: .bool, group: .supplements,
              blurb: String(localized: "Often taken alongside caffeine or before bed.")),
        .init(canonical: "Took glycine", kind: .bool, group: .supplements,
              blurb: String(localized: "A commonly tracked sleep-onset supplement.")),
        .init(canonical: "Took ashwagandha", kind: .bool, group: .supplements,
              blurb: String(localized: "A commonly tracked adaptogen supplement.")),
        .init(canonical: "Took creatine", kind: .bool, group: .supplements,
              blurb: String(localized: "Usually tracked against training and recovery rather than sleep.")),
        .init(canonical: "Took a protein shake", kind: .bool, group: .supplements,
              blurb: String(localized: "Often tracked alongside training days.")),
        .init(canonical: "Took electrolytes", kind: .bool, group: .supplements,
              blurb: String(localized: "Commonly tracked on hot days or after hard training.")),
        .init(canonical: "Took CBD", kind: .bool, group: .supplements,
              blurb: String(localized: "Commonly tracked against sleep or stress.")),
    ]

    static let activity: [JournalFactorTemplate] = [
        .init(canonical: "Did strength training", kind: .bool, group: .activity,
              blurb: String(localized: "Resistance training specifically, separate from cardio or a WHOOP-logged workout.")),
        .init(canonical: "Did cardio", kind: .bool, group: .activity,
              blurb: String(localized: "Aerobic exercise specifically, separate from strength training.")),
        .init(canonical: "Did HIIT", kind: .bool, group: .activity,
              blurb: String(localized: "High-intensity interval training, tracked separately from steady cardio.")),
        .init(canonical: "Did yoga", kind: .bool, group: .activity,
              blurb: String(localized: "Tracked separately from general stretching or a structured workout.")),
        .init(canonical: "Went for a walk", kind: .bool, group: .activity,
              blurb: String(localized: "Lower-intensity movement that a strap's strain score may barely register.")),
        .init(canonical: "Cycled", kind: .bool, group: .activity,
              blurb: String(localized: "Tracked separately if you want it distinct from general cardio.")),
        .init(canonical: "Swam", kind: .bool, group: .activity,
              blurb: String(localized: "Tracked separately if you want it distinct from general cardio.")),
        .init(canonical: "Played a sport", kind: .bool, group: .activity,
              blurb: String(localized: "Team or individual sport play, distinct from structured training.")),
        .init(canonical: "Stretched", kind: .bool, group: .activity,
              blurb: String(localized: "Flexibility work, tracked separately from a structured workout.")),
        .init(canonical: "Trained fasted", kind: .bool, group: .activity,
              blurb: String(localized: "Training before eating, if that's something you vary.")),
        .init(canonical: "Trained in the morning", kind: .bool, group: .activity,
              blurb: String(localized: "Training timing, tracked separately from whether you trained at all.")),
        .init(canonical: "Trained late in the day", kind: .bool, group: .activity,
              blurb: String(localized: "Training timing, tracked separately from whether you trained at all.")),
        .init(canonical: "Had an unusually hard workout", kind: .bool, group: .activity,
              blurb: String(localized: "A session that felt harder than your normal training.")),
        .init(canonical: "Took a rest day", kind: .bool, group: .activity,
              blurb: String(localized: "A deliberate day off training.")),
        .init(canonical: "Workout duration", kind: .duration(unitLabel: String(localized: "min")), group: .activity,
              blurb: String(localized: "Total training time, if you want more detail than a strain score alone gives you.")),
    ]

    static let recovery: [JournalFactorTemplate] = [
        .init(canonical: "Had cold exposure", kind: .bool, group: .recovery,
              blurb: String(localized: "Cold plunge, ice bath or a cold shower used deliberately for recovery.")),
        .init(canonical: "Used a sauna blanket or infrared sauna", kind: .bool, group: .recovery,
              blurb: String(localized: "Distinct from the starter's general sauna question if you use a different modality.")),
        .init(canonical: "Got a massage", kind: .bool, group: .recovery,
              blurb: String(localized: "Manual recovery work.")),
        .init(canonical: "Used a percussion massager", kind: .bool, group: .recovery,
              blurb: String(localized: "Device-assisted recovery work, tracked separately from manual massage.")),
        .init(canonical: "Used a foam roller", kind: .bool, group: .recovery,
              blurb: String(localized: "A common self-administered recovery tool.")),
        .init(canonical: "Used compression gear", kind: .bool, group: .recovery,
              blurb: String(localized: "Compression sleeves or boots, commonly used post-training.")),
        .init(canonical: "Meditated", kind: .bool, group: .recovery,
              blurb: String(localized: "Any seated meditation practice.")),
        .init(canonical: "Did breathwork", kind: .bool, group: .recovery,
              blurb: String(localized: "Structured breathing exercises, tracked separately from meditation.")),
        .init(canonical: "Took an Epsom salt bath", kind: .bool, group: .recovery,
              blurb: String(localized: "A commonly tried recovery habit.")),
        .init(canonical: "Did a contrast shower", kind: .bool, group: .recovery,
              blurb: String(localized: "Alternating hot and cold water, distinct from a plain cold exposure.")),
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
        .init(canonical: "Got morning sunlight", kind: .bool, group: .lifestyle,
              blurb: String(localized: "Morning light exposure specifically, tracked separately from general outdoor time.")),
    ]

    static let environment: [JournalFactorTemplate] = [
        .init(canonical: "Room felt too warm", kind: .bool, group: .environment,
              blurb: String(localized: "Self-reported room temperature, since NOOP has no ambient-temperature sensor.")),
        .init(canonical: "Room felt too cold", kind: .bool, group: .environment,
              blurb: String(localized: "Self-reported room temperature, since NOOP has no ambient-temperature sensor.")),
        .init(canonical: "Used air conditioning", kind: .bool, group: .environment,
              blurb: String(localized: "Tracked separately from how the room actually felt.")),
        .init(canonical: "Slept with a window open", kind: .bool, group: .environment,
              blurb: String(localized: "Airflow and outside noise/temperature can both change with this.")),
        .init(canonical: "Noise disrupted sleep", kind: .bool, group: .environment,
              blurb: String(localized: "Traffic, a partner, pets, or anything else audibly disruptive.")),
        .init(canonical: "Slept in a different bed", kind: .bool, group: .environment,
              blurb: String(localized: "A hotel, a guest room, or anywhere other than your usual bed.")),
        .init(canonical: "High pollen or allergy day", kind: .bool, group: .environment,
              blurb: String(localized: "Self-reported, since NOOP has no environmental sensor of its own.")),
        .init(canonical: "Daylight saving / clock change", kind: .bool, group: .environment,
              blurb: String(localized: "The day of (or right after) a clock change, which can shift sleep timing for a night or two.")),
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
        .init(canonical: "Motivation", kind: .scale(range: 1...5), group: .subjective,
              blurb: String(localized: "Your own sense of motivation for the day, on a 1–5 scale.")),
        .init(canonical: "Focus", kind: .scale(range: 1...5), group: .subjective,
              blurb: String(localized: "Your own sense of mental focus, on a 1–5 scale.")),
        .init(canonical: "Appetite", kind: .scale(range: 1...5), group: .subjective,
              blurb: String(localized: "Your own sense of appetite for the day, on a 1–5 scale.")),
        .init(canonical: "Overall day rating", kind: .scale(range: 1...5), group: .subjective,
              blurb: String(localized: "A single overall rating for the day, on a 1–5 scale.")),
    ]

    /// New category beyond the brief's original list (explicitly allowed: "Allow additional
    /// sensible categories/factors"). Work stress is one of the most commonly cited sleep
    /// disruptors and didn't fit cleanly under Lifestyle's more general framing.
    static let work: [JournalFactorTemplate] = [
        .init(canonical: "Had a stressful day at work", kind: .bool, group: .lifestyle,
              blurb: String(localized: "Work-specific stress, distinct from the starter's general 'felt stressed' question.")),
        .init(canonical: "Worked late", kind: .bool, group: .lifestyle,
              blurb: String(localized: "Working past your normal end time.")),
        .init(canonical: "Took a day off work", kind: .bool, group: .lifestyle,
              blurb: String(localized: "A day away from work, for any reason.")),
        .init(canonical: "Had a big deadline or presentation", kind: .bool, group: .lifestyle,
              blurb: String(localized: "A specific, often-anticipated source of work stress.")),
        .init(canonical: "Commuted longer than usual", kind: .bool, group: .lifestyle,
              blurb: String(localized: "An unusually long commute, which can eat into sleep or recovery time.")),
    ]

    /// New category beyond the brief's original list. Social and emotional context is a common
    /// omission from purely physiological tracking, and both are self-report by nature — exactly
    /// what Journal is for.
    static let social: [JournalFactorTemplate] = [
        .init(canonical: "Attended a social event", kind: .bool, group: .lifestyle,
              blurb: String(localized: "Social occasions often come with later nights or different eating/drinking patterns.")),
        .init(canonical: "Spent quality time with family or friends", kind: .bool, group: .lifestyle,
              blurb: String(localized: "Positive social time, tracked distinctly from a general social event.")),
        .init(canonical: "Had an argument or conflict", kind: .bool, group: .lifestyle,
              blurb: String(localized: "A specific, often-cited source of emotional stress.")),
        .init(canonical: "Watched something emotionally intense", kind: .bool, group: .lifestyle,
              blurb: String(localized: "A stressful film, show or news event before bed, for anyone who suspects it affects their sleep.")),
        .init(canonical: "Felt anxious about the next day", kind: .bool, group: .lifestyle,
              blurb: String(localized: "Anticipatory anxiety about tomorrow, distinct from stress about today.")),
    ]
}
