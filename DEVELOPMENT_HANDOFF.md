# NOOP — Development Handoff

Working notes for whoever (human or AI) picks this up next. Read this, then
[`CLAUDE.md`](CLAUDE.md) for the project's hard rules (offline-only, no telemetry, cross-platform
parity, design-system-only UI).

---

## Status

| | |
|---|---|
| **Branch** | `claude/noop-premium-ui-jhlhvg` |
| **Latest commit** | `5a461ac` (see "CI" below for the last commit verified green) |
| **App version** | `MARKETING_VERSION 9.1.3`, `CURRENT_PROJECT_VERSION 213` (`project.yml`) |
| **Scope of recent work** | iOS Premium UI only (`StrandiOS/App/Premium*.swift`). No BLE, HealthKit, storage-schema or Android changes. |

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
- **`PremiumMetricKit` / `PremiumMetricDetailView`** — the older 6-metric detail path still exists
  alongside the new catalog-driven `PremiumCatalogDetailView`. Both are registered. Consolidating
  onto the catalog one would remove the duplication.

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
   pure math out would let `swift test` cover it.
5. Consolidate the two metric-detail paths.

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
