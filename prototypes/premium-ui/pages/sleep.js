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

      <!-- Stage breakdown (per-stage density lanes) -->
      <div class="section-title" data-reveal><h2>Stage breakdown</h2><span class="link">${s.inBed} – ${s.outBed}</span></div>
      <section class="card breakdown" data-reveal>
        <div class="bd-cap">${fmtDur(s.inBedMin)} in bed · ${s.efficiency}% efficiency · <span class="bd-approx">stages approximate (on-device)</span></div>
        <div class="bd-nums">
          <div class="bd-num">
            <div class="bd-big">${fmtDur(s.hoursMin)}</div>
            <div class="bd-lab">Hours of sleep</div>
            <div class="bd-typ">typically ${fmtDur(s.hoursTypicalMin)}</div>
          </div>
          <div class="bd-num restorative">
            <div class="bd-big">${fmtDur(s.restorativeMin)}</div>
            <div class="bd-lab">Restorative sleep</div>
            <div class="bd-typ">typically ${fmtDur(s.restorativeTypicalMin)}</div>
          </div>
        </div>
        <div class="chart bd-depth" style="margin-top:16px"><canvas data-depth></canvas></div>
        <div class="bd-lanes">
          ${['awake','light','deep','rem'].map(laneRow).join('')}
        </div>
        <div class="axis bd-axis"><span>${s.times.bed}</span><span>${s.times.mid}</span><span>${s.times.wake}</span></div>
        <div class="bd-hint">${icon('info', 13)} Tap a stage to compare with your 30-day typical.</div>
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
      const s = data.sleep;
      ui.$$('[data-w]', root).forEach((i) => requestAnimationFrame(() => { i.style.width = i.dataset.w + '%'; }));

      // sleep-depth ribbon above the lanes
      const dc = ui.$('[data-depth]', root);
      if (dc) charts.area(dc, s.depth, { color: 'sleep', height: 132, min: 48, max: 104,
        grid: true, markers: false,
        labels: s.depth.map((_, i) => s.fmtTime(i)),
        fmt: (v) => v >= 86 ? 'Awake' : v >= 74 ? 'REM' : v >= 64 ? 'Light' : 'Deep' });

      // per-stage density lanes — place each stage's blocks at their times
      const total = s.inBedMin;
      ['awake', 'light', 'deep', 'rem'].forEach((key) => {
        const track = root.querySelector(`[data-lane-track="${key}"]`);
        if (!track) return;
        const blocks = s.hypnogram.filter((seg) => seg.key === key);
        track.innerHTML = blocks.map((seg, i) => {
          const left = seg.from / total * 100, w = Math.max(0.7, (seg.to - seg.from) / total * 100);
          return `<span class="lane-blk" style="left:${left}%;width:${w}%;background:${stageColor(key)};animation-delay:${i * 45}ms"></span>`;
        }).join('');
      });
      // tap a lane → compare with 30-day typical
      ui.$$('[data-lane]', root).forEach((b) => b.addEventListener('click', (e) => {
        ui.ripple(e, b); openCompare(b.dataset.lane);
      }));

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
  // One per-stage density lane: name · % of night · duration, over a hatched track.
  function laneRow(key) {
    const s = data.sleep;
    const mins = s.byStage[key];
    const pct = Math.round(mins / s.inBedMin * 100);
    return `<button class="lane" data-lane="${key}" style="--tint:${stageColor(key)}">
      <div class="lane-head">
        <span class="lane-name">${cap(key)}</span>
        <span class="lane-pct">${pct}%</span>
        <span class="lane-dur">${fmtDur(mins)}</span>
      </div>
      <div class="lane-track" data-lane-track="${key}"></div>
    </button>`;
  }
  // Tap a stage → a bottom-sheet comparing last night vs the 30-day typical.
  function openCompare(key) {
    const s = data.sleep;
    const mins = s.byStage[key];
    const pct = Math.round(mins / s.inBedMin * 100);
    const typ = s.typical[key];
    const diff = pct - typ;
    const word = diff > 1 ? `${diff}% more` : diff < -1 ? `${-diff}% less` : 'right on';
    const dir = key === 'awake' ? (diff <= 0 ? 'good' : 'watch') : (diff >= 0 ? 'good' : 'watch');
    const body = `
      <p class="ctr-note" style="margin:2px 0 16px">Last night you spent <b style="color:${stageColor(key)}">${fmtDur(mins)}</b> in ${cap(key)} — ${word} than your 30-day typical of ${typ}%.</p>
      <div class="cmp-bars">
        ${cmpBar('Last night', pct, stageColor(key), true)}
        ${cmpBar('30-day typical', typ, 'var(--ink-4)', false)}
      </div>
      <div class="cmp-verdict ${dir}">${icon(dir === 'good' ? 'check' : 'info', 15)} ${dir === 'good' ? 'In a healthy range for you' : 'Slightly outside your usual'}</div>`;
    ui.sheet(cap(key) + ' sleep', body);
    // animate the compare bars once the sheet is up
    setTimeout(() => ui.$$('.cmp-bars .bar > i', document).forEach((i) =>
      requestAnimationFrame(() => { i.style.width = i.dataset.w + '%'; })), 60);
  }
  function cmpBar(label, pct, color, strong) {
    return `<div class="cmp-row">
      <div class="cmp-top"><span>${label}</span><span class="cmp-val">${pct}%</span></div>
      <div class="bar"><i data-w="${pct}" style="width:0;background:${color};box-shadow:${strong ? `0 0 14px ${color}` : 'none'}"></i></div>
    </div>`;
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
