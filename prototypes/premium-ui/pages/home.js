/* ============================================================================
   NOOP · Premium UI — Home / Today (v2, data-rich)
   Keeps the flagship concepts — Recovery, Sleep, Day Strain, Today's Story,
   Live Vitals — but each metric is now a tappable card with a value, unit, mini
   sparkline, baseline comparison, trend and a line of context. Clean at rest,
   deep on demand: every tile drills into the reusable Metric Detail (or its own
   richer screen for Energy / Blood Oxygen).
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  // A rich, tappable vital tile: glyph + trend, value, label, sparkline, baseline.
  function vtile(o) {
    const b = o.baseline;
    const diff = o.raw - b;
    const pct = b ? Math.round((diff / b) * 100) : 0;
    const dir = Math.abs(diff) < (o.eps || 0.05) ? 'flat' : diff > 0 ? 'up' : 'down';
    const good = dir === 'flat' ? null : ((dir === 'up') === o.higherBetter);
    const chipCls = dir === 'flat' ? '' : good ? 'pos' : 'neg';
    const arrow = dir === 'up' ? 'arrowUp' : dir === 'down' ? 'arrowDn' : 'minus';
    const trend = o.live
      ? `<span class="tchip" style="color:var(--accent-heart);background:color-mix(in oklab,var(--accent-heart) 15%,transparent)">
           <span class="lv" style="width:6px;height:6px;border-radius:50%;background:var(--accent-heart);box-shadow:0 0 8px var(--accent-heart)"></span>LIVE</span>`
      : `<span class="tchip ${chipCls}">${icon(arrow, 12)}${dir === 'flat' ? '0%' : Math.abs(pct) + '%'}</span>`;
    const foot = o.foot || (o.live ? 'Streaming from your strap' :
      `${o.higherBetter ? (dir === 'up' ? 'Above' : dir === 'down' ? 'Below' : 'On') : (dir === 'down' ? 'Below' : dir === 'up' ? 'Above' : 'On')} baseline ${o.baseFmt || b}${o.unit ? ' ' + o.unit : ''}`);
    const act = o.metric ? `data-open-metric="${o.metric}"` : `data-route="${o.route}"`;
    return `
    <div class="vtile" data-reveal ${act} style="--tint:var(--accent-${o.tint})">
      <div class="vt-head"><span class="glyph tint" style="width:32px;height:32px;border-radius:10px">${icon(o.icon, 17)}</span>${trend}</div>
      <div class="vt-val"><span class="n count" data-to="${o.raw}">0</span><span class="u">${o.unit || ''}</span></div>
      <div class="vt-label">${o.label}</div>
      <div class="vt-spark"><canvas data-spark2="${o.spark}" data-tint="${o.tint}"></canvas></div>
      <div class="vt-foot">${o.live ? '' : icon(arrow, 11)}<span>${foot}</span></div>
    </div>`;
  }

  NS.pages.home = {
    title: 'Today', eyebrow: 'Thursday · Aug 1', tint: 'recovery',
    render() {
      const d = data;
      const recBand = d.band(d.recovery);
      const bandLabel = recBand === 'high' ? 'Recovered' : recBand === 'mid' ? 'Moderate' : 'Low';
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

      <!-- Rich vitals grid -->
      <div class="vgrid" style="margin-top:var(--s-4)">
        ${vtile({ icon:'hrv', tint:'hrv', label:'HRV', raw:d.hrv, unit:'ms', spark:'hrv', metric:'hrv',
          baseline:d.baselines.hrv, higherBetter:true, foot:`+${d.hrv-d.baselines.hrv} ms vs baseline` })}
        ${vtile({ icon:'heart', tint:'heart', label:'Resting HR', raw:d.rhr, unit:'bpm', spark:'rhr', metric:'rhr',
          baseline:d.baselines.rhr, higherBetter:false, foot:`${d.rhr-d.baselines.rhr} bpm vs baseline` })}
        ${vtile({ icon:'lungs', tint:'recovery', label:'Respiratory', raw:d.respiratory, unit:'rpm', spark:'resp', metric:'respiratory',
          baseline:d.baselines.respiratory, higherBetter:false, eps:0.3, foot:'Steady · on baseline' })}
        ${vtile({ icon:'spo2', tint:'strain', label:'Blood Oxygen', raw:d.spo2Latest, unit:'%', spark:'spo2', route:'spo2',
          baseline:d.baselines.spo2, higherBetter:true, foot:'Nightly avg 96% · normal' })}
        ${vtile({ icon:'flame', tint:'flame', label:'Active Energy', raw:d.activeKcal, unit:'kcal', spark:'active', route:'energy',
          baseline:d.baselines.active, higherBetter:true, foot:`+${Math.round((d.activeKcal-d.baselines.active)/d.baselines.active*100)}% vs typical` })}
        ${vtile({ icon:'steps', tint:'recovery', label:'Steps', raw:d.stepsToday, unit:'', spark:'steps', metric:'steps',
          baseline:d.baselines.steps, higherBetter:true, foot:`${Math.round(d.stepsToday/d.stepGoal*100)}% of 10k goal` })}
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
      const d = data;
      ui.$$('[data-w]', root).forEach((i) => requestAnimationFrame(() => { i.style.width = i.dataset.w + '%'; }));

      // rich-tile sparklines
      const map = {
        hrv: d.hrvSeries.slice(-14), rhr: d.rhrSeries.slice(-14),
        resp: d.respSeries.slice(-14), spo2: d.spo2Series.slice(-14),
        active: d.activeSeries.slice(-14), steps: d.stepsSeries.slice(-14).map((v) => v / 100),
      };
      ui.$$('canvas[data-spark2]', root).forEach((cv) => charts.spark(cv, map[cv.dataset.spark2] || [1, 2, 3], { color: cv.dataset.tint, height: 34 }));

      // live HR mini strip
      const strip = ui.$('[data-hr-strip]', root);
      if (strip) charts.spark(strip, d.dayHR().filter((_, i) => i % 8 === 0).slice(-24), { color: 'heart', height: 56 });

      // tap → metric detail / dedicated screens
      ui.$$('[data-open-metric]', root).forEach((el) => el.addEventListener('click', (e) => {
        if (e.target.closest('[data-noroute]')) return; ui.ripple(e, el); NS.openMetric(el.dataset.openMetric);
      }));

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

      // live HR nudge
      const liveEl = ui.$('[data-live-hr]', root);
      if (liveEl) setInterval(() => { const v = 58 + Math.round(Math.random() * 9);
        if (document.body.contains(liveEl)) liveEl.textContent = v; }, 2400);
    },
  };

  function stageColor(k) {
    return ({ awake: 'var(--accent-heart)', rem: 'var(--accent-hrv)', light: 'var(--accent-strain)', deep: 'var(--accent-sleep)' })[k];
  }
  function fmtDur(m) { const h = Math.floor(m / 60), mm = m % 60; return h ? `${h}h ${mm}m` : `${mm}m`; }
})(window.NOOP = window.NOOP || {});
