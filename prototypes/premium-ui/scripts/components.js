/* ============================================================================
   NOOP · Premium UI — Component builders & interaction primitives
   Small, composable factories that return HTML strings (pages concatenate them)
   plus behaviours wired after mount: rings, count-up numbers, staggered reveal,
   ripples, segmented controls, expandable cards, bottom-sheets and toasts.
   Designed to read cleanly and map 1:1 onto SwiftUI views later.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { icon } = NS;

  /* ---------------------------------------------------- tiny DOM helpers */
  const h = (html) => { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; };
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  /* ---------------------------------------------------- SVG progress ring */
  // buildRing({value, size, stroke, tint, label, sub, mega, gradient})
  function ring(o) {
    const size = o.size || 200, stroke = o.stroke || 14;
    const r = (size - stroke) / 2, c = 2 * Math.PI * r;
    const id = 'g' + Math.random().toString(36).slice(2, 7);
    const t = o.tint || 'recovery';
    const c1 = `var(--accent-${t})`, c2 = `var(--accent-${t}-2, var(--accent-${t}))`;
    const numFs = o.numFs || Math.round(size * 0.30);
    return `
    <div class="ring-wrap" style="width:${size}px;height:${size}px">
      <svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
        <defs>
          <linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stop-color="${c2}"/><stop offset="1" stop-color="${c1}"/>
          </linearGradient>
          <filter id="${id}f" x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation="5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
          </filter>
        </defs>
        <circle class="ring-track" cx="${size/2}" cy="${size/2}" r="${r}" stroke-width="${stroke}"/>
        <circle class="ring-prog" cx="${size/2}" cy="${size/2}" r="${r}" stroke-width="${stroke}"
          stroke="url(#${id})" filter="url(#${id}f)"
          stroke-dasharray="${c}" stroke-dashoffset="${c}"
          data-ring="${o.value}" data-circ="${c}" ${o.max ? `data-max="${o.max}"` : ''}/>
      </svg>
      <div class="ring-center">
        <div>
          <div class="num" style="font-size:${numFs}px;color:var(--ink-1)">
            <span class="count" data-to="${o.value}" data-suffix="${o.suffix||''}">0</span>${o.unit ? `<span style="font-size:.42em;color:var(--ink-3);font-weight:600"> ${o.unit}</span>` : ''}
          </div>
          ${o.cap ? `<div class="cap">${o.cap}</div>` : ''}
        </div>
      </div>
    </div>`;
  }

  // Activate rings within root (draw stroke + count number)
  function animateRings(root) {
    $$('.ring-prog', root).forEach((p) => {
      const v = parseFloat(p.dataset.ring), circ = parseFloat(p.dataset.circ);
      const pct = Math.max(0, Math.min(1, v / (p.dataset.max ? +p.dataset.max : 100)));
      requestAnimationFrame(() => { p.style.strokeDashoffset = String(circ * (1 - pct)); });
    });
  }

  /* ---------------------------------------------------- count-up numbers */
  function countUp(root) {
    $$('.count', root).forEach((el) => {
      if (el._done) return; el._done = true;
      const to = parseFloat(el.dataset.to);
      const dec = (el.dataset.to.indexOf('.') > -1) ? 1 : 0;
      const suffix = el.dataset.suffix || '';
      const dur = 1100; let start;
      const step = (ts) => {
        if (!start) start = ts;
        const p = Math.min((ts - start) / dur, 1);
        const e = 1 - Math.pow(1 - p, 3);
        el.textContent = (to * e).toFixed(dec) + suffix;
        if (p < 1) requestAnimationFrame(step); else el.textContent = to.toFixed(dec) + suffix;
      };
      requestAnimationFrame(step);
    });
  }

  /* ---------------------------------------------------- staggered reveal */
  function reveal(root) {
    const items = $$('[data-reveal]', root);
    items.forEach((el, i) => { if (el.style.getPropertyValue('--i') === '') el.style.setProperty('--i', i % 8); });
    const io = new IntersectionObserver((es) => {
      es.forEach((e) => { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
    }, { threshold: 0.08, root: root.closest('.scroll') });
    items.forEach((el) => io.observe(el));
    // reveal above-the-fold immediately
    requestAnimationFrame(() => items.forEach((el) => {
      const r = el.getBoundingClientRect(); if (r.top < window.innerHeight * 1.05) el.classList.add('in');
    }));
  }

  /* ---------------------------------------------------- ripple on press */
  function ripple(e, host) {
    const target = host || e.currentTarget;
    const rect = target.getBoundingClientRect();
    const size = Math.max(rect.width, rect.height);
    const x = (e.clientX ?? rect.left + rect.width / 2) - rect.left - size / 2;
    const y = (e.clientY ?? rect.top + rect.height / 2) - rect.top - size / 2;
    const r = document.createElement('span');
    r.className = 'ripple';
    r.style.cssText = `width:${size}px;height:${size}px;left:${x}px;top:${y}px`;
    if (getComputedStyle(target).position === 'static') target.style.position = 'relative';
    target.appendChild(r);
    setTimeout(() => r.remove(), 700);
  }

  /* ---------------------------------------------------- segmented control */
  // <div class="segment" data-seg>… buttons …</div>; calls onChange(index,value)
  function initSegments(root, onChange) {
    $$('.segment', root).forEach((seg) => {
      if (seg._init) return; seg._init = true;
      const btns = $$('button', seg);
      const thumb = h('<span class="thumb"></span>');
      seg.insertBefore(thumb, seg.firstChild);
      const place = (btn) => { thumb.style.width = btn.offsetWidth + 'px';
        thumb.style.transform = `translateX(${btn.offsetLeft - 4}px)`; };
      let active = btns.find((b) => b.classList.contains('active')) || btns[0];
      requestAnimationFrame(() => place(active));
      btns.forEach((b, i) => b.addEventListener('click', () => {
        btns.forEach((x) => x.classList.remove('active')); b.classList.add('active');
        place(b); active = b;
        onChange && onChange(i, b.dataset.value || b.textContent.trim(), seg);
      }));
      seg._place = () => place(active);
    });
  }

  /* ---------------------------------------------------- expandable cards */
  function initExpandables(root) {
    $$('.expandable [data-toggle]', root).forEach((btn) => {
      if (btn._init) return; btn._init = true;
      btn.addEventListener('click', () => btn.closest('.expandable').classList.toggle('open'));
    });
  }

  /* ---------------------------------------------------- chips (multi-select) */
  function initChips(root) {
    $$('.chip[data-chip]', root).forEach((c) => {
      if (c._init) return; c._init = true;
      c.addEventListener('click', () => { c.classList.toggle('on'); ripple({ currentTarget: c }, c);
        NS.haptic && NS.haptic(); });
    });
  }

  /* ---------------------------------------------------- toggles */
  function initSwitches(root, onToggle) {
    $$('.switch', root).forEach((sw) => {
      if (sw._init) return; sw._init = true;
      sw.addEventListener('click', () => { sw.classList.toggle('on');
        onToggle && onToggle(sw.dataset.key, sw.classList.contains('on')); });
    });
  }

  /* ---------------------------------------------------- bottom sheet */
  let sheetHost;
  function sheet(title, bodyHTML) {
    if (!sheetHost) {
      sheetHost = h('<div><div class="scrim"></div><div class="sheet"></div></div>');
      document.querySelector('.device').appendChild(sheetHost);
    }
    const scrim = $('.scrim', sheetHost), sh = $('.sheet', sheetHost);
    sh.innerHTML = `<div class="grabber"></div><h2>${title}</h2>${bodyHTML}`;
    requestAnimationFrame(() => { scrim.classList.add('show'); sh.classList.add('show'); });
    reveal(sh); countUp(sh); animateRings(sh);
    const close = () => { scrim.classList.remove('show'); sh.classList.remove('show'); };
    scrim.onclick = close;
    // drag-to-dismiss
    let sy = 0, dy = 0, drag = false;
    const grab = $('.grabber', sh);
    const down = (e) => { drag = true; sy = e.touches ? e.touches[0].clientY : e.clientY; sh.style.transition = 'none'; };
    const mv = (e) => { if (!drag) return; dy = Math.max(0, (e.touches ? e.touches[0].clientY : e.clientY) - sy);
      sh.style.transform = `translateY(${dy}px)`; };
    const up = () => { if (!drag) return; drag = false; sh.style.transition = '';
      if (dy > 90) close(); else sh.style.transform = ''; dy = 0; };
    grab.addEventListener('pointerdown', down); window.addEventListener('pointermove', mv);
    window.addEventListener('pointerup', up);
    return { close };
  }

  /* ---------------------------------------------------- toast */
  function toast(msg, kind) {
    let host = $('.toast-host');
    if (!host) { host = h('<div class="toast-host"></div>'); document.querySelector('.device').appendChild(host); }
    const t = h(`<div class="toast">${kind !== false ? `<span class="tk">${icon('check', 16)}</span>` : ''}<span>${esc(msg)}</span></div>`);
    host.appendChild(t);
    setTimeout(() => { t.style.transition = 'opacity .3s, transform .3s';
      t.style.opacity = '0'; t.style.transform = 'translateY(10px)'; setTimeout(() => t.remove(), 300); }, 2100);
  }

  /* ---------------------------------------------------- reusable markup */
  // A metric card with big number + sparkline canvas (populated by page)
  function metricCard(o) {
    return `
    <div class="card tap" data-reveal ${o.route ? `data-route="${o.route}"` : ''}>
      <div class="card-head">
        <div class="lead"><span class="glyph tint" style="--tint:var(--accent-${o.tint})">${icon(o.icon, 18)}</span></div>
        ${o.delta != null ? `<span class="delta ${o.deltaDir}">${icon(o.deltaDir === 'up' ? 'arrowUp' : o.deltaDir==='down'?'arrowDn':'minus', 12)}${o.delta}</span>` : ''}
      </div>
      <div class="metric" style="margin-top:auto">
        <div class="value" style="font-size:34px">${o.value}<span class="unit">${o.unit||''}</span></div>
        <div class="label">${o.label}</div>
      </div>
      ${o.spark ? `<div class="chart" style="margin-top:10px"><canvas data-spark="${o.spark}" data-tint="${o.tint}"></canvas></div>` : ''}
    </div>`;
  }

  function chip(label, tint, on) {
    return `<button class="chip ${on ? 'on' : ''}" data-chip style="--tint:var(--accent-${tint||'gold'})"><span class="swatch"></span>${label}</button>`;
  }

  /* ---------------------------------------------------- consistency dot-grid */
  // One dot per value in `values01` (each 0..1), wrapped every `cols` — a calendar-
  // style regularity read (e.g. bedtime consistency). Brighter/bigger = closer to 1.
  function dotGrid(values01, tintName, cols) {
    cols = cols || 7;
    const dots = values01.map((v) => {
      const op = 0.25 + 0.75 * Math.max(0, Math.min(1, v));
      const scale = 0.6 + 0.4 * Math.max(0, Math.min(1, v));
      return `<span style="width:9px;height:9px;border-radius:3px;background:var(--accent-${tintName});
        opacity:${op.toFixed(2)};transform:scale(${scale.toFixed(2)})"></span>`;
    }).join('');
    return `<div style="display:grid;grid-template-columns:repeat(${cols},1fr);gap:6px;align-items:center">${dots}</div>`;
  }

  NS.ui = {
    h, $, $$, esc, ring, animateRings, countUp, reveal, ripple, initSegments,
    initExpandables, initChips, initSwitches, sheet, toast, metricCard, chip, dotGrid, icon,
  };
})(window.NOOP = window.NOOP || {});
