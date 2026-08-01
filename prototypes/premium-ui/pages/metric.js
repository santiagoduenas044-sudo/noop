/* ============================================================================
   NOOP · Premium UI — Reusable Metric Detail
   ONE screen that any drillable signal reuses (HRV, Resting HR, Respiratory,
   Blood Oxygen, Active Calories, Steps, Recovery, Strain, Sleep). Driven purely
   by the metric registry in data.js. Open with NOOP.openMetric('hrv').

   Layout (the shared template): hero value + baseline + daily change · range
   selector (Day/Week/Month/6M) · interactive chart · average / min / max ·
   where-today-sits range bar · recent history · what-it-means · personal insight.
   Maps cleanly onto a single reusable SwiftUI `MetricDetailView`.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  // Open the detail for a metric key (set target, then route).
  NS.openMetric = function (key) {
    if (!data.metrics[key]) return;
    NS.pages.metric._key = key;
    NS.router.go('metric');
  };

  // Build a deterministic series for a given range from the metric's 30-day base.
  function rangeSeries(m, range) {
    const d = data;
    if (range === 'W') return { vals: m.series.slice(-7), labels: dayLabels(7) };
    if (range === 'M') return { vals: m.series, labels: sparseLabels(30) };
    if (range === '6M') {
      const w = d.walk(26, m.baseline, (Math.max(...m.series) - Math.min(...m.series)) / 6,
        Math.min(...m.series), Math.max(...m.series)).map((v) => d.round(v, m.decimals));
      return { vals: w, labels: weekLabels(26) };
    }
    // Day — a synthetic 24h intraday walk around today's value (demo only).
    const day = d.walk(24, m.value, Math.max(0.6, Math.abs(m.value) * 0.03),
      m.value * 0.82, m.value * 1.18).map((v) => d.round(v, m.decimals));
    return { vals: day, labels: hourLabels() };
  }
  function dayLabels(n) { const D = data.DAYS; const out = []; for (let i = n - 1; i >= 0; i--) out.push(D[(5 - i + 7) % 7]); return out; }
  function sparseLabels(n) { return Array.from({ length: n }, (_, i) => (i % 6 === 0 ? `${30 - i}d` : '')); }
  function weekLabels(n) { return Array.from({ length: n }, (_, i) => (i % 4 === 0 ? `${26 - i}w` : '')); }
  function hourLabels() { return Array.from({ length: 24 }, (_, i) => (i % 6 === 0 ? `${i}:00` : '')); }

  function fmt(v, m) { return m.decimals ? (+v).toFixed(m.decimals) : Math.round(v).toLocaleString(); }

  function deltaChip(cur, base, higherBetter, unit) {
    const diff = cur - base;
    const pct = base ? Math.round((diff / base) * 100) : 0;
    const dir = diff > 0.001 ? 'up' : diff < -0.001 ? 'down' : 'flat';
    const good = dir === 'flat' ? false : ((dir === 'up') === higherBetter);
    const cls = dir === 'flat' ? '' : good ? 'pos' : 'neg';
    const arrow = dir === 'up' ? 'arrowUp' : dir === 'down' ? 'arrowDn' : 'minus';
    const txt = dir === 'flat' ? 'on baseline' : `${Math.abs(pct)}% vs baseline`;
    return `<span class="tchip ${cls}">${icon(arrow, 12)}${txt}</span>`;
  }

  NS.pages.metric = {
    _key: 'hrv',
    title: 'Metric', eyebrow: 'Detail', tint: 'hrv',
    render() {
      const m = data.metrics[this._key] || data.metrics.hrv;
      this.title = m.short; this.eyebrow = 'Metric detail'; this.tint = m.tint;
      const base = m.baseline;
      const range = rangeSeries(m, 'M');
      const vmin = Math.min(...range.vals), vmax = Math.max(...range.vals);
      const avg = data.round(data.mean(range.vals), m.decimals);
      // where today sits within the personal min..max band
      const span = (vmax - vmin) || 1;
      const nowPct = Math.max(4, Math.min(96, ((m.value - vmin) / span) * 100));
      const bandLo = Math.max(0, ((base - span * 0.12 - vmin) / span) * 100);
      const bandHi = Math.min(100, ((base + span * 0.12 - vmin) / span) * 100);

      return `
      <div class="metric-hero" data-reveal style="--tint:var(--accent-${m.tint})">
        <div class="mh-glyph">${icon(m.icon, 24)}</div>
        <div class="mh-val"><span class="count" data-to="${m.value}">0</span><span class="u">${m.unit}</span></div>
        <div class="mh-sub">
          <span>Baseline <b style="color:var(--ink-1)">${fmt(base, m)}${m.unit ? ' ' + m.unit : ''}</b></span>
          <span class="sep"></span>
          ${deltaChip(m.value, base, m.higherBetter, m.unit)}
        </div>
      </div>

      <div style="display:flex;justify-content:center;margin:6px 0 var(--s-4)" data-reveal>
        <div class="segment" data-seg>
          <button data-value="D">Day</button>
          <button class="active" data-value="M">Month</button>
          <button data-value="W">Week</button>
          <button data-value="6M">6M</button>
        </div>
      </div>

      <section class="card" data-reveal>
        <div class="chart" style="height:210px"><canvas data-metric-chart></canvas></div>
        <div class="axis" data-axis></div>
        <div style="height:var(--s-4)"></div>
        <div class="stat3" data-stats>
          ${statBlk('Average', fmt(avg, m), m.unit)}
          ${statBlk(m.higherBetter ? 'Lowest' : 'Minimum', fmt(vmin, m), m.unit)}
          ${statBlk(m.higherBetter ? 'Highest' : 'Maximum', fmt(vmax, m), m.unit)}
        </div>
      </section>

      <div class="section-title" data-reveal><h2 style="font-size:19px">Where today sits</h2></div>
      <section class="card" data-reveal style="--tint:var(--accent-${m.tint})">
        <div class="rangebar">
          <span class="band" style="left:${bandLo}%;right:${100 - bandHi}%"></span>
          <span class="now" style="left:${nowPct}%"></span>
        </div>
        <div style="display:flex;justify-content:space-between;font-size:var(--fs-xs);color:var(--ink-3);font-weight:600">
          <span>${fmt(vmin, m)}${m.unit ? ' ' + m.unit : ''}</span>
          <span>your 30-day range</span>
          <span>${fmt(vmax, m)}${m.unit ? ' ' + m.unit : ''}</span>
        </div>
      </section>

      <div class="section-title" data-reveal><h2 style="font-size:19px">Recent</h2><span class="link">Last 7</span></div>
      <section class="card" data-reveal>
        <div class="rows">
          ${range.vals.slice(-7).map((v, i, a) => {
            const lbl = dayLabels(7)[i];
            const d = i === a.length - 1 ? 'Today' : lbl;
            const diff = v - base;
            const dir = diff > 0.001 ? 'up' : diff < -0.001 ? 'down' : 'flat';
            const good = dir === 'flat' ? false : ((dir === 'up') === m.higherBetter);
            const col = dir === 'flat' ? 'var(--ink-3)' : good ? 'var(--band-high)' : 'var(--band-low)';
            return `<div class="row"><div class="r-body"><div class="r-title" style="font-weight:500">${d}</div></div>
              <div class="r-val">${fmt(v, m)}<small> ${m.unit}</small>
              <span style="color:${col};font-weight:700;margin-left:8px;font-size:12px">${dir==='flat'?'·':(diff>0?'+':'')+fmt(diff,m)}</span></div></div>`;
          }).join('')}
        </div>
      </section>

      <div class="section-title" data-reveal><h2 style="font-size:19px">What it means</h2></div>
      <section class="card" data-reveal><p class="explain">${m.explain}</p></section>

      <section class="card" data-reveal style="--tint:var(--accent-${m.tint});margin-top:var(--s-4)">
        <div class="insight-line">
          <span class="il-ic">${icon('sparkles', 16)}</span>
          <div class="il-body">${m.insight}</div>
        </div>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      const m = data.metrics[this._key] || data.metrics.hrv;
      const cv = ui.$('[data-metric-chart]', root);
      const axis = ui.$('[data-axis]', root);
      const draw = (range) => {
        const r = rangeSeries(m, range);
        if (range === 'W' || range === '6M' || range === 'D') {
          // fewer points → bars read better for Week/6M; Day keeps the line
          if (range === 'W') { charts.bars(cv, r.vals, { color: m.tint, height: 210, highlight: r.vals.length - 1,
            labels: r.labels, fmt: (v) => fmt(v, m) + (m.unit ? ' ' + m.unit : '') }); }
          else charts.area(cv, r.vals, { color: m.tint, height: 210, labels: r.labels, fmt: (v) => fmt(v, m) + (m.unit ? ' ' + m.unit : '') });
        } else {
          charts.area(cv, r.vals, { color: m.tint, height: 210, labels: r.labels, fmt: (v) => fmt(v, m) + (m.unit ? ' ' + m.unit : '') });
        }
        axis.innerHTML = r.labels.filter(Boolean).map((l) => `<span>${l}</span>`).join('');
        // refresh stat blocks
        const vmin = Math.min(...r.vals), vmax = Math.max(...r.vals), avg = data.round(data.mean(r.vals), m.decimals);
        const st = ui.$('[data-stats]', root);
        st.innerHTML = statBlk('Average', fmt(avg, m), m.unit) +
          statBlk(m.higherBetter ? 'Lowest' : 'Minimum', fmt(vmin, m), m.unit) +
          statBlk(m.higherBetter ? 'Highest' : 'Maximum', fmt(vmax, m), m.unit);
      };
      draw('M');
      ui.initSegments(root, (i, val) => draw(val));
    },
  };

  function statBlk(cap, val, unit) {
    return `<div class="stat-blk"><div class="sb-cap">${cap}</div>
      <div class="sb-val">${val}<small> ${unit || ''}</small></div></div>`;
  }
})(window.NOOP = window.NOOP || {});
