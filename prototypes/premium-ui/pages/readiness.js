/* ============================================================================
   NOOP · Premium UI — Recovery (v2, expanded)
   The readiness score, then the WHY: each contributor (HRV, Resting HR, Sleep,
   Respiratory) with its share of the score, its value, direction and reason —
   every one tappable into the reusable Metric Detail. Plus the recent baseline,
   a 7-day and 30-day trend, and a plain-language "why today changed" summary.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  NS.pages.readiness = {
    title: 'Recovery', eyebrow: 'Readiness · today', tint: 'recovery',
    render() {
      const d = data;
      const band = d.band(d.recovery);
      const label = band === 'high' ? 'Recovered' : band === 'mid' ? 'Moderate' : 'Low';
      const base7 = Math.round(d.mean(d.recSeries.slice(-7)));
      return `
      <section class="home-hero" data-reveal>
        <div class="hero-glow" style="--g:var(--accent-recovery)"></div>
        <div class="hero-rings">${ui.ring({ value: d.recovery, size: 216, stroke: 15, tint: 'recovery', unit: '%', cap: label, numFs: 64 })}</div>
      </section>

      <section class="card" data-reveal style="--tint:var(--accent-recovery)">
        <div class="insight-line"><span class="il-ic">${icon('sparkles',16)}</span>
          <div class="il-body">You're <b>${d.recovery}% recovered</b> — in the green. HRV led the way (12% above baseline) while sleep held steady. Your body can take on a strain of 14–16 today without denting tomorrow.</div></div>
      </section>

      <!-- Why: contributions -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Why today's recovery</h2><span class="link">Tap to explore</span></div>
      <section class="card" data-reveal>
        ${d.recoveryContribs.map((c) => `
          <div class="contrib2" data-open-metric="${c.key}" style="--tint:var(--accent-${c.tint});cursor:pointer">
            <div class="c2-name"><span class="cg">${icon(metricIcon(c.key),16)}</span>${c.name}
              <span class="tchip ${c.dir==='up'?'pos':c.dir==='down'?'neg':''}" style="margin-left:4px">${c.share}%</span></div>
            <div class="c2-val">${c.value}<small>${c.unit?' '+c.unit:''}</small> ${icon('chevR',14)}</div>
            <div class="c2-bar bar" style="--tint:var(--accent-${c.tint})"><i style="width:${c.share/38*100}%"></i></div>
            <div class="c2-note">${c.note}</div>
          </div>`).join('')}
      </section>

      <!-- Baseline + trend -->
      <div class="dual" data-reveal style="margin-top:var(--s-4)">
        <section class="card"><div class="figure"><div class="f-val">${base7}%</div><div class="f-cap">7-day baseline</div>
          <div class="f-sub">${d.recovery - base7 >= 0 ? '+' : ''}${d.recovery - base7} pts today</div></div></section>
        <section class="card"><div class="figure"><div class="f-val">5</div><div class="f-cap">Green streak</div>
          <div class="f-sub">days recovered ≥ 67%</div></div></section>
      </div>

      <div class="section-title" data-reveal><h2 style="font-size:19px">30-day recovery</h2></div>
      <section class="card" data-reveal>
        <div class="chart" style="height:180px"><canvas data-rec-chart></canvas></div>
        <div class="axis"><span>30d</span><span>20d</span><span>10d</span><span>today</span></div>
        <div class="stat3" style="margin-top:var(--s-4)">
          ${statBlk('Average', Math.round(d.mean(d.recSeries)) + '%')}
          ${statBlk('Lowest', Math.min(...d.recSeries) + '%')}
          ${statBlk('Highest', Math.max(...d.recSeries) + '%')}
        </div>
      </section>

      <div class="section-title" data-reveal><h2 style="font-size:19px">What moved it</h2></div>
      <section class="card" data-reveal>
        <div class="kv"><span class="k">${gi('arrowUp','hrv')} Earlier bedtime</span><span class="v" style="color:var(--band-high)">+6%</span></div>
        <div class="kv"><span class="k">${gi('arrowUp','recovery')} Cool sleeping room</span><span class="v" style="color:var(--band-high)">+4%</span></div>
        <div class="kv"><span class="k">${gi('arrowDn','gold')} Skin temp +0.3°C</span><span class="v" style="color:var(--band-low)">−2%</span></div>
        <div class="kv"><span class="k">${gi('arrowDn','strain')} Prior-day strain 15.1</span><span class="v" style="color:var(--band-low)">−3%</span></div>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      const d = data;
      const cv = ui.$('[data-rec-chart]', root);
      if (cv) charts.area(cv, d.recSeries, { color: 'recovery', height: 180, min: 20, max: 100, fmt: (v) => Math.round(v) + '%' });
      ui.$$('[data-open-metric]', root).forEach((el) => el.addEventListener('click', (e) => { ui.ripple(e, el); NS.openMetric(el.dataset.openMetric); }));
    },
  };

  function metricIcon(k) { return ({ hrv: 'hrv', rhr: 'heart', sleep: 'moon', respiratory: 'lungs' })[k] || 'dot'; }
  function gi(name, tint) { return `<span class="kg" style="--tint:var(--accent-${tint})">${icon(name, 16)}</span>`; }
  function statBlk(cap, val) { return `<div class="stat-blk"><div class="sb-cap">${cap}</div><div class="sb-val">${val}</div></div>`; }
})(window.NOOP = window.NOOP || {});
