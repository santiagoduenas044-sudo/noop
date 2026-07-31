/* ============================================================================
   NOOP · Premium UI — Home / Today
   The flagship dashboard: a living recovery hero, the day's charge ring, an AI
   "Today's Story", live vitals, sleep performance, recovery drivers, and coach
   recommendations. Editorial layout, generous whitespace, everything animates.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  NS.pages.home = {
    title: 'Today', eyebrow: 'Thursday · Jul 31', tint: 'recovery',
    render() {
      const d = data;
      const recBand = d.band(d.recovery);
      const bandLabel = recBand === 'high' ? 'Recovered' : recBand === 'mid' ? 'Moderate' : 'Low';
      return `
      <!-- Hero: recovery + charge -->
      <section class="home-hero" data-reveal style="--i:0">
        <div class="hero-glow" style="--g:var(--accent-recovery)"></div>
        <div class="hero-rings">
          <div class="ring-stack">
            ${ui.ring({ value: d.recovery, size: 232, stroke: 15, tint: 'recovery', unit: '%', cap: bandLabel, numFs: 68 })}
          </div>
        </div>
        <div class="hero-side">
          <div class="hero-metric">
            <span class="eyebrow">Day Strain</span>
            <div class="metric"><div class="value" style="font-size:30px"><span class="count" data-to="${d.strain}">0</span></div></div>
            <div class="bar" style="--tint:var(--accent-strain);margin-top:8px"><i data-w="${(d.strain/21*100).toFixed(0)}"></i></div>
            <span class="hero-metric-sub">Target ${d.strainTarget}</span>
          </div>
          <div class="hero-metric">
            <span class="eyebrow">Sleep</span>
            <div class="metric"><div class="value" style="font-size:30px"><span class="count" data-to="${d.sleepScore}">0</span><span class="unit">%</span></div></div>
            <div class="bar" style="--tint:var(--accent-sleep);margin-top:8px"><i data-w="${d.sleepScore}"></i></div>
            <span class="hero-metric-sub">7h 29m asleep</span>
          </div>
        </div>
      </section>

      <!-- AI story -->
      <section class="ai-card" data-reveal style="--i:1;margin-top:20px" data-route="insights">
        <div class="ai-head"><span class="ai-orb"></span><span class="ai-title">Today's Story</span></div>
        <p class="ai-body">You're <b>recovered and ready</b>. HRV climbed to 96 ms overnight — 12% above baseline — and your resting heart rate settled to 48 bpm. Your body can absorb a solid session today; aim for a strain around <b>14–16</b>.</p>
      </section>

      <!-- Live vitals -->
      <div class="section-title" data-reveal><h2>Live vitals</h2><span class="link" data-route="heart">Heart ›</span></div>
      <div class="grid-2 vitals">
        ${vital({ icon: 'heart', tint: 'heart', label: 'Heart rate', value: d.liveHR, unit: 'bpm', spark: 'hr', live: true, route: 'heart' })}
        ${vital({ icon: 'wave', tint: 'hrv', label: 'HRV', value: d.hrv, unit: 'ms', spark: 'hrv', delta: '+12%', dir: 'up', route: 'readiness' })}
        ${vital({ icon: 'lungs', tint: 'recovery', label: 'Respiratory', value: d.respiratory, unit: 'rpm', spark: 'resp', route: 'readiness' })}
        ${vital({ icon: 'drop', tint: 'strain', label: 'Blood oxygen', value: d.spo2, unit: '%', spark: 'spo2', route: 'readiness' })}
      </div>

      <!-- Sleep performance -->
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
      <div class="section-title" data-reveal><h2>Recovery drivers</h2><span class="link" data-route="readiness">All ›</span></div>
      <section class="card" data-reveal>
        ${d.drivers.slice(0, 4).map((c) => driverRow(c)).join('')}
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
      // fill hero bars
      ui.$$('[data-w]', root).forEach((i) => requestAnimationFrame(() => { i.style.width = i.dataset.w + '%'; }));

      // sparklines
      const map = { hr: d.dayHR().filter((_, i) => i % 12 === 0), hrv: d.hrvSeries.slice(-14),
        resp: d.walk(14, 14, .4, 12.5, 16), spo2: d.walk(14, 97, .5, 95, 99) };
      ui.$$('canvas[data-spark]', root).forEach((cv) => {
        charts.spark(cv, map[cv.dataset.spark] || [1,2,3], { color: cv.dataset.tint });
      });

      // sleep stage bar
      const sb = ui.$('[data-stagebar]', root);
      if (sb) {
        const total = d.sleep.hypnogram[d.sleep.hypnogram.length - 1].to;
        sb.innerHTML = d.sleep.hypnogram.map((seg, i) => {
          const w = ((seg.to - seg.from) / total) * 100;
          const heights = { awake: 30, rem: 62, light: 78, deep: 100 };
          return `<span class="seg" style="width:${w}%;height:${heights[seg.key]}%;background:${stageColor(seg.key)};animation-delay:${i*40}ms"></span>`;
        }).join('');
      }

      // recommendation actions
      ui.$$('[data-act]', root).forEach((b) => b.addEventListener('click', (e) => {
        e.stopPropagation(); ui.ripple(e, b);
        if (b.dataset.act === 'start') ui.toast('Activity started · tracking strain');
        else NS.router.go('coach');
      }));

      // live HR nudge
      const liveEl = root.querySelector('.vitals [data-live] .count');
      if (liveEl) {
        setInterval(() => { const v = 60 + Math.round(Math.random() * 8);
          if (document.body.contains(liveEl)) liveEl.textContent = v; }, 2400);
      }
    },
  };

  /* ---- local partials ---- */
  function vital(o) {
    return `
    <div class="card tap vital" data-reveal ${o.route ? `data-route="${o.route}"` : ''} ${o.live ? 'data-live' : ''} style="--tint:var(--accent-${o.tint})">
      <div class="card-head">
        <span class="glyph tint">${icon(o.icon, 17)}</span>
        ${o.live ? `<span class="live-dot"></span>` : o.delta ? `<span class="delta ${o.dir}">${o.delta}</span>` : ''}
      </div>
      <div class="metric">
        <div class="value" style="font-size:30px"><span class="count" data-to="${o.value}">0</span><span class="unit">${o.unit}</span></div>
        <div class="label">${o.label}</div>
      </div>
      <div class="chart" style="margin-top:6px;height:40px"><canvas data-spark="${o.spark}" data-tint="${o.tint}"></canvas></div>
    </div>`;
  }
  function driverRow(c) {
    const dir = c.dir === 'up' ? 'up' : c.dir === 'down' ? 'down' : '';
    return `
    <div class="contrib" style="--tint:var(--accent-${c.tint})">
      <span class="c-name">${c.name}</span>
      <div class="bar"><i style="width:${c.pct}%"></i></div>
      <span class="c-val" style="color:${dir === 'up' ? 'var(--band-high)' : dir === 'down' ? 'var(--band-low)' : 'var(--ink-1)'}">${c.value}<small>${c.unit ? ' '+c.unit : ''}</small></span>
    </div>`;
  }
  function stageColor(k) {
    return ({ awake: 'var(--accent-heart)', rem: 'var(--accent-hrv)',
      light: 'var(--accent-strain)', deep: 'var(--accent-sleep)' })[k];
  }
  function fmtDur(m) { const h = Math.floor(m / 60), mm = m % 60; return h ? `${h}h ${mm}m` : `${mm}m`; }
})(window.NOOP = window.NOOP || {});
