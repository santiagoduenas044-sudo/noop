/* ============================================================================
   NOOP · Premium UI — Sleep (v3, ONE OF THE MOST POWERFUL SCREENS)
   Keeps the score hero, key figures and hypnogram identity, but rebuilds the
   core interaction: Stage Breakdown and the Overnight chart are now ONE
   connected experience — tap a stage and it stays highlighted everywhere,
   drag anywhere and read the exact time · bpm · stage. Then goes far deeper:
   duration & timing trends, consistency, efficiency, restorative sleep,
   sleep debt/need, awakenings, stage-distribution trends, and nightly
   HRV / respiratory / SpO2 / skin-temp — each with a baseline comparison and
   a plain-language "what this means" / "why it matters" explanation.

   NOTE (data integrity): the prototype uses CORRECT mock values. The shipping
   app currently mis-aggregates HealthKit sleep (e.g. "836h in bed", efficiency
   = 1). Those must be fixed at the query/calculation layer — never clamped in UI.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;
  const s = () => data.sleep;

  const STAGE = {
    deep:  { name: 'Deep',  sub: 'Restorative', color: 'var(--accent-sleep)' },
    rem:   { name: 'REM',   sub: 'Restorative', color: 'var(--accent-hrv)' },
    light: { name: 'Core',  sub: 'Light sleep', color: 'var(--accent-strain)' },
    awake: { name: 'Awake', sub: 'In bed', color: 'var(--accent-heart)' },
  };
  const ORDER = ['awake', 'rem', 'light', 'deep'];

  NS.pages.sleep = {
    _selectedStage: null,
    title: 'Sleep', eyebrow: 'Last night · Aug 1', tint: 'sleep',
    render() {
      const d = data, sl = s();
      const inBed = sl.inBedMin, asleep = sl.asleep;
      const restMin = sl.restorativeMin, restPct = Math.round(restMin / asleep * 100);
      const total = sl.hypnogram[sl.hypnogram.length - 1].to;
      return `
      <!-- Score hero -->
      <section class="home-hero" data-reveal style="padding-bottom:6px">
        <div class="hero-glow" style="--g:var(--accent-sleep)"></div>
        <div class="hero-rings">${ui.ring({ value: d.sleepScore, size: 208, stroke: 14, tint: 'sleep', unit: '%', cap: 'Sleep score', numFs: 62 })}</div>
      </section>
      <div style="text-align:center;color:var(--ink-3);font-size:var(--fs-sm);font-weight:500;margin-top:-4px" data-reveal>
        ${fmtDur(asleep)} asleep · ${fmtDur(inBed)} in bed · fell asleep ${sl.times.bed}
      </div>

      <!-- Key figures -->
      <div class="dual" data-reveal style="margin-top:var(--s-5)">
        <section class="card"><div class="figure"><div class="f-val">${fmtDur(asleep)}</div><div class="f-cap">Hours of sleep</div>
          <div class="f-sub">typically ${fmtDur(sl.hoursTypicalMin)}</div></div></section>
        <section class="card" style="--tint:var(--accent-sleep)"><div class="figure"><div class="f-val" style="color:var(--accent-sleep)">${fmtDur(restMin)}</div>
          <div class="f-cap">Restorative</div><div class="f-sub">REM + Deep · typically ${fmtDur(sl.restorativeTypicalMin)}</div></div></section>
      </div>

      <section class="card" data-reveal style="margin-top:var(--s-4)">
        <div class="kv"><span class="k">${gi('scale','sleep')} Time in bed</span><span class="v">${fmtDur(inBed)}</span></div>
        <div class="kv"><span class="k">${gi('check','recovery')} Sleep efficiency</span><span class="v">${sl.efficiency}<small> %</small></span></div>
        <div class="kv"><span class="k">${gi('calendar','hrv')} Consistency</span><span class="v">${sl.consistency}<small> %</small></span></div>
        <div class="kv"><span class="k">${gi('moon','sleep')} Sleep need</span><span class="v">${fmtDur(sl.needed)}</span></div>
        <div class="kv"><span class="k">${gi('timer','heart')} Sleep debt</span><span class="v" style="color:var(--band-mid)">+${sl.debt}<small> min</small></span></div>
        <div class="kv"><span class="k">${gi('clock','strain')} Latency</span><span class="v">${sl.latency}<small> min</small></span></div>
      </section>

      <!-- ============ ONE CONNECTED EXPERIENCE: Overnight ↔ Stage Breakdown ============ -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Sleep stages</h2><span class="link">Tap a stage · drag to explore</span></div>
      ${nightPanel(sl, total)}
      <section class="card" data-reveal style="margin-top:var(--s-4)" data-stage-rows>
        ${ORDER.slice().reverse().map((k) => {
          const mins = sl.byStage[k];
          const pct = Math.round(mins / inBed * 100);
          return `<div class="stage-tap" data-stage="${k}" style="--k:${STAGE[k].color}">
            <span class="st-dot"></span>
            <span class="st-name">${STAGE[k].name}<small>${STAGE[k].sub}</small></span>
            <div class="st-bar"><i data-w="${pct}"></i></div>
            <span class="st-min">${fmtDur(mins)}<small> · ${pct}%</small></span>
          </div>`;
        }).join('')}
      </section>
      <section class="card expandable" data-reveal style="--tint:var(--accent-sleep);margin-top:var(--s-4)">
        <button class="ins-head" data-toggle>
          <span class="il-ic glyph tint">${icon('moon', 16)}</span>
          <div class="ins-title-wrap"><div class="ins-title">Why restorative sleep matters</div></div>
          <span class="chev-tog">${icon('chevD', 16)}</span>
        </button>
        <div class="expand-body"><div class="inner">
          <div class="disclose">
            <div class="disclose-step"><span class="ds-k">What happened</span><span class="ds-v">${fmtDur(restMin)} restorative (${restPct}% of sleep) — Deep and REM combined are trending +8% this week.</span></div>
            <div class="disclose-step"><span class="ds-k">Why it matters</span><span class="ds-v">Deep sleep drives physical repair; REM supports memory and mood. More of both usually means a stronger next-day recovery.</span></div>
            <div class="disclose-step"><span class="ds-k">Show me the data</span><span class="ds-v">See "Restorative sleep" below for the 30-day trend against your typical.</span></div>
          </div>
        </div></div>
      </section>

      <!-- ============ Duration & timing ============ -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Duration &amp; timing</h2><span class="link">30 days</span></div>
      <section class="card" data-reveal>
        <div class="grid-2">
          <div><div class="eyebrow">Bedtime</div>
            <div class="chart" style="height:110px;margin-top:6px"><canvas data-bedtime-chart></canvas></div></div>
          <div><div class="eyebrow">Wake time</div>
            <div class="chart" style="height:110px;margin-top:6px"><canvas data-waketime-chart></canvas></div></div>
        </div>
        <p class="note" style="margin-top:var(--s-3)">Bedtime has drifted ${bedtimeDriftText()} over the last two weeks; wake time has stayed within a ${waketimeSpreadText()} window.</p>
      </section>

      <!-- ============ Consistency ============ -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Sleep consistency</h2><span class="link">${d.sleep.consistency}%</span></div>
      <section class="card" data-reveal>
        <p class="note" style="margin-bottom:var(--s-3)">How closely your bed/wake times matched your typical schedule each of the last 30 nights — brighter squares are more on-schedule.</p>
        ${ui.dotGrid(data.consistencySeries.map((v) => v / 100), 'hrv', 10)}
      </section>

      <!-- ============ Efficiency & time in bed ============ -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Efficiency</h2></div>
      <section class="card" data-reveal>
        <div class="dual">
          <div class="figure"><div class="f-val">${fmtDur(inBed)}</div><div class="f-cap">Time in bed</div></div>
          <div class="figure"><div class="f-val" style="color:var(--accent-sleep)">${fmtDur(asleep)}</div><div class="f-cap">Time asleep</div></div>
        </div>
        <div class="bar" style="margin-top:var(--s-4);--tint:var(--accent-sleep)"><i data-w="${sl.efficiency}"></i></div>
        <div class="chart" style="height:130px;margin-top:var(--s-4)"><canvas data-eff-chart></canvas></div>
        <p class="note" style="margin-top:var(--s-2)">Efficiency is the share of time in bed actually spent asleep. Above 85% is considered strong; yours has averaged ${Math.round(data.mean(data.consistencySeries))}%-consistent scheduling this month, which tends to support it.</p>
      </section>

      <!-- ============ Restorative sleep ============ -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Restorative sleep</h2><span class="link">Deep + REM</span></div>
      <section class="card" data-reveal>
        <div class="chart" style="height:140px"><canvas data-restorative-chart></canvas></div>
        <p class="note" style="margin-top:var(--s-2)">The shaded band is your typical range. Tonight's ${restPct}% sits ${restVsTypicalText(restPct)}.</p>
      </section>

      <!-- ============ Sleep debt & need ============ -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Sleep debt</h2><span class="link">14-night ledger</span></div>
      <section class="card" data-reveal style="--tint:var(--accent-heart)">
        <div class="figure"><div class="f-val" style="color:${debtColor()}">${debtHeadline()}</div><div class="f-cap">Running balance</div></div>
        <div class="chart" style="height:90px;margin-top:var(--s-3)"><div data-debt-bars></div></div>
        <p class="note" style="margin-top:var(--s-2)">A rolling balance of sleep vs your ${fmtDur(sl.needed)} personal need — a surplus night offsets a deficit one. It is not a medical measure, just a running total.</p>
      </section>

      <!-- ============ Night awakenings ============ -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Night awakenings</h2></div>
      <section class="card" data-reveal>
        <div class="dual">
          <div class="figure"><div class="f-val">${data.awakeningsSeries[data.awakeningsSeries.length-1]}</div><div class="f-cap">Last night</div></div>
          <div class="figure"><div class="f-val">${(data.mean(data.awakeningsSeries)).toFixed(1)}</div><div class="f-cap">30-day average</div></div>
        </div>
        <div class="chart" style="height:100px;margin-top:var(--s-4)"><canvas data-awakenings-chart></canvas></div>
      </section>

      <!-- ============ Stage-distribution trend ============ -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Stage trends</h2><span class="link">% of sleep · 30 days</span></div>
      <section class="card" data-reveal>
        ${['deep','rem','light','awake'].map((k) => devRow(STAGE[k].name, `data-stage-trend="${k}"`, STAGE[k].color, `${data[k+'PctSeries'][data[k+'PctSeries'].length-1]}%`)).join('')}
      </section>

      <!-- ============ Overnight vitals (nightly aggregates + baseline) ============ -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Overnight vitals</h2><span class="link">Nightly · vs baseline</span></div>
      <section class="card" data-reveal>
        ${devRow('HRV', 'data-vital-trend="hrv"', 'var(--accent-hrv)', Math.round(data.hrvNightlySeries[data.hrvNightlySeries.length-1]) + ' ms')}
        ${devRow('Respiratory', 'data-vital-trend="resp"', 'var(--accent-recovery)', data.respNightlySeries[data.respNightlySeries.length-1].toFixed(1) + ' rpm')}
        ${devRow('Blood oxygen', 'data-vital-trend="spo2"', 'var(--accent-strain)', Math.round(data.spo2NightlySeries[data.spo2NightlySeries.length-1]) + '%')}
        ${devRow('Wrist temp', 'data-vital-trend="temp"', 'var(--accent-gold)', signed(data.skinTempNightlySeries[data.skinTempNightlySeries.length-1]) + '°C')}
        <p class="note" style="margin-top:var(--s-2)">Heart rate is measured continuously overnight (see the chart above). HRV, respiratory rate, blood oxygen and wrist temperature are stored as nightly averages, so they're shown as one value per night — never invented minute-by-minute curves.</p>
      </section>

      <!-- 7-day trend -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Last 7 nights</h2><span class="link">Hours asleep</span></div>
      <section class="card" data-reveal>
        <div class="chart" style="height:150px"><canvas data-sleep7></canvas></div>
        <div class="axis" data-sleep7-axis></div>
      </section>

      <!-- 30-day trend -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">30-day sleep score</h2></div>
      <section class="card" data-reveal>
        <div class="chart" style="height:170px"><canvas data-sleep30></canvas></div>
        <div class="axis"><span>30d</span><span>20d</span><span>10d</span><span>today</span></div>
        <div class="stat3 c2" style="margin-top:var(--s-4)">
          ${statBlk('30-day avg', Math.round(data.mean(data.sleepSeries)) + '%')}
          ${statBlk('This week', Math.round(data.mean(data.sleepSeries.slice(-7))) + '%')}
        </div>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      const d = data, sl = d.sleep, total = sl.hypnogram[sl.hypnogram.length - 1].to;
      ui.$$('[data-w]', root).forEach((i) => requestAnimationFrame(() => { i.style.width = i.dataset.w + '%'; }));
      ui.initExpandables(root);
      wireStageSelection(root, sl, total, this);

      // Duration & timing
      const bt = ui.$('[data-bedtime-chart]', root);
      if (bt) charts.bandArea(bt, d.bedtimeSeries.slice(-14), { color: 'sleep', height: 110,
        min: Math.min(...d.bedtimeSeries) - 20, max: Math.max(...d.bedtimeSeries) + 20,
        fmt: (v) => clockFromMinutes(v) });
      const wt = ui.$('[data-waketime-chart]', root);
      if (wt) charts.bandArea(wt, d.waketimeSeries.slice(-14), { color: 'gold', height: 110,
        min: Math.min(...d.waketimeSeries) - 20, max: Math.max(...d.waketimeSeries) + 20,
        fmt: (v) => clockFromMinutes(v) });

      // Efficiency trend (derive a plausible efficiency series from consistency+sleepScore)
      const eff = ui.$('[data-eff-chart]', root);
      if (eff) {
        const effSeries = d.sleepSeries.map((v, i) => Math.min(99, Math.round(78 + (v - 75) * 0.35 + (d.consistencySeries[i] - 80) * 0.08)));
        charts.bandArea(eff, effSeries.slice(-30), { color: 'sleep', height: 130, min: 55, max: 100,
          bandLo: 82, bandHi: 92, fmt: (v) => Math.round(v) + '%' });
      }

      // Restorative sleep vs typical band
      const rest = ui.$('[data-restorative-chart]', root);
      if (rest) {
        const restSeries = d.deepPctSeries.map((v, i) => v + d.remPctSeries[i]);
        charts.bandArea(rest, restSeries.slice(-30), { color: 'sleep', height: 140, min: 20, max: 65,
          bandLo: Math.round(data.mean(restSeries)) - 6, bandHi: Math.round(data.mean(restSeries)) + 6,
          fmt: (v) => Math.round(v) + '%' });
      }

      // Sleep-debt ledger — diverging bars around a zero line
      const debtHost = ui.$('[data-debt-bars]', root);
      if (debtHost) renderDebtBars(debtHost, d.sleepDebtLedger);

      // Awakenings
      const awk = ui.$('[data-awakenings-chart]', root);
      if (awk) charts.bars(awk, d.awakeningsSeries.slice(-14), { color: 'heart', height: 100, min: 0,
        fmt: (v) => v + (v === 1 ? ' awakening' : ' awakenings') });

      // Stage-distribution trends (mini inline charts inside dev-rows)
      ['deep','rem','light','awake'].forEach((k) => {
        const cv = ui.$(`[data-stage-trend="${k}"]`, root);
        if (cv) charts.spark(cv, d[k + 'PctSeries'].slice(-30), { color: stageTint(k), height: 34 });
      });

      // Overnight vitals mini trends
      const vitalMap = { hrv: [d.hrvNightlySeries, 'hrv'], resp: [d.respNightlySeries, 'recovery'],
        spo2: [d.spo2NightlySeries, 'strain'], temp: [d.skinTempNightlySeries, 'gold'] };
      Object.keys(vitalMap).forEach((k) => {
        const cv = ui.$(`[data-vital-trend="${k}"]`, root);
        if (cv) charts.spark(cv, vitalMap[k][0].slice(-30), { color: vitalMap[k][1], height: 34 });
      });

      // 7-day / 30-day
      const c7 = ui.$('[data-sleep7]', root);
      if (c7) {
        const hrs = d.sleepSeries.slice(-7).map((v) => Math.round((6 + v / 100 * 2.6) * 10) / 10);
        charts.bars(c7, hrs, { color: 'sleep', height: 150, highlight: 6, min: 0, labels: ['Fri','Sat','Sun','Mon','Tue','Wed','Thu'], fmt: (v) => v + ' h' });
        ui.$('[data-sleep7-axis]', root).innerHTML = ['Fri','Sat','Sun','Mon','Tue','Wed','Thu'].map((x) => `<span>${x}</span>`).join('');
      }
      const c30 = ui.$('[data-sleep30]', root);
      if (c30) charts.area(c30, d.sleepSeries, { color: 'sleep', height: 170, min: 40, max: 100, fmt: (v) => Math.round(v) + '%' });
    },
  };

  // ------------------------------------------------------------------ helpers

  function stageTint(k) { return ({ deep: 'sleep', rem: 'hrv', light: 'strain', awake: 'heart' })[k]; }
  function signed(v) { return (v >= 0 ? '+' : '') + v.toFixed(2); }
  function debtColor() {
    const bal = data.sleepDebtLedger[data.sleepDebtLedger.length - 1].balanceMin;
    return bal >= 0 ? 'var(--band-high)' : 'var(--band-low)';
  }
  function debtHeadline() {
    const bal = data.sleepDebtLedger[data.sleepDebtLedger.length - 1].balanceMin;
    const sign = bal >= 0 ? '+' : '−';
    return sign + fmtDur(Math.abs(bal));
  }
  function bedtimeDriftText() {
    const s2 = data.bedtimeSeries.slice(-14); const drift = s2[s2.length - 1] - s2[0];
    return Math.abs(drift) < 10 ? 'very little' : (drift > 0 ? `${fmtDur(drift)} later` : `${fmtDur(-drift)} earlier`);
  }
  function waketimeSpreadText() {
    const s2 = data.waketimeSeries.slice(-14);
    return fmtDur(Math.max(...s2) - Math.min(...s2));
  }
  function restVsTypicalText(pct) {
    const avg = Math.round(data.mean(data.deepPctSeries.map((v, i) => v + data.remPctSeries[i])));
    const diff = pct - avg;
    return Math.abs(diff) <= 2 ? 'right on your typical range' : diff > 0 ? `${diff} points above your typical range` : `${-diff} points below your typical range`;
  }
  function clockFromMinutes(mins) {
    mins = ((Math.round(mins) % 1440) + 1440) % 1440;
    let h = Math.floor(mins / 60), m = mins % 60, ap = h < 12 ? 'AM' : 'PM', hh = h % 12 || 12;
    return `${hh}:${String(m).padStart(2, '0')} ${ap}`;
  }
  function devRow(name, chartAttr, color, val) {
    return `<div class="dev-row"><span class="dr-name">${name}</span>
      <div class="dr-chart chart"><canvas ${chartAttr}></canvas></div>
      <span class="dr-val" style="color:${color}">${val}</span></div>`;
  }
  function renderDebtBars(host, ledger) {
    const deltas = ledger.map((n) => n.deltaMin);
    const scale = Math.max(...deltas.map((d) => Math.abs(d)), 1);
    host.style.cssText = 'position:relative;height:90px';
    const n = deltas.length, slotW = 100 / n;
    let html = `<div style="position:absolute;left:0;right:0;top:50%;height:1px;background:var(--hairline)"></div>`;
    deltas.forEach((d2, i) => {
      const h = Math.max(2, Math.abs(d2) / scale * 42);
      const top = d2 >= 0 ? 50 - (h / 90 * 100) : 50;
      html += `<div style="position:absolute;left:${i * slotW + slotW * 0.2}%;width:${slotW * 0.6}%;top:${top}%;height:${h}px;
        border-radius:3px;background:${d2 >= 0 ? 'var(--accent-recovery)' : 'var(--accent-heart)'};opacity:.9"></div>`;
    });
    host.innerHTML = html;
  }

  // -------------------------------------------- ONE connected stage experience
  // Wires BOTH the tap-to-select (persistent, shared between the overnight
  // ribbon's legend AND the Stage Breakdown rows below it) and the drag-scrub
  // (transient time · bpm · stage readout). Selecting a stage keeps it fully
  // coloured everywhere and mutes the others; the HR line itself is NEVER
  // dimmed, so physiology stays comparable across stages.
  function wireStageSelection(root, sl, total, page) {
    const stack = ui.$('[data-np-stack]', root); if (!stack) return;
    const cursor = ui.$('[data-np-cursor]', root);
    const bpmEl = ui.$('[data-np-bpm]', root), timeEl = ui.$('[data-np-time]', root), stageEl = ui.$('[data-np-stage]', root);
    const hypWrap = ui.$('[data-np-hyp]', root);
    const blks = ui.$$('.hyp2-blk', hypWrap);
    const legendBtns = ui.$$('[data-lg-btn]', root);
    const stageRows = ui.$$('[data-stage-rows] .stage-tap', root);
    const contextEl = ui.$('[data-np-context]', root);
    const hr = charts.overnight(ui.$('[data-np-hr]', root), sl.overnight.hr, { color: 'heart', height: 118 });

    function applySelection() {
      const sel = page._selectedStage;
      hypWrap.classList.toggle('np-selecting', !!sel);
      blks.forEach((b) => b.classList.toggle('sel', b.dataset.stage === sel));
      legendBtns.forEach((b) => b.classList.toggle('active', b.dataset.lgBtn === sel));
      stageRows.forEach((r) => {
        const match = r.dataset.stage === sel;
        r.classList.toggle('sel', !!sel && match);
        r.classList.toggle('dim', !!sel && !match);
      });
      if (!sel) { contextEl.innerHTML = 'Tap a stage to compare it with your 30-day typical.'; return; }
      const mins = sl.byStage[sel], pct = Math.round(mins / sl.inBedMin * 100);
      const typPct = sl.typical[sel], typMins = Math.round(typPct / 100 * sl.inBedMin);
      const deltaMin = mins - typMins;
      const cls = deltaMin >= 0 ? 'up' : 'down', sign = deltaMin >= 0 ? '+' : '−';
      contextEl.innerHTML = `<div class="ctx-head"><span style="color:${STAGE[sel].color}">${STAGE[sel].name}</span> ${fmtDur(mins)}</div>
        <div>${pct}% of sleep · Typical ${fmtDur(typMins)} · <span class="ctx-delta ${cls}">${sign}${fmtDur(Math.abs(deltaMin))} vs typical</span></div>`;
    }
    function toggleStage(k) { page._selectedStage = page._selectedStage === k ? null : k; applySelection(); }
    legendBtns.forEach((b) => b.addEventListener('click', (e) => { ui.ripple(e, b); toggleStage(b.dataset.lgBtn); }));
    stageRows.forEach((r) => r.addEventListener('click', (e) => { ui.ripple(e, r); toggleStage(r.dataset.stage); }));
    applySelection();

    // Drag-scrub: exact time · bpm · stage, independent of the persistent selection.
    function scrub(frac) {
      frac = Math.max(0, Math.min(1, frac));
      const minute = Math.round(frac * total), k = sl.stageAt(minute);
      cursor.style.left = (frac * 100) + '%'; cursor.style.opacity = '1';
      bpmEl.textContent = Math.round(hr.valueAt(frac));
      timeEl.textContent = sl.fmtTime(minute);
      stageEl.textContent = STAGE[k].name; stageEl.style.setProperty('--k', STAGE[k].color); stageEl.classList.add('show');
      hr.setCursor(frac);
    }
    function clear() {
      cursor.style.opacity = '0';
      bpmEl.textContent = '—';
      timeEl.textContent = 'Drag to explore';
      stageEl.classList.remove('show');
      hr.setCursor(null);
    }
    const fracFrom = (e) => { const r = stack.getBoundingClientRect();
      const x = (e.touches ? e.touches[0].clientX : e.clientX) - r.left; return x / r.width; };
    let dragging = false;
    stack.addEventListener('pointerdown', (e) => { dragging = true; scrub(fracFrom(e)); try { stack.setPointerCapture(e.pointerId); } catch {} });
    stack.addEventListener('pointermove', (e) => { if (e.pointerType === 'mouse' || dragging) scrub(fracFrom(e)); });
    stack.addEventListener('pointerup', () => { dragging = false; });
    stack.addEventListener('pointerleave', () => { if (!dragging) clear(); });
  }

  // The connected overnight panel: real HR chart + 4-lane stage ribbon, a
  // clickable legend that doubles as the selection control, a live readout,
  // and the context bar the selection fills in.
  function nightPanel(sl, total) {
    return `
    <section class="card night-panel" data-night data-reveal>
      <div class="np-readout">
        <div class="metric"><div class="value" style="font-size:30px;color:var(--accent-heart)">
          <span data-np-bpm>—</span><span class="unit">bpm</span></div></div>
        <div style="text-align:right">
          <div class="np-time" data-np-time>Drag to explore</div>
          <span class="np-stage" data-np-stage></span>
        </div>
      </div>
      <div class="np-legend">
        ${ORDER.map((k) => `<button class="lg" data-lg-btn="${k}" style="--k:${STAGE[k].color}"><i style="background:${STAGE[k].color}"></i>${STAGE[k].name}</button>`).join('')}
      </div>
      <div class="np-stack" data-np-stack>
        <div class="chart" style="height:118px;margin-bottom:12px"><canvas data-np-hr></canvas></div>
        <div class="np-hyp" data-np-hyp>
          ${ORDER.map((k) => `<div class="hyp2">${sl.hypnogram.filter((seg) => seg.key === k).map((seg) => `<span class="hyp2-blk" data-stage="${k}" style="left:${seg.from/total*100}%;width:${(seg.to-seg.from)/total*100}%;background:${STAGE[k].color};color:${STAGE[k].color}"></span>`).join('')}</div>`).join('')}
        </div>
        <div class="np-cursor" data-np-cursor></div>
      </div>
      <div class="axis" style="margin-top:8px"><span>${sl.times.bed}</span><span>${sl.times.mid}</span><span>${sl.times.wake}</span></div>
      <div class="np-context" data-np-context>Tap a stage to compare it with your 30-day typical.</div>
      <p class="note" style="margin-top:10px">Heart rate measured continuously overnight, aligned to your decoded sleep stages. Tap a stage above or a row below to highlight it everywhere; drag the chart to read any moment.</p>
    </section>`;
  }

  function gi(name, tint) { return `<span class="kg" style="--tint:var(--accent-${tint})">${icon(name, 16)}</span>`; }
  function statBlk(cap, val) { return `<div class="stat-blk"><div class="sb-cap">${cap}</div><div class="sb-val">${val}</div></div>`; }
  function fmtDur(m) { m = Math.round(m); const h = Math.floor(m / 60), mm = m % 60; return h ? `${h}h ${mm}m` : `${mm}m`; }
})(window.NOOP = window.NOOP || {});
