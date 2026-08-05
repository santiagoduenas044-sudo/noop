# NOOP Premium Prototype — Milestone Changelog

The HTML prototype is the **single source of truth** for the NOOP redesign. Each
milestone is completed and approved here first; SwiftUI migrates only approved
milestones. Version info is surfaced in **Settings** and the **What's New** screen.

Legend: ✅ Added · ✨ Improved · 🎨 Redesigned · 🚧 In progress · ❌ Not started

---

## Milestone 3 — HTML-first workflow · Prototype 0.3.0
_Jul 31, 2026_

The prototype becomes the definitive visual spec, with in-app milestone tracking.

**Screens changed**
- **What's New** (new screen) — categorized milestone view with per-item screen,
  interactivity, and SwiftUI-migration status.
- **Settings** — added a version/build card (Prototype version, milestone, commit,
  build date, native app version + build) and a What's New link + version footer.

**Components added**
- `scripts/config.js` — single source for version/milestone/commit/date.
- `pages/whatsnew.js` — the What's New screen + in-app changelog timeline.
- Version footer + monospace version rows.

**Interactions added**
- Settings → What's New navigation; tappable "Open screen" links on each item.

**Build injection**
- `build-single.js` stamps the real git short-SHA + timestamp into the bundle,
  so the displayed commit always matches the deployed Artifact.

**Bugs fixed**
- None (infrastructure milestone).

**Remaining limitations**
- The nine design screens are already the rich spec; SwiftUI still trails them
  (see below). What's New itself is not yet migrated to SwiftUI.

**SwiftUI migration status**
- Not migrated (this milestone is HTML-only by design — awaiting approval).

---

## Milestone 2 — SwiftUI re-skin + native rebuilds · (app v9.1.0 → 9.1.2)
_Jul 31, 2026_

**Screens changed (native SwiftUI, real data, compiling on CI):**
- 🎨 Home, Sleep, Heart, Coach, Trends, Readiness, Insights — rebuilt natively on
  `Repository`/`DailyMetric`/`LiveState`/`AICoachEngine`.
- ✨ Global token re-skin to the prototype identity (Phase 1).

**Known gaps vs. the HTML spec**
- Sleep: proportional stage bars, not time-resolved lanes.
- Heart: pulse + real day-HR sparkline, no ECG / zone-shaded ribbon.
- Home: shipping recovery ring wording; efficiency vs. a distinct sleep score.
- Journal + Settings: not migrated. 5-tab native nav: not done.

**SwiftUI migration status**
- Home ✅ · Sleep 🚧 · Heart 🚧 · Coach ✅ · Trends ✅ · Readiness ✅ · Insights ✅ ·
  Journal ❌ · Settings ❌

---

## Milestone 1 — Premium HTML prototype · Prototype 0.1.0 → 0.2.0
_Jul 31, 2026_

- ✅ All nine screens designed and interactive in HTML (Home, Sleep, Readiness,
  Heart, Coach, Journal, Trends, Insights, Settings).
- ✅ Bespoke canvas charts, rings, glass components, bottom-sheets, light/dark
  themes, accent picker.
- ✅ Sleep stage-breakdown density lanes + tap-to-compare added as the definitive
  Sleep spec.
- **SwiftUI migration status:** none (prototype only).
