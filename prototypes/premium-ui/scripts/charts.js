/* ============================================================================
   NOOP · Premium UI — Chart engine
   Bespoke canvas charts: smooth (Catmull-Rom) area/line with gradient fill +
   ambient glow and a draw-on reveal, animated bar columns, sparklines, and the
   day-in-the-life heart-rate ribbon with zone shading. All HiDPI-crisp and
   interactive (crosshair + floating tooltip). No SVG polylines, no libraries.
   ============================================================================ */
(function (NS) {
  'use strict';

  const cssVar = (n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  const easeOut = (t) => 1 - Math.pow(1 - t, 3);

  // Resolve an accent token like "recovery" → its two hex stops.
  function tint(name) {
    const map = {
      recovery: ['--accent-recovery', '--accent-recovery-2'],
      strain:   ['--accent-strain', '--accent-strain-2'],
      sleep:    ['--accent-sleep', '--accent-sleep-2'],
      heart:    ['--accent-heart', '--accent-heart-2'],
      hrv:      ['--accent-hrv', '--accent-hrv'],
      gold:     ['--accent-gold', '--accent-gold-2'],
      flame:    ['--accent-flame', '--accent-flame-2'],
    };
    const [a, b] = map[name] || map.gold;
    return [cssVar(a), cssVar(b)];
  }

  // Set up a HiDPI canvas; returns {ctx,w,h,dpr}.
  function prep(canvas, height) {
    const dpr = Math.min(window.devicePixelRatio || 1, 2.5);
    const w = canvas.clientWidth || canvas.parentElement.clientWidth || 300;
    const h = height || canvas.clientHeight || 160;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    canvas.style.height = h + 'px';
    const ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    return { ctx, w, h, dpr };
  }

  // Catmull-Rom → bezier for silky curves through the points.
  function smoothPath(ctx, pts) {
    if (pts.length < 2) return;
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = pts[i - 1] || pts[i];
      const p1 = pts[i];
      const p2 = pts[i + 1];
      const p3 = pts[i + 2] || p2;
      const c1x = p1.x + (p2.x - p0.x) / 6;
      const c1y = p1.y + (p2.y - p0.y) / 6;
      const c2x = p2.x - (p3.x - p1.x) / 6;
      const c2y = p2.y - (p3.y - p1.y) / 6;
      ctx.bezierCurveTo(c1x, c1y, c2x, c2y, p2.x, p2.y);
    }
  }

  function scalePoints(data, w, h, pad, min, max) {
    const n = data.length;
    const span = (max - min) || 1;
    const innerW = w - pad.l - pad.r;
    const innerH = h - pad.t - pad.b;
    return data.map((v, i) => ({
      x: pad.l + (n === 1 ? innerW / 2 : (i / (n - 1)) * innerW),
      y: pad.t + innerH - ((v - min) / span) * innerH,
      v, i,
    }));
  }

  /* --------------------------------------------------------- Area / line */
  // opts: { color:'recovery', height, min, max, fill:true, glow:true,
  //         markers:false, labels:[], onHover, interactive:true }
  function area(canvas, data, opts = {}) {
    const height = opts.height || 170;
    const color = opts.color || 'recovery';
    const [c1, c2] = tint(color);
    const pad = opts.pad || { l: 6, r: 6, t: 14, b: 8 };
    const min = opts.min != null ? opts.min : Math.min(...data) - (Math.max(...data)-Math.min(...data)) * 0.15 - 1;
    const max = opts.max != null ? opts.max : Math.max(...data) + (Math.max(...data)-Math.min(...data)) * 0.2 + 1;

    let raf, start;
    const render = (progress) => {
      const { ctx, w, h } = prep(canvas, height);
      const pts = scalePoints(data, w, h, pad, min, max);
      const shown = Math.max(2, Math.floor(lerp(0, pts.length, easeOut(progress))));
      const vis = pts.slice(0, shown);
      // partial last point interpolation for buttery draw
      if (shown < pts.length) {
        const frac = (lerp(0, pts.length, easeOut(progress))) - (shown - 1);
        const a = pts[shown - 1], b = pts[shown] || a;
        vis[vis.length] = { x: lerp(a.x, b.x, frac), y: lerp(a.y, b.y, frac) };
      }

      // baseline grid (faint)
      if (opts.grid !== false) {
        ctx.strokeStyle = cssVar('--hairline');
        ctx.lineWidth = 1;
        for (let g = 0; g <= 2; g++) {
          const y = pad.t + (h - pad.t - pad.b) * (g / 2);
          ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(w - pad.r, y); ctx.stroke();
        }
      }

      // fill
      if (opts.fill !== false) {
        ctx.beginPath(); smoothPath(ctx, vis);
        ctx.lineTo(vis[vis.length - 1].x, h - pad.b);
        ctx.lineTo(vis[0].x, h - pad.b); ctx.closePath();
        const grad = ctx.createLinearGradient(0, pad.t, 0, h);
        grad.addColorStop(0, hexA(c1, 0.34));
        grad.addColorStop(0.55, hexA(c1, 0.10));
        grad.addColorStop(1, hexA(c1, 0.0));
        ctx.fillStyle = grad; ctx.fill();
      }

      // glow underlay
      if (opts.glow !== false) {
        ctx.save();
        ctx.shadowColor = hexA(c1, 0.55); ctx.shadowBlur = 16;
        ctx.beginPath(); smoothPath(ctx, vis);
        ctx.lineWidth = 3; ctx.lineJoin = 'round'; ctx.lineCap = 'round';
        ctx.strokeStyle = hexA(c1, 0.9); ctx.stroke();
        ctx.restore();
      }
      // crisp stroke on top (gradient along X)
      const lg = ctx.createLinearGradient(pad.l, 0, w - pad.r, 0);
      lg.addColorStop(0, c2); lg.addColorStop(1, c1);
      ctx.beginPath(); smoothPath(ctx, vis);
      ctx.lineWidth = 2.6; ctx.lineJoin = 'round'; ctx.lineCap = 'round';
      ctx.strokeStyle = lg; ctx.stroke();

      // leading dot
      const tip = vis[vis.length - 1];
      ctx.beginPath(); ctx.arc(tip.x, tip.y, 3.6, 0, 7); ctx.fillStyle = c1; ctx.fill();
      ctx.beginPath(); ctx.arc(tip.x, tip.y, 6.5, 0, 7); ctx.strokeStyle = hexA(c1, 0.4); ctx.lineWidth = 2; ctx.stroke();

      // markers
      if (opts.markers) {
        vis.forEach((p) => { if (p.v == null) return;
          ctx.beginPath(); ctx.arc(p.x, p.y, 2.4, 0, 7); ctx.fillStyle = cssVar('--bg-1');
          ctx.fill(); ctx.lineWidth = 1.6; ctx.strokeStyle = c1; ctx.stroke(); });
      }
      canvas._pts = pts; canvas._pad = pad; canvas._h = h;
    };

    const anim = (ts) => {
      if (!start) start = ts;
      const p = clamp((ts - start) / (opts.dur || 900), 0, 1);
      render(p);
      if (p < 1) raf = requestAnimationFrame(anim);
    };
    // only animate when visible
    onVisible(canvas, () => { start = 0; cancelAnimationFrame(raf); raf = requestAnimationFrame(anim); });
    if (opts.interactive !== false) attachHover(canvas, color, opts);
    return { redraw: () => { start = 0; render(1); } };
  }

  /* --------------------------------------------------------- Bars */
  // opts: { color, height, min:0, labels, highlight:index, values:true }
  function bars(canvas, data, opts = {}) {
    const height = opts.height || 150;
    const color = opts.color || 'strain';
    const [c1, c2] = tint(color);
    const pad = { l: 4, r: 4, t: 16, b: 6 };
    const max = opts.max != null ? opts.max : Math.max(...data) * 1.15;
    const min = opts.min != null ? opts.min : 0;
    let raf, start;

    const render = (progress) => {
      const { ctx, w, h } = prep(canvas, height);
      const n = data.length;
      const innerW = w - pad.l - pad.r;
      const gap = Math.min(10, innerW / n * 0.34);
      const bw = (innerW - gap * (n - 1)) / n;
      const innerH = h - pad.t - pad.b;
      data.forEach((v, i) => {
        const bh = ((v - min) / (max - min)) * innerH * easeOut(clamp(progress * 1.4 - i * 0.03, 0, 1));
        const x = pad.l + i * (bw + gap);
        const y = pad.t + innerH - bh;
        const isHi = opts.highlight === i;
        const g = ctx.createLinearGradient(0, y, 0, y + bh);
        if (isHi) { g.addColorStop(0, c1); g.addColorStop(1, c2); }
        else { g.addColorStop(0, hexA(c1, 0.6)); g.addColorStop(1, hexA(c1, 0.18)); }
        ctx.fillStyle = g;
        if (isHi) { ctx.shadowColor = hexA(c1, 0.6); ctx.shadowBlur = 14; }
        roundRect(ctx, x, y, bw, Math.max(bh, 2), Math.min(bw / 2, 6));
        ctx.fill(); ctx.shadowBlur = 0;
      });
      canvas._bars = { bw, gap, pad, innerH, max, min, data };
    };
    const anim = (ts) => { if (!start) start = ts;
      const p = clamp((ts - start) / (opts.dur || 800), 0, 1); render(p);
      if (p < 1) raf = requestAnimationFrame(anim); };
    onVisible(canvas, () => { start = 0; cancelAnimationFrame(raf); raf = requestAnimationFrame(anim); });
    if (opts.interactive !== false) attachBarHover(canvas, color, opts);
  }

  /* --------------------------------------------------------- Sparkline */
  function spark(canvas, data, opts = {}) {
    const height = opts.height || 40;
    const color = opts.color || 'recovery';
    const [c1] = tint(color);
    const pad = { l: 2, r: 2, t: 6, b: 4 };
    const min = Math.min(...data), max = Math.max(...data);
    let raf, start;
    const render = (progress) => {
      const { ctx, w, h } = prep(canvas, height);
      const pts = scalePoints(data, w, h, pad, min - 1, max + 1);
      const shown = Math.max(2, Math.floor(pts.length * easeOut(progress)));
      const vis = pts.slice(0, shown);
      ctx.beginPath(); smoothPath(ctx, vis);
      ctx.lineTo(vis[vis.length-1].x, h); ctx.lineTo(vis[0].x, h); ctx.closePath();
      const g = ctx.createLinearGradient(0, 0, 0, h);
      g.addColorStop(0, hexA(c1, 0.28)); g.addColorStop(1, hexA(c1, 0));
      ctx.fillStyle = g; ctx.fill();
      ctx.beginPath(); smoothPath(ctx, vis);
      ctx.strokeStyle = c1; ctx.lineWidth = 2; ctx.lineCap = 'round'; ctx.stroke();
      const t = vis[vis.length-1];
      ctx.beginPath(); ctx.arc(t.x, t.y, 2.6, 0, 7); ctx.fillStyle = c1; ctx.fill();
    };
    const anim = (ts) => { if (!start) start = ts;
      const p = clamp((ts - start) / 700, 0, 1); render(p);
      if (p < 1) raf = requestAnimationFrame(anim); };
    onVisible(canvas, () => { start = 0; cancelAnimationFrame(raf); raf = requestAnimationFrame(anim); });
  }

  /* --------------------------------------------------------- Day heart-rate ribbon */
  // zones: [{min, color}] ascending or from data spec. Shades under the line.
  function heartDay(canvas, data, opts = {}) {
    const height = opts.height || 200;
    const [c1, c2] = tint('heart');
    const pad = { l: 4, r: 4, t: 18, b: 8 };
    const min = 40, max = Math.max(...data) + 8;
    let raf, start;
    const render = (progress) => {
      const { ctx, w, h } = prep(canvas, height);
      const pts = scalePoints(data, w, h, pad, min, max);
      const shown = Math.max(2, Math.floor(pts.length * easeOut(progress)));
      const vis = pts.slice(0, shown);
      // zone bands (horizontal tints)
      const bands = [
        { from: 40, to: 114, c: '--accent-hrv', a: 0.05 },
        { from: 114, to: 133, c: '--accent-recovery', a: 0.06 },
        { from: 133, to: 152, c: '--accent-gold', a: 0.06 },
        { from: 152, to: max, c: '--accent-heart', a: 0.07 },
      ];
      bands.forEach((b) => {
        const y1 = pad.t + (h-pad.t-pad.b) * (1 - (Math.min(b.to,max)-min)/(max-min));
        const y2 = pad.t + (h-pad.t-pad.b) * (1 - (b.from-min)/(max-min));
        ctx.fillStyle = hexA(cssVar(b.c), b.a);
        ctx.fillRect(pad.l, y1, w-pad.l-pad.r, y2-y1);
      });
      // fill
      ctx.beginPath(); smoothPath(ctx, vis);
      ctx.lineTo(vis[vis.length-1].x, h-pad.b); ctx.lineTo(vis[0].x, h-pad.b); ctx.closePath();
      const g = ctx.createLinearGradient(0, pad.t, 0, h);
      g.addColorStop(0, hexA(c1, 0.30)); g.addColorStop(1, hexA(c1, 0));
      ctx.fillStyle = g; ctx.fill();
      // line
      ctx.save(); ctx.shadowColor = hexA(c1, 0.5); ctx.shadowBlur = 12;
      ctx.beginPath(); smoothPath(ctx, vis);
      ctx.strokeStyle = c1; ctx.lineWidth = 2.2; ctx.lineCap = 'round'; ctx.stroke(); ctx.restore();
      canvas._pts = pts; canvas._pad = pad; canvas._h = h;
    };
    const anim = (ts) => { if (!start) start = ts;
      const p = clamp((ts - start) / 1200, 0, 1); render(p);
      if (p < 1) raf = requestAnimationFrame(anim); };
    onVisible(canvas, () => { start = 0; cancelAnimationFrame(raf); raf = requestAnimationFrame(anim); });
    attachHover(canvas, 'heart', { labels: opts.labels, fmt: (v) => Math.round(v) + ' bpm' });
  }

  /* --------------------------------------------------------- Live ECG trace */
  // A continuously scrolling synthetic ECG. Returns a stop() handle.
  function liveECG(canvas, opts = {}) {
    const height = opts.height || 120;
    const [c1] = tint('heart');
    let t = 0, raf; const speed = opts.speed || 1.4;
    const beat = opts.beat || 62; // bpm
    function wave(x) { // one PQRST-ish complex
      const p = ((x % 1) + 1) % 1;
      if (p < 0.10) return Math.sin(p / 0.10 * Math.PI) * 0.12;      // P
      if (p < 0.16) return 0;
      if (p < 0.19) return -0.18;                                    // Q
      if (p < 0.23) return 1.0;                                      // R
      if (p < 0.27) return -0.28;                                    // S
      if (p < 0.45) return Math.sin((p - 0.27) / 0.18 * Math.PI) * 0.22; // T
      return 0;
    }
    const render = () => {
      const { ctx, w, h } = prep(canvas, height);
      const mid = h * 0.56; const amp = h * 0.34;
      const cycles = w / 120; // px per beat
      ctx.beginPath();
      for (let px = 0; px <= w; px += 2) {
        const phase = (px / 120) - t;
        const y = mid - wave(phase) * amp;
        px === 0 ? ctx.moveTo(px, y) : ctx.lineTo(px, y);
      }
      const g = ctx.createLinearGradient(0, 0, w, 0);
      g.addColorStop(0, hexA(c1, 0.05)); g.addColorStop(0.7, hexA(c1, 0.7)); g.addColorStop(1, c1);
      ctx.strokeStyle = g; ctx.lineWidth = 2; ctx.lineJoin = 'round';
      ctx.save(); ctx.shadowColor = hexA(c1, 0.6); ctx.shadowBlur = 10; ctx.stroke(); ctx.restore();
      // leading blip
      const lead = mid - wave(w / 120 - t) * amp;
      ctx.beginPath(); ctx.arc(w - 1, lead, 3, 0, 7); ctx.fillStyle = c1; ctx.fill();
      t += (speed * beat / 60) / 60;
      raf = requestAnimationFrame(render);
    };
    onVisible(canvas, () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(render); });
    return { stop: () => cancelAnimationFrame(raf) };
  }

  /* --------------------------------------------------------- Overnight scrub chart */
  // A compact area/line chart whose CURSOR is driven externally (by a shared
  // scrubber), so several charts + a hypnogram can be synchronised on one timeline.
  // No internal pointer handlers. Returns { valueAt(frac), setCursor(frac|null) }.
  function overnight(canvas, data, opts = {}) {
    const height = opts.height || 64;
    const color = opts.color || 'heart';
    const [c1] = tint(color);
    const pad = opts.pad || { l: 0, r: 0, t: 10, b: 6 };
    const rangePad = (Math.max(...data) - Math.min(...data)) * 0.18 + 0.4;
    const min = opts.min != null ? opts.min : Math.min(...data) - rangePad;
    const max = opts.max != null ? opts.max : Math.max(...data) + rangePad;
    let raf, start;
    const render = (progress) => {
      const { ctx, w, h } = prep(canvas, height);
      const pts = scalePoints(data, w, h, pad, min, max);
      const shown = Math.max(2, Math.floor(pts.length * easeOut(progress)));
      const vis = pts.slice(0, shown);
      ctx.beginPath(); smoothPath(ctx, vis);
      ctx.lineTo(vis[vis.length - 1].x, h - pad.b); ctx.lineTo(vis[0].x, h - pad.b); ctx.closePath();
      const g = ctx.createLinearGradient(0, pad.t, 0, h);
      g.addColorStop(0, hexA(c1, 0.24)); g.addColorStop(1, hexA(c1, 0));
      ctx.fillStyle = g; ctx.fill();
      ctx.beginPath(); smoothPath(ctx, vis);
      ctx.lineWidth = 1.8; ctx.lineJoin = 'round'; ctx.lineCap = 'round'; ctx.strokeStyle = c1;
      ctx.save(); ctx.shadowColor = hexA(c1, 0.4); ctx.shadowBlur = 6; ctx.stroke(); ctx.restore();
      canvas._pts = pts;
    };
    const anim = (ts) => { if (!start) start = ts; const p = clamp((ts - start) / (opts.dur || 800), 0, 1); render(p); if (p < 1) raf = requestAnimationFrame(anim); };
    onVisible(canvas, () => { start = 0; cancelAnimationFrame(raf); raf = requestAnimationFrame(anim); });

    function overlay() {
      let ov = canvas._ov;
      if (!ov) { ov = document.createElement('canvas'); ov.style.cssText = 'position:absolute;inset:0;pointer-events:none';
        canvas.parentElement.style.position = 'relative'; canvas.parentElement.appendChild(ov); canvas._ov = ov; }
      return ov;
    }
    function pointAt(frac) {
      const pts = canvas._pts; if (!pts) return null;
      const t = clamp(frac, 0, 1) * (pts.length - 1), i = Math.floor(t), f = t - i;
      const a = pts[i], b = pts[Math.min(pts.length - 1, i + 1)];
      return { x: lerp(a.x, b.x, f), y: lerp(a.y, b.y, f) };
    }
    return {
      valueAt(frac) {
        const t = clamp(frac, 0, 1) * (data.length - 1), i = Math.floor(t), f = t - i;
        return lerp(data[i], data[Math.min(data.length - 1, i + 1)], f);
      },
      setCursor(frac) {
        const ov = overlay(), dpr = Math.min(window.devicePixelRatio || 1, 2.5);
        ov.width = canvas.width; ov.height = canvas.height;
        ov.style.width = canvas.clientWidth + 'px'; ov.style.height = canvas.clientHeight + 'px';
        const ctx = ov.getContext('2d'); ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.clearRect(0, 0, ov.clientWidth, ov.clientHeight);
        if (frac == null) return;
        const p = pointAt(frac); if (!p) return;
        ctx.beginPath(); ctx.arc(p.x, p.y, 4.2, 0, 7); ctx.fillStyle = cssVar('--bg-1'); ctx.fill();
        ctx.lineWidth = 2.4; ctx.strokeStyle = c1; ctx.stroke();
      },
    };
  }

  /* --------------------------------------------------------- Hover plumbing */
  function attachHover(canvas, color, opts = {}) {
    const tip = ensureTip(canvas);
    const [c1] = tint(color);
    const move = (e) => {
      const pts = canvas._pts; if (!pts) return;
      const rect = canvas.getBoundingClientRect();
      const x = (e.touches ? e.touches[0].clientX : e.clientX) - rect.left;
      let nearest = pts[0], dmin = Infinity;
      pts.forEach((p) => { const d = Math.abs(p.x - x); if (d < dmin) { dmin = d; nearest = p; } });
      redrawWithCursor(canvas, nearest, c1);
      const label = (opts.labels && opts.labels[nearest.i]) || '';
      const val = opts.fmt ? opts.fmt(nearest.v) : String(nearest.v);
      tip.innerHTML = `<div class="tip-v">${val}</div>${label ? `<div class="tip-l">${label}</div>` : ''}`;
      tip.style.left = nearest.x + 'px'; tip.style.top = nearest.y + 'px';
      tip.classList.add('show');
    };
    const leave = () => { tip.classList.remove('show'); const pts = canvas._pts; if (pts) redrawWithCursor(canvas, null, c1); };
    canvas.addEventListener('pointermove', move);
    canvas.addEventListener('pointerleave', leave);
    canvas.addEventListener('touchmove', move, { passive: true });
    canvas.addEventListener('touchend', leave);
  }
  function redrawWithCursor(canvas, pt, c1) {
    // lightweight overlay pass — redraw a crosshair without touching the base chart
    if (!canvas._pts) return;
    // We re-render base by dispatching a soft redraw via stored renderer isn't kept;
    // instead draw crosshair on a sibling overlay to avoid clearing the animated chart.
    let ov = canvas._overlay;
    if (!ov) {
      ov = document.createElement('canvas');
      ov.style.cssText = 'position:absolute;inset:0;pointer-events:none';
      canvas.parentElement.style.position = 'relative';
      canvas.parentElement.appendChild(ov);
      canvas._overlay = ov;
    }
    const dpr = Math.min(window.devicePixelRatio || 1, 2.5);
    ov.width = canvas.width; ov.height = canvas.height;
    ov.style.width = canvas.clientWidth + 'px'; ov.style.height = canvas.clientHeight + 'px';
    const ctx = ov.getContext('2d'); ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, ov.clientWidth, ov.clientHeight);
    if (!pt) return;
    ctx.strokeStyle = hexA(c1, 0.35); ctx.lineWidth = 1; ctx.setLineDash([4, 4]);
    ctx.beginPath(); ctx.moveTo(pt.x, 6); ctx.lineTo(pt.x, canvas._h - 4); ctx.stroke();
    ctx.setLineDash([]);
    ctx.beginPath(); ctx.arc(pt.x, pt.y, 5, 0, 7); ctx.fillStyle = cssVar('--bg-1');
    ctx.fill(); ctx.lineWidth = 2.4; ctx.strokeStyle = c1; ctx.stroke();
  }
  function attachBarHover(canvas, color, opts = {}) {
    const tip = ensureTip(canvas);
    const move = (e) => {
      const b = canvas._bars; if (!b) return;
      const rect = canvas.getBoundingClientRect();
      const x = (e.touches ? e.touches[0].clientX : e.clientX) - rect.left;
      const i = clamp(Math.floor((x - b.pad.l) / (b.bw + b.gap)), 0, b.data.length - 1);
      const cx = b.pad.l + i * (b.bw + b.gap) + b.bw / 2;
      const v = b.data[i];
      const y = b.pad.t + b.innerH - ((v - b.min) / (b.max - b.min)) * b.innerH;
      tip.innerHTML = `<div class="tip-v">${opts.fmt ? opts.fmt(v) : v}</div>${opts.labels ? `<div class="tip-l">${opts.labels[i]||''}</div>` : ''}`;
      tip.style.left = cx + 'px'; tip.style.top = y + 'px'; tip.classList.add('show');
    };
    const leave = () => tip.classList.remove('show');
    canvas.addEventListener('pointermove', move);
    canvas.addEventListener('pointerleave', leave);
    canvas.addEventListener('touchmove', move, { passive: true });
    canvas.addEventListener('touchend', leave);
  }
  function ensureTip(canvas) {
    canvas.parentElement.style.position = 'relative';
    let tip = canvas.parentElement.querySelector('.chart-tip');
    if (!tip) { tip = document.createElement('div'); tip.className = 'chart-tip';
      canvas.parentElement.appendChild(tip); }
    return tip;
  }

  /* --------------------------------------------------------- helpers */
  function roundRect(ctx, x, y, w, h, r) {
    r = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  }
  function hexA(hex, a) {
    hex = (hex || '#000').trim();
    if (hex.startsWith('rgb')) return hex;
    const c = hex.replace('#', '');
    const n = c.length === 3 ? c.split('').map((x) => x + x).join('') : c;
    const r = parseInt(n.slice(0, 2), 16), g = parseInt(n.slice(2, 4), 16), b = parseInt(n.slice(4, 6), 16);
    return `rgba(${r},${g},${b},${a})`;
  }
  // Fire cb once the element scrolls into view (for entrance animations).
  function onVisible(el, cb) {
    if (el._io) el._io.disconnect();
    const io = new IntersectionObserver((es) => {
      es.forEach((e) => { if (e.isIntersecting) { cb(); } });
    }, { threshold: 0.2, root: el.closest('.scroll') });
    io.observe(el); el._io = io;
    // if already visible, kick immediately next frame
    requestAnimationFrame(() => { const r = el.getBoundingClientRect();
      if (r.top < window.innerHeight && r.bottom > 0) cb(); });
  }

  NS.charts = { area, bars, spark, heartDay, liveECG, overnight, tint, hexA };
})(window.NOOP = window.NOOP || {});
