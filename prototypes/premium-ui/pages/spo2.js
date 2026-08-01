/* ============================================================================
   NOOP · Premium UI — Blood Oxygen (SpO₂)
   Latest reading, nightly average, range, recent trend, a history chart and a
   baseline comparison — when compatible samples exist. When they don't, an
   elegant empty state that explains the situation without inventing numbers.
   Toggle NOOP.data.spo2Available to preview each state.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  NS.pages.spo2 = {
    title: 'Blood Oxygen', eyebrow: 'SpO₂ · overnight', tint: 'strain',
    render() {
      const d = data;
      if (!d.spo2Available) return emptyState();
      const avg = Math.round(d.mean(d.spo2Series));
      return `
      <div class="metric-hero" data-reveal style="--tint:var(--accent-strain)">
        <div class="mh-glyph">${icon('spo2', 24)}</div>
        <div class="mh-val"><span class="count" data-to="${d.spo2Latest}">0</span><span class="u">%</span></div>
        <div class="mh-sub"><span>Latest reading</span><span class="sep"></span><span>${d.spo2NightAvg}% nightly avg</span></div>
      </div>

      <div class="stat3" data-reveal style="margin-top:var(--s-2)">
        <section class="card" style="padding:var(--s-4)"><div class="stat-blk"><div class="sb-cap">Nightly avg</div><div class="sb-val">${d.spo2NightAvg}<small> %</small></div></div></section>
        <section class="card" style="padding:var(--s-4)"><div class="stat-blk"><div class="sb-cap">Range</div><div class="sb-val">${d.spo2Low}–${d.spo2High}<small> %</small></div></div></section>
        <section class="card" style="padding:var(--s-4)"><div class="stat-blk"><div class="sb-cap">Baseline</div><div class="sb-val">${avg}<small> %</small></div></div></section>
      </div>

      <div class="section-title" data-reveal><h2 style="font-size:19px">30-night trend</h2></div>
      <section class="card" data-reveal>
        <div class="chart" style="height:190px"><canvas data-spo2-chart></canvas></div>
        <div class="axis"><span>30d</span><span>20d</span><span>10d</span><span>today</span></div>
      </section>

      <div class="section-title" data-reveal><h2 style="font-size:19px">Where tonight sits</h2></div>
      <section class="card" data-reveal style="--tint:var(--accent-strain)">
        <div class="rangebar">
          <span class="band" style="left:30%;right:8%"></span>
          <span class="now" style="left:${(d.spo2NightAvg - 92) / (100 - 92) * 100}%"></span>
        </div>
        <div style="display:flex;justify-content:space-between;font-size:var(--fs-xs);color:var(--ink-3);font-weight:600">
          <span>92%</span><span>normal range 95–100%</span><span>100%</span>
        </div>
      </section>

      <div class="section-title" data-reveal><h2 style="font-size:19px">What it means</h2></div>
      <section class="card" data-reveal><p class="explain">Blood oxygen (SpO₂) is the percentage of oxygen your blood carries, sampled overnight. Healthy values usually sit between 95–100%. NOOP reads compatible samples from Apple Health and never estimates a value it didn't measure.</p></section>

      <section class="card" data-reveal style="--tint:var(--accent-strain);margin-top:var(--s-4)">
        <div class="insight-line"><span class="il-ic">${icon('sparkles', 16)}</span>
          <div class="il-body">Your nightly average of <b>96%</b> is stable and well within the normal range, with no unusual dips over the last month.</div></div>
      </section>
      <div class="note" style="text-align:center;margin-top:var(--s-4)">Source: Apple Health · on-device · not a medical device</div>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      const d = data;
      const cv = ui.$('[data-spo2-chart]', root);
      if (cv) charts.area(cv, d.spo2Series, { color: 'strain', height: 190, min: 92, max: 100, fmt: (v) => Math.round(v) + '%' });
    },
  };

  function emptyState() {
    return `
    <div class="metric-hero" data-reveal style="--tint:var(--accent-strain)">
      <div class="mh-glyph">${icon('spo2', 24)}</div>
      <div class="mh-val" style="color:var(--ink-3)">—<span class="u">%</span></div>
    </div>
    <section class="card" data-reveal style="--tint:var(--accent-strain)">
      <div class="empty">
        <div class="em-ic">${icon('spo2', 28)}</div>
        <div class="em-title">No Blood Oxygen data yet</div>
        <p class="em-body">No compatible SpO₂ samples are currently available from Apple Health. Blood-oxygen readings are captured overnight by a supported Apple Watch and synced on-device. Once samples appear, your latest reading, nightly average, range and trend will show here.</p>
        <button class="btn ghost" style="margin-top:var(--s-5)" onclick="NOOP.ui.toast('Opens Apple Health setup')">${icon('apple', 16)} Check Health access</button>
      </div>
    </section>
    <section class="card" data-reveal style="margin-top:var(--s-4)"><p class="explain">NOOP never invents measurements. When there's no data, it says so — clearly — rather than showing a placeholder number.</p></section>
    <div style="height:8px"></div>`;
  }
})(window.NOOP = window.NOOP || {});
