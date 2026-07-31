/* ============================================================================
   NOOP · Premium UI — Sleep
   Sleep score ring, a hypnogram timeline of stages, stage breakdown, sleep debt
   & consistency, and weekly / monthly trends with interactive charts.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  NS.pages.sleep = {
    title: 'Sleep', eyebrow: 'Last night', tint: 'sleep',
    render() {
      const s = data.sleep;
      return `
      <section class="hero-score" data-reveal>
        <div class="hero-glow" style="--g:var(--accent-sleep)"></div>
        ${ui.ring({ value: data.sleepScore, size: 220, stroke: 15, tint: 'sleep', unit: '%', cap: 'Sleep score', numFs: 66 })}
        <div class="hero-caption">${fmtDur(s.asleep)} of ${fmtDur(s.needed)} needed · ${s.efficiency}% efficient</div>
      </section>

      <div class="grid-2" data-reveal style="margin-top:18px">
        ${miniStat('Time in bed', fmtDur(s.asleep + s.stages[0].minutes), 'timer', 'sleep')}
        ${miniStat('Efficiency', s.efficiency + '%', 'check', 'recovery')}
        ${miniStat('Latency', s.latency + 'm', 'zzz', 'hrv')}
        ${miniStat('Restorative', s.restorative + '%', 'moon', 'strain')}
      </div>

      <!-- Hypnogram -->
      <div class="section-title" data-reveal><h2>Sleep stages</h2><span class="link">${s.inBed} – ${s.outBed}</span></div>
      <section class="card" data-reveal>
        <div class="hypno" data-hypno></div>
        <div class="legend" style="margin-top:14px">
          ${['deep','light','rem','awake'].map((k) => `<span class="k" style="--k:${stageColor(k)}"><i></i>${cap(k)}</span>`).join('')}
        </div>
        <div class="rows" style="margin-top:8px">
          ${s.stages.map((st) => `
            <div class="row">
              <span class="glyph tint" style="--tint:${stageColor(st.key)};color:${stageColor(st.key)}">${icon(stageIcon(st.key), 16)}</span>
              <div class="r-body"><div class="r-title">${st.stage}</div>
                <div class="r-sub">${Math.round(st.minutes / s.asleep * 100)}% of sleep</div></div>
              <div class="r-val">${fmtDur(st.minutes)}</div>
            </div>`).join('')}
        </div>
      </section>

      <!-- Debt + consistency -->
      <div class="grid-2" data-reveal>
        <section class="card" style="--tint:var(--accent-heart)">
          <div class="card-head"><h3 style="font-size:15px">Sleep debt</h3></div>
          <div class="metric"><div class="value" style="font-size:40px"><span class="count" data-to="${s.debt}">0</span><span class="unit">min</span></div>
            <div class="label">Across 4 nights</div></div>
          <div class="bar" style="--tint:var(--accent-heart);margin-top:12px"><i data-w="${Math.min(100, s.debt/90*100).toFixed(0)}"></i></div>
        </section>
        <section class="card" style="--tint:var(--accent-recovery)">
          <div class="card-head"><h3 style="font-size:15px">Consistency</h3></div>
          <div class="metric"><div class="value" style="font-size:40px"><span class="count" data-to="${s.consistency}">0</span><span class="unit">%</span></div>
            <div class="label">Same window ±30m</div></div>
          <div class="bar" style="--tint:var(--accent-recovery);margin-top:12px"><i data-w="${s.consistency}"></i></div>
        </section>
      </div>

      <!-- Trends -->
      <div class="section-title" data-reveal><h2>Trends</h2>
        <div class="segment" data-seg><button class="active" data-value="7">Week</button><button data-value="30">Month</button><button data-value="90">3M</button></div>
      </div>
      <section class="card" data-reveal>
        <div class="trend-head"><div class="metric"><div class="value" style="font-size:26px"><span data-avg>82</span><span class="unit">% avg</span></div><div class="label">Sleep performance</div></div>
          <span class="delta up">${icon('arrowUp',12)} +6%</span></div>
        <div class="chart" style="margin-top:10px"><canvas data-sleep-trend></canvas></div>
        <div class="axis" data-axis></div>
      </section>

      <!-- Recommendation -->
      <section class="ai-card" data-reveal style="margin-top:18px">
        <div class="ai-head"><span class="ai-orb"></span><span class="ai-title">Sleep coach</span></div>
        <p class="ai-body">Your deep sleep was strong at <b>2h 6m</b>. To clear the remaining 42-min debt, aim for lights-out by <b>10:50 PM</b> tonight — 20 minutes earlier than usual.</p>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      ui.$$('[data-w]', root).forEach((i) => requestAnimationFrame(() => { i.style.width = i.dataset.w + '%'; }));

      // hypnogram render
      const hy = ui.$('[data-hypno]', root);
      if (hy) renderHypno(hy);

      // trend chart with segment switching
      let series = data.sleepSeries.slice(-7);
      const cv = ui.$('[data-sleep-trend]', root);
      const axis = ui.$('[data-axis]', root);
      const avg = ui.$('[data-avg]', root);
      const draw = (n) => {
        series = data.sleepSeries.slice(-n);
        charts.bars(cv, series, { color: 'sleep', height: 150, min: 0, max: 100,
          highlight: series.length - 1, labels: series.map((_, i) => label(i, n)),
          fmt: (v) => v + '%' });
        if (avg) avg.textContent = Math.round(series.reduce((a, b) => a + b, 0) / series.length);
        if (axis) axis.innerHTML = axisFor(n);
      };
      draw(7);
      ui.initSegments(root, (i, v) => draw(+v));
    },
  };

  /* ---- partials ---- */
  function renderHypno(host) {
    const s = data.sleep;
    const total = s.hypnogram[s.hypnogram.length - 1].to;
    const lanes = { awake: 0, rem: 1, light: 2, deep: 3 };
    host.style.cssText = 'position:relative;height:120px;border-radius:14px;overflow:hidden;background:var(--surface);border:1px solid var(--hairline)';
    const laneH = 100 / 4;
    host.innerHTML = s.hypnogram.map((seg, i) => {
      const lane = lanes[seg.key];
      const left = seg.from / total * 100, w = (seg.to - seg.from) / total * 100;
      return `<span style="position:absolute;left:${left}%;width:${w}%;top:${lane*laneH+8}%;height:${laneH-6}%;
        background:${stageColor(seg.key)};border-radius:5px;opacity:0;transform:scaleX(.4);transform-origin:left;
        box-shadow:0 0 14px ${stageColor(seg.key)}55;animation:grow-up .5s var(--ease-out) forwards;animation-delay:${i*45}ms"></span>`;
    }).join('') +
    ['Awake','REM','Light','Deep'].map((n, i) => `<span style="position:absolute;left:8px;top:${i*laneH+8}%;font-size:9px;font-weight:600;color:var(--ink-4);letter-spacing:.05em">${n}</span>`).join('');
  }
  function miniStat(label, val, ic, tint) {
    return `<div class="card mini" data-reveal style="--tint:var(--accent-${tint})">
      <span class="glyph tint" style="margin-bottom:10px">${icon(ic, 16)}</span>
      <div class="metric"><div class="value" style="font-size:24px">${val}</div><div class="label">${label}</div></div></div>`;
  }
  function stageColor(k){return ({awake:'var(--accent-heart)',rem:'var(--accent-hrv)',light:'var(--accent-strain)',deep:'var(--accent-sleep)'})[k];}
  function stageIcon(k){return ({awake:'bell',rem:'wave',light:'moon',deep:'zzz'})[k];}
  function cap(k){return ({awake:'Awake',rem:'REM',light:'Light',deep:'Deep'})[k];}
  function fmtDur(m){const h=Math.floor(m/60),mm=m%60;return h?`${h}h ${mm}m`:`${mm}m`;}
  function label(i,n){ if(n===7) return data.DAYS[i]; return '−'+(n-1-i)+'d'; }
  function axisFor(n){ const labels = n===7?data.DAYS:(n===30?['4w','3w','2w','1w','now']:['3M','2M','1M','now']);
    return labels.map((l)=>`<span>${l}</span>`).join(''); }
})(window.NOOP = window.NOOP || {});
