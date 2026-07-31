/* ============================================================================
   NOOP · Premium UI — Readiness / Recovery
   A large premium readiness score, a plain-language explanation, every
   contributor with its bar, a 30-day recovery history, and a 3-day forecast.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  NS.pages.readiness = {
    title: 'Readiness', eyebrow: 'Recovery', tint: 'recovery',
    render() {
      const d = data, band = d.band(d.recovery);
      const word = band === 'high' ? 'primed to perform' : band === 'mid' ? 'ready with care' : 'in need of rest';
      return `
      <section class="hero-score" data-reveal>
        <div class="hero-glow" style="--g:var(--accent-recovery)"></div>
        ${ui.ring({ value: d.recovery, size: 232, stroke: 16, tint: 'recovery', unit: '%', cap: 'Recovered', numFs: 70 })}
        <p class="hero-caption" style="max-width:280px">Your body is <b style="color:var(--ink-1)">${word}</b>. Recovery is driven mostly by a strong HRV and a low resting heart rate this morning.</p>
      </section>

      <!-- Contributors -->
      <div class="section-title" data-reveal><h2>Contributors</h2></div>
      <section class="card" data-reveal>
        ${d.drivers.map((c, i) => `
        <div class="expandable ${i===0?'open':''}" style="--tint:var(--accent-${c.tint})">
          <button class="ctr-row" data-toggle>
            <span class="glyph tint">${icon(driverIcon(c.name), 16)}</span>
            <div class="ctr-main">
              <div class="ctr-top"><span class="ctr-name">${c.name}</span>
                <span class="ctr-val">${c.value}<small> ${c.unit}</small></span></div>
              <div class="bar" style="margin-top:8px"><i data-w="${c.pct}"></i></div>
            </div>
            <span class="chev-tog">${icon('chevD', 16)}</span>
          </button>
          <div class="expand-body"><div class="inner"><p class="ctr-note">${c.note}</p></div></div>
        </div>`).join('')}
      </section>

      <!-- Stress / balance dial -->
      <div class="grid-2" data-reveal>
        ${miniStat('Stress load', 'Low', 'wave', 'hrv', '2.4 / 10')}
        ${miniStat('Skin temp', '+0.3°C', 'thermo', 'gold', 'vs baseline')}
      </div>

      <!-- History -->
      <div class="section-title" data-reveal><h2>Recovery history</h2>
        <div class="segment" data-seg><button class="active" data-value="14">14d</button><button data-value="30">30d</button></div>
      </div>
      <section class="card" data-reveal>
        <div class="chart"><canvas data-rec-hist></canvas></div>
        <div class="axis" data-axis></div>
      </section>

      <!-- Forecast -->
      <div class="section-title" data-reveal><h2>Forecast</h2></div>
      <section class="card" data-reveal>
        <div class="forecast">
          ${forecast('Tonight', 'If you sleep by 11 PM', 84, 'sleep')}
          ${forecast('Tomorrow', 'With Zone 2 today', 81, 'recovery')}
          ${forecast('Sunday', 'Projected', 74, 'gold')}
        </div>
        <p class="ctr-note" style="margin-top:14px">Forecast blends your recent recovery trend, tonight's projected sleep and planned strain. It updates as you log the day.</p>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      ui.$$('[data-w]', root).forEach((i) => requestAnimationFrame(() => { i.style.width = i.dataset.w + '%'; }));
      const cv = ui.$('[data-rec-hist]', root), axis = ui.$('[data-axis]', root);
      const draw = (n) => {
        const s = data.recSeries.slice(-n);
        charts.area(cv, s, { color: 'recovery', height: 170, min: 0, max: 100,
          labels: s.map((_, i) => '−' + (n - 1 - i) + 'd'), fmt: (v) => v + '%' });
        if (axis) axis.innerHTML = (n === 14 ? ['2w', '1w', 'today'] : ['30d', '20d', '10d', 'today'])
          .map((l) => `<span>${l}</span>`).join('');
      };
      draw(14);
      ui.initSegments(root, (i, v) => draw(+v));
    },
  };

  function miniStat(label, val, ic, tint, sub) {
    return `<div class="card mini" data-reveal style="--tint:var(--accent-${tint})">
      <span class="glyph tint" style="margin-bottom:10px">${icon(ic, 16)}</span>
      <div class="metric"><div class="value" style="font-size:24px">${val}</div><div class="label">${sub||label}</div></div></div>`;
  }
  function forecast(day, cond, val, tint) {
    return `<div class="fc" style="--tint:var(--accent-${tint})">
      <div class="fc-ring">${ui.ring({ value: val, size: 74, stroke: 7, tint, unit: '', cap: '', numFs: 22 })}</div>
      <div class="fc-day">${day}</div><div class="fc-cond">${cond}</div></div>`;
  }
  function driverIcon(n) {
    return ({ 'HRV': 'wave', 'Resting HR': 'heart', 'Sleep': 'moon', 'Respiratory': 'lungs',
      'Skin temp': 'thermo', 'Prior strain': 'flame' })[n] || 'info';
  }
})(window.NOOP = window.NOOP || {});
