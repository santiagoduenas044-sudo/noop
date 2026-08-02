/* ============================================================================
   NOOP · Premium UI — Trends (v3, redesigned)
   Keeps the concept — explore any signal over time — but now actually answers
   "am I improving, what changed, when, and what moves together": 7D/30D/3M/6M
   ranges, the hero chart + period comparison + digest (unchanged core), a
   correlation scatter for the selected metric against Recovery, a fixed set of
   notable cross-metric relationships (including Journal behaviours), and a
   "notable changes" summary — not just a screen of disconnected charts.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  const PICKS = [
    { key: 'recovery', name: 'Recovery' }, { key: 'hrv', name: 'HRV' },
    { key: 'rhr', name: 'Resting HR' }, { key: 'sleep', name: 'Sleep' },
    { key: 'efficiency', name: 'Sleep Eff.' }, { key: 'respiratory', name: 'Respiratory' },
    { key: 'spo2', name: 'Blood O₂' }, { key: 'active', name: 'Calories' },
    { key: 'steps', name: 'Steps' }, { key: 'strain', name: 'Strain' },
  ];
  const RANGES = [['7D', 7], ['30D', 30], ['3M', 90], ['6M', 180]];

  function spec(key) {
    if (key === 'efficiency') {
      const series = data.sleepSeries.map((v) => Math.min(99, Math.round(84 + (v - 82) * 0.4)));
      return { key, name: 'Sleep Efficiency', short: 'Sleep Eff.', unit: '%', tint: 'sleep', icon: 'moon',
        value: series[series.length - 1], series, baseline: Math.round(data.mean(series)), decimals: 0, higherBetter: true };
    }
    return data.metrics[key];
  }
  function longSeries(m, n) {
    // Extend a 30-point base series out to n points with a plausible deterministic
    // walk around the same baseline/range — used for 3M/6M where we don't bank
    // that much raw history, same technique the original 6M branch already used.
    if (n <= m.series.length) return m.series.slice(-n);
    return data.walk(n, m.baseline, (Math.max(...m.series) - Math.min(...m.series)) / 6,
      Math.min(...m.series), Math.max(...m.series)).map((v) => data.round(v, m.decimals));
  }
  function fmt(v, m) { return m.decimals ? (+v).toFixed(m.decimals) : Math.round(v).toLocaleString(); }

  NS.pages.trends = {
    _key: 'recovery', _rangeIdx: 1,
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
          ${RANGES.map(([label], i) => `<button class="${i === this._rangeIdx ? 'active' : ''}" data-value="${i}">${label}</button>`).join('')}
        </div>
      </div>

      <section class="card" data-reveal style="--tint:var(--accent-${m.tint})">
        <div style="display:flex;align-items:baseline;justify-content:space-between;margin-bottom:6px">
          <div><div class="metric"><div class="value" style="font-size:34px">${fmt(m.value, m)}<span class="unit">${m.unit}</span></div>
            <div class="label" data-hero-label>${m.name} · this period avg</div></div></div>
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

      <!-- Notable changes -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Notable changes</h2></div>
      <section class="card" data-reveal>
        <div class="rows">
          ${data.notableChanges.map((c) => `<div class="row" style="--tint:var(--accent-${c.tint})">
            <span class="glyph tint">${icon(c.dir === 'up' ? 'arrowUp' : 'arrowDn', 16)}</span>
            <div class="r-body"><div class="r-title">${c.metric} ${c.change}</div><div class="r-sub">${c.note}</div></div>
            <div class="r-val" style="font-weight:600;color:var(--ink-3)">${c.when}</div></div>`).join('')}
        </div>
      </section>

      <!-- What moves together -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">${m.name} vs Recovery</h2><span class="link">30-day correlation</span></div>
      <section class="card" data-reveal id="tr-scatter-card" ${this._key === 'recovery' ? 'style="display:none"' : ''}>
        <div class="corr">
          <div class="corr-num" data-corr-num style="color:var(--accent-${m.tint})">—</div>
          <div class="corr-body"><div class="corr-title" data-corr-title>—</div>
            <div class="corr-sub" data-corr-sub></div></div>
        </div>
        <div style="margin-top:var(--s-3)"><canvas data-corr-scatter></canvas></div>
      </section>

      <div class="section-title" data-reveal><h2 style="font-size:19px">Patterns across your signals</h2></div>
      <div class="stack">
        ${data.correlationPairs.map(patternCard).join('')}
        ${data.journalCorrelations.slice(0, 1).map(journalPatternCard).join('')}
      </div>

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
        const m = spec(self._key), n = RANGES[self._rangeIdx][1];
        const vals = longSeries(m, n);
        const cv = ui.$('[data-trend-chart]', root);
        if (n <= 7) charts.bars(cv, vals, { color: m.tint, height: 210, highlight: vals.length - 1, fmt: (v) => fmt(v, m) + (m.unit ? ' ' + m.unit : '') });
        else charts.area(cv, vals, { color: m.tint, height: 210, fmt: (v) => fmt(v, m) + (m.unit ? ' ' + m.unit : '') });
        const avg = data.round(data.mean(vals), m.decimals), vmin = Math.min(...vals), vmax = Math.max(...vals);
        ui.$('[data-trend-stats]', root).innerHTML =
          sb('Average', fmt(avg, m), m.unit) + sb(m.higherBetter ? 'Lowest' : 'Min', fmt(vmin, m), m.unit) + sb(m.higherBetter ? 'Highest' : 'Max', fmt(vmax, m), m.unit);
        ui.$('[data-hero-label]', root).textContent = `${m.name} · ${RANGES[self._rangeIdx][0]} avg`;
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

        // correlation scatter vs recovery (skip when Recovery itself is selected)
        const scCard = ui.$('#tr-scatter-card', root);
        if (m.key !== 'recovery' && scCard) {
          scCard.style.display = '';
          const recVals = longSeries(data.metrics.recovery, n);
          const len = Math.min(vals.length, recVals.length);
          const xs = vals.slice(-len), ys = recVals.slice(-len);
          const xlo = Math.min(...xs), xhi = Math.max(...xs), ylo = Math.min(...ys), yhi = Math.max(...ys);
          const pts = xs.map((x, i) => ({ x: xhi > xlo ? (x - xlo) / (xhi - xlo) : 0.5, y: yhi > ylo ? (ys[i] - ylo) / (yhi - ylo) : 0.5 }));
          const r = pearson(xs, ys);
          ui.$('[data-corr-num]', root).textContent = r.toFixed(2);
          ui.$('[data-corr-title]', root).textContent = `${m.name} ↔ Recovery`;
          ui.$('[data-corr-sub]', root).textContent = Math.abs(r) >= 0.5
            ? `A ${r >= 0 ? 'positive' : 'inverse'} relationship over this period.` : 'A weak relationship over this period.';
          const sc = ui.$('[data-corr-scatter]', root);
          if (sc) charts.scatter(sc, pts, { color: m.tint, height: 130 });
        } else if (scCard) scCard.style.display = 'none';
      };
      draw();
      // metric picker
      ui.$$('[data-mpick] .mp', root).forEach((mp) => mp.addEventListener('click', () => {
        ui.$$('[data-mpick] .mp', root).forEach((x) => x.classList.remove('on'));
        mp.classList.add('on'); self._key = mp.dataset.key; draw();
      }));
      ui.initSegments(root, (i) => { self._rangeIdx = i; draw(); });
      const det = ui.$('[data-open-detail]', root);
      if (det) det.addEventListener('click', (e) => { ui.ripple(e, det);
        if (self._key === 'efficiency') NS.router.go('sleep'); else NS.openMetric(self._key); });
    },
  };

  function pearson(xs, ys) {
    const n = xs.length; const mx = xs.reduce((a, b) => a + b, 0) / n, my = ys.reduce((a, b) => a + b, 0) / n;
    let num = 0, dx2 = 0, dy2 = 0;
    for (let i = 0; i < n; i++) { const dx = xs[i] - mx, dy = ys[i] - my; num += dx * dy; dx2 += dx * dx; dy2 += dy * dy; }
    const denom = Math.sqrt(dx2 * dy2); return denom ? num / denom : 0;
  }
  function sb(cap, val, unit) { return `<div class="stat-blk"><div class="sb-cap">${cap}</div><div class="sb-val">${val}<small> ${unit || ''}</small></div></div>`; }
  function confLabel(c) { return ({ early: 'Early signal', emerging: 'Emerging pattern', consistent: 'Consistent pattern' })[c] || c; }
  function patternCard(p) {
    return `<div class="pattern-card" data-reveal style="--tint:var(--accent-${p.tint})">
      <span class="glyph tint">${icon('insight', 16)}</span>
      <div class="pc-body">
        <div class="pc-head"><span class="pc-title">${p.an} ↔ ${p.bn}</span>
          <span class="conf-tag ${p.confidence}"><i></i>${confLabel(p.confidence)}</span></div>
        <div class="pc-text">${p.note}</div>
        <div class="pc-meta">r = ${p.r.toFixed(2)} over the last 30 days</div>
      </div>
    </div>`;
  }
  function journalPatternCard(j) {
    return `<div class="pattern-card" data-reveal data-route="journal" style="--tint:var(--accent-gold);cursor:pointer">
      <span class="glyph tint">${icon('book', 16)}</span>
      <div class="pc-body">
        <div class="pc-head"><span class="pc-title">Journal: ${j.behaviorLabel} ↔ ${j.metricLabel}</span>
          <span class="conf-tag ${j.confidence}"><i></i>${confLabel(j.confidence)}</span></div>
        <div class="pc-text">${j.text}</div>
        <div class="pc-meta">Observed across ${j.occurrences} logged occasions</div>
      </div>
    </div>`;
  }
})(window.NOOP = window.NOOP || {});
