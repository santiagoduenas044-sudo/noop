/* ============================================================================
   NOOP · Premium UI — Stress Monitor (CONCEPTUAL — future feature)
   A design-only exploration of a physiological-load view. NOOP does NOT yet
   compute stress; this screen demonstrates the intended shape only. Every label
   makes the "future / preview" status explicit — no algorithm is claimed to exist.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  const zoneColor = (v) => v < 1 ? 'var(--accent-recovery)' : v < 2 ? 'var(--band-mid)' : 'var(--accent-heart)';
  const zoneName = (v) => v < 1 ? 'Low' : v < 2 ? 'Medium' : 'High';

  NS.pages.stress = {
    title: 'Stress', eyebrow: 'Preview · concept', tint: 'gold',
    render() {
      const d = data;
      const now = d.stressNow, dist = d.stressDist;
      return `
      <div style="text-align:center;margin:var(--s-2) 0 var(--s-4)" data-reveal>
        <span class="future-tag">Future feature · preview</span>
      </div>

      <section class="home-hero" data-reveal>
        <div class="hero-glow" style="--g:${zoneColor(now)}"></div>
        <div class="hero-rings">${ui.ring({ value: now, max: 3, size: 208, stroke: 14, tint: 'gold', unit: '', cap: zoneName(now) + ' · of 3.0', numFs: 58 })}</div>
      </section>

      <!-- Daily timeline -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Today</h2><span class="link">Physiological load</span></div>
      <section class="card" data-reveal>
        <div class="stress-track" data-stress-track></div>
        <div class="axis" style="margin-top:8px"><span>12a</span><span>6a</span><span>12p</span><span>6p</span><span>now</span></div>
        <div class="stress-scale">
          <span class="ss-k"><i style="background:var(--accent-recovery)"></i>Low</span>
          <span class="ss-k"><i style="background:var(--band-mid)"></i>Medium</span>
          <span class="ss-k"><i style="background:var(--accent-heart)"></i>High</span>
          <span class="ss-k" style="margin-left:auto"><i style="background:var(--accent-sleep)"></i>Asleep</span>
        </div>
      </section>

      <!-- Distribution -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Daily distribution</h2></div>
      <section class="card" data-reveal>
        <div class="stress-dist">
          <span style="width:${dist.low}%;background:var(--accent-recovery)"></span>
          <span style="width:${dist.medium}%;background:var(--band-mid)"></span>
          <span style="width:${dist.high}%;background:var(--accent-heart)"></span>
        </div>
        <div class="dual" style="margin-top:var(--s-4)">
          <div class="figure"><div class="f-val" style="color:var(--accent-recovery)">${dist.low}%</div><div class="f-cap">Low</div></div>
          <div class="figure"><div class="f-val" style="color:var(--accent-heart)">${dist.high}%</div><div class="f-cap">High</div></div>
        </div>
      </section>

      <!-- Trend -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">14-day trend</h2></div>
      <section class="card" data-reveal>
        <div class="chart" style="height:150px"><canvas data-stress-trend></canvas></div>
      </section>

      <section class="card" data-reveal style="--tint:var(--accent-sleep);margin-top:var(--s-4)">
        <div class="insight-line"><span class="il-ic">${icon('info', 16)}</span>
          <div class="il-body"><b>Concept only.</b> NOOP does not currently calculate a stress score. This screen shows how a future physiological-load view could look, using placeholder data — no algorithm is running.</div></div>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      const d = data;
      const track = ui.$('[data-stress-track]', root);
      if (track) {
        const vals = d.stressDay();
        track.innerHTML = vals.map((v, i) => {
          const asleep = (i / 4) < 6.5;
          const col = asleep ? 'var(--accent-sleep)' : zoneColor(v);
          const hpct = asleep ? 22 : Math.max(10, v / 3 * 100);
          return `<span class="stk" style="height:${hpct}%;background:${col};animation-delay:${i * 6}ms"></span>`;
        }).join('');
      }
      const tr = ui.$('[data-stress-trend]', root);
      if (tr) charts.area(tr, d.stressSeries, { color: 'gold', height: 150, min: 0, max: 3, fmt: (v) => v.toFixed(1) });
    },
  };
})(window.NOOP = window.NOOP || {});
