#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

/// The WITH vs WITHOUT screen for one journal factor.
///
/// Answers, for a single logged behaviour: what were my numbers on days I logged it, what were they
/// on days I didn't, how big is the gap in both absolute and percentage terms, and how much data is
/// that built on. Every figure comes verbatim from `BehaviorInsights` via `PremiumJournalIntel` —
/// this view formats, it does not compute.
///
/// **Association language only, everywhere, structurally.** There is no code path here that can
/// produce a causal sentence: the headline states co-occurrence, the disclaimer is not optional, and
/// the methodology under ⓘ says plainly that a third factor can drive both sides.
struct PremiumFactorDetailView: View {
    let factorCanonical: String

    @EnvironmentObject var repo: Repository
    @StateObject private var catalog = JournalCatalogStore()

    @State private var intel = PremiumJournalIntel.empty
    @State private var loaded = false

    private var rows: [PremiumJournalIntel.Discovery] { intel.discoveries(for: factorCanonical) }
    private var display: String { rows.first?.factorDisplay ?? catalog.displayName(for: factorCanonical) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if !loaded {
                    PremiumLoadingState(label: String(localized: "Comparing your logged days…"))
                } else if rows.isEmpty {
                    StrandCard {
                        MetricUnavailable(
                            name: display,
                            reason: String(localized: "Not enough logged days yet to compare against your metrics. Keep logging this factor and a comparison will appear once there's enough history to stand behind."))
                    }
                } else {
                    header
                    ForEach(rows) { row in comparisonCard(row) }
                    disclaimer
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 96)
        }
        .background(PremiumAmbient(tints: [StrandPalette.gold]).ignoresSafeArea())
        .navigationTitle(display)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: repo.refreshSeq) {
            intel = await PremiumJournalIntel.load(repo: repo) { catalog.displayName(for: $0) }
            loaded = true
        }
    }

    private var header: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    PremiumIconTile(system: "square.and.pencil", tint: StrandPalette.gold, size: 30)
                    Text(display).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 0)
                }
                Text(String(format: String(localized: "Compared across %1$d of your tracked signals."), rows.count))
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    // MARK: One outcome's WITH vs WITHOUT

    private func comparisonCard(_ row: PremiumJournalIntel.Discovery) -> some View {
        let d = PremiumMetricCatalog.def(row.outcome)
        let tint: Color = row.isGood == nil
            ? StrandPalette.textSecondary
            : (row.isGood! ? StrandPalette.recoveryColor(85) : StrandPalette.metricRose)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                PremiumSectionHeader(title: d.shortName)
                Spacer()
                PremiumExplainer(title: String(format: String(localized: "%1$@ and %2$@"), display, d.shortName),
                                 items: explainerItems(row),
                                 methodology: methodology(row))
            }
            StrandCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text(sentence(row))
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 16) {
                        sideStat(String(localized: "WITH"), row.effect.meanWith, row.effect.nWith, d, StrandPalette.gold)
                        Rectangle().fill(StrandPalette.hairline).frame(width: 1, height: 46)
                        sideStat(String(localized: "WITHOUT"), row.effect.meanWithout, row.effect.nWithout, d, StrandPalette.textTertiary)
                    }

                    Rectangle().fill(StrandPalette.hairline).frame(height: 1)

                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.deltaText)
                                .font(.system(size: 20, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(tint)
                            Text("DIFFERENCE").font(StrandFont.overline).tracking(1.0)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let p = row.pctText {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p)
                                    .font(.system(size: 20, weight: .heavy)).monospacedDigit()
                                    .foregroundStyle(tint)
                                Text("RELATIVE").font(StrandFont.overline).tracking(1.0)
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(row.totalSamples)")
                                .font(.system(size: 20, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(StrandPalette.textSecondary)
                            Text("DAYS").font(StrandFont.overline).tracking(1.0)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack {
                        Text(row.confidence.label).font(StrandFont.footnote)
                            .foregroundStyle(row.confidence.tint)
                        Spacer()
                        if row.lagDays == 1 {
                            Text("measured the following day", comment: "Journal factor lag note")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private func sideStat(_ label: String, _ value: Double, _ n: Int,
                          _ d: PremiumMetricDef, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(StrandFont.overline).tracking(1.2)
                .foregroundStyle(StrandPalette.textTertiary)
            Text(d.format(value, withUnit: false))
                .font(.system(size: 26, weight: .heavy)).monospacedDigit()
                .foregroundStyle(tint)
            Text(String(format: String(localized: "%1$d day(s)"), n))
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Co-occurrence phrasing. There is deliberately no variant of this sentence that asserts cause.
    private func sentence(_ row: PremiumJournalIntel.Discovery) -> String {
        let d = PremiumMetricCatalog.def(row.outcome)
        let direction = row.effect.delta >= 0
            ? String(localized: "higher") : String(localized: "lower")
        let template = row.lagDays == 1
            ? String(localized: "On days following “%1$@”, your %2$@ has averaged %3$@ %4$@ than on days without it.")
            : String(localized: "On days you logged “%1$@”, your %2$@ has averaged %3$@ %4$@ than on days without it.")
        return String(format: template, display, d.shortName.lowercased(),
                      d.format(abs(row.effect.delta), withUnit: true), direction)
    }

    private func explainerItems(_ row: PremiumJournalIntel.Discovery) -> [PremiumExplainerItem] {
        let d = PremiumMetricCatalog.def(row.outcome)
        return [
            .init(question: String(localized: "What is this comparing?"),
                  answer: String(format: String(localized: "Your average %1$@ on days you logged “%2$@” (%3$d days), against your average on days you did not (%4$d days)."),
                                 d.shortName.lowercased(), display, row.effect.nWith, row.effect.nWithout)),
            .init(question: String(localized: "Is this a lot?"),
                  answer: String(format: String(localized: "The gap is %1$@ in %2$@. Whether that matters to you depends on how much your %2$@ normally varies night to night — the distribution on the %2$@ screen shows that range."),
                                 row.deltaText, d.shortName.lowercased())),
            .init(question: String(localized: "How much can I trust it?"),
                  answer: String(format: String(localized: "This is labelled “%1$@”, based on %2$d matched days. NOOP does not surface a comparison at all below %3$d logged days, so nothing here is built on a handful of entries — but more logging still sharpens it."),
                                 row.confidence.label, row.totalSamples, PremiumAnalysis.minBehaviorOccurrences)),
            .init(question: String(localized: "Does this mean it caused the change?"),
                  answer: String(localized: "No. This measures that two things happened together, not that one produced the other. Something else may drive both — a busy week could push a late meal AND poor sleep, without the meal affecting the sleep at all.")),
        ]
    }

    private func methodology(_ row: PremiumJournalIntel.Discovery) -> String {
        let d = PremiumMetricCatalog.def(row.outcome)
        let lag = row.lagDays == 1
            ? String(localized: "Each logged day is matched against the FOLLOWING day's value, because a behaviour late in the day often shows up in the next morning's numbers.")
            : String(localized: "Each logged day is matched against the SAME day's value.")
        return String(format: String(localized: "Your recorded days are split into two groups: those where “%1$@” was logged and those where it was not. The mean %2$@ of each group is taken, and the difference reported both absolutely and as a percentage of the without-group mean. %3$@ NOOP computes both the same-day and next-day framings and reports whichever shows the stronger association, which is why some comparisons are labelled as measured the following day.\n\nSample counts are the days that had BOTH a journal entry and a recorded %2$@ value — days missing either are excluded rather than filled in. Effect size (Cohen's d over the pooled standard deviation) is what ranks findings against each other, not the percentage, so a large percentage swing on a small or noisy baseline cannot outrank a well-evidenced one.\n\nThis is an observational split of your own history. It is not a controlled experiment: nothing was randomised, and confounding factors are not adjusted for."),
                      display, d.shortName.lowercased(), lag)
    }

    private var disclaimer: some View {
        StrandCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("These are associations measured in your own logged history — not proof that one caused the other. Keep logging to sharpen them.", comment: "Journal factor detail disclaimer")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
