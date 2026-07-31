/* ============================================================================
   NOOP · Premium UI — What's New (Milestone screen)
   The definitive, in-prototype record of what each milestone changes. Every item
   names the affected screen, the component/interaction, what changed, whether it
   is fully interactive here, and whether it has been migrated to SwiftUI yet.
   Backed by the same facts as CHANGELOG.md. Reachable from Settings and the dock.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, icon } = NS;
  const B = NS.build;

  // ---- Milestone 3 content (honest current state) ----------------------------
  const cats = [
    { emoji: '✅', name: 'Added', tint: 'recovery', items: [
      { screen: 'What’s New', route: 'whatsnew', component: 'New screen',
        change: 'A categorized milestone view (this screen) with per-item screen, interactivity and SwiftUI-migration status.',
        interactive: true, swift: 'no' },
      { screen: 'Settings', route: 'settings', component: 'Version & build card',
        change: 'Prototype version, milestone, git commit, build date and last-updated now shown in Settings and here.',
        interactive: true, swift: 'no' },
      { screen: 'Global', component: 'CHANGELOG.md + in-app changelog',
        change: 'A milestone changelog file plus the visual summary at the bottom of this screen.',
        interactive: true, swift: 'n/a' },
    ]},
    { emoji: '✨', name: 'Improved', tint: 'gold', items: [
      { screen: 'All screens', component: 'Design tokens (palette/type)',
        change: 'Phase-1 re-skin to the prototype identity — near-black canvas, gold accent, per-signal hues.',
        interactive: false, swift: 'yes' },
      { screen: 'Workflow', component: 'HTML-first process',
        change: 'The prototype is now the single source of truth; SwiftUI migrates only approved HTML milestones.',
        interactive: false, swift: 'n/a' },
    ]},
    { emoji: '🎨', name: 'Redesigned', tint: 'sleep', items: [
      { screen: 'Home', route: 'home', component: 'Recovery hero + vitals grid + story + drivers',
        change: 'Ring hero, live vitals with sparklines, AI story, recovery drivers, recommendation.',
        interactive: true, swift: 'yes (simplified)' },
      { screen: 'Sleep', route: 'sleep', component: 'Stage-breakdown density lanes + tap-to-compare',
        change: 'Dual Hours/Restorative headline, per-stage density lanes, depth ribbon, compare sheet.',
        interactive: true, swift: 'partial' },
      { screen: 'Heart', route: 'heart', component: 'Live pulse + ECG + zone-shaded day ribbon',
        change: 'Pulsing hero, live ECG trace, day HR with zone bands, time-in-zone, trends.',
        interactive: true, swift: 'partial' },
      { screen: 'Coach', route: 'coach', component: 'Conversational chat + forecast cards',
        change: 'Chat thread with typing, quick prompts, forecast strip and guidance tiles.',
        interactive: true, swift: 'yes (real AI, simplified)' },
      { screen: 'Trends', route: 'trends', component: 'Metric picker + animated charts',
        change: 'Metric-morphing hero chart, range control, period comparison, digest, auto-insight.',
        interactive: true, swift: 'yes' },
      { screen: 'Readiness', route: 'readiness', component: 'Contributors + forecast',
        change: 'Large score, expandable contributors, recovery history and forecast.',
        interactive: true, swift: 'yes' },
      { screen: 'Insights', route: 'insights', component: '“Why, explained” cards',
        change: 'Filterable insight cards, discovered-correlation scatter.',
        interactive: true, swift: 'yes' },
    ]},
    { emoji: '🚧', name: 'Still in progress', tint: 'strain', items: [
      { screen: 'Sleep', component: 'Time-resolved hypnogram in SwiftUI',
        change: 'Native lanes currently show real stage proportions, not true per-minute timing.',
        interactive: false, swift: 'partial' },
      { screen: 'Heart', component: 'ECG trace + zone-shaded ribbon in SwiftUI',
        change: 'Native Heart shows a pulse + real day-HR sparkline; the animated ECG and zone bands are pending.',
        interactive: false, swift: 'partial' },
      { screen: 'Navigation', component: '5-tab native bar (Home·Sleep·Heart·Coach·Trends)',
        change: 'Heart & Coach are reachable via “More” natively; promoting them to tabs is planned (without orphaning other screens).',
        interactive: false, swift: 'no' },
    ]},
    { emoji: '❌', name: 'Not started', tint: 'heart', items: [
      { screen: 'Journal', route: 'journal', component: 'Native Journal on BehaviorStore',
        change: 'Mood/log grid/behaviour toggles exist in HTML; the SwiftUI screen is not built yet.',
        interactive: true, swift: 'no' },
      { screen: 'Settings', route: 'settings', component: 'Native prototype Settings layout',
        change: 'SwiftUI still uses the re-skinned classic Settings; the prototype layout isn’t migrated.',
        interactive: true, swift: 'no' },
      { screen: 'Global', component: 'Native animation parity',
        change: 'Count-ups, chart draw-on, ripples and ambient parallax are HTML-only so far.',
        interactive: false, swift: 'no' },
    ]},
  ];

  const changelog = [
    { m: 1, title: 'Premium HTML prototype', body: 'All nine screens designed and interactive in HTML.' },
    { m: 2, title: 'SwiftUI re-skin + native rebuilds', body: 'Token re-skin, then native Home/Sleep/Heart/Coach/Trends/Readiness/Insights on real data.' },
    { m: 3, title: 'HTML-first workflow', body: 'What’s New, visible version info, CHANGELOG, and the spec-finalisation this screen documents.' },
  ];

  NS.pages.whatsnew = {
    title: 'What’s New', eyebrow: 'Milestone ' + B.milestone, tint: 'gold',
    render() {
      return `
      <section class="ai-card" data-reveal>
        <div class="ai-head"><span class="ai-orb"></span><span class="ai-title">Milestone ${B.milestone}</span></div>
        <p class="ai-body">${B.milestoneName}. This screen is the definitive record of what changed — and what is (and isn’t) in the native iOS build yet.</p>
      </section>

      ${versionCard()}

      ${cats.map(catBlock).join('')}

      <div class="section-title" data-reveal><h2>Changelog</h2><span class="link">CHANGELOG.md</span></div>
      <section class="card" data-reveal>
        <div class="timeline">
          ${changelog.slice().reverse().map((c) => `
            <div class="tl-item" style="--tint:var(--accent-gold)">
              <div class="tl-time">MILESTONE ${c.m}</div>
              <div class="tl-title">${c.title}</div>
              <div class="tl-sub">${c.body}</div>
            </div>`).join('')}
        </div>
      </section>
      <div style="height:8px"></div>`;
    },
    mount(root) {
      // legend key for the migration badges
    },
  };

  function versionCard() {
    return `
    <section class="card" data-reveal style="margin-top:16px">
      <div class="card-head"><h3>NOOP Premium Prototype</h3><span class="tag" style="--tint:var(--accent-gold)">M${B.milestone}</span></div>
      <div class="rows">
        ${vrow('Prototype', B.prototypeVersion)}
        ${vrow('Milestone', String(B.milestone))}
        ${vrow('Commit', B.commit)}
        ${vrow('Build date', B.buildDate)}
        ${vrow('Updated', B.updated)}
        ${vrow('Native app', 'v' + B.appVersion + ' · build ' + B.iosBuild)}
        ${vrow('Bundle id', B.bundleId)}
      </div>
    </section>`;
  }
  function vrow(k, v) {
    return `<div class="row"><div class="r-body"><div class="r-title" style="font-weight:500">${k}</div></div>
      <div class="r-val" style="font-family:var(--font-mono);font-size:13px;color:var(--ink-2)">${v}</div></div>`;
  }

  function catBlock(c) {
    return `
    <div class="section-title" data-reveal><h2>${c.emoji} ${c.name}</h2><span class="link">${c.items.length}</span></div>
    <div class="stack">
      ${c.items.map((it) => itemCard(it, c.tint)).join('')}
    </div>`;
  }
  function itemCard(it, tint) {
    return `
    <div class="card ${it.route ? 'tap' : ''}" data-reveal ${it.route ? `data-route="${it.route}"` : ''} style="--tint:var(--accent-${tint})">
      <div class="wn-head">
        <span class="tag" style="--tint:var(--accent-${tint})">${it.screen}</span>
        <span class="wn-badges">
          ${badge(it.interactive ? 'Interactive' : 'Static', it.interactive ? 'recovery' : 'strain')}
          ${swiftBadge(it.swift)}
        </span>
      </div>
      <div class="wn-comp">${it.component}</div>
      <div class="wn-change">${it.change}</div>
      ${it.route ? `<div class="wn-open">Open ${it.screen} ${icon('chevR', 13)}</div>` : ''}
    </div>`;
  }
  function badge(text, tint) {
    return `<span class="wn-badge" style="--tint:var(--accent-${tint})">${text}</span>`;
  }
  function swiftBadge(state) {
    const map = {
      'yes': ['SwiftUI ✓', 'recovery'], 'yes (simplified)': ['SwiftUI ~', 'gold'],
      'yes (real AI, simplified)': ['SwiftUI ~', 'gold'], 'partial': ['SwiftUI partial', 'strain'],
      'no': ['SwiftUI ✗', 'heart'], 'n/a': ['n/a', 'hrv'],
    };
    const [t, tint] = map[state] || ['SwiftUI ?', 'hrv'];
    return `<span class="wn-badge" style="--tint:var(--accent-${tint})">${t}</span>`;
  }
})(window.NOOP = window.NOOP || {});
