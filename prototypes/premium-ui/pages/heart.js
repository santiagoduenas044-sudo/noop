/* ============================================================================
   NOOP · Premium UI — Heart rate  (the showcase screen)
   A live BPM with an animated pulse + halo, a real-time ECG ribbon, the
   day-in-the-life HR chart with zone shading, HR zones with time-in-zone, and
   resting / max / recovery stats with weekly & monthly graphs.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, charts, icon } = NS;

  NS.pages.heart = {
    title: 'Heart', eyebrow: 'Live · resting 48 bpm', tint: 'heart',
    render() {
      const d = data;
      return `
      <!-- Live hero -->
      <section class="heart-hero" data-reveal>
        <div class="hero-glow" style="--g:var(--accent-heart)"></div>
        <div class="pulse-cluster">
          <span class="pulse-halo"></span>
          <span class="pulse-halo" style="animation-delay:.46s"></span>
          <div class="pulse-heart" style="--beat:.95s">${icon('heart', 62)}</div>
        </div>
        <div class="heart-read">
          <div class="value" style="font-size:64px;font-weight:800;letter-spacing:-.03em"><span class="count" data-to="${d.liveHR}" data-live-bpm>0</span></div>
          <div class="label" style="letter-spacing:.14em;text-transform:uppercase;font-size:11px;color:var(--ink-3);font-weight:600">bpm · live</div>
        </div>
        <div class="chart ecg" style="width:100%;margin-top:8px"><canvas data-ecg></canvas></div>
      </section>

      <!-- key stats -->
      <div class="grid-3" data-reveal>
        ${stat('Resting', d.rhr, 'bpm', 'hrv')}
        ${stat('Average', 72, 'bpm', 'gold')}
        ${stat('Max', 178, 'bpm', 'heart')}
      </div>

      <!-- Day chart -->
      <div class="section-title" data-reveal><h2>Today</h2><span class="link">00:00 – now</span></div>
      <section class="card" data-reveal>
        <div class="chart"><canvas data-hr-day></canvas></div>
        <div class="axis"><span>12a</span><span>6a</span><span>12p</span><span>6p</span><span>now</span></div>
      </section>

      <!-- Zones -->
      <div class="section-title" data-reveal><h2>Zones today</h2><span class="link">2h 30m active</span></div>
      <section class="card" data-reveal>
        <div class="zones">
          ${d.hrZones.map((z) => zoneRow(z)).join('')}
        </div>
      </section>

      <!-- Recovery HR + trends -->
      <div class="grid-2" data-reveal>
        <section class="card" style="--tint:var(--accent-recovery)">
          <div class="card-head"><h3 style="font-size:15px">Recovery HR</h3></div>
          <div class="metric"><div class="value" style="font-size:34px"><span class="count" data-to="32">0</span><span class="unit">bpm</span></div>
            <div class="label">1-min drop after effort</div></div>
          <span class="delta up" style="margin-top:8px">${icon('arrowUp',12)} Excellent</span>
        </section>
        <section class="card mini" style="--tint:var(--accent-heart)">
          <span class="glyph tint" style="margin-bottom:10px">${icon('drop',16)}</span>
          <div class="metric"><div class="value" style="font-size:26px">97<span class="unit">%</span></div><div class="label">Blood oxygen</div></div>
        </section>
      </div>

      <div class="section-title" data-reveal><h2>Resting HR trend</h2>
        <div class="segment" data-seg><button class="active" data-value="7">Week</button><button data-value="30">Month</button></div>
      </div>
      <section class="card" data-reveal>
        <div class="trend-head"><div class="metric"><div class="value" style="font-size:26px"><span data-avg>48</span><span class="unit">bpm avg</span></div><div class="label">Lower is better</div></div>
          <span class="delta down">${icon('arrowDn',12)} −2 bpm</span></div>
        <div class="chart" style="margin-top:8px"><canvas data-rhr-trend></canvas></div>
        <div class="axis" data-axis></div>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      const d = data;
      // ECG
      const ecg = ui.$('[data-ecg]', root);
      if (ecg) this._ecg = charts.liveECG(ecg, { height: 110, beat: d.liveHR });
      // day HR
      const day = ui.$('[data-hr-day]', root);
      if (day) charts.heartDay(day, d.dayHR(), { height: 200,
        labels: Array.from({ length: 288 }, (_, i) => fmtClock(i)) });
      // zone bars width
      const totalActive = d.hrZones.reduce((a, z) => a + (z.name === 'Resting' ? 0 : z.minutes), 0);
      ui.$$('[data-zw]', root).forEach((i) => {
        const m = +i.dataset.zm; requestAnimationFrame(() => { i.style.width = Math.max(4, m / 60 * 100) + '%'; });
      });
      // trend
      const cv = ui.$('[data-rhr-trend]', root), axis = ui.$('[data-axis]', root), avg = ui.$('[data-avg]', root);
      const draw = (n) => {
        const s = d.rhrSeries.slice(-n);
        charts.area(cv, s, { color: 'hrv', height: 150, labels: s.map((_, i) => '−' + (n-1-i) + 'd'), fmt: (v)=>v+' bpm' });
        if (avg) avg.textContent = Math.round(s.reduce((a,b)=>a+b,0)/s.length);
        if (axis) axis.innerHTML = (n === 7 ? data.DAYS : ['4w','3w','2w','1w','now']).map((l)=>`<span>${l}</span>`).join('');
      };
      draw(7);
      ui.initSegments(root, (i, v) => draw(+v));

      // live bpm + pulse tempo wobble
      const live = ui.$('[data-live-bpm]', root);
      const heart = ui.$('.pulse-heart', root);
      const halos = ui.$$('.pulse-halo', root);
      if (live) this._t = setInterval(() => {
        if (!document.body.contains(live)) return clearInterval(this._t);
        const v = 58 + Math.round(Math.random() * 10); live.textContent = v;
        const beat = (60 / v).toFixed(2) + 's';
        heart && heart.style.setProperty('--beat', beat);
        halos.forEach((x) => x.style.setProperty('--beat', beat));
      }, 1600);
    },
  };

  function stat(label, val, unit, tint) {
    return `<div class="card mini" data-reveal style="--tint:var(--accent-${tint})">
      <div class="metric"><div class="value" style="font-size:26px"><span class="count" data-to="${val}">0</span><span class="unit">${unit}</span></div>
      <div class="label">${label}</div></div></div>`;
  }
  function zoneRow(z) {
    return `<div class="zone" style="--tint:var(--accent-${z.color})">
      <div class="z-name">${z.name}<small>${z.sub} bpm</small></div>
      <div class="bar"><i data-zw data-zm="${z.minutes}" style="background:var(--accent-${z.color})"></i></div>
      <div class="z-time">${fmtDur(z.minutes)}</div></div>`;
  }
  function fmtDur(m){ const h=Math.floor(m/60),mm=m%60; return h?`${h}h${mm?' '+mm+'m':''}`:`${mm}m`; }
  function fmtClock(i){ const h=Math.floor(i/12), m=(i%12)*5; return `${(h%12)||12}:${String(m).padStart(2,'0')}${h<12?'am':'pm'}`; }
})(window.NOOP = window.NOOP || {});
