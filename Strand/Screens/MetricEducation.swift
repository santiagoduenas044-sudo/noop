import SwiftUI
import StrandDesign

// MetricEducation.swift — the per-metric educational content registry (iOS app layer).
//
// NOOP should teach, not just measure. Each metric gets a concise, non-clinical explainer surfaced
// through the shared `LearnMoreDisclosure` (collapsed by default, unobtrusive). Copy is deliberately
// short — a line or a few bullets per section, never a wall of text.
//
// HONESTY (non-negotiable): every "Typical range" says the numbers are GENERAL-POPULATION guidance,
// and the shared footnote reminds the reader that their own baseline and trend matter more. No metric
// here is presented as a diagnosis or a target to chase.

enum MetricEducation {

    enum Metric {
        case recovery, hrv, restingHR, sleepPerformance, respiratoryRate
    }

    /// The standing disclaimer appended to every explainer — general guidance, personal baseline, trend.
    static let footnote = "These are general-population ranges, not medical advice. What matters most is your own baseline and how it trends over time."

    /// Build the ready-to-drop-in disclosure for a metric.
    static func disclosure(for metric: Metric) -> LearnMoreDisclosure {
        let c = content(for: metric)
        return LearnMoreDisclosure(title: c.title, tint: c.tint, sections: c.sections, footnote: footnote)
    }

    // MARK: - Content

    private struct Content {
        let title: String
        let tint: Color
        let sections: [LearnMoreDisclosure.Section]
    }

    private static func content(for metric: Metric) -> Content {
        switch metric {
        case .recovery:
            return Content(title: "About Recovery", tint: StrandPalette.chargeColor, sections: [
                .init(systemImage: "questionmark.circle", heading: "What it measures",
                      body: "How ready your body is today. NOOP blends your overnight heart-rate variability, resting heart rate, sleep and recent strain into one 0–100 read."),
                .init(systemImage: "heart.text.square", heading: "Why it matters",
                      body: "A quick gut-check on whether to push or ease off — higher means your body is better prepared for stress today."),
                .init(systemImage: "chart.bar", heading: "Typical range",
                      body: "As a general guide: 0–33 low, 34–66 moderate, 67–100 high. Treat these as rough bands — your own baseline matters more than the number."),
                .init(systemImage: "arrow.triangle.branch", heading: "What influences it",
                      bullets: ["Sleep quality and duration", "Alcohol, caffeine and late meals", "Training load and daily stress", "Illness and travel"]),
                .init(systemImage: "arrow.up.forward", heading: "How to improve",
                      bullets: ["Keep a steady sleep schedule", "Recover after hard days", "Limit late alcohol and caffeine", "Manage daytime stress"]),
            ])

        case .hrv:
            return Content(title: "About HRV", tint: StrandPalette.metricCyan, sections: [
                .init(systemImage: "questionmark.circle", heading: "What it measures",
                      body: "The tiny beat-to-beat variation in your heart rhythm overnight, in milliseconds. More variation generally reflects a well-rested, adaptable nervous system."),
                .init(systemImage: "heart.text.square", heading: "Why it matters",
                      body: "One of the most responsive signals of stress and recovery — it tends to rise when you’re rested and dip when you’re run down."),
                .init(systemImage: "chart.bar", heading: "Typical range",
                      body: "HRV varies enormously between people (often ~20–150 ms) and declines with age, so there’s no universal ‘good’ number. Your trend against your own baseline is what counts."),
                .init(systemImage: "arrow.triangle.branch", heading: "What influences it",
                      bullets: ["Sleep and recovery", "Alcohol — often a large overnight drop", "Training load and stress", "Hydration and illness"]),
                .init(systemImage: "arrow.up.forward", heading: "How to improve",
                      bullets: ["Prioritise consistent sleep", "Go easy on alcohol", "Build aerobic fitness gradually", "Try slow breathing before bed"]),
            ])

        case .restingHR:
            return Content(title: "About Resting Heart Rate", tint: StrandPalette.metricRose, sections: [
                .init(systemImage: "questionmark.circle", heading: "What it measures",
                      body: "Your heart rate at deep rest overnight, in beats per minute. A lower resting rate generally reflects better cardiovascular fitness and recovery."),
                .init(systemImage: "heart.text.square", heading: "Why it matters",
                      body: "A simple, stable window on cardiovascular health and readiness. A rise above your usual often flags fatigue, stress or illness."),
                .init(systemImage: "chart.bar", heading: "Typical range",
                      body: "For most adults resting heart rate sits ~40–100 bpm, with fit people often in the 40s–50s. Age and genetics shift this, so compare to your own baseline."),
                .init(systemImage: "arrow.triangle.branch", heading: "What influences it",
                      bullets: ["Fitness level", "Sleep, stress and illness", "Alcohol, caffeine, dehydration", "Room temperature"]),
                .init(systemImage: "arrow.up.forward", heading: "How to improve",
                      bullets: ["Build aerobic fitness over time", "Sleep consistently", "Stay hydrated", "Limit alcohol and late caffeine"]),
            ])

        case .sleepPerformance:
            return Content(title: "About Sleep Performance", tint: StrandPalette.restColor, sections: [
                .init(systemImage: "questionmark.circle", heading: "What it measures",
                      body: "How well last night met your body’s needs — combining how long you slept, how efficiently, and your stage balance."),
                .init(systemImage: "heart.text.square", heading: "Why it matters",
                      body: "Sleep is the foundation of recovery. Consistent, efficient sleep supports nearly every other metric here."),
                .init(systemImage: "chart.bar", heading: "Typical range",
                      body: "Most adults need ~7–9 hours, with sleep efficiency above ~85% considered solid. Individual need varies — your own trend is the best guide."),
                .init(systemImage: "arrow.triangle.branch", heading: "What influences it",
                      bullets: ["A consistent bed and wake time", "Caffeine, alcohol and late meals", "Screens and light before bed", "Room temperature and noise"]),
                .init(systemImage: "arrow.up.forward", heading: "How to improve",
                      bullets: ["Keep bed and wake times steady", "Wind down and dim the lights", "Avoid late caffeine and alcohol", "Keep the room cool and dark"]),
            ])

        case .respiratoryRate:
            return Content(title: "About Respiratory Rate", tint: StrandPalette.metricPurple, sections: [
                .init(systemImage: "questionmark.circle", heading: "What it measures",
                      body: "Your breaths per minute during sleep. For a given person it’s usually very stable night to night."),
                .init(systemImage: "heart.text.square", heading: "Why it matters",
                      body: "Because it’s so steady, a clear rise above your baseline can be an early hint of illness, alcohol, or a hard day."),
                .init(systemImage: "chart.bar", heading: "Typical range",
                      body: "Adults typically breathe ~12–20 times per minute at rest. Your own overnight baseline is remarkably consistent — watch for deviations from it."),
                .init(systemImage: "arrow.triangle.branch", heading: "What influences it",
                      bullets: ["Illness or fever", "Alcohol", "Altitude", "Stress and late meals"]),
                .init(systemImage: "eye", heading: "What to watch",
                      bullets: ["It’s not a number to chase — aim for stability", "Note sustained rises from your baseline"]),
            ])
        }
    }
}
