/* ============================================================================
   NOOP · Premium UI — Home / Today (v3)
   Keeps the flagship concepts — Recovery, Sleep, Day Strain, Today's Story —
   but replaces the hard-to-read pill/bubble weekly visual with a clear ring +
   tick day-strip (tap a day for its real numbers, plus a short narrative), and
   makes the vitals grid fully customizable: "Edit Home" lets you choose which
   of ~20 metrics show, hide the rest, reorder, and pick compact/standard tiles.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  // A rich, tappable vital tile: glyph + trend, value, label, sparkline, baseline.
  function vtile(o) {
    const b = o.baseline;
    const diff = b != null ? o.raw - b : null;
    const pct = (b && diff != null) ? Math.round((diff / b) * 100) : 0;
    const dir = diff == null ? 'flat' : Math.abs(diff) < (o.eps || 0.05) ? 'flat' : diff > 0 ? 'up' : 'down';
    const good = (o.higherBetter == null || dir === 'flat') ? null : ((dir === 'up') === o.higherBetter);
    const chipCls = dir === 'flat' ? '' : good == null ? '' : good ? 'pos' : 'neg';
    const arrow = dir === 'up' ? 'arrowUp' : dir === 'down' ? 'arrowDn' : 'minus';
    const trend = o.live
      ? `<span class="tchip" style="color:var(--accent-heart);background:color-mix(in oklab,var(--accent-heart) 15%,transparent)">
           <span class="lv" style="width:6px;height:6px;border-radius:50%;background:var(--accent-heart);box-shadow:0 0 8px var(--accent-heart)"></span>LIVE</span>`
      : `<span class="tchip ${chipCls}">${icon(arrow, 12)}${dir === 'flat' ? '0%' : Math.abs(pct) + '%'}</span>`;
    const foot = o.foot || (o.live ? 'Streaming from your strap' : b == null ? 'No baseline yet' :
      `${o.higherBetter ? (dir === 'up' ? 'Above' : dir === 'down' ? 'Below' : 'On') : (dir === 'down' ? 'Below' : dir === 'up' ? 'Above' : 'On')} baseline ${o.baseFmt || b}${o.unit ? ' ' + o.unit : ''}`);
    const act = o.metric ? `data-open-metric="${o.metric}"` : `data-route="${o.route}"`;
    const compactCls = o.compact ? ' compact' : '';
    return `
    <div class="vtile${compactCls}" data-reveal ${act} style="--tint:var(--accent-${o.tint})">
      <div class="vt-head"><span class="glyph tint" style="width:32px;height:32px;border-radius:10px">${icon(o.icon, 17)}</span>${trend}</div>
      <div class="vt-val"><span class="n count" data-to="${o.raw}">0</span><span class="u">${o.unit || ''}</span></div>
      <div class="vt-label">${o.label}</div>
      ${o.compact ? '' : `<div class="vt-spark"><canvas data-spark2="${o.spark}" data-tint="${o.tint}"></canvas></div>`}
      <div class="vt-foot">${o.live ? '' : icon(arrow, 11)}<span>${foot}</span></div>
    </div>`;
  }

  // A non-numeric "clock" tile (bedtime / wake time) — same card shape, no delta chip.
  function clockTile(ic, tint, label, timeStr, route, compact) {
    return `
    <div class="vtile${compact ? ' compact' : ''}" data-reveal data-route="${route}" style="--tint:var(--accent-${tint})">
      <div class="vt-head"><span class="glyph tint" style="width:32px;height:32px;border-radius:10px">${icon(ic, 17)}</span></div>
      <div class="vt-val" style="font-size:22px;font-weight:800;margin-top:8px">${timeStr}</div>
      <div class="vt-label">${label}</div>
      ${compact ? '' : '<div class="vt-spark"></div>'}
      <div class="vt-foot"><span>Tap for sleep detail</span></div>
    </div>`;
  }

  // Every metric in the catalog → its real (mock) value + tile markup. Kept as
  // one switch so Home / Edit Home / the catalog all describe the SAME set.
  function tileFor(key, compact) {
    const d = data;
    switch (key) {
      case 'heartRateNow': return vtile({ icon: 'heart', tint: 'heart', label: 'Heart Rate', raw: d.liveHR, unit: 'bpm',
        spark: 'hr', route: 'heart', live: true, compact });
      case 'rhr': return vtile({ icon: 'heart', tint: 'hrv', label: 'Resting HR', raw: d.rhr, unit: 'bpm', spark: 'rhr',
        metric: 'rhr', baseline: d.baselines.rhr, higherBetter: false, compact });
      case 'hrv': return vtile({ icon: 'hrv', tint: 'hrv', label: 'HRV', raw: d.hrv, unit: 'ms', spark: 'hrv',
        metric: 'hrv', baseline: d.baselines.hrv, higherBetter: true, compact });
      case 'respiratory': return vtile({ icon: 'lungs', tint: 'recovery', label: 'Respiratory', raw: d.respiratory, unit: 'rpm',
        spark: 'resp', metric: 'respiratory', baseline: d.baselines.respiratory, higherBetter: false, eps: 0.3, compact });
      case 'spo2': return vtile({ icon: 'spo2', tint: 'strain', label: 'Blood Oxygen', raw: d.spo2Latest, unit: '%',
        spark: 'spo2', route: 'spo2', baseline: d.baselines.spo2, higherBetter: true, compact });
      case 'skinTemp': return vtile({ icon: 'thermo', tint: 'gold', label: 'Skin Temp', raw: d.skinTemp, unit: '°C',
        spark: 'skinTemp', route: 'sleep', baseline: 0, higherBetter: null, foot: 'vs your overnight baseline', compact });
      case 'steps': return vtile({ icon: 'steps', tint: 'recovery', label: 'Steps', raw: d.stepsToday, unit: '',
        spark: 'steps', metric: 'steps', baseline: d.baselines.steps, higherBetter: true, compact });
      case 'active': return vtile({ icon: 'flame', tint: 'flame', label: 'Active Energy', raw: d.activeKcal, unit: 'kcal',
        spark: 'active', route: 'energy', baseline: d.baselines.active, higherBetter: true, compact });
      case 'resting': return vtile({ icon: 'flame', tint: 'gold', label: 'Resting Energy', raw: d.restingKcal, unit: 'kcal',
        spark: 'active', route: 'energy', baseline: null, higherBetter: null, foot: 'Estimated basal rate', compact });
      case 'totalEnergy': return vtile({ icon: 'flame', tint: 'flame', label: 'Total Energy', raw: d.totalKcal, unit: 'kcal',
        spark: 'active', route: 'energy', baseline: null, higherBetter: null, foot: 'Active + resting', compact });
      case 'workouts': return vtile({ icon: 'run', tint: 'strain', label: 'Workouts', raw: d.workouts.length, unit: '',
        spark: 'strain', route: 'strain', baseline: null, higherBetter: null,
        foot: d.workouts.length ? d.workouts[0].name + ' today' : 'None logged today', compact });
      case 'sleepDuration': return vtile({ icon: 'moon', tint: 'sleep', label: 'Sleep Duration', raw: Math.round(d.sleep.asleep / 6) / 10, unit: 'h',
        spark: 'sleep', route: 'sleep', baseline: Math.round(d.sleep.hoursTypicalMin / 6) / 10, higherBetter: true, compact });
      case 'sleepEfficiency': return vtile({ icon: 'check', tint: 'sleep', label: 'Sleep Efficiency', raw: d.sleep.efficiency, unit: '%',
        spark: 'sleep', route: 'sleep', baseline: 85, higherBetter: true, compact });
      case 'restorative': return vtile({ icon: 'moon', tint: 'sleep', label: 'Restorative Sleep', raw: Math.round(d.sleep.restorativeMin / d.sleep.asleep * 100), unit: '%',
        spark: 'sleep', route: 'sleep', baseline: Math.round(d.sleep.restorativeTypicalMin / d.sleep.hoursTypicalMin * 100), higherBetter: true, compact });
      case 'recovery': return vtile({ icon: 'recovery', tint: 'recovery', label: 'Recovery', raw: d.recovery, unit: '%',
        spark: 'recovery', route: 'readiness', baseline: d.baselines.recovery, higherBetter: true, compact });
      case 'strain': return vtile({ icon: 'strain', tint: 'strain', label: 'Effort / Strain', raw: d.strain, unit: '',
        spark: 'strain', route: 'strain', baseline: d.baselines.strain, higherBetter: null, foot: `Target ${d.strainTarget}`, compact });
      case 'stress': return vtile({ icon: 'stress', tint: 'gold', label: 'Stress', raw: d.stressNow, unit: '',
        spark: 'stress', route: 'stress', baseline: 1.4, higherBetter: false, foot: 'Preview · concept only', compact });
      case 'sleepConsistency': return vtile({ icon: 'calendar', tint: 'hrv', label: 'Sleep Consistency', raw: d.sleep.consistency, unit: '%',
        spark: 'consistency', route: 'sleep', baseline: 80, higherBetter: true, compact });
      case 'bedtime': return clockTile('moon', 'sleep', 'Bedtime', d.sleep.times.bed, 'sleep', compact);
      case 'waketime': return clockTile('today', 'gold', 'Wake Time', d.sleep.times.wake, 'sleep', compact);
      case 'sleepDebt': return vtile({ icon: 'timer', tint: 'heart', label: 'Sleep Debt', raw: d.sleep.debt, unit: 'min',
        spark: 'debt', route: 'sleep', baseline: 0, higherBetter: false, foot: 'Running balance', compact });
      default: return '';
    }
  }

  function sparkValuesFor(key) {
    const d = data;
    const map = {
      heartRateNow: d.dayHR().filter((_, i) => i % 8 === 0).slice(-14),
      rhr: d.rhrSeries.slice(-14), hrv: d.hrvSeries.slice(-14), respiratory: d.respSeries.slice(-14),
      spo2: d.spo2Series.slice(-14), skinTemp: d.skinTempNightlySeries.slice(-14),
      steps: d.stepsSeries.slice(-14).map((v) => v / 100), active: d.activeSeries.slice(-14),
      resting: d.activeSeries.slice(-14), totalEnergy: d.activeSeries.slice(-14),
      workouts: d.strainSeries.slice(-14), sleepDuration: d.sleepSeries.slice(-14),
      sleepEfficiency: d.sleepSeries.slice(-14), restorative: d.sleepSeries.slice(-14),
      recovery: d.recSeries.slice(-14), strain: d.strainSeries.slice(-14), stress: d.stressSeries.slice(-14),
      sleepConsistency: d.consistencySeries.slice(-14), sleepDebt: d.sleepDebtLedger.map((n) => n.balanceMin),
    };
    return map[key] || [1, 2, 3];
  }

  NS.pages.home = {
    _layout: null, _hidden: null, _compact: false,
    title: 'Today', eyebrow: 'Thursday · Aug 1', tint: 'recovery',
    ensureLayoutState() {
      if (this._layout) return;
      this._layout = data.defaultHomeLayout.slice();
      const rest = data.metricCatalog.map((m) => m.key).filter((k) => !this._layout.includes(k));
      this._layout = this._layout.concat(rest);
      this._hidden = new Set(data.metricCatalog.map((m) => m.key).filter((k) => !data.defaultHomeLayout.includes(k)));
    },
    visibleKeys() { this.ensureLayoutState(); return this._layout.filter((k) => !this._hidden.has(k)); },

    render() {
      const d = data;
      const recBand = d.band(d.recovery);
      const bandLabel = recBand === 'high' ? 'Recovered' : recBand === 'mid' ? 'Moderate' : 'Low';
      this.ensureLayoutState();
      return `
      <!-- Hero: recovery ring + strain + sleep -->
      <section class="home-hero" data-reveal style="--i:0">
        <div class="hero-glow" style="--g:var(--accent-recovery)"></div>
        <div class="hero-rings" data-route="readiness" style="cursor:pointer">
          ${ui.ring({ value: d.recovery, size: 224, stroke: 15, tint: 'recovery', unit: '%', cap: bandLabel, numFs: 66 })}
        </div>
        <div class="hero-side">
          <div class="hero-metric" data-route="strain" style="cursor:pointer">
            <span class="eyebrow">Day Strain</span>
            <div class="metric"><div class="value" style="font-size:30px"><span class="count" data-to="${d.strain}">0</span></div></div>
            <div class="bar" style="--tint:var(--accent-strain);margin-top:8px"><i data-w="${(d.strain/21*100).toFixed(0)}"></i></div>
            <span class="hero-metric-sub">Target ${d.strainTarget}</span>
          </div>
          <div class="hero-metric" data-route="sleep" style="cursor:pointer">
            <span class="eyebrow">Sleep</span>
            <div class="metric"><div class="value" style="font-size:30px"><span class="count" data-to="${d.sleepScore}">0</span><span class="unit">%</span></div></div>
            <div class="bar" style="--tint:var(--accent-sleep);margin-top:8px"><i data-w="${d.sleepScore}"></i></div>
            <span class="hero-metric-sub">7h 45m asleep</span>
          </div>
        </div>
      </section>

      <!-- Today's Story -->
      <section class="ai-card" data-reveal style="--i:1;margin-top:20px" data-route="insights">
        <div class="ai-head"><span class="ai-orb"></span><span class="ai-title">Today's Story</span>
          <span class="data-badge" style="margin-left:auto"><span class="lv"></span>Updated 6:54 AM</span></div>
        <p class="ai-body">You're <b>recovered and ready</b>. HRV climbed to 96 ms overnight — 12% above baseline — and resting heart rate settled to 48 bpm. Your body can absorb a solid session today; a strain around <b>14–16</b> fits.</p>
        <div class="pillrow" style="margin-top:14px">
          <span class="softpill" style="color:var(--accent-hrv)">${icon('arrowUp',12)} HRV +12%</span>
          <span class="softpill" style="color:var(--accent-recovery)">${icon('check',12)} 5-day recovery streak</span>
          <span class="softpill">${icon('moon',12)} Sleep on target</span>
        </div>
      </section>

      <!-- This week (replaces the pill/bubble visual) -->
      <div class="section-title" data-reveal><h2>This week</h2><span class="link" data-route="trends">Trends ›</span></div>
      <section class="card" data-reveal>
        <div class="week-strip" data-week-strip>
          ${d.week.map((w, i) => weekCol(w, i)).join('')}
        </div>
        <div class="wk-narrative"><span class="wn-ic">${icon('sparkles',16)}</span><p data-week-narrative>${d.weekNarrative()}</p></div>
      </section>

      <!-- Live heart rate -->
      <div class="section-title" data-reveal><h2>Live vitals</h2><span class="link" data-route="heart">Heart ›</span></div>
      <section class="card tap" data-reveal data-route="heart" style="--tint:var(--accent-heart)">
        <div style="display:flex;align-items:center;gap:var(--s-4)">
          <div>
            <div class="metric"><div class="value" style="font-size:38px;color:var(--accent-heart)">
              <span class="count" data-to="${d.liveHR}" data-live-hr>0</span><span class="unit">bpm</span></div>
              <div class="label">Heart rate now</div></div>
          </div>
          <div class="chart" style="flex:1;height:56px"><canvas data-hr-strip></canvas></div>
        </div>
      </section>

      <!-- Customizable vitals grid -->
      <div class="section-title" data-reveal><h2>Your metrics</h2>
        <button class="link" data-edit-home style="display:inline-flex;align-items:center;gap:5px;background:none">${icon('gear',13)} Edit Home</button></div>
      <div class="vgrid" style="margin-top:var(--s-4)" data-vgrid>
        ${this.visibleKeys().map((k) => tileFor(k, this._compact)).join('')}
      </div>

      <!-- Sleep summary -->
      <div class="section-title" data-reveal><h2>Sleep</h2><span class="link" data-route="sleep">Details ›</span></div>
      <section class="card tap" data-reveal data-route="sleep">
        <div class="sleep-row">
          ${ui.ring({ value: d.sleepScore, size: 116, stroke: 10, tint: 'sleep', unit: '%', cap: 'Score', numFs: 34 })}
          <div class="sleep-legend">
            ${d.sleep.stages.map((s) => `
              <div class="sl-row">
                <span class="sl-dot" style="background:${stageColor(s.key)}"></span>
                <span class="sl-name">${s.stage}</span>
                <span class="sl-min">${fmtDur(s.minutes)}</span>
              </div>`).join('')}
          </div>
        </div>
        <div class="stagebar" data-stagebar style="margin-top:16px"></div>
      </section>

      <!-- Recovery drivers -->
      <div class="section-title" data-reveal><h2>Recovery drivers</h2><span class="link" data-route="readiness">Why ›</span></div>
      <section class="card" data-reveal data-route="readiness" style="cursor:pointer">
        ${d.recoveryContribs.map((c) => `
          <div class="contrib" style="--tint:var(--accent-${c.tint})">
            <span class="c-name">${c.name}</span>
            <div class="bar"><i style="width:${c.share * 2.4}%"></i></div>
            <span class="c-val" style="color:${c.dir==='up'?'var(--band-high)':c.dir==='down'?'var(--band-low)':'var(--ink-1)'}">${c.value}<small>${c.unit?' '+c.unit:''}</small></span>
          </div>`).join('')}
      </section>

      <!-- Recommendation -->
      <div class="section-title" data-reveal><h2>Recommended today</h2></div>
      <section class="card tap" data-reveal data-route="coach" style="--tint:var(--accent-gold)">
        <div class="rec">
          <span class="glyph tint" style="--tint:var(--accent-gold)">${icon('flame', 20)}</span>
          <div class="rec-body">
            <div class="rec-title">Aerobic base · Zone 2</div>
            <div class="rec-sub">45–60 min · target strain 12–14 · keeps tomorrow green</div>
          </div>
          <span class="chev">${icon('chevR', 18)}</span>
        </div>
        <div class="rec-actions">
          <button class="btn primary" data-noroute data-act="start">${icon('bolt', 16)} Start activity</button>
          <button class="btn ghost" data-noroute data-act="ask">Ask coach</button>
        </div>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      const d = data, page = this;
      ui.$$('[data-w]', root).forEach((i) => requestAnimationFrame(() => { i.style.width = i.dataset.w + '%'; }));

      wireVitalTiles(root);

      // live HR mini strip
      const strip = ui.$('[data-hr-strip]', root);
      if (strip) charts.spark(strip, d.dayHR().filter((_, i) => i % 8 === 0).slice(-24), { color: 'heart', height: 56 });

      // week strip: tap a day for its real numbers
      ui.$$('[data-week-day]', root).forEach((el) => el.addEventListener('click', (e) => {
        ui.ripple(e, el); openWeekDay(+el.dataset.weekDay);
      }));

      // tap → metric detail / dedicated screens (delegate so re-rendered grids stay wired)
      root.addEventListener('click', (e) => {
        const el = e.target.closest('[data-open-metric]');
        if (el && !e.target.closest('[data-noroute]')) { ui.ripple(e, el); NS.openMetric(el.dataset.openMetric); }
      });

      // sleep stage bar
      const sb = ui.$('[data-stagebar]', root);
      if (sb) {
        const total = d.sleep.hypnogram[d.sleep.hypnogram.length - 1].to;
        sb.innerHTML = d.sleep.hypnogram.map((seg, i) => {
          const w = ((seg.to - seg.from) / total) * 100;
          const heights = { awake: 30, rem: 62, light: 78, deep: 100 };
          return `<span class="seg" style="width:${w}%;height:${heights[seg.key]}%;background:${stageColor(seg.key)};animation-delay:${i * 40}ms"></span>`;
        }).join('');
      }

      ui.$$('[data-act]', root).forEach((b) => b.addEventListener('click', (e) => {
        e.stopPropagation(); ui.ripple(e, b);
        if (b.dataset.act === 'start') ui.toast('Activity started · tracking strain');
        else NS.router.go('coach');
      }));

      // Edit Home
      ui.$('[data-edit-home]', root)?.addEventListener('click', (e) => { ui.ripple(e, e.currentTarget); openEditHome(root, page); });

      // live HR nudge
      const liveEl = ui.$('[data-live-hr]', root);
      if (liveEl) setInterval(() => { const v = 58 + Math.round(Math.random() * 9);
        if (document.body.contains(liveEl)) liveEl.textContent = v; }, 2400);
    },
  };

  // Re-render just the vgrid after Edit Home changes — no full page reload.
  function refreshVitalsGrid(root, page) {
    const vg = ui.$('[data-vgrid]', root); if (!vg) return;
    vg.innerHTML = page.visibleKeys().map((k) => tileFor(k, page._compact)).join('');
    ui.reveal(vg); ui.countUp(vg);
    wireVitalTiles(root);
  }
  function wireVitalTiles(root) {
    ui.$$('canvas[data-spark2]', root).forEach((cv) => {
      if (cv._wired) return; cv._wired = true;
      charts.spark(cv, sparkValuesFor(spark2Key(cv)), { color: cv.dataset.tint, height: 34 });
    });
  }
  // data-spark2 stores the chart key ("hrv","rhr",…) — map back through tileFor's
  // spark names, which already match sparkValuesFor's map keys 1:1 except the
  // couple of aliases below.
  function spark2Key(cv) {
    const raw = cv.dataset.spark2;
    const alias = { hr: 'heartRateNow', consistency: 'sleepConsistency', debt: 'sleepDebt',
      resp: 'respiratory', sleep: 'sleepDuration' };
    return alias[raw] || raw;
  }

  function weekCol(w, i) {
    const size = 38, stroke = 4, r = (size - stroke) / 2, c = 2 * Math.PI * r;
    const pct = Math.max(0, Math.min(1, w.recovery / 100));
    const color = w.recovery >= 67 ? 'var(--band-high)' : w.recovery >= 34 ? 'var(--band-mid)' : 'var(--band-low)';
    return `<div class="wk-col ${w.isToday ? 'today' : ''}" data-week-day="${i}">
      <div class="wk-ring">
        <svg viewBox="0 0 ${size} ${size}">
          <circle class="wk-track" cx="${size/2}" cy="${size/2}" r="${r}" stroke-width="${stroke}"/>
          <circle class="wk-prog" cx="${size/2}" cy="${size/2}" r="${r}" stroke-width="${stroke}"
            stroke="${color}" stroke-dasharray="${c}" stroke-dashoffset="${c*(1-pct)}"/>
        </svg>
        <div class="wk-num">${w.recovery}</div>
      </div>
      <div class="wk-ticks">
        <span class="wk-tick" style="background:var(--accent-strain);opacity:${(0.35+w.strain/21*0.65).toFixed(2)}"></span>
        <span class="wk-tick" style="background:var(--accent-sleep);opacity:${(0.35+w.sleep/100*0.65).toFixed(2)}"></span>
      </div>
      <div class="wk-day">${w.day}</div>
    </div>`;
  }
  function openWeekDay(i) {
    const w = data.week[i];
    ui.sheet(w.day + (w.isToday ? ' · Today' : ''), `
      <p class="note" style="margin-bottom:14px">Ring colour follows the same recovery bands used everywhere in NOOP — green ≥ 67%, amber 34–66%, red below.</p>
      <div class="stat3 c2">
        <div class="stat-blk"><div class="sb-cap">Recovery</div><div class="sb-val">${w.recovery}<small> %</small></div></div>
        <div class="stat-blk"><div class="sb-cap">Strain</div><div class="sb-val">${w.strain.toFixed(1)}</div></div>
      </div>
      <div class="stat3 c2" style="margin-top:14px">
        <div class="stat-blk"><div class="sb-cap">Sleep</div><div class="sb-val">${w.sleep}<small> %</small></div></div>
      </div>`);
  }

  // ------------------------------------------------------------- Edit Home
  function openEditHome(root, page) {
    const catalog = data.metricCatalog;
    const body = () => `
      <p class="note" style="margin:2px 0 14px">Choose which metrics show on Home, reorder them, and pick how much detail you want.</p>
      <div class="compact-toggle">
        <span style="font-size:var(--fs-body);font-weight:600">Compact tiles</span>
        <div class="switch ${page._compact ? 'on' : ''}" data-compact-switch></div>
      </div>
      <div style="height:10px"></div>
      <div data-edit-list>
        ${page._layout.map((k, i) => editRow(catalog.find((m) => m.key === k), i, page)).join('')}
      </div>
      <button class="btn primary block" data-eh-apply style="margin-top:16px">${icon('check',16)} Apply to Home</button>`;
    const { close } = ui.sheet('Edit Home', body());
    setTimeout(() => wireEditSheet(page, close, root), 40);
  }
  function editRow(m, i, page) {
    if (!m) return '';
    const hidden = page._hidden.has(m.key);
    return `<div class="edit-row ${hidden ? 'hidden-item' : ''}" data-edit-row="${m.key}">
      <span class="er-grip">${icon('dots', 16)}</span>
      <div class="er-body"><div class="er-name">${m.name}${m.sometimes ? ' <span class="future-tag" style="padding:2px 6px;font-size:9px">not on every device</span>' : ''}${m.preview ? ' <span class="future-tag" style="padding:2px 6px;font-size:9px">preview</span>' : ''}</div>
        <div class="er-group">${m.group}${m.unit ? ' · ' + m.unit : ''}</div></div>
      <div class="er-actions">
        <button class="er-move" data-move="-1" data-key="${m.key}" ${i === 0 ? 'disabled' : ''}>${icon('chevU', 15)}</button>
        <button class="er-move" data-move="1" data-key="${m.key}" ${i === page._layout.length - 1 ? 'disabled' : ''}>${icon('chevD', 15)}</button>
        <button class="er-eye ${hidden ? 'off' : ''}" data-eye="${m.key}">${icon(hidden ? 'close' : 'check', 15)}</button>
      </div>
    </div>`;
  }
  function wireEditSheet(page, close, root) {
    const sheet = document.querySelector('.sheet'); if (!sheet) return;
    const relist = () => { const list = ui.$('[data-edit-list]', sheet);
      list.innerHTML = page._layout.map((k, i) => editRow(data.metricCatalog.find((m) => m.key === k), i, page)).join('');
      wireRows();
    };
    function wireRows() {
      ui.$$('[data-move]', sheet).forEach((b) => b.addEventListener('click', (e) => {
        ui.ripple(e, b); const k = b.dataset.key, dir = +b.dataset.move;
        const idx = page._layout.indexOf(k), swap = idx + dir;
        if (swap < 0 || swap >= page._layout.length) return;
        [page._layout[idx], page._layout[swap]] = [page._layout[swap], page._layout[idx]];
        relist();
      }));
      ui.$$('[data-eye]', sheet).forEach((b) => b.addEventListener('click', (e) => {
        ui.ripple(e, b); const k = b.dataset.eye;
        if (page._hidden.has(k)) page._hidden.delete(k); else page._hidden.add(k);
        relist();
      }));
    }
    wireRows();
    ui.$('[data-compact-switch]', sheet)?.addEventListener('click', (e) => {
      const sw = e.currentTarget; sw.classList.toggle('on'); page._compact = sw.classList.contains('on');
    });
    ui.$('[data-eh-apply]', sheet)?.addEventListener('click', () => { close(); refreshVitalsGrid(root, page); ui.toast('Home updated'); });
  }

  function stageColor(k) {
    return ({ awake: 'var(--accent-heart)', rem: 'var(--accent-hrv)', light: 'var(--accent-strain)', deep: 'var(--accent-sleep)' })[k];
  }
  function fmtDur(m) { const h = Math.floor(m / 60), mm = m % 60; return h ? `${h}h ${mm}m` : `${mm}m`; }
})(window.NOOP = window.NOOP || {});
