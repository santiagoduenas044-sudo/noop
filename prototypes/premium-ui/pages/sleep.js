/* ============================================================================
   NOOP · Premium UI — Sleep (v2, expanded)
   Keeps the established sleep design language and hypnogram, but goes far deeper:
   score, hours asleep, time in bed, efficiency, consistency, need, debt,
   restorative sleep, and the full stage breakdown (Awake / REM / Core / Deep)
   with REM+Deep restorative total, tappable stages, a typical comparison, and
   both a 7-day and 30-day trend.

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

  // The overnight signals charted below the hypnogram. `hb` = higher-is-better (for
  // baseline-delta colouring); temp is neutral (signed). All read from data.sleep.overnight.
  const NIGHT = [
    { key: 'hr',   name: 'Heart rate',   unit: 'bpm', tint: 'heart',    dec: 0, hb: false },
    { key: 'hrv',  name: 'HRV',          unit: 'ms',  tint: 'hrv',      dec: 0, hb: true },
    { key: 'resp', name: 'Respiratory',  unit: 'rpm', tint: 'recovery', dec: 1, hb: false },
    { key: 'spo2', name: 'Blood oxygen', unit: '%',   tint: 'strain',   dec: 0, hb: true },
    { key: 'temp', name: 'Wrist temp',   unit: '°C',  tint: 'gold',     dec: 2, hb: null, signed: true },
  ];
  const nfmt = (v, mc) => (mc.signed && v >= 0 ? '+' : '') + (mc.dec ? (+v).toFixed(mc.dec) : Math.round(v));

  NS.pages.sleep = {
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

      <!-- Hypnogram -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Sleep stages</h2><span class="link">Tap a stage</span></div>
      <section class="card" data-reveal>
        ${hyp(sl, total)}
        <div class="axis" style="margin-top:10px"><span>${sl.times.bed}</span><span>${sl.times.mid}</span><span>${sl.times.wake}</span></div>
      </section>

      <!-- Stage breakdown (tappable) -->
      <section class="card" data-reveal style="margin-top:var(--s-4)">
        ${['deep','rem','light','awake'].map((k) => {
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
      <section class="card" data-reveal style="--tint:var(--accent-sleep);margin-top:var(--s-4)">
        <div class="insight-line"><span class="il-ic">${icon('moon', 16)}</span>
          <div class="il-body"><b>${fmtDur(restMin)} restorative</b> (${restPct}% of sleep) — Deep and REM combined are trending +8% this week, a good sign your recovery is being earned overnight.</div></div>
      </section>

      <!-- Overnight physiology (synchronized, scrubbable) -->
      <div class="section-title" data-reveal><h2 style="font-size:19px">Overnight</h2><span class="link">Drag to explore</span></div>
      ${nightPanel(sl, total)}

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
      ui.$$('.stage-tap', root).forEach((el) => el.addEventListener('click', (e) => { ui.ripple(e, el); openStage(el.dataset.stage); }));
      wireNight(root, sl, total);
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

  function openStage(k) {
    const sl = s();
    const mins = sl.byStage[k], pct = Math.round(mins / sl.inBedMin * 100), typ = sl.typical[k];
    const diff = pct - typ;
    const word = diff > 2 ? 'more than' : diff < -2 ? 'less than' : 'about the same as';
    ui.sheet(STAGE[k].name + ' sleep', `
      <p class="note" style="margin:2px 0 16px">Last night you spent <b style="color:${STAGE[k].color}">${fmtDur(mins)}</b> in ${STAGE[k].name} — ${pct}% of time in bed, ${word} your 30-day typical of ${typ}%.</p>
      <div class="stat3 c2">${statBlk('Last night', pct + '%')}${statBlk('Typical', typ + '%')}</div>
      <p class="note" style="margin-top:16px">${stageBlurb(k)}</p>`);
  }
  function stageBlurb(k) {
    return ({
      deep: 'Deep sleep is when the body repairs tissue and consolidates physical recovery. It clusters early in the night.',
      rem: 'REM sleep supports memory and mood, and dominates the later cycles toward morning.',
      light: 'Core (light) sleep is the connective tissue of the night — the transitions between deeper stages.',
      awake: 'Brief awakenings are normal. What matters is how quickly you settle back down.',
    })[k];
  }

  // The synchronized overnight panel: a compact full-width hypnogram + one mini
  // chart per signal, a shared cursor line, a live readout, and per-metric stats.
  function nightPanel(sl, total) {
    const ov = sl.overnight;
    const order = ['awake', 'rem', 'light', 'deep'];
    return `
    <section class="card night-panel" data-night data-reveal>
      <div class="np-readout">
        <div class="np-time" data-np-time>Drag across any chart</div>
        <span class="np-stage" data-np-stage></span>
      </div>
      <div class="np-legend">
        ${['deep','rem','light','awake'].map((k) => `<span class="lg" data-lg="${k}"><i style="background:${STAGE[k].color}"></i>${STAGE[k].name}</span>`).join('')}
      </div>
      <div class="np-stack" data-np-stack>
        <div class="np-hyp" data-np-hyp>
          ${order.map((k) => `<div class="hyp2">${sl.hypnogram.filter((s) => s.key === k).map((s) => `<span class="hyp2-blk" data-from="${s.from}" data-to="${s.to}" style="left:${s.from/total*100}%;width:${(s.to-s.from)/total*100}%;background:${STAGE[k].color};color:${STAGE[k].color}"></span>`).join('')}</div>`).join('')}
        </div>
        <div class="np-rows">
          ${NIGHT.map((mc) => {
            const arr = ov[mc.key], avg = data.round(data.mean(arr), mc.dec), lo = Math.min(...arr), hi = Math.max(...arr);
            const base = ov.baseline[mc.key], delta = data.round(avg - base, mc.dec);
            const good = mc.hb == null ? null : ((delta > 0) === mc.hb);
            const dcol = mc.hb == null || Math.abs(delta) < (mc.dec ? 0.05 : 0.5) ? 'var(--ink-3)' : good ? 'var(--band-high)' : 'var(--band-low)';
            return `<div class="np-row" data-metric="${mc.key}" style="--tint:var(--accent-${mc.tint})">
              <div class="np-head">
                <span class="np-name">${mc.name}</span>
                <span class="np-live" data-live="${mc.key}"></span>
                <span class="np-stat">avg ${nfmt(avg, mc)} · ${nfmt(lo, mc)}–${nfmt(hi, mc)} ${mc.unit} · <b style="color:${dcol}">${nfmt(delta, mc)} vs base</b></span>
              </div>
              <div class="chart" style="height:60px"><canvas data-np-chart="${mc.key}"></canvas></div>
            </div>`;
          }).join('')}
        </div>
        <div class="np-cursor" data-np-cursor></div>
      </div>
      <div class="axis" style="margin-top:8px"><span>${sl.times.bed}</span><span>${sl.times.mid}</span><span>${sl.times.wake}</span></div>
      <p class="note" style="margin-top:12px">Overnight heart rate, HRV, respiratory rate, blood oxygen and wrist temperature from Apple Health, aligned to your sleep stages. Drag to read any moment.</p>
    </section>`;
  }

  function wireNight(root, sl, total) {
    const stack = ui.$('[data-np-stack]', root); if (!stack) return;
    const cursor = ui.$('[data-np-cursor]', root);
    const timeEl = ui.$('[data-np-time]', root), stageEl = ui.$('[data-np-stage]', root);
    const hyp = ui.$('[data-np-hyp]', root), blks = ui.$$('.hyp2-blk', hyp), legs = ui.$$('[data-lg]', root);
    const inst = {};
    NIGHT.forEach((mc) => { const cv = ui.$(`[data-np-chart="${mc.key}"]`, root);
      if (cv) inst[mc.key] = charts.overnight(cv, sl.overnight[mc.key], { color: mc.tint, height: 60 }); });

    function scrub(frac) {
      frac = Math.max(0, Math.min(1, frac));
      const minute = Math.round(frac * total), k = sl.stageAt(minute);
      cursor.style.left = (frac * 100) + '%'; cursor.style.opacity = '1';
      timeEl.textContent = sl.fmtTime(minute);
      stageEl.textContent = STAGE[k].name; stageEl.style.setProperty('--k', STAGE[k].color); stageEl.classList.add('show');
      hyp.classList.add('np-dim');
      blks.forEach((b) => b.classList.toggle('active', minute >= +b.dataset.from && minute < +b.dataset.to));
      legs.forEach((l) => l.classList.toggle('active', l.dataset.lg === k));
      NIGHT.forEach((mc) => { if (!inst[mc.key]) return; inst[mc.key].setCursor(frac);
        const live = ui.$(`[data-live="${mc.key}"]`, root);
        if (live) live.textContent = nfmt(inst[mc.key].valueAt(frac), mc) + ' ' + mc.unit; });
    }
    function clear() {
      cursor.style.opacity = '0'; timeEl.textContent = 'Drag across any chart';
      stageEl.classList.remove('show'); hyp.classList.remove('np-dim');
      blks.forEach((b) => b.classList.remove('active')); legs.forEach((l) => l.classList.remove('active'));
      NIGHT.forEach((mc) => { if (!inst[mc.key]) return; inst[mc.key].setCursor(null);
        const live = ui.$(`[data-live="${mc.key}"]`, root); if (live) live.textContent = ''; });
    }
    const fracFrom = (e) => { const r = stack.getBoundingClientRect();
      const x = (e.touches ? e.touches[0].clientX : e.clientX) - r.left; return x / r.width; };
    let dragging = false;
    stack.addEventListener('pointerdown', (e) => { dragging = true; scrub(fracFrom(e)); try { stack.setPointerCapture(e.pointerId); } catch {} });
    stack.addEventListener('pointermove', (e) => { if (e.pointerType === 'mouse' || dragging) scrub(fracFrom(e)); });
    stack.addEventListener('pointerup', () => { dragging = false; });      // touch keeps the last reading
    stack.addEventListener('pointerleave', () => { if (!dragging) clear(); }); // mouse-out resets to summary
  }

  function hyp(sl, total) {
    const order = ['awake', 'rem', 'light', 'deep'];
    return `<div class="hyp">
      ${order.map((k) => `
        <div class="hyp-lane">
          <span class="hyp-cap">${STAGE[k].name}</span>
          <div class="hyp-track">
            ${sl.hypnogram.filter((seg) => seg.key === k).map((seg, i) => {
              const left = seg.from / total * 100, w = (seg.to - seg.from) / total * 100;
              return `<span class="hyp-blk" style="left:${left}%;width:${w}%;background:${STAGE[k].color};animation-delay:${i * 30}ms"></span>`;
            }).join('')}
          </div>
        </div>`).join('')}
    </div>`;
  }
  function gi(name, tint) { return `<span class="kg" style="--tint:var(--accent-${tint})">${icon(name, 16)}</span>`; }
  function statBlk(cap, val) { return `<div class="stat-blk"><div class="sb-cap">${cap}</div><div class="sb-val">${val}</div></div>`; }
  function fmtDur(m) { m = Math.round(m); const h = Math.floor(m / 60), mm = m % 60; return h ? `${h}h ${mm}m` : `${mm}m`; }
})(window.NOOP = window.NOOP || {});
