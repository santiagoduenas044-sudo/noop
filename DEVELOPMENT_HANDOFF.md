# Development handoff log

A running log of engineering milestones that benefit from a written record beyond the commit message —
audits, investigations, and cross-platform decisions — so the next person (or agent) picking up the repo
has the reasoning, not just the diff. Newest entry on top.

---

## Home customization persistence audit + fix

**Report:** "When I customize Home (add/remove/reorder metrics/cards), the changes later disappear/reset."
Expected: a customization survives relaunch, navigation away/back, device reconnect, data refresh, and
normal app-state reconstruction.

**Scope:** "Home" in this app is the Today screen. Three independent, display-only persistence
subsystems back its customization:

| Subsystem | Persisted key | What it controls | Swift | Kotlin |
|---|---|---|---|---|
| `KeyMetricPrefs` | `today.keyMetrics` | Which Key-Metric tiles show + their order | `Strand/Data/KeyMetricPrefs.swift` | `android/.../ui/KeyMetricPrefs.kt` |
| `TodayLayoutPrefs` | `today.sectionOrder` | The order of the below-hero Today sections | `Strand/Data/TodayLayoutPrefs.swift` | `android/.../ui/TodayLayoutPrefs.kt` |
| `DashboardCardPrefs` | `today.dashboardCards` | Which "Your Cards" (WHOOP "My Dashboard") cards show + order | `Strand/Screens/DashboardCards.swift` | `android/.../ui/DashboardCards.kt` |

All three follow the same shape: an ordered list encoded to a string, stored in `@AppStorage` (UserDefaults)
on Apple / `SharedPreferences` via `NoopPrefs` on Android, decoded back on read. None are in the `.noopbak`
backup whitelist (`BackupSettings.swift`/`BackupSettingsCodec.kt`) — display prefs are deliberately excluded
from that whitelist by design, same as every other `noop.*`/`today.*` toggle, so a backup/restore is not a
factor here.

### What was audited (and found sound)

- **Write path**: every editor (`KeyMetricsEditorSheet`/`KeyMetricsEditorDialog`,
  `TodayArrangeSheet`/`TodayLayoutEditorDialog`, `DashboardCardsEditorSheet`/`DashboardCardsEditorDialog`,
  and Android's hold-to-drag section reorder) writes synchronously to durable storage on save/drop, then
  mirrors the same value into local view state immediately. No buffering, no debounce, no "batch and flush
  later."
- **No competing writers**: grepped the whole tree for every write site touching `today.keyMetrics`,
  `today.sectionOrder`, `today.dashboardCards` on both platforms. Only the intended editors write them —
  nothing else (no migration, no "reset on refresh", no widget) touches these keys.
- **No migration/version logic resets them**: there is no schema-version or migration path for these
  UserDefaults/SharedPreferences keys at all (migrations in this codebase are a GRDB/Room *database*
  concept — `WhoopStoreInfo.schemaVersion` — these are display prefs, a different layer entirely).
  On Android, the JSON round-trip test `DashboardCardPrefsTest.decode_acceptsTheLegacyCommaJoinedForm`
  now pins that even the pre-JSON legacy encoding still decodes, so a decoder change couldn't silently wipe
  an old save either.
- **Not two state sources fighting**: `TodayView` (classic) and `LiquidTodayView` (the newer "liquid" UI,
  behind the `liquidTodayEnabled` toggle) each declare their own `@AppStorage`/`remember` binding, but both
  point at the exact same underlying key — a single source of truth with two readers, not two competing
  writers. Swapping between classic/liquid does not lose or overwrite the saved layout.
- **"Compact/expanded" UI state** (`metricsExpanded`, `sourcesExpanded`, `synthesisExpanded` — the "Show all
  metrics"/"Show fewer" and section-collapse affordances) is genuinely **not persisted** on either
  platform — but this is an explicit, pre-existing, cross-platform-mirrored design decision, not an
  oversight: both `TodayView.swift` and `TodayScreen.kt` carry an identical comment ("NOT persisted, so
  the home screen reopens compact"). Left unchanged; flagged here so it isn't rediscovered as a "bug" later.

### The bug found and fixed

**`KeyMetricPrefs.decodeEnabled` (Swift only) did not fall back to the default tile order when every saved
token failed to decode** — it returned an empty array instead. Concretely:

```swift
// Before: an all-unknown/corrupt string returned [] — a BLANK Key Metrics grid, which reads exactly
// like the user's customisation vanished, even though nothing else was actually wrong.
for token in trimmed.split(separator: ",") { ... }
return result   // could be []

// After: matches its own sibling (DashboardCardPrefs.decodeEnabled) and the Kotlin twin, both of which
// already treated "nothing decodable" as "nothing saved" (→ defaults), never as "show nothing".
return result.isEmpty ? KeyMetric.defaultOrder : result
```

This was a genuine cross-platform divergence: the Kotlin `KeyMetricPrefs.decodeEnabled` already had the
`if (seen.isEmpty()) KeyMetric.defaultOrder else seen.toList()` guard, and Swift's own
`DashboardCardPrefs.decodeEnabled` already had the equivalent `result.isEmpty ? DashboardCard.defaultSelection
: result` guard — only `KeyMetricPrefs.decodeEnabled` on Swift was missing it. Fixed in
`Strand/Data/KeyMetricPrefs.swift`.

### What was *not* found

A blanket "every customization always resets on every relaunch/navigation/refresh" bug was not
reproducible from the code: the write/read chain described above is synchronous, durable, and correctly
wired at every call site found. If the symptom is still observed after this fix, the most useful next
report would narrow down:

1. **Which surface** — Key Metrics grid, Your Cards dashboard, or Today section order (they're
   independent subsystems; a bug in one wouldn't imply the others).
2. **Platform + OS version**, and whether it reproduces **every time** or **intermittently**. Intermittent
   loss specifically after a fast force-swipe/force-stop on Android would point at the one remaining
   theoretical gap: Android's `SharedPreferences.Editor.apply()` is asynchronous and, while it is flushed
   by the framework on normal backgrounding/process death, an abrupt kill *can* in principle race it. None
   of the writers found here showed evidence of this in practice, so it wasn't changed pre-emptively —
   but if confirmed, the fix is switching those specific (rare, user-initiated, not hot-path) writes from
   `.apply()` to `.commit()`.
3. **Exact steps**, since "customize → background app → relaunch" and "customize → tap Done → still on
   Today" are different code paths and only one of them touches process lifecycle at all.

### Tests added

Neither `KeyMetricPrefs` nor `DashboardCardPrefs` had *any* test coverage on either platform before this
(only `TodayLayoutPrefs`/section-order did). Added, mirroring the existing `TodayLayoutPrefsTests` /
`MoreSectionPrefsTests` house style:

- `StrandTests/KeyMetricPrefsTests.swift`
- `StrandTests/DashboardCardPrefsTests.swift`
- `android/app/src/test/java/com/noop/ui/KeyMetricPrefsTest.kt`
- `android/app/src/test/java/com/noop/ui/DashboardCardPrefsTest.kt`

Each covers: add a tile/card, remove one, reorder, decode-stability across repeated decodes of the same
string (the pure-function equivalent of "relaunch," since these are just re-decoded from a persisted
string on cold start), the all-unknown-tokens fallback (the exact bug class just fixed), stable/unique raw
keys (the cross-platform wire contract), and one end-to-end pass through a throwaway `UserDefaults` suite /
an in-memory `FakeSharedPreferences` that pins the actual storage key name, not just the pure functions.

### Verification status — please confirm

This environment has neither Xcode nor the Android SDK (per `CLAUDE.md`'s documented local walls), so
**neither test suite was actually run here**. The new tests were written and hand-reviewed against the
established patterns of the tests they're twinned with, but need a real run before this is considered
verified:

```bash
# macOS, once available:
xcodegen generate && xcodebuild -project Strand.xcodeproj -scheme Strand \
  -destination 'platform=macOS' test -only-testing:StrandTests/KeyMetricPrefsTests \
  -only-testing:StrandTests/DashboardCardPrefsTests

# Any machine with the Android SDK:
cd android && ./gradlew testFullDebugUnitTest \
  --tests "com.noop.ui.KeyMetricPrefsTest" --tests "com.noop.ui.DashboardCardPrefsTest"
```

### Files touched

- `Strand/Data/KeyMetricPrefs.swift` — the decoder fix.
- `StrandTests/KeyMetricPrefsTests.swift` — new.
- `StrandTests/DashboardCardPrefsTests.swift` — new.
- `android/app/src/test/java/com/noop/ui/KeyMetricPrefsTest.kt` — new.
- `android/app/src/test/java/com/noop/ui/DashboardCardPrefsTest.kt` — new.
