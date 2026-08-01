/* ============================================================================
   NOOP · Premium UI — More
   The 6th tab: everything the primary five don't surface. Grouped tiles into the
   detail screens (Recovery, Strain, Energy, Blood Oxygen, Stress, Trends) plus
   data/journal/settings entries. Keeps the bottom nav to a clean five + More.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, icon } = NS;

  const GROUPS = [
    { title: 'Body', tiles: [
      { name: 'Recovery', sub: 'Readiness & why', ic: 'recovery', tint: 'recovery', route: 'readiness' },
      { name: 'Day Strain', sub: 'Activity & zones', ic: 'strain', tint: 'strain', route: 'strain' },
      { name: 'Energy', sub: 'Calories', ic: 'flame', tint: 'flame', route: 'energy' },
      { name: 'Blood Oxygen', sub: 'SpO₂', ic: 'spo2', tint: 'strain', route: 'spo2' },
      { name: 'Stress', sub: 'Preview', ic: 'stress', tint: 'gold', route: 'stress' },
      { name: 'Trends', sub: 'Explore signals', ic: 'trends', tint: 'hrv', route: 'trends' },
    ]},
    { title: 'Metrics', tiles: [
      { name: 'HRV', sub: '', ic: 'hrv', tint: 'hrv', metric: 'hrv' },
      { name: 'Resting HR', sub: '', ic: 'heart', tint: 'heart', metric: 'rhr' },
      { name: 'Respiratory', sub: '', ic: 'lungs', tint: 'recovery', metric: 'respiratory' },
      { name: 'Steps', sub: '', ic: 'steps', tint: 'recovery', metric: 'steps' },
    ]},
    { title: 'App', tiles: [
      { name: 'Journal', sub: 'Behaviours', ic: 'book', tint: 'gold', route: 'journal' },
      { name: 'Insights', sub: 'What moves you', ic: 'insight', tint: 'recovery', route: 'insights' },
      { name: "What's New", sub: 'Milestone', ic: 'sparkles', tint: 'sleep', route: 'whatsnew' },
      { name: 'Settings', sub: 'On-device', ic: 'gear', tint: 'gold', route: 'settings' },
    ]},
  ];

  NS.pages.more = {
    title: 'More', eyebrow: 'Everything else', tint: 'sleep',
    render() {
      const brand = `
        <section class="card" data-reveal style="margin-top:var(--s-2)">
          <div class="brand-card">
            <span class="bl-mark" style="line-height:0">${NS.appIcon(52)}</span>
            <div style="flex:1"><div class="bc-name">NOOP</div><div class="bc-sub">Offline · on-device · v9.1.3</div></div>
            <span class="data-badge"><span class="lv"></span>All local</span>
          </div>
        </section>`;
      return brand + GROUPS.map((g) => `
        <div class="section-title" data-reveal><h2 style="font-size:19px">${g.title}</h2></div>
        <div class="more-grid" data-reveal>
          ${g.tiles.map((t) => `
            <div class="more-tile" ${t.route ? `data-route="${t.route}"` : `data-open-metric="${t.metric}"`} style="--tint:var(--accent-${t.tint})">
              <span class="glyph tint" style="--tint:var(--accent-${t.tint})">${icon(t.ic, 18)}</span>
              <div><div class="mt-name">${t.name}</div>${t.sub ? `<div class="mt-sub">${t.sub}</div>` : ''}</div>
            </div>`).join('')}
        </div>`).join('') + '<div style="height:8px"></div>';
    },
    mount(root) {
      ui.$$('[data-open-metric]', root).forEach((el) => el.addEventListener('click', (e) => { ui.ripple(e, el); NS.openMetric(el.dataset.openMetric); }));
    },
  };
})(window.NOOP = window.NOOP || {});
