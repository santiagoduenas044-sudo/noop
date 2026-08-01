/* ============================================================================
   NOOP · Premium UI — Icon & brand system (v2)
   One cohesive family: 24px grid, 1.75px stroke, round caps/joins, geometric and
   minimal so nav, metrics and glyphs read as ONE system. Offline & themeable via
   currentColor. Access with NOOP.icon(name, size).

   Brand:
     NOOP.logomark(size)  → monochrome inline glyph (currentColor) — the "pulse-O"
     NOOP.appIcon(size)   → rounded-square app icon (purple gradient + white mark)
     NOOP.wordmark(size)  → mark + "NOOP" lettering, for headers
   The mark is an open recovery-arc ring with a single orbiting node — a nod to the
   ring at the heart of NOOP, distilled to a premium, minimal monogram.
   ============================================================================ */
(function (NS) {
  'use strict';
  const P = (d) => `<path d="${d}"/>`;
  const S = (inner, extra = '') =>
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" ` +
    `stroke-linecap="round" stroke-linejoin="round" ${extra}>${inner}</svg>`;

  const I = {
    /* ---------------------------------------------------------- navigation */
    // Home — a soft arch roof over a hearth (rounded, friendly, distinct from a plain house).
    home:   S(P('M4 11.2 12 4l8 7.2') + P('M6 10v9a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1v-9') + P('M10 20v-4.5a2 2 0 0 1 4 0V20')),
    // Sleep — crescent with a small star; unified with the recovery-arc language.
    moon:   S(P('M20 13.4A7.5 7.5 0 1 1 10.6 4 6 6 0 0 0 20 13.4Z') + P('M17 4.2l.7 1.6 1.6.7-1.6.7-.7 1.6-.7-1.6-1.6-.7 1.6-.7Z')),
    sleep:  S(P('M20 13.4A7.5 7.5 0 1 1 10.6 4 6 6 0 0 0 20 13.4Z') + P('M17 4.2l.7 1.6 1.6.7-1.6.7-.7 1.6-.7-1.6-1.6-.7 1.6-.7Z')),
    // Heart — a beat inside the heart, so "Heart" reads as cardiac, not "like".
    heart:  S(P('M12 20.3c-.5-.3-6.6-4.2-8.8-8.4C1.8 8.9 3.3 5 6.7 5c2 0 3.4 1.3 4.2 2.6l1.1-.01c.8-1.3 2.2-2.6 4.2-2.6 3.4 0 4.9 3.9 3.5 6.9-.9 1.7-2.6 3.5-4.2 4.9') + P('M4.5 12.4h3l1.4-2.6 1.9 4.3 1.5-3 .9 1.3H17')),
    // Coach — a facetted spark/gem (the AI "orb" distilled). Cohesive with sparkles.
    coach:  S(P('M12 3.2 14 8l4.8 2-4.8 2-2 4.8L10 12 5.2 10 10 8Z') + P('M18.5 15.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7Z')),
    // Trends — an upward line over an axis with a leading node.
    trends: S(P('M4 4v15a1 1 0 0 0 1 1h15') + P('M7.5 15l3.2-3.6 2.7 2.4L19 8') + `<circle cx="19" cy="8" r="1.5" fill="currentColor" stroke="none"/>`),
    // More — a rounded 2×2 grid, distinct from the 3-dot menu.
    more:   S(`<rect x="4" y="4" width="6.5" height="6.5" rx="2"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="2"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="2"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="2"/>`),

    /* ------------------------------------------------------ metrics / signals */
    // Recovery — an upward pulse cradled in an open shield-arc.
    recovery: S(P('M12 3.5c2.6 1.4 4.6 1.8 6.5 1.9v6c0 4.6-3 7.4-6.5 9.1C8.5 18.8 5.5 16 5.5 11.4v-6c1.9-.1 3.9-.5 6.5-1.9Z') + P('M8.5 12h2l1.3-2.4L13.5 14l1-2h1')),
    // Strain — filled-feel lightning within the round grid.
    strain: S(P('M12.8 3 6.5 12.6H11l-.8 8.4 6.4-9.9H12.2Z')),
    bolt:   S(P('M12.8 3 6.5 12.6H11l-.8 8.4 6.4-9.9H12.2Z')),
    // Calories / energy — a clean flame.
    flame:  S(P('M12 21c3.6 0 6-2.5 6-5.9 0-2.4-1.4-4-2.6-5.4-.5 1.2-1.2 1.8-2 2 .4-2 .1-4.6-2.4-6.7-.3 2.6-1.6 3.9-2.9 5.2C6.9 11 6 12.7 6 15.1 6 18.5 8.4 21 12 21Z') + P('M12 21c1.7 0 2.8-1.2 2.8-2.8 0-1.5-1-2.2-1.5-3-.7 1-1.6 1.3-1.9 2.4-.6-.4-.7-1-.7-1.6-1 .7-1.5 1.5-1.5 2.5C9.2 19.8 10.3 21 12 21Z')),
    // Steps — two footprints.
    steps:  S(P('M8.5 4c1.2 0 1.9 1.2 1.9 3s-.5 4-.5 5.4c0 1-.6 1.6-1.6 1.6s-1.6-.7-1.6-1.9c0-1.1.2-1.8.2-3C6.9 6.2 7.1 4 8.5 4Z') + P('M7 17.4c.2-1 .8-1.4 1.8-1.4s1.6.5 1.6 1.5c0 1.4-.6 2.5-1.9 2.5-1 0-1.8-.6-1.5-2.6Z') + P('M15.5 7c1.2 0 1.9 1.2 1.9 3s-.5 4-.5 5.4c0 1-.6 1.6-1.6 1.6s-1.6-.7-1.6-1.9c0-1.1.2-1.8.2-3C13.9 9.2 14.1 7 15.5 7Z') + P('M14 20.4c.2-1 .8-1.4 1.8-1.4s1.6.5 1.6 1.5' )),
    // HRV — a symmetric variability waveform.
    hrv:    S(P('M3 12h2.5l1.5-5 2.5 10 2-7 2 4 1.5-2H21')),
    wave:   S(P('M3 12c1.4 0 1.6-3 3-3s1.4 6 3 6 1.6-9 3-9 1.4 6 3 6 1.6-3 3-3')),
    // Respiratory — lungs with a breath channel.
    lungs:  S(P('M12 3v8.5') + P('M12 8c0-1.6-1-2.2-2.1-2.2-1.3 0-2.1 1.1-2.1 3.2v3c-2.1 0-3.3 1.2-3.3 4.2 0 2.1 1.1 3.3 2.7 3.3S9.3 22 9.3 19.7v-6.8') + P('M12 8c0-1.6 1-2.2 2.1-2.2 1.3 0 2.1 1.1 2.1 3.2v3c2.1 0 3.3 1.2 3.3 4.2 0 2.1-1.1 3.3-2.7 3.3S14.7 22 14.7 19.7v-6.8')),
    thermo: S(P('M14 14.6V5a2 2 0 1 0-4 0v9.6a4 4 0 1 0 4 0Z') + P('M12 14V8.5') + `<circle cx="12" cy="17.5" r="1.4" fill="currentColor" stroke="none"/>`),
    // Blood oxygen — droplet holding an O₂ node.
    drop:   S(P('M12 3.2c1.2 1.4 5.5 5.6 5.5 9.6a5.5 5.5 0 0 1-11 0c0-4 4.3-8.2 5.5-9.6Z') + `<circle cx="12" cy="13" r="2.4"/>`),
    spo2:   S(P('M12 3.2c1.2 1.4 5.5 5.6 5.5 9.6a5.5 5.5 0 0 1-11 0c0-4 4.3-8.2 5.5-9.6Z') + `<circle cx="12" cy="13" r="2.4"/>`),
    // Sleep depth — layered "z" waves.
    zzz:    S(P('M6 7h5L6 12.5h5') + P('M13.5 11h4l-4 5.5h4')),
    // Stress — a gauge dial with a needle.
    stress: S(P('M4.5 17a8 8 0 1 1 15 0') + P('M12 14.5 15.5 10') + `<circle cx="12" cy="15" r="1.6" fill="currentColor" stroke="none"/>`),
    // Today — a sun/day marker (used for the Today's Story eyebrow if needed).
    today:  S(`<circle cx="12" cy="12" r="4"/>` + P('M12 3v2.4M12 18.6V21M3 12h2.4M18.6 12H21M5.4 5.4l1.7 1.7M16.9 16.9l1.7 1.7M18.6 5.4l-1.7 1.7M7.1 16.9l-1.7 1.7')),
    timer:  S(`<circle cx="12" cy="13.5" r="7.5"/>` + P('M12 13.5V9.5M9.5 2.5h5M18.5 6.5l1.3-1.3')),
    scale:  S(P('M4 20h16') + `<circle cx="12" cy="8" r="4.2"/>` + P('M12 8V6')),
    // Workout / exercise — a runner.
    run:    S(`<circle cx="15.5" cy="5.3" r="1.7"/>` + P('M13.8 8.2l-3 2.1.6 3.2 2.4 1.7-1.4 4.3') + P('M11.4 13.5 8 13l-1.6 3') + P('M14 11.6l2.7 1 2.3-.6')),

    /* ------------------------------------------------------------------ ui */
    chevR:  S(P('M9 5l7 7-7 7')),
    chevL:  S(P('M15 5l-7 7 7 7')),
    chevD:  S(P('M5 9l7 7 7-7')),
    chevU:  S(P('M5 15l7-7 7 7')),
    bell:   S(P('M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6') + P('M10 19a2 2 0 0 0 4 0')),
    plus:   S(P('M12 5v14M5 12h14')),
    close:  S(P('M6 6l12 12M18 6 6 18')),
    share:  S(P('M12 3v12M12 3 8.5 6.5M12 3l3.5 3.5') + P('M6 12v6a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1v-6')),
    check:  S(P('M5 12.5 10 17 19 7')),
    dots:   S(`<circle cx="5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="19" cy="12" r="1.4"/>`),
    info:   S(`<circle cx="12" cy="12" r="9"/>` + P('M12 11v5M12 8h.01')),
    calendar:S(`<rect x="3.5" y="5" width="17" height="16" rx="3"/>` + P('M3.5 10h17M8 3v4M16 3v4')),
    search: S(`<circle cx="11" cy="11" r="6.5"/>` + P('M20 20l-3.6-3.6')),
    clock:  S(`<circle cx="12" cy="12" r="8.5"/>` + P('M12 7.5V12l3 2')),
    filter: S(P('M4 6h16M7 12h10M10 18h4')),
    target: S(`<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4"/><circle cx="12" cy="12" r="1" fill="currentColor" stroke="none"/>`),

    /* --------------------------------------------------------- signals / misc */
    sparkles:S(P('M12 3l1.7 4.6L18 9l-4.3 1.4L12 15l-1.7-4.6L6 9l4.3-1.4Z') + P('M18.5 14.5l.7 1.9 1.9.7-1.9.7-.7 1.9-.7-1.9-1.9-.7 1.9-.7Z')),
    smile:  S(`<circle cx="12" cy="12" r="9"/>` + P('M8.5 14.5a4.5 4.5 0 0 0 7 0M9 9.5h.01M15 9.5h.01')),
    wine:   S(P('M8 3h8l-.6 6a3.4 3.4 0 0 1-6.8 0Z') + P('M12 15v4M9 21h6')),
    coffee: S(P('M4 8h13v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5Z') + P('M17 9h1.5a2.5 2.5 0 0 1 0 5H17M7 3v2M11 3v2')),
    plate:  S(`<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4"/>`),
    pill:   S(`<rect x="3" y="9" width="18" height="6" rx="3" transform="rotate(-45 12 12)"/>` + P('M8.5 8.5l7 7')),
    photo:  S(`<rect x="3.5" y="5" width="17" height="14" rx="3"/><circle cx="8.5" cy="10" r="1.6"/>` + P('M4 17l4.5-4 3.5 3 3-2.5 5 4')),
    apple:  S(P('M15.5 3c-1.2.1-2.4.8-3.1 1.7-.6.8-1.1 2-.9 3.2 1.3.1 2.6-.7 3.3-1.6.7-.8 1.1-2 .7-3.3Z') + P('M12 8c-1-.6-2-.8-3-.5-2.4.7-3.6 3.4-2.8 6.4.5 1.9 2 5 4 5 .9 0 1.2-.5 2.3-.5s1.4.5 2.3.5c2 0 3.4-3.4 3.8-4.9-2.6-1-2.9-4.6-.1-5.9-.8-1.1-2.1-1.6-3.4-1.2-.9.3-1.4.6-2.4.6')),
    watch:  S(`<rect x="7" y="7" width="10" height="10" rx="3"/>` + P('M9 7l.7-4h4.6L15 7M9 17l.7 4h4.6l.7-4')),
    lock:   S(`<rect x="4.5" y="10" width="15" height="10" rx="2.5"/>` + P('M8 10V7a4 4 0 0 1 8 0v3')),
    shield: S(P('M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6Z') + P('M9 12l2 2 4-4')),
    flask:  S(P('M9 3h6M10 3v6l-4.5 8A2 2 0 0 0 7.3 20h9.4a2 2 0 0 0 1.8-3L14 9V3') + P('M8 15h8')),
    user:   S(`<circle cx="12" cy="8" r="4"/>` + P('M4.5 20a7.5 7.5 0 0 1 15 0')),
    gear:   S(`<circle cx="12" cy="12" r="3"/>` + P('M19.4 13a7.9 7.9 0 0 0 0-2l2-1.5-2-3.4-2.3 1a7.6 7.6 0 0 0-1.7-1L14.9 3H9.1l-.5 2.6a7.6 7.6 0 0 0-1.7 1l-2.3-1-2 3.4L4.6 11a7.9 7.9 0 0 0 0 2l-2 1.5 2 3.4 2.3-1a7.6 7.6 0 0 0 1.7 1l.5 2.6h5.8l.5-2.6a7.6 7.6 0 0 0 1.7-1l2.3 1 2-3.4Z')),
    palette:S(P('M12 3a9 9 0 0 0 0 18c1.4 0 2-1 2-2 0-1.4-1.3-1.6-1.3-3 0-.8.7-1.5 1.8-1.5H16a5 5 0 0 0 5-5c0-3.6-4-6.5-9-6.5Z') + P('M7.5 12h.01M9.5 8.5h.01M13.5 7.5h.01')),
    download:S(P('M12 3v12M12 15l-4-4M12 15l4-4') + P('M5 20h14')),
    book:   S(P('M5 4h11a2 2 0 0 1 2 2v13a1 1 0 0 1-1.4.9L12 18l-4.6 1.9A1 1 0 0 1 6 19V6') + P('M9 4v13')),
    insight:S(P('M9.5 18h5M10 21h4') + P('M12 3a6 6 0 0 0-4 10.5c.7.7 1 1.2 1 2v.5h6v-.5c0-.8.3-1.3 1-2A6 6 0 0 0 12 3Z')),
    grid:   S(`<rect x="4" y="4" width="6.5" height="6.5" rx="2"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="2"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="2"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="2"/>`),
    arrowUp:S(P('M12 19V5M12 5l-5 5M12 5l5 5')),
    arrowDn:S(P('M12 5v14M12 19l-5-5M12 19l5-5')),
    arrowR: S(P('M5 12h14M19 12l-5-5M19 12l-5 5')),
    minus:  S(P('M6 12h12')),
    dot:    S(`<circle cx="12" cy="12" r="3.4" fill="currentColor" stroke="none"/>`),
    // legacy alias
    logo:   S(`<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3.4"/>`, 'stroke-width="1.8"'),
  };

  NS.icon = function (name, size) {
    const svg = I[name] || I.info;
    const s = size ? ` style="width:${size}px;height:${size}px"` : '';
    return svg.replace('<svg ', `<svg width="${size||20}" height="${size||20}"${s} `);
  };
  NS.icons = I;

  /* ------------------------------------------------------------------ Brand */
  // The NOOP mark: a 300° recovery-arc ring (open at the top-right, echoing the
  // gauge) with a solid orbiting node riding the gap. Minimal, premium, unique.
  // `col` lets the appIcon paint it white while the inline version uses currentColor.
  NS.logomark = function (size = 28, col) {
    const c = col || 'currentColor';
    const sw = Math.max(2, size * 0.11);
    return `
    <svg width="${size}" height="${size}" viewBox="0 0 48 48" fill="none" aria-hidden="true"
         style="width:${size}px;height:${size}px">
      <path d="M24 7.5a16.5 16.5 0 1 1 -11.7 4.85" stroke="${c}" stroke-width="${sw}"
            stroke-linecap="round"/>
      <circle cx="24" cy="7.5" r="${sw * 1.35}" fill="${c}"/>
      <circle cx="24" cy="24" r="${sw * 1.05}" fill="${c}" opacity="0.9"/>
    </svg>`;
  };

  // Rounded-square app icon: deep violet→indigo gradient, soft inner glow, white mark.
  NS.appIcon = function (size = 64) {
    const id = 'ai' + Math.random().toString(36).slice(2, 6);
    const r = size * 0.225;
    return `
    <svg width="${size}" height="${size}" viewBox="0 0 64 64" aria-label="NOOP"
         style="width:${size}px;height:${size}px;display:block">
      <defs>
        <linearGradient id="${id}g" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#8B6BFF"/>
          <stop offset="0.5" stop-color="#6E52E0"/>
          <stop offset="1" stop-color="#3B2E8F"/>
        </linearGradient>
        <radialGradient id="${id}h" cx="0.32" cy="0.24" r="0.8">
          <stop offset="0" stop-color="#B79BFF" stop-opacity="0.65"/>
          <stop offset="1" stop-color="#B79BFF" stop-opacity="0"/>
        </radialGradient>
      </defs>
      <rect x="1" y="1" width="62" height="62" rx="${r}" fill="url(#${id}g)"/>
      <rect x="1" y="1" width="62" height="62" rx="${r}" fill="url(#${id}h)"/>
      <rect x="1.5" y="1.5" width="61" height="61" rx="${r - 0.5}" fill="none"
            stroke="#fff" stroke-opacity="0.18"/>
      <g transform="translate(32,32) scale(0.66) translate(-24,-24)">
        <path d="M24 7.5a16.5 16.5 0 1 1 -11.7 4.85" stroke="#fff" stroke-width="5"
              stroke-linecap="round"/>
        <circle cx="24" cy="7.5" r="4.2" fill="#fff"/>
        <circle cx="24" cy="24" r="3.4" fill="#fff" fill-opacity="0.92"/>
      </g>
    </svg>`;
  };

  // Mark + "NOOP" lettering for the header.
  NS.wordmark = function (size = 22) {
    return `<span class="wordmark" style="display:inline-flex;align-items:center;gap:8px">
      ${NS.logomark(size, 'currentColor')}
      <span style="font-weight:800;letter-spacing:0.02em;font-size:${size * 0.82}px">NOOP</span>
    </span>`;
  };
})(window.NOOP = window.NOOP || {});
