/* ============================================================================
   NOOP · Premium UI — Stress Monitor (CONCEPTUAL — future feature)
   A design-only exploration of a physiological-load view. NOOP does NOT yet
   compute stress; this screen demonstrates the intended shape only. Every label
   makes the "future / preview" status explicit — no algorithm is claimed to exist.
   v3 adds: rest-vs-elevated split, a sleep-vs-awake breakdown, and the
   recovery relationship — closely tied to the Heart tab this links from.
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
      const rve = d.stressRestVsElevated, phase = d.stressByPhase;
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

      <!-- Rest vs elevated -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Rest vs elevated</h2></div>
      <section class="card" data-reveal>
        <div class="bar" style="height:14px;--tint:var(--accent-recovery)"><i style="width:${rve.restPct}%"></i></div>
        <div class="dual" style="margin-top:var(--s-4)">
          <div class="figure"><div class="f-val" style="color:var(--accent-recovery)">${rve.restPct}%</div><div class="f-cap">Rest state</div></div>
          <div class="figure"><div class="f-val" style="color:var(--accent-heart)">${rve.elevatedPct}%</div><div class="f-cap">Elevated</div></div>
        </div>
        <p class="note" style="margin-top:var(--s-3)">The share of today your estimated load spent below vs above your resting baseline.</p>
      </section>

      <!-- By phase: sleep vs awake -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">By phase</h2></div>
      <section class="card" data-reveal>
        <div class="dev-row"><span class="dr-name">Asleep</span>
          <div class="dr-chart bar" style="--tint:var(--accent-sleep)"><i style="width:${phase.sleep/3*100}%"></i></div>
          <span class="dr-val">${phase.sleep.toFixed(1)}</span></div>
        <div class="dev-row"><span class="dr-name">Awake</span>
          <div class="dr-chart bar" style="--tint:var(--accent-gold)"><i style="width:${phase.awake/3*100}%"></i></div>
          <span class="dr-val">${phase.awake.toFixed(1)}</span></div>
        <p class="note" style="margin-top:var(--s-2)">Load is markedly lower overnight, as expected — a sanity check this concept would need to pass consistently before ever shipping as a real signal.</p>
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

      <!-- Recovery relationship -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Recovery relationship</h2></div>
      ${patternCard(d.correlationPairs.find((p) => p.a === 'stress'))}

      <section class="card" data-reveal style="--tint:var(--accent-sleep);margin-top:var(--s-4)">
        <div class="insight-line"><span class="il-ic">${icon('info', 16)}</span>
          <div class="il-body"><b>Concept only.</b> NOOP does not currently calculate a stress score. This screen shows how a future physiological-load view — built from heart rate, HRV and motion — could look, using placeholder data. It is never a medical diagnosis, only an estimated signal.</div></div>
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

  function patternCard(p) {
    if (!p) return '';
    return `<section class="pattern-card" data-reveal style="--tint:var(--accent-${p.tint})">
      <span class="glyph tint">${icon('insight', 16)}</span>
      <div class="pc-body">
        <div class="pc-head"><span class="pc-title">${p.an} ↔ ${p.bn}</span>
          <span class="conf-tag ${p.confidence}"><i></i>${confLabel(p.confidence)}</span></div>
        <div class="pc-text">${p.note}</div>
        <div class="pc-meta">r = ${p.r.toFixed(2)} · concept-only estimate, not a validated signal</div>
      </div>
    </section>`;
  }
  function confLabel(c) { return ({ early: 'Early signal', emerging: 'Emerging pattern', consistent: 'Consistent pattern' })[c] || c; }
})(window.NOOP = window.NOOP || {});
