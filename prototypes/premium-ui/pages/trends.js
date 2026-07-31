/* ============================================================================
   NOOP · Premium UI — Trends
   Multiple animated graphs over week / month / year, a period comparison, and
   auto-surfaced insights. A metric picker morphs the hero chart in place.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  const metrics = [
    { key: 'recovery', label: 'Recovery', unit: '%', tint: 'recovery', series: 'recSeries' },
    { key: 'hrv', label: 'HRV', unit: 'ms', tint: 'hrv', series: 'hrvSeries' },
    { key: 'strain', label: 'Strain', unit: '', tint: 'strain', series: 'strainSeries' },
    { key: 'sleep', label: 'Sleep', unit: '%', tint: 'sleep', series: 'sleepSeries' },
    { key: 'rhr', label: 'Rest HR', unit: 'bpm', tint: 'heart', series: 'rhrSeries' },
  ];

  NS.pages.trends = {
    title: 'Trends', eyebrow: 'Your long game', tint: 'strain',
    render() {
      return `
      <!-- Metric picker -->
      <section data-reveal>
        <div class="chip-row metric-picker" data-metrics>
          ${metrics.map((m, i) => `<button class="chip ${i===0?'on':''}" data-metric="${m.key}" style="--tint:var(--accent-${m.tint})"><span class="swatch"></span>${m.label}</button>`).join('')}
        </div>
      </section>

      <!-- Hero chart -->
      <section class="card" data-reveal style="margin-top:14px">
        <div class="trend-head">
          <div class="metric"><div class="value" style="font-size:40px"><span data-hero-val>—</span><span class="unit" data-hero-unit></span></div>
            <div class="label" data-hero-label>30-day average</div></div>
          <span class="delta up" data-hero-delta>—</span>
        </div>
        <div class="segment" data-seg style="margin:14px 0 4px"><button data-value="7">Week</button><button class="active" data-value="30">Month</button><button data-value="90">Year</button></div>
        <div class="chart" style="margin-top:8px"><canvas data-hero-chart></canvas></div>
        <div class="axis" data-hero-axis></div>
      </section>

      <!-- Compare periods -->
      <div class="section-title" data-reveal><h2>This month vs last</h2></div>
      <section class="card" data-reveal>
        <div class="legend" style="margin-bottom:10px">
          <span class="k" style="--k:var(--accent-recovery)"><i></i>This month</span>
          <span class="k" style="--k:var(--ink-4)"><i></i>Last month</span>
        </div>
        <div class="chart"><canvas data-compare></canvas></div>
        <div class="axis"><span>Wk 1</span><span>Wk 2</span><span>Wk 3</span><span>Wk 4</span></div>
      </section>

      <!-- Weekly digest tiles -->
      <div class="section-title" data-reveal><h2>Weekly digest</h2></div>
      <div class="grid-2" data-reveal>
        ${digest('Best recovery', 'Wednesday', '99%', 'recovery', 'up')}
        ${digest('Highest strain', 'Saturday', '18.2', 'strain', 'up')}
        ${digest('Best sleep', 'Monday', '96%', 'sleep', 'up')}
        ${digest('Avg HRV', '7-day', '92 ms', 'hrv', 'up')}
      </div>

      <!-- Auto insights -->
      <div class="section-title" data-reveal><h2>What we noticed</h2><span class="link" data-route="insights">More ›</span></div>
      <div class="stack">
        ${autoInsight('Recovery is trending up', 'Your 7-day average recovery rose 8 points. Consistent sleep timing is the strongest driver.', 'recovery')}
        ${autoInsight('Strain is well balanced', 'You alternated hard and easy days 5 of 7 times — an ideal build pattern.', 'strain')}
      </div>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      let active = metrics[0];
      let range = 30;

      const cv = ui.$('[data-hero-chart]', root);
      const axis = ui.$('[data-hero-axis]', root);
      const valEl = ui.$('[data-hero-val]', root);
      const unitEl = ui.$('[data-hero-unit]', root);
      const deltaEl = ui.$('[data-hero-delta]', root);
      const labelEl = ui.$('[data-hero-label]', root);

      const drawHero = () => {
        const s = data[active.series].slice(-range);
        const useBars = active.key === 'strain';
        cv.parentElement.querySelector('.chart-tip')?.remove();
        cv._overlay?.remove(); cv._overlay = null;
        if (useBars) charts.bars(cv, s, { color: active.tint, height: 190, min: 0,
          highlight: s.length - 1, labels: s.map((_, i) => lab(i, range)), fmt: (v) => v });
        else charts.area(cv, s, { color: active.tint, height: 190,
          labels: s.map((_, i) => lab(i, range)), fmt: (v) => v + (active.unit ? ' ' + active.unit : '') });
        const avg = s.reduce((a, b) => a + b, 0) / s.length;
        valEl.textContent = active.unit === 'ms' || active.key === 'rhr' ? Math.round(avg) : (active.key === 'strain' ? avg.toFixed(1) : Math.round(avg));
        unitEl.textContent = active.unit ? ' ' + active.unit : '';
        labelEl.textContent = (range === 7 ? '7-day' : range === 30 ? '30-day' : 'Yearly') + ' average';
        const first = s.slice(0, Math.ceil(s.length/2)).reduce((a,b)=>a+b,0);
        const last = s.slice(Math.ceil(s.length/2)).reduce((a,b)=>a+b,0);
        const up = last >= first;
        const better = active.key === 'rhr' ? !up : up;
        deltaEl.className = 'delta ' + (better ? 'up' : 'down');
        deltaEl.innerHTML = `${icon(up ? 'arrowUp' : 'arrowDn', 12)} ${up ? 'Rising' : 'Easing'}`;
        axis.innerHTML = axisFor(range);
      };

      drawHero();
      ui.initSegments(root, (i, v) => { range = +v; drawHero(); });
      ui.$$('[data-metric]', root).forEach((b) => b.addEventListener('click', (e) => {
        ui.$$('[data-metric]', root).forEach((x) => x.classList.remove('on'));
        b.classList.add('on'); ui.ripple(e, b);
        active = metrics.find((m) => m.key === b.dataset.metric);
        drawHero();
      }));

      // compare chart: this month vs last (two overlaid areas via separate canvases trick)
      const comp = ui.$('[data-compare]', root);
      if (comp) drawCompare(comp);
    },
  };

  function drawCompare(cv) {
    const thisM = [72, 78, 81, 84];
    // draw ghost line first (last month) then this month over it
    charts.area(cv, [64, 70, 69, 74], { color: 'strain', height: 150, min: 55, max: 100,
      fill: false, glow: false, interactive: false, grid: true });
    // overlay this month after a tick so the animation of the second reads
    setTimeout(() => {
      const overlay = document.createElement('canvas');
      overlay.style.cssText = 'position:absolute;inset:0';
      cv.parentElement.appendChild(overlay);
      overlay.className = 'cmp-top';
      charts.area(overlay, thisM, { color: 'recovery', height: 150, min: 55, max: 100,
        labels: ['Wk 1','Wk 2','Wk 3','Wk 4'], fmt: (v) => v + '%' });
    }, 120);
  }

  function digest(label, when, val, tint, dir) {
    return `<div class="card mini" data-reveal style="--tint:var(--accent-${tint})">
      <div class="card-head"><span class="eyebrow">${label}</span><span class="delta ${dir}">${icon(dir==='up'?'arrowUp':'arrowDn',11)}</span></div>
      <div class="metric" style="margin-top:6px"><div class="value" style="font-size:26px">${val}</div><div class="label">${when}</div></div></div>`;
  }
  function autoInsight(title, body, tint) {
    return `<div class="card tap" data-reveal data-route="insights" style="--tint:var(--accent-${tint})">
      <div class="ai-mini"><span class="glyph tint">${icon('sparkles',16)}</span>
        <div><div class="ai-mini-title">${title}</div><div class="ai-mini-body">${body}</div></div>
        <span class="chev">${icon('chevR',16)}</span></div></div>`;
  }
  function lab(i, n){ return n === 7 ? data.DAYS[i] : '−' + (n - 1 - i) + 'd'; }
  function axisFor(n){ const l = n===7?data.DAYS:(n===30?['30d','20d','10d','today']:['Q1','Q2','Q3','now']);
    return l.map((x)=>`<span>${x}</span>`).join(''); }
})(window.NOOP = window.NOOP || {});
