# NOOP · Premium UI Prototype

A self-contained, **fully-offline** front-end prototype exploring a next-generation
interface for NOOP — recovery, sleep, heart rate, coach, journal, trends and
insights — built to feel like a premium Apple-grade health product.

Pure **HTML5 + CSS3 + vanilla JavaScript**. No React, Vue, Tailwind, Bootstrap,
build step, or network calls. It opens straight from disk, which keeps it true to
NOOP's ethos: *your data, your machine, no cloud*.

> This lives under `prototypes/` as a **design exploration**. It is not wired into
> the shipping macOS / iOS / Android apps and ships no product data — the numbers
> are a deterministic on-device mock. It's a visual/interaction reference intended
> to be portable to SwiftUI / Compose later.

## Run it

Just open the file — no server required:

```bash
open prototypes/premium-ui/index.html      # macOS
xdg-open prototypes/premium-ui/index.html  # Linux
```

Best viewed in a Chromium/WebKit browser. On desktop it renders inside a phone
frame; on a phone it goes edge-to-edge. There's a light/dark toggle in the header
(the ☾ icon) and an accent picker in **Settings → Appearance**.

### Single-file build (for hosting / sharing)

`node build-single.js` bundles the whole prototype into one self-contained file
at `dist/index.html` (no external requests — everything inlined). Drop that single
file on any static host, or open it directly. `dist/` is git-ignored since it's
regenerable.

### Deploy to GitHub Pages

`.github/workflows/deploy-premium-ui.yml` publishes this folder to Pages on push.
It needs Pages enabled once by a repo admin (**Settings → Pages → Source: "GitHub
Actions"**) — the Actions token can't enable Pages on its own. After that, the site
serves at `https://<owner>.github.io/<repo>/`.

## What's in it

Nine fully-interactive screens, reachable from the bottom dock and via in-page links:

| Screen | Highlights |
|---|---|
| **Home / Today** | Living recovery ring, day-strain + sleep, AI "Today's Story", live vitals with sparklines, recovery drivers, recommendation |
| **Sleep** | Sleep-score ring, lane-based hypnogram, stage breakdown, debt & consistency, week/month/3-month trends |
| **Readiness** | Large recovery score, plain-language explanation, expandable contributors, history, 3-day forecast |
| **Heart** | Pulsing live BPM, animated ECG ribbon, day-in-the-life HR with zone shading, time-in-zone, resting-HR trend |
| **Coach** | Forecast cards, AI plan card, guidance tiles, a **working conversational thread** (typing indicator, context-aware replies) |
| **Journal** | Mood selector, 8-type log grid with bottom-sheets, today's entries, behaviour→impact toggles, note + save |
| **Trends** | Metric picker that morphs the hero chart, week/month/year ranges, period comparison, weekly digest, auto-insights |
| **Insights** | Expandable "why, explained" cards with tags + filters, a discovered-correlation scatter |
| **Settings** | Profile, live theme + accent, notifications, health sources, export (`.noopbak`), privacy, experimental, about |

Every chart animates on reveal and responds to hover/touch; rings draw and numbers
count up; cards lift, buttons ripple, pages transition directionally.

## Structure

```
premium-ui/
├── index.html            # shell: device frame, top bar, scroll region, dock
├── styles/
│   ├── tokens.css        # design tokens — the single source of truth (color, type, space, motion, depth)
│   ├── base.css          # reset, device stage, ambient background, scroll shell
│   ├── components.css    # reusable component library (cards, rings, chips, nav, sheets, charts…)
│   ├── pages.css         # per-screen composition
│   └── animations.css    # keyframes, page transitions, micro-interactions
├── scripts/
│   ├── data.js           # deterministic on-device mock of NOOP's signals
│   ├── icons.js          # inline SVG icon set (offline, themeable via currentColor)
│   ├── charts.js         # bespoke canvas chart engine (area/bar/spark/heart-day/live-ECG)
│   ├── components.js      # component builders + interaction primitives (rings, count-up, sheets, toasts…)
│   ├── router.js         # SPA router: transitions, dock, header, per-page lifecycle
│   └── app.js            # bootstrap, preferences, global micro-interactions
└── pages/
    └── {home,sleep,readiness,heart,coach,journal,trends,insights,settings}.js
```

## Design system

- **Tokens first.** No raw colors/spacing in components — everything references
  `styles/tokens.css`. Each life-signal owns an accent (recovery mint, strain
  indigo, sleep violet, heart coral, HRV aqua) over a signature liquid-metal gold.
- **Two themes.** A default *Midnight* dark theme and a *Daylight* light theme via
  `[data-theme]`; domain accents stay constant across both.
- **Components are factories.** Each returns markup and is wired after mount, so the
  structure maps cleanly onto SwiftUI/Compose views when it's time to port.
- **Motion is intentional.** One "settle" easing and one gentle-overshoot spring,
  staggered reveals, and a `prefers-reduced-motion` escape hatch.

## Scope & honesty

This is a **UI prototype**, not a medical or production surface. The health values
are fabricated mock data for demonstration and do not come from a strap. It adds no
server, account, telemetry, or firmware — consistent with the repo's hard scope
limits in [`CLAUDE.md`](../../CLAUDE.md).
