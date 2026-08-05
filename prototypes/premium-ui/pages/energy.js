/* ============================================================================
   NOOP · Premium UI — Energy / Calories
   Active + Resting + Total energy (from HealthKit conceptually), the calories
   accumulated across the day, a weekly comparison, the daily average, and the
   activity sources that drove today's active burn. Total is shown only because
   both Active and Resting are available to sum correctly.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  NS.pages.energy = {
    title: 'Energy', eyebrow: 'Calories · today', tint: 'flame',
    render() {
      const d = data;
      const activePct = Math.round(d.activeKcal / d.totalKcal * 100);
      const avgActive = d.baselines.active;
      const vsAvg = Math.round((d.activeKcal - avgActive) / avgActive * 100);
      const sign = vsAvg >= 0 ? '+' : '';
      return `
      <!-- Total + split -->
      <section class="card" data-reveal style="--tint:var(--accent-flame)">
        <div class="energy-row">
          <div class="ring-wrap-sm" style="position:relative">
            ${ui.ring({ value: activePct, size: 128, stroke: 12, tint: 'flame', unit: '%', cap: 'Active', numFs: 30 })}
          </div>
          <div class="energy-legend">
            <div class="el-item"><span class="el-dot" style="--k:var(--accent-flame)"></span>
              <span class="el-name">Active</span><span class="el-val"><span class="count" data-to="${d.activeKcal}">0</span><small> kcal</small></span></div>
            <div class="el-item"><span class="el-dot" style="--k:var(--accent-hrv)"></span>
              <span class="el-name">Resting</span><span class="el-val"><span class="count" data-to="${d.restingKcal}">0</span><small> kcal</small></span></div>
            <div class="el-item" style="border-top:1px solid var(--hairline);padding-top:12px;margin-top:2px">
              <span class="el-dot" style="--k:var(--ink-1)"></span>
              <span class="el-name" style="color:var(--ink-1);font-weight:700">Total</span>
              <span class="el-val" style="font-size:18px"><span class="count" data-to="${d.totalKcal}">0</span><small> kcal</small></span></div>
          </div>
        </div>
      </section>

      <div class="dual" data-reveal style="margin-top:var(--s-4)">
        <section class="card"><div class="figure"><div class="f-val">${sign}${vsAvg}%</div><div class="f-cap">vs typical day</div>
          <div class="f-sub">avg ${avgActive} kcal active</div></div></section>
        <section class="card"><div class="figure"><div class="f-val">${d.exerciseMin}<small style="font-size:15px;color:var(--ink-3)"> min</small></div>
          <div class="f-cap">Exercise</div><div class="f-sub">${d.distanceKm} km · ${d.flights} flights</div></div></section>
      </div>

      <!-- Calories through the day -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Active energy today</h2><span class="link">Cumulative</span></div>
      <section class="card" data-reveal>
        <div class="chart" style="height:190px"><canvas data-cal-day></canvas></div>
        <div class="axis"><span>12a</span><span>6a</span><span>12p</span><span>6p</span><span>now</span></div>
      </section>

      <!-- Weekly comparison -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">This week</h2><span class="link">Active kcal</span></div>
      <section class="card" data-reveal>
        <div class="chart" style="height:150px"><canvas data-cal-week></canvas></div>
        <div class="axis" data-week-axis></div>
      </section>

      <!-- Activity contribution -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">What burned it</h2></div>
      <section class="card" data-reveal>
        ${d.activitySplit.map((a) => `
          <div class="contrib2" style="--tint:var(--accent-${a.tint})">
            <div class="c2-name"><span class="cg">${icon(a.icon, 16)}</span>${a.label}</div>
            <div class="c2-val">${a.kcal}<small> kcal</small></div>
            <div class="c2-bar bar" style="--tint:var(--accent-${a.tint})"><i style="width:${a.kcal / d.activeKcal * 100}%"></i></div>
          </div>`).join('')}
      </section>

      <section class="card" data-reveal style="--tint:var(--accent-flame);margin-top:var(--s-4)">
        <div class="insight-line"><span class="il-ic">${icon('sparkles', 16)}</span>
          <div class="il-body">Your active burn is <b>${Math.abs(vsAvg)}% ${vsAvg >= 0 ? 'above' : 'below'}</b> a typical Thursday, driven mostly by the midday tempo run. Resting energy is estimated from your profile and heart rate.</div></div>
      </section>
      <div class="note" style="text-align:center;margin-top:var(--s-4)">Energy data comes from Apple Health · on-device</div>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      const d = data;
      const day = ui.$('[data-cal-day]', root);
      if (day) charts.area(day, d.calDayCurve(), { color: 'flame', height: 190, min: 0, fmt: (v) => Math.round(v) + ' kcal' });
      const wk = ui.$('[data-cal-week]', root);
      if (wk) {
        const vals = d.activeSeries.slice(-7);
        charts.bars(wk, vals, { color: 'flame', height: 150, highlight: vals.length - 1, min: 0,
          labels: d.DAYS.map((x, i) => d.DAYS[(i + 1) % 7]), fmt: (v) => Math.round(v) + ' kcal' });
        ui.$('[data-week-axis]', root).innerHTML = ['Fri','Sat','Sun','Mon','Tue','Wed','Thu'].map((x) => `<span>${x}</span>`).join('');
      }
    },
  };
})(window.NOOP = window.NOOP || {});
