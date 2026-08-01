/* ============================================================================
   NOOP · Premium UI — Trends (v2, expanded)
   Explore every signal over time: a scrollable metric picker (Recovery, HRV,
   Resting HR, Sleep, Sleep Efficiency, Respiratory, Blood Oxygen, Calories,
   Steps, Strain), a Week/Month/6M range control, the hero chart, average/
   min/max, a this-period-vs-previous comparison, and a jump into full detail.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  // Picker entries → registry key (+ a couple of synthesised extras).
  const PICKS = [
    { key: 'recovery', name: 'Recovery' }, { key: 'hrv', name: 'HRV' },
    { key: 'rhr', name: 'Resting HR' }, { key: 'sleep', name: 'Sleep' },
    { key: 'efficiency', name: 'Sleep Eff.' }, { key: 'respiratory', name: 'Respiratory' },
    { key: 'spo2', name: 'Blood O₂' }, { key: 'active', name: 'Calories' },
    { key: 'steps', name: 'Steps' }, { key: 'strain', name: 'Strain' },
  ];

  // Resolve a metric spec (registry + a synthetic efficiency series).
  function spec(key) {
    if (key === 'efficiency') {
      const series = data.sleepSeries.map((v) => Math.min(99, Math.round(84 + (v - 82) * 0.4)));
      return { key, name: 'Sleep Efficiency', short: 'Sleep Eff.', unit: '%', tint: 'sleep', icon: 'moon',
        value: series[series.length - 1], series, baseline: Math.round(data.mean(series)), decimals: 0, higherBetter: true };
    }
    return data.metrics[key];
  }

  function seriesFor(m, range) {
    if (range === 'W') return m.series.slice(-7);
    if (range === '6M') return data.walk(26, m.baseline, (Math.max(...m.series) - Math.min(...m.series)) / 6,
      Math.min(...m.series), Math.max(...m.series)).map((v) => data.round(v, m.decimals));
    return m.series;
  }
  function fmt(v, m) { return m.decimals ? (+v).toFixed(m.decimals) : Math.round(v).toLocaleString(); }

  NS.pages.trends = {
    _key: 'recovery', _range: 'M',
    title: 'Trends', eyebrow: 'Explore your signals', tint: 'recovery',
    render() {
      const m = spec(this._key);
      this.tint = m.tint;
      return `
      <div class="mpick" data-mpick>
        ${PICKS.map((p) => { const sp = spec(p.key); return `<div class="mp ${p.key === this._key ? 'on' : ''}" data-key="${p.key}" style="--k:var(--accent-${sp.tint})"><span class="md"></span>${p.name}</div>`; }).join('')}
      </div>

      <div style="display:flex;justify-content:center;margin:var(--s-4) 0" data-reveal>
        <div class="segment" data-seg>
          <button data-value="W">Week</button>
          <button class="active" data-value="M">Month</button>
          <button data-value="6M">6M</button>
        </div>
      </div>

      <section class="card" data-reveal style="--tint:var(--accent-${m.tint})">
        <div style="display:flex;align-items:baseline;justify-content:space-between;margin-bottom:6px">
          <div><div class="metric"><div class="value" style="font-size:34px">${fmt(m.value, m)}<span class="unit">${m.unit}</span></div>
            <div class="label" data-hero-label>${m.name} · this month avg</div></div></div>
          <span class="tchip" data-hero-chip>—</span>
        </div>
        <div class="chart" style="height:210px;margin-top:8px"><canvas data-trend-chart></canvas></div>
        <div class="stat3" style="margin-top:var(--s-4)" data-trend-stats></div>
      </section>

      <div class="section-title" data-reveal><h2 style="font-size:19px">Period comparison</h2></div>
      <section class="card" data-reveal>
        <div class="dual">
          <div class="figure"><div class="f-cap">This period</div><div class="f-val" data-cmp-now>—</div></div>
          <div class="figure"><div class="f-cap">Previous</div><div class="f-val" style="color:var(--ink-3)" data-cmp-prev>—</div></div>
        </div>
        <div class="bar" style="margin-top:var(--s-4);--tint:var(--accent-${m.tint})"><i data-cmp-bar style="width:0"></i></div>
        <p class="note" data-cmp-note style="margin-top:10px"></p>
      </section>

      <section class="card tap" data-reveal data-open-detail style="--tint:var(--accent-${m.tint});margin-top:var(--s-4);cursor:pointer">
        <div class="rec"><span class="glyph tint" style="--tint:var(--accent-${m.tint})">${icon(m.icon, 18)}</span>
          <div class="rec-body"><div class="rec-title">Open ${m.name} detail</div><div class="rec-sub">Full history, baseline & insight</div></div>
          <span class="chev">${icon('chevR', 18)}</span></div>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      const self = this;
      const draw = () => {
        const m = spec(self._key), range = self._range;
        const vals = seriesFor(m, range);
        const cv = ui.$('[data-trend-chart]', root);
        if (range === 'W') charts.bars(cv, vals, { color: m.tint, height: 210, highlight: vals.length - 1, fmt: (v) => fmt(v, m) + (m.unit ? ' ' + m.unit : '') });
        else charts.area(cv, vals, { color: m.tint, height: 210, fmt: (v) => fmt(v, m) + (m.unit ? ' ' + m.unit : '') });
        const avg = data.round(data.mean(vals), m.decimals), vmin = Math.min(...vals), vmax = Math.max(...vals);
        ui.$('[data-trend-stats]', root).innerHTML =
          sb('Average', fmt(avg, m), m.unit) + sb(m.higherBetter ? 'Lowest' : 'Min', fmt(vmin, m), m.unit) + sb(m.higherBetter ? 'Highest' : 'Max', fmt(vmax, m), m.unit);
        ui.$('[data-hero-label]', root).textContent = `${m.name} · ${range === 'W' ? 'this week' : range === '6M' ? '6-month' : 'this month'} avg`;
        // period comparison
        const half = Math.floor(vals.length / 2);
        const now = data.round(data.mean(vals.slice(half)), m.decimals);
        const prev = data.round(data.mean(vals.slice(0, half)), m.decimals);
        const diffPct = prev ? Math.round((now - prev) / prev * 100) : 0;
        const good = (now > prev) === m.higherBetter;
        ui.$('[data-cmp-now]', root).textContent = fmt(now, m) + (m.unit ? ' ' + m.unit : '');
        ui.$('[data-cmp-prev]', root).textContent = fmt(prev, m) + (m.unit ? ' ' + m.unit : '');
        ui.$('[data-cmp-bar]', root).style.width = Math.min(100, 50 + diffPct) + '%';
        ui.$('[data-cmp-note]', root).innerHTML = diffPct === 0 ? 'Holding steady versus the previous period.'
          : `<b style="color:${good ? 'var(--band-high)' : 'var(--band-low)'}">${diffPct > 0 ? '+' : ''}${diffPct}%</b> versus the previous period.`;
        const chip = ui.$('[data-hero-chip]', root);
        chip.className = 'tchip ' + (diffPct === 0 ? '' : good ? 'pos' : 'neg');
        chip.innerHTML = `${icon(diffPct > 0 ? 'arrowUp' : diffPct < 0 ? 'arrowDn' : 'minus', 12)}${Math.abs(diffPct)}%`;
      };
      draw();
      // metric picker
      ui.$$('[data-mpick] .mp', root).forEach((mp) => mp.addEventListener('click', () => {
        ui.$$('[data-mpick] .mp', root).forEach((x) => x.classList.remove('on'));
        mp.classList.add('on'); self._key = mp.dataset.key; draw();
      }));
      ui.initSegments(root, (i, val) => { self._range = val; draw(); });
      const det = ui.$('[data-open-detail]', root);
      if (det) det.addEventListener('click', (e) => { ui.ripple(e, det);
        if (self._key === 'efficiency') NS.router.go('sleep'); else NS.openMetric(self._key); });
    },
  };
  function sb(cap, val, unit) { return `<div class="stat-blk"><div class="sb-cap">${cap}</div><div class="sb-val">${val}<small> ${unit || ''}</small></div></div>`; }
})(window.NOOP = window.NOOP || {});
