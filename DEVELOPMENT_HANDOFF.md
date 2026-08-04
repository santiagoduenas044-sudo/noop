# NOOP — Development Handoff

Working notes for whoever (human or AI) picks this up next. Read this, then
[`CLAUDE.md`](CLAUDE.md) for the project's hard rules (offline-only, no telemetry, cross-platform
parity, design-system-only UI).

---

## PRODUCT RULES (standing — set by the owner, do not violate without being asked to)

1. **The app already looks good. Do NOT perform another global redesign.** Sleep's visual design in
   particular is locked. Improvements must be *visibly useful*, not internal refactors that leave the
   installed app looking identical — that was the specific complaint that triggered this direction.
2. **Never add a chart just to make a screen longer.** Every chart/card must answer at least one of:
   *What changed? · Compared with what? · Is this normal for me? · Is it improving or declining? ·
   How unusual is today? · What may be associated with it?*
3. **Prefer fewer high-information visualizations over many basic line charts.** Where a screen wants
   the same question asked of several metrics, use ONE re-aimable card
   (`PremiumChipPicker`) rather than one card per metric.
4. **Combine, don't scatter:** current value + personal baseline + 7D/30D change + range + a short
   explanation belong in ONE card, not spread across separate sections.
5. **Audit and upgrade the weakest/repetitive charts before adding anything new.**
6. **Real data only.** Never fabricate health data to make a chart look populated; use a proper
   sparse/empty state (`MetricUnavailable`, `PremiumEmptyState`).
7. **The engine computes; the model explains.** Coach explains deterministic findings from real NOOP
   data — it never derives relationships or invents health conclusions.

---

## CURRENT IMPLEMENTATION STATUS

**Last updated:** after the chart audit/consolidation pass + testing IPA (build 214)
**Current commit:** `a521faa`
**Installable build:** `NOOP-ios-unsigned-v9.1.3.ipa` on the rolling `testing-latest` release,
built from `a521faa` (build 214) and **asset presence verified**, not just "workflow went green".
Confirm the asset actually exists on the release before ever telling the owner an IPA is ready.
**Previous commit line (superseded):** `0f9548c`
**Current milestone:** Product-direction pivot — the owner explicitly redirected priority AWAY from
finishing i18n-4 and toward visibly useful analytics depth (richer graphs, baselines, 7/30/90D
comparisons, relationships). i18n-4 is still genuinely incomplete (see KNOWN ISSUES) but is NOT the
next task anymore unless the owner asks for it again.
**Build status: VERIFIED GREEN at `0f9548c`** — `app-build.yml` run
[30867729650](https://github.com/santiagoduenas044-sudo/noop/actions/runs/30867729650) succeeded
(macOS + iOS both). Commit `6fe7128` (the Sleep bug-fix commit) FAILED CI first
(`PremiumMetricDef` — see IMPORTANT IMPLEMENTATION NOTES); `9ed8119` fixed it and `0f9548c` is the
first green commit after the pivot. Always check `app-build.yml` yourself before trusting a commit —
CI does not run this by default (see "Known bugs / gotchas" below).

### COMPLETED (this session, on top of everything below)
- **Sleep bug fixes** (`6fe7128`):
  - **AM/PM midpoint bug** — `PremiumSleepIntel.Night.midpointMinutes` and `SleepTimingMap`'s local
    wake-time offset both added a spurious extra `+1440` on top of `minutesSinceNoon`, which already
    self-wraps a post-midnight wake time onto the same noon-anchored scale as the evening bedtime.
    The extra offset shifted every DISPLAYED midpoint by exactly 12 hours (verified the exact
    reported symptom numerically: bed 8:57 PM / wake 8:03 AM produced a 2:30 PM midpoint instead of
    2:30 AM). Fixed in both places. Variance-based stats (regularity score, bedtime/wake/midpoint
    variability) were NOT affected — a constant offset doesn't change spread — only the displayed
    clock values were wrong.
  - **Absurd temperature percentage changes** — `skinTempDevC` is already a deviation from the
    wearable's own baseline, so this app's OWN 30-day mean of that value sits near zero; dividing by
    it for a percent-of-baseline blew up (e.g. "+900%" for a normal 0.4°C night). Added
    `PremiumMetricDef.usesAbsoluteDeviation` (true only for `.skinTemp`) plus a parallel
    signed-absolute-delta code path: `PremiumMetricAnalysis.deviationAbs` /
    `change7Abs`/`change30Abs`/`change90Abs`, `PremiumMetricDef.formatSigned(_:)`, and catalog-level
    helpers `PremiumMetricCatalog.deviationText/deviationGood/changeText/changeGood` that every
    display site now goes through instead of reading `.deviationPct` raw. Wired into Sleep's
    overnight-vitals row, `PremiumCatalogDetailView`'s header delta + change-over-time rows, Heart's
    baseline cards, and `PremiumCoachContext.MetricState.brief` (so the Coach never gets fed an
    absurd percentage either). Also added a defensive guard in `PremiumAnalysis.baselineFinding` that
    skips any metric in `absoluteDeviationMetricKeys` — belt-and-braces against a future call site
    re-adding skinTemp to a findings loop.
  - Confirmed (did NOT need to build) that stage-selection fading (tap REM/Deep/Light/Awake → dims
    other stages in the ribbon AND shades that stage's windows on the HR curve, curve itself never
    dimmed) was ALREADY correctly implemented in `StageRibbon` (opacity 0.16 vs 1.0) and
    `SleepNightPanel.hrChart`. Design decision #1 in this doc describes it; nothing to do there.
- **Heart — HRV given equal prominence to RHR** (`0f9548c`):
  - `distributionSection` was RHR-only; generalized into `metricDistributionCard(_:analysis:tint:)`
    and called for both `.restingHr` and `.hrv` — HRV now gets its own distribution histogram +
    weekday pattern, not just a baseline card.
  - New `changeOverTimeSection` — a 7D/30D/90D change card for RHR and HRV side by side, using the
    same `PremiumMetricCatalog.changeText/changeGood` absolute-vs-percent logic as the temp fix.
  - `relationshipSection` generalized from the single hardcoded HRV↔recovery scatter into
    `relationshipCard(_:_:tint:)`, called for HRV↔recovery, HRV↔sleep duration, and RHR↔recovery.
  - New `journalRelationshipsSection` — journal behaviour associations against HRV/RHR, computed the
    same way `PremiumJournalView.loadAssociations` does (own `@State journalFindings`, loaded in
    `load()`).
- **Trends — moved toward "long-term analytics center"** (`0f9548c`):
  - Added a `Year` (365d) range alongside Week/Month/Quarter.
  - `comparisonCard` ("this period vs last") now shows an explicit signed absolute + percent delta
    chip (`periodComparison`), not just two bare numbers with no stated difference.
  - `correlationCard` used a hand-rolled, duplicate Pearson implementation (`Self.pearson`) —
    against CLAUDE.md's "reuse the shipping analytics package" rule. Replaced with
    `CorrelationEngine.alignByDay` + `.pearson` (the same engine `PremiumAnalysis` uses elsewhere);
    the card now also shows matched-day sample size and a `PremiumConfidence` label.
  - Added a weekday-vs-weekend average rollup under the existing by-day-of-week bar chart
    (`Self.weekdayVsWeekend`).
  - NOT done yet: a rolling-average overlay on the hero chart (`PremiumAnalysis.rollingMean` exists
    and is unused by Trends) — flagged in NEXT TASK below.

- **Chart audit + consolidation** (`c397c07`) — applied the PRODUCT RULES above, *including to
  additions made earlier in the same session that violated them*. Worth reading before adding any
  chart:
  - **Heart** had 7 charts answering two questions. `distributionSection` was 2 cards / 4 charts
    (RHR histogram + weekday, HRV histogram + weekday) → ONE card with an RHR/HRV
    `PremiumChipPicker`, now captioned with today's **percentile** so it answers "how unusual is
    this?" rather than just drawing a shape. `relationshipSection` was 3 near-identical scatters →
    ONE card **ranked strongest-first** (answering "which relationship actually matters *for me*?"),
    each stating a plain-language non-causal sentence + confidence + n. The standalone
    `changeOverTimeSection` was deleted and its 7/30/90D figures + observed range folded INTO
    `baselineCard` (rule 4).
  - **Sleep** — `regularitySection` and `timingSection` were two sections both describing
    bed/wake/midpoint (± stats in one, three stacked `BaselineBandChart`s in the other). Merged into
    ONE `scheduleSection`: score + timing map + ± row kept, three charts replaced by ONE re-aimable
    drift chart that also states how far the last 7 nights moved vs the 7 before. Its two scatters
    got the same ranked-single-card treatment.
  - **Trends** — the distribution card drew bare bucket bars with no baseline, no marker, no labels
    (it answered nothing). Replaced with the shared `DistributionHistogram` (marks the latest
    reading) + min/max labels + a percentile caption. Its bespoke `histogramCounts` helper is gone.
  - Added **`PremiumChipPicker`** to `PremiumKit.swift` — the mechanism that makes "one re-aimable
    chart" cheap. Use it instead of stacking a card per option.

### IN PROGRESS / STILL OPEN FROM THE ORIGINAL PRIORITY LIST
- **Heart / Trends / Sleep** — the depth and consolidation asks are largely done (above). Trends'
  hero and comparison cards still lack a confidence/sample-size line (the correlation card has one),
  and `PremiumAnalysis.rollingMean` exists but no screen surfaces a rolling-average overlay yet.
- **Metric detail views** — `PremiumCatalogDetailView` is now the ONLY detail path (the duplicate was
  deleted in `abbfeca`) and already carries history / baseline / 7-30-90D change / distribution /
  weekday / related / explanation. It has NOT yet been re-read against the new PRODUCT RULES — it
  likely has the same "separate section per question" pattern that was just consolidated out of
  Heart, so it is the obvious next audit target.
- **Journal factor library + one-tap Home access, and Coach wiring** — NOT started. Unchanged from
  the descriptions in "Partially implemented" / "What still needs to be done" below.

### NEXT TASK
1. **Audit `PremiumCatalogDetailView` against the PRODUCT RULES.** It is the screen every metric card
   opens into, and it predates the rules. Expect to merge its separate `changeSection` into the
   header/history card the same way Heart's `baselineCard` was fixed, and to check each section
   earns its place. This is the highest-value remaining UI work because it is shared by ~24 metrics.
2. **Journal** — bigger configurable factor library + one-tap access from Home. NOTE: the catalog
   lives in `Strand/Data/JournalCatalog.swift`, which is **shared with macOS** — a higher blast
   radius than the iOS-only `StrandiOS/App/Premium*` files touched so far. Build BOTH targets.
3. **Coach** — `PremiumCoachContext` is complete and correct (read it before changing anything);
   `PremiumCoachView` still shows canned content. Wire the context in; any API client must be behind
   an explicit user opt-in (offline-by-default is a hard project rule, not a preference).
4. **Verify on a real device with real history** — none of this session's analytics output has been
   eyeballed against a populated database; sparse-history and brand-new-install states especially.

Always dispatch `app-build.yml` and confirm green before considering a milestone done — this branch's
CI does not build app targets by default. To cut an installable build: bump `CURRENT_PROJECT_VERSION`
in `project.yml`, dispatch `fork-testing-build.yml`, then **verify the `.ipa` asset actually exists on
the `testing-latest` release** before telling the owner it is ready.

### IMPORTANT IMPLEMENTATION NOTES
- **Swift gotcha hit this session:** a stored property with an inline default value
  (`let usesAbsoluteDeviation: Bool = false`) inside a struct that otherwise relies on the
  compiler-synthesized memberwise init does NOT reliably let you override that default by explicit
  argument at every call site — `PremiumMetricCatalog.swift`'s `.skinTemp` definition hit
  `error: extra argument 'usesAbsoluteDeviation' in call` in CI (`app-build.yml` run 30867151827).
  Fixed by giving `PremiumMetricDef` an **explicit** `init(...)` with the default only on that one
  parameter. If you add another optional/defaulted field to a struct that already has many
  positional call sites, prefer an explicit init over relying on memberwise synthesis + inline
  defaults — CI (the ONLY thing that catches this) takes ~7-10 minutes per round trip, so getting
  this right the first time matters.
- `Tools/add_catalog_strings.py` preserves the catalog's exact on-disk formatting and never
  overwrites an existing translation. Do NOT re-serialise the catalog another way — a plain
  `json.dump` with `sort_keys` produces a 7700-line diff.
- The language override writes Apple's `AppleLanguages` key; bundle lookup resolves at launch, hence
  the "relaunch to finish" note in Settings. Don't try to make it instant by reloading bundles.
- Interpolated `String(localized: "… \(x)")` is not extracted cleanly — use
  `String(format: String(localized: "… %1$@"), x)` with **positional** specifiers, so translators
  can reorder arguments.
- `PremiumMetricCatalog.all` is a `static let`, so its `String(localized:)` calls resolve once per
  process. That is deliberate and matches the relaunch-to-apply behaviour — don't "fix" it into a
  per-render lookup.
- `PremiumMetricGroup.rawValue` is a stable identifier (used in stored prefs); `.label` is the
  display string. Never render `rawValue`.
- **Deviation/change display:** any NEW code that shows `PremiumMetricAnalysis.deviationPct` or
  `.change7/30/90` directly (as a raw percentage) is a latent bug for any future metric whose own
  baseline can sit near zero. Go through `PremiumMetricCatalog.deviationText/deviationGood/
  changeText/changeGood` instead — they pick absolute-vs-percent per metric automatically.
- **Repo branch names:** the real work branch is `claude/noop-premium-ui-jhlhvg` (no suffix) — it has
  an open PR (#1) and all 60+ prior commits. Some session harnesses designate a suffixed branch name
  (e.g. `claude/noop-premium-ui-jhlhvg-0vo958`); if you're handed a designated branch that's actually
  just a fresh copy of `main`, check `git log` before assuming it's the right base — reset it to
  track the real branch instead of starting over. This session pushed to both branch names to satisfy
  both the owner's explicit instruction and an automated harness check; if you only have one to push
  to, prefer the un-suffixed `claude/noop-premium-ui-jhlhvg`.

### KNOWN ISSUES
- ~129 un-localized static literals in the Premium **views**, unchanged this session (deprioritized,
  see CURRENT MILESTONE above) — see the OLD next-task recipe below if the owner asks for this again.
- macOS `SettingsView` has no language picker — the override is iOS-only so far.
- Coach still shows demo content; `PremiumCoachContext` is built but unused by the UI.
- `PremiumSectionHeader(title:)` and similar `String`-typed (not `LocalizedStringKey`-typed) view
  parameters are a systemic i18n blind spot across EVERY Premium screen, old and new — a literal
  passed through such a parameter never reaches `Text(LocalizedStringKey)`'s automatic string-catalog
  lookup, so it silently never gets extracted or translated even when "done" by the i18n audit tool.
  Confirmed by checking `Strand/Resources/Localizable.xcstrings` directly: e.g. "Time in zone" (an
  existing, pre-session title) and "Change over time" (added this session) are BOTH absent from the
  catalog. This is pre-existing and not a regression from this session's work, but whoever resumes
  i18n-4 should know `PremiumSectionHeader`/similar wrapper titles need a structural fix (e.g. change
  `title: String` to `title: LocalizedStringKey`), not per-call-site wrapping.

<details>
<summary>Old i18n-4 recipe (deprioritized — expand if the owner asks to resume it)</summary>

Finish `i18n-4` for the remaining view files: secondary screens — `PremiumCoachView` (9),
`PremiumStrainView` (7), `PremiumSettingsView` (7), `PremiumEditHomeView` (7),
`PremiumCatalogDetailView` (6), `PremiumEnergyView` (5), `PremiumBloodOxygenView` (5),
`PremiumWhatsNewView` (4), `PremiumReadinessView` (3), `PremiumMetricDetailView` (3),
`PremiumInsightsView` (2), `PremiumCharts` (1), plus ~20 numeric/format literals that are
deliberately NOT translated (axis ticks like `12a`/`6p`, bpm ranges like `120–140`).

1. `python3 Tools/i18n_audit.py --platform ios --full` → lists the exact file:line and literal.
2. Wrap prose in `String(localized:)`, or `Text("…", comment: "…")` for plain literals; use
   `String(format: String(localized: "… %1$@"), x)` for anything interpolated.
3. Add keys + de/es/fr: `python3 Tools/add_catalog_strings.py Strand/Resources/Localizable.xcstrings
   entries.json`
4. Re-run the audit, commit that file, push.

Skip pure numeric formats (axis ticks, "120–140" ranges) — they are not language.
</details>

---

## Status

| | |
|---|---|
| **Branch** | `claude/noop-premium-ui-jhlhvg` (real branch, PR #1 open). Some sessions also mirror to a harness-designated `claude/noop-premium-ui-jhlhvg-<suffix>` — same commits, not a fork. |
| **App version** | `MARKETING_VERSION 9.1.3`, `CURRENT_PROJECT_VERSION 213` (`project.yml`) |
| **Scope of recent work** | iOS Premium UI, analytics depth (Heart/Trends), Sleep bug fixes. No BLE, HealthKit, storage-schema or Android changes. |

### Checkpoint commits
| SHA | Milestone |
|---|---|
| `f3d7281` | Premium analysis engine, charts, metric catalog, customizable Home |
| `d57948e` | Sleep / Heart / Trends / Journal rebuilt on the analysis layer |
| `5a461ac` | Heart formatter hoist |
| `3f693d0` | `DEVELOPMENT_HANDOFF.md` added |
| `ee5bd36` | `i18n-1` — language picker |
| `5b33e61` | `i18n-2` — generated insight sentences localized |
| `fe09ac9` | `i18n-3` — metric catalog names/explanations localized |
| `0ddfccc` | handoff checkpoint |
| `a700c62` | `i18n-4a` — Heart + Sleep view copy localized |
| `42b3bc9` | handoff checkpoint |
| `4759283` | `i18n-4b` — Home + Trends + Journal view copy localized |
| `6fe7128` | Sleep AM/PM midpoint bug + absurd temperature percentages fixed — **CI FAILED**, see next row |
| `9ed8119` | Fix build break from `6fe7128` (`PremiumMetricDef` explicit init) |
| `0f9548c` | Heart HRV parity (distribution/change/relationships/journal) + Trends analytics depth (Year range, delta chip, shared correlation engine, weekday/weekend) — verified green |
| `abbfeca` | Removed the dead legacy metric-detail path (`PremiumMetricKind`/`PremiumMetricKit`/`PremiumMetricDetailView` + its unreachable `PremiumRoute.metric` case) — the consolidation this doc had flagged as outstanding |
| `6f631de` | Sleep depth — duration distribution + Sleep/Recovery + Sleep/HRV relationships — verified green |
| `c397c07` | **Chart audit + consolidation** (see PRODUCT RULES above) — verified green (`app-build.yml` run 30877739443) |
| `a521faa` | Build number 213→214 for the testing IPA — **current head, IPA published and verified** |

---

## What has been implemented

**A deterministic analysis layer, and screens rebuilt on top of it.** The guiding rule: the app
*computes* every interpretation it shows; nothing is estimated by a model, and any figure that can't
be computed honestly is shown as unavailable rather than filled in.

- **`PremiumAnalysis`** — personal baselines, deviation (% and z), 7/30/90-day changes, trend
  direction, rolling means, run-length ("4 days below baseline"), day-of-week patterns, same-day and
  lag-1 correlations, journal behaviour associations, confidence levels
  (Early signal / Emerging pattern / Consistent pattern), and physiological bounds validation.
  Reuses the shipping `StrandAnalytics` engines (`CorrelationEngine`, `BehaviorInsights`,
  `SleepDebt`) rather than re-deriving tested statistics.
- **`PremiumMetricCatalog`** — one registry of ~24 signals: real readers, provenance
  (measured / wearable-estimated / calculated), bounds keys, formatting, and *computed* availability.
- **`PremiumCharts`** — baseline-band, range-column, deviation-bars, distribution, weekday-pattern,
  scrubbable, dual-metric, correlation-scatter, stage-ribbon, plus finding/provenance/unavailable
  presentation components.
- **Home** — customisable catalog-driven metric grid (show/hide, reorder, compact/expanded,
  persisted), Edit Home sheet, Journal fast-access card, computed "Your patterns" section. Every
  card opens a detail screen.
- **Sleep** — stage list and overnight HR merged into ONE instrument (see design decisions below),
  plus continuity (WASO / awakenings / longest wake), regularity (timing map + bed/wake/midpoint
  variability + regularity score), timing trends vs personal bands, balance vs personal sleep need,
  overnight vitals vs baselines, and history with 7/30/90-day changes.
- **Heart** — today's range, RHR/HRV vs personal baselines, zone stack + time-in-zone, data-gated
  physiological-load estimate, scrubbable overnight curve, 14-day daily-range columns, RHR
  distribution + weekday pattern, HRV↔recovery scatter.
- **Trends** — hero chart against the personal typical range, user-selectable comparison metric,
  tappable calendar days revealing that day's real signals, computed "What changed" section
  including journal associations.
- **Journal** — one-tap quick-log row ranked by what this user actually logs, plus a computed
  associations section.
- **`PremiumCoachContext`** — structured, already-computed brief for the future Claude Coach.

---

## Partially implemented

- **Coach** — the *context layer* is complete and correct, but `PremiumCoachView` still shows the
  older canned/demo content. Nothing consumes `PremiumCoachContext` in the UI yet, and there is no
  API client. This is the main unfinished seam.
- **Derived metrics on Home** — `liveHeartRate`, `stressLoad`, `sleepRegularity`, `sleepBalance`,
  `bedtime`, `wakeTime` are in the catalog and appear in Edit Home, but their Home cards render "—"
  because they aren't per-day `DailyMetric` columns. Tapping them routes to a detail screen that
  explains where the metric actually lives. Wiring real values into those cards is straightforward
  (`PremiumSleepIntel` already computes the sleep ones).
- ~~`PremiumMetricKit` / `PremiumMetricDetailView` duplicate detail path~~ — **RESOLVED in
  `abbfeca`**: it was never reachable (nothing ever constructed `PremiumRoute.metric`), so both files
  and the dead route case were deleted. `PremiumCatalogDetailView` is now the only detail screen.

---

## What still needs to be done

1. Wire `PremiumCoachContext` into `PremiumCoachView` and add the Claude API client.
2. Populate the derived Home cards with real values.
3. Android parity — **none of this exists on Android.** Per `CLAUDE.md`, analytics/stored values must
   stay byte-identical across platforms. Nothing here changes stored data or existing analytics
   (it only *reads* and presents), so there is no divergence today, but any new stored value would
   need its Kotlin twin.
4. Tests. `PremiumAnalysis` is pure and nonisolated specifically so it can be unit-tested; there are
   no tests yet. It cannot live in `Packages/` as-is (it imports SwiftUI for `Color`) — splitting the
   pure math out would let `swift test` cover it. **This is why the AM/PM midpoint bug survived so
   long**: `midpointMinutes` was a one-line property no test ever exercised. A handful of tests over
   the clock maths and the deviation/change helpers would be cheap and high-value.
5. ~~Consolidate the two metric-detail paths.~~ Done in `abbfeca`.

---

## Important SwiftUI files

All under `StrandiOS/App/`, all `#if os(iOS)`.

| File | Controls |
|---|---|
| `PremiumAnalysis.swift` | **The analysis engine.** Baselines, deviations, changes, trends, correlations, associations, confidence, provenance, bounds validation. Pure + nonisolated. |
| `PremiumMetricCatalog.swift` | The ~24-metric registry + `PremiumHomeLayoutStore` (Home customisation, `UserDefaults`-backed). |
| `PremiumCharts.swift` | All rich chart components + finding/provenance/unavailable UI. |
| `PremiumSleepIntel.swift` | Sleep intelligence shared by the Sleep screen AND the Coach context: per-night bed/wake windows, regularity, WASO, stage minutes. |
| `PremiumCoachContext.swift` | Structured brief for the Coach + grounding rules. |
| `PremiumHomeView.swift` | Home dashboard. |
| `PremiumEditHomeView.swift` | Home customisation sheet. |
| `PremiumCatalogDetailView.swift` | Reusable detail screen for every catalog metric. |
| `PremiumSleepView.swift` | Sleep screen; contains the private `SleepNightPanel` (merged stage/HR instrument) and `SleepTimingMap`. |
| `PremiumHeartView.swift` | Cardiovascular dashboard. |
| `PremiumTrendsView.swift` | Trends exploration. |
| `PremiumJournalView.swift` | Journal logging + associations. |
| `PremiumNav.swift` | `PremiumRoute` enum + `.premiumRouteDestinations()`. Add new deep screens here. |
| `RootTabView.swift` | Tab shell, FAB quick actions, journal sheet routing. |

---

## Health/data architecture

- `Repository` (`Strand/Data/Repository.swift`) is the single data source: `repo.days`
  (`[DailyMetric]`, oldest→newest), `repo.today`, plus async reads
  (`allSleepSessions()`, `hrBuckets(from:to:bucketSeconds:)`, `hrSamples(...)`, `journalEntries()`).
- `DailyMetric` (`Packages/WhoopStore`) is the per-day row. **`efficiency` is a FRACTION in [0,1]**
  on the on-device path but 0–100 from some importers — always normalise
  (`$0 <= 1.0 ? $0 * 100 : $0`). `PremiumMetricCatalog.efficiencyPct` does this once.
- Sleep sessions carry `effectiveStartTs` (honours user edits) — use it, not `startTs`.
- Main-night selection and stage decoding go through `SleepView.mainNightSession` /
  `SleepView.decodedIntervals` so every screen agrees. Don't re-derive these.
- HealthKit (`StrandiOS/Health/HealthKitBridge.swift`) is **untouched** by this work.

---

## Analysis / Insights engine status

Complete and in use by Home, Sleep, Heart, Trends and Journal. Thresholds live in one place at the
top of `PremiumAnalysis`:

```
minBaselineSamples     = 7    // before any baseline is computed
minCorrelationSamples  = 10   // before any correlation is shown
minBehaviorOccurrences = 5    // before a journal association is shown
baselineWindow         = 30
```

Findings are emitted only when they clear both a relative and a dispersion threshold **and** have
persisted (`runLength >= 2`), which is what keeps one noisy night off the screen.

---

## Journal status

Backed by the existing real store (`repo.saveJournalAnswer` / `saveJournalNumeric` /
`clearJournalAnswer` / `journalEntries()`, device id `noop-journal`, merged with imported WHOOP
rows). Quick-log chips rank by the user's own logging frequency. Associations come from
`PremiumAnalysis.behaviorAssociation`, which tries same-day and next-day framings and keeps the
stronger — a late meal plausibly shows up in the *following* morning's numbers.

---

## Claude Coach / API architecture status

`PremiumCoachContext.build(...)` assembles metrics, baselines, sleep/heart intelligence, journal
state, computed findings and explicit data-quality limits, and renders `promptBrief` (readable text,
deliberately — it's also what a debug view could show the user before anything is ever sent).
`groundingRules` travels with it and makes fabrication a rule violation.

**The division is the whole point: the engine discovers, the model explains.** Do not move
relationship-finding into the prompt.

No network client exists. Adding one must respect the project's offline guarantee — it would be an
explicit, user-enabled exception, not a default.

---

## Known bugs / gotchas

- **Nothing in the Premium UI compiles on Linux or in CI by default.** `swift-packages.yml` does NOT
  build app targets, and `app-build.yml` is **disabled** (run it on demand). A compile error here
  passes every default check. Always run `app-build.yml` before claiming success.
- **SwiftUI type-checker timeouts are a live hazard.** Two have already been hit and fixed. Keep
  arithmetic out of `@ViewBuilder` position — annotate types explicitly and lift computation into
  helper functions (see `PremiumTrendsView.normalizedPoints`, `PremiumHeartView.normalise`).
- `Repository.localDayKey` is `@MainActor`-isolated. From nonisolated code use
  `PremiumAnalysis.dayParser` (same format, same time zone).
- Old sleep data can carry a bad `efficiency`, which historically produced absurd "time in bed".
  `PremiumSleepView.inBedMin` now prefers the real recorded window and only falls back to the
  efficiency derivation within sane bounds. **Fix such issues at the query/calculation layer, never
  by clamping in the UI.**
- `PremiumTrendsView.Metric.id` is a fresh `UUID()` per computed-property access — pre-existing, and
  `.id(metric.id)` on the hero relies on it changing. Be careful if you refactor it.

---

## Build / IPA workflow

No Xcode on Linux; everything goes through GitHub Actions.

```
app-build.yml           compile gate (macOS + iOS). DISABLED by default — dispatch manually.
fork-testing-build.yml  full build → rolling `testing-latest` release with apk + macOS zip + unsigned IPA.
swift-packages.yml      swift test for Packages/** only. Does NOT cover app targets.
```

Dispatch on branch `claude/noop-premium-ui-jhlhvg`. The IPA lands at:
`https://github.com/santiagoduenas044-sudo/noop/releases/download/testing-latest/NOOP-ios-unsigned-v<VERSION>.ipa`
(unsigned — sideload via AltStore/Sideloadly). The release tag is **rolling**: each run replaces it.

Bump `CURRENT_PROJECT_VERSION` in `project.yml` before producing a build users will install.

`Strand.xcodeproj` is generated by XcodeGen from `project.yml` — never hand-edit or commit it.

---

## Entitlements / configuration

Nothing new was added. The app remains offline-only: no server, no account, no telemetry. iOS
deployment target 17.0; the iOS CI leg needs `macos-26` (iOS 26 SDK, for `glassEffect`). The IPA
packaging step strips the watch app and widget extension for free-account sideload reliability.

---

## Design decisions that should NOT be reverted

1. **Sleep stages and overnight HR are one instrument.** Selecting a stage dims the other stages in
   the ribbon *and* shades that stage's time windows on the HR chart. **The HR curve itself is never
   dimmed** — the entire point is comparing physiology *between* stages, which needs the curve
   legible throughout.
2. **The engine computes; the model explains.** Findings are deterministic. Never let the Coach
   derive relationships.
3. **Association language only.** "Coincided with", never "caused". Confidence labels are mandatory
   on every finding.
4. **Unavailable beats fabricated.** No zero stand-ins, no invented baselines, no placeholder
   charts. `MetricUnavailable` exists for this.
5. **Provenance labelling** (measured / wearable-estimated / calculated). A wearable sleep-stage
   estimate must never read as a clinical measurement.
6. **Sample-count thresholds are honesty gates**, not tuning knobs. Lowering them to make the screen
   look fuller would be a correctness regression.
7. **Sleep need = `max(450, personal 30-day mean)`** — matches `SleepView.sleepNeedMin`. Keep the
   two in agreement.
8. **Bounds validation** rejects impossible readings before display or baselines.
9. **Minutes-since-noon** for sleep clock maths, so averaging works across midnight.
10. **Design tokens only** — `StrandPalette` / `StrandFont` / `StrandCard`. No raw colours or fonts.

---

## NEXT STEPS (priority order)

1. **Wire the Coach.** Consume `PremiumCoachContext` in `PremiumCoachView`; show the computed
   findings first, then add the API client behind an explicit user opt-in. Highest value, and the
   context layer is already done.
2. **Populate derived Home cards** (bedtime, wake time, regularity, balance, live HR) — data already
   exists in `PremiumSleepIntel` / `LiveState`.
3. **Test `PremiumAnalysis`.** Split the pure math out of the SwiftUI import so it can move to
   `Packages/` and be covered by `swift test`.
4. **Verify on a real device with real history.** Everything is compile-verified and reasoned from
   the data model, but the analysis output has not been eyeballed against a populated database.
   Sparse-history and brand-new-install states especially deserve a look.
5. **Consolidate the two metric-detail screens** onto the catalog-driven one.
6. **Android parity** if any of this graduates into stored values.
