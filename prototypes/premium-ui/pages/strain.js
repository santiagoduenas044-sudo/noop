/* ============================================================================
   NOOP · Premium UI — Day Strain / Activity
   Current strain against a suggested range, the day's activity (active calories,
   steps, exercise minutes, workouts), a heart-rate-zone breakdown, the day's
   heart-rate timeline, and a weekly strain trend.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  NS.pages.strain = {
    title: 'Day Strain', eyebrow: 'Activity · today', tint: 'strain',
    render() {
      const d = data;
      return `
      <section class="home-hero" data-reveal>
        <div class="hero-glow" style="--g:var(--accent-strain)"></div>
        <div class="hero-rings">${ui.ring({ value: d.strain, max: 21, size: 216, stroke: 15, tint: 'strain', unit: '', cap: 'of 21 · Day Strain', numFs: 60 })}</div>
      </section>

      <section class="card" data-reveal style="--tint:var(--accent-strain)">
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px">
          <span class="eyebrow">Suggested range</span><span class="tnum" style="color:var(--accent-strain)">12.0 – 16.0</span>
        </div>
        <div class="rangebar" style="--tint:var(--accent-strain)">
          <span class="band" style="left:${12/21*100}%;right:${(21-16)/21*100}%"></span>
          <span class="now" style="left:${d.strain/21*100}%"></span>
        </div>
        <p class="note" style="margin-top:10px">You're below your target band — there's room for a Zone 2 aerobic block without cutting into tomorrow's recovery.</p>
      </section>

      <!-- Activity tiles -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Today's activity</h2></div>
      <div class="stat3 c4" data-reveal>
        ${actTile('flame','flame', d.activeKcal, 'kcal', 'energy')}
        ${actTile('steps','recovery', (d.stepsToday/1000).toFixed(1)+'k', 'steps', null,'steps')}
        ${actTile('timer','strain', d.exerciseMin, 'min', null)}
        ${actTile('run','heart', d.workouts.length, 'workout', null)}
      </div>

      <!-- HR zones -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Heart-rate zones</h2><span class="link">Time in zone</span></div>
      <section class="card" data-reveal>
        <div class="zones">
          ${d.hrZones.map((z) => `
            <div class="zone" style="--tint:var(--accent-${z.color})">
              <span class="z-name">${z.name}<small>${z.sub} bpm</small></span>
              <div class="bar" style="--tint:var(--accent-${z.color})"><i data-w="${Math.min(100, z.minutes / 90 * 100)}"></i></div>
              <span class="z-time">${fmtDur(z.minutes)}</span>
            </div>`).join('')}
        </div>
      </section>

      <!-- Day HR timeline -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Heart rate today</h2></div>
      <section class="card" data-reveal>
        <div class="chart" style="height:200px"><canvas data-hr-day></canvas></div>
        <div class="axis"><span>12a</span><span>6a</span><span>12p</span><span>6p</span><span>now</span></div>
      </section>

      <!-- Workouts -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Workouts</h2></div>
      <section class="card" data-reveal>
        ${d.workouts.map((w) => `
          <div class="row" style="--tint:var(--accent-${w.tint})">
            <span class="glyph tint" style="--tint:var(--accent-${w.tint})">${icon(w.icon, 18)}</span>
            <div class="r-body"><div class="r-title">${w.name}</div>
              <div class="r-sub">${w.time} · ${w.dur} min · avg ${w.avgHr} · peak ${w.peakHr} bpm</div></div>
            <div class="r-val">${w.strain}<small> strain</small></div>
          </div>`).join('')}
      </section>

      <!-- Weekly strain -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">This week's strain</h2></div>
      <section class="card" data-reveal>
        <div class="chart" style="height:150px"><canvas data-strain-week></canvas></div>
        <div class="axis" data-strain-axis></div>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      const d = data;
      ui.$$('[data-w]', root).forEach((i) => requestAnimationFrame(() => { i.style.width = i.dataset.w + '%'; }));
      ui.$$('[data-open]', root).forEach((el) => el.addEventListener('click', (e) => {
        ui.ripple(e, el); const t = el.dataset.open;
        if (t === 'energy') NS.router.go('energy'); else if (t) NS.openMetric(t);
      }));
      const hr = ui.$('[data-hr-day]', root);
      if (hr) charts.heartDay(hr, d.dayHR().filter((_, i) => i % 3 === 0), { height: 200 });
      const wk = ui.$('[data-strain-week]', root);
      if (wk) {
        const vals = d.strainSeries.slice(-7);
        charts.bars(wk, vals, { color: 'strain', height: 150, highlight: 6, min: 0, max: 21, labels: ['Fri','Sat','Sun','Mon','Tue','Wed','Thu'], fmt: (v) => v.toFixed(1) });
        ui.$('[data-strain-axis]', root).innerHTML = ['Fri','Sat','Sun','Mon','Tue','Wed','Thu'].map((x) => `<span>${x}</span>`).join('');
      }
    },
  };

  function actTile(ic, tint, val, unit, route, metric) {
    const attr = route ? `data-open="${route}"` : metric ? `data-open="${metric}"` : '';
    return `<section class="card" style="padding:var(--s-4);--tint:var(--accent-${tint});${(route||metric)?'cursor:pointer':''}" ${attr}>
      <span class="glyph tint" style="width:30px;height:30px;border-radius:9px;--tint:var(--accent-${tint})">${icon(ic, 16)}</span>
      <div class="sb-val" style="margin-top:10px;font-size:19px">${val}</div>
      <div class="sb-cap">${unit}</div></section>`;
  }
  function fmtDur(m) { const h = Math.floor(m / 60), mm = m % 60; return h ? `${h}h ${mm}m` : `${mm}m`; }
})(window.NOOP = window.NOOP || {});
