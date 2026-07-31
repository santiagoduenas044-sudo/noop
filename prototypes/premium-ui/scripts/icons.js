/* ============================================================================
   NOOP · Premium UI — Icon set
   Hand-tuned inline SVG icons (1.6px stroke, 24px grid). Offline & themeable via
   currentColor. Access with NOOP.icon(name, size). Keeps the app self-contained.
   ============================================================================ */
(function (NS) {
  'use strict';
  const P = (d) => `<path d="${d}"/>`;
  const S = (inner, extra = '') =>
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" ` +
    `stroke-linecap="round" stroke-linejoin="round" ${extra}>${inner}</svg>`;

  const I = {
    // ---- navigation ----
    home:   S(P('M3 10.5 12 3l9 7.5') + P('M5 9.5V20a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9.5')),
    moon:   S(P('M20 14.5A8 8 0 0 1 9.5 4a7 7 0 1 0 10.5 10.5Z')),
    bolt:   S(P('M13 2 4.5 13.5H11l-1 8.5L19.5 10H13Z')),
    heart:  S(P('M12 20s-7-4.6-9.4-9C1 8 2.5 4.5 6 4.5c2 0 3.2 1.2 4 2.3.8-1.1 2-2.3 4-2.3 3.5 0 5 3.5 3.4 6.5C19 15.4 12 20 12 20Z')),
    coach:  S(`<circle cx="12" cy="12" r="3.2"/>` + P('M12 3v2.4M12 18.6V21M3 12h2.4M18.6 12H21M5.6 5.6l1.7 1.7M16.7 16.7l1.7 1.7M18.4 5.6l-1.7 1.7M7.3 16.7l-1.7 1.7')),
    book:   S(P('M5 4h11a2 2 0 0 1 2 2v13a1 1 0 0 1-1.4.9L12 18l-4.6 1.9A1 1 0 0 1 6 19V6') + P('M9 4v13')),
    trends: S(P('M4 19V5M4 15l4.5-4.5 3.5 3.5L20 6') + P('M20 6h-4M20 6v4')),
    insight:S(P('M9.5 18h5M10 21h4') + P('M12 3a6 6 0 0 0-4 10.5c.7.7 1 1.2 1 2v.5h6v-.5c0-.8.3-1.3 1-2A6 6 0 0 0 12 3Z')),
    grid:   S(`<rect x="3.5" y="3.5" width="7" height="7" rx="1.6"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.6"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.6"/><rect x="13.5" y="13.5" width="7" height="7" rx="1.6"/>`),
    gear:   S(`<circle cx="12" cy="12" r="3"/>` + P('M19.4 13a7.9 7.9 0 0 0 0-2l2-1.5-2-3.4-2.3 1a7.6 7.6 0 0 0-1.7-1L14.9 3H9.1l-.5 2.6a7.6 7.6 0 0 0-1.7 1l-2.3-1-2 3.4L4.6 11a7.9 7.9 0 0 0 0 2l-2 1.5 2 3.4 2.3-1a7.6 7.6 0 0 0 1.7 1l.5 2.6h5.8l.5-2.6a7.6 7.6 0 0 0 1.7-1l2.3 1 2-3.4Z')),

    // ---- ui ----
    chevR:  S(P('M9 5l7 7-7 7')),
    chevD:  S(P('M5 9l7 7 7-7')),
    chevU:  S(P('M5 15l7-7 7 7')),
    bell:   S(P('M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6') + P('M10 19a2 2 0 0 0 4 0')),
    plus:   S(P('M12 5v14M5 12h14')),
    close:  S(P('M6 6l12 12M18 6 6 18')),
    share:  S(P('M12 3v12M12 3 8.5 6.5M12 3l3.5 3.5') + P('M6 12v6a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1v-6')),
    check:  S(P('M5 12.5 10 17 19 7')),
    dots:   S(`<circle cx="5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="19" cy="12" r="1.4"/>`),
    info:   S(`<circle cx="12" cy="12" r="9"/>` + P('M12 11v5M12 8h.01')),
    calendar:S(`<rect x="3.5" y="5" width="17" height="16" rx="2.5"/>` + P('M3.5 10h17M8 3v4M16 3v4')),
    search: S(`<circle cx="11" cy="11" r="6.5"/>` + P('M20 20l-3.6-3.6')),

    // ---- metrics / signals ----
    sparkles:S(P('M12 3l1.6 4.4L18 9l-4.4 1.6L12 15l-1.6-4.4L6 9l4.4-1.6Z') + P('M18.5 15l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8Z')),
    flame:  S(P('M12 21c3.9 0 6-2.6 6-6 0-3.2-2.4-4.8-3-7-2 1.5-2.3 3.2-2 4.5C11 9 9.5 6.5 10 3 6.5 5 6 9 6 12c0 4 2.6 9 6 9Z')),
    wave:   S(P('M3 12c1.5 0 1.5-3 3-3s1.5 6 3 6 1.5-9 3-9 1.5 6 3 6 1.5-3 3-3')),
    thermo: S(P('M14 14.8V5a2 2 0 1 0-4 0v9.8a4 4 0 1 0 4 0Z') + P('M12 14V9')),
    lungs:  S(P('M12 3v9') + P('M12 8c0-1.5-1-2-2-2s-2 1-2 3v3c-2 0-3 1-3 4 0 2 1 3 2.5 3S9 20 9 18v-6') + P('M12 8c0-1.5 1-2 2-2s2 1 2 3v3c2 0 3 1 3 4 0 2-1 3-2.5 3S15 20 15 18v-6')),
    drop:   S(P('M12 3s6 6.2 6 10a6 6 0 0 1-12 0c0-3.8 6-10 6-10Z')),
    zzz:    S(P('M6 7h5L6 13h5M13 11h4l-4 5h4')),
    timer:  S(`<circle cx="12" cy="13" r="8"/>` + P('M12 13V9M9 2h6')),
    scale:  S(P('M4 20h16') + `<circle cx="12" cy="8" r="4.5"/>` + P('M12 8v-2')),

    // ---- journal glyphs ----
    smile:  S(`<circle cx="12" cy="12" r="9"/>` + P('M8.5 14.5a4.5 4.5 0 0 0 7 0M9 9.5h.01M15 9.5h.01')),
    wine:   S(P('M8 3h8l-.6 6a3.4 3.4 0 0 1-6.8 0Z') + P('M12 15v4M9 21h6')),
    coffee: S(P('M4 8h13v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5Z') + P('M17 9h1.5a2.5 2.5 0 0 1 0 5H17M7 3v2M11 3v2')),
    plate:  S(`<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4"/>`),
    pill:   S(`<rect x="3" y="9" width="18" height="6" rx="3" transform="rotate(-45 12 12)"/>` + P('M8.5 8.5l7 7')),
    photo:  S(`<rect x="3.5" y="5" width="17" height="14" rx="2.5"/><circle cx="8.5" cy="10" r="1.6"/>` + P('M4 17l4.5-4 3.5 3 3-2.5 5 4')),

    // ---- misc ----
    apple:  S(P('M15.5 3c-1.2.1-2.4.8-3.1 1.7-.6.8-1.1 2-.9 3.2 1.3.1 2.6-.7 3.3-1.6.7-.8 1.1-2 .7-3.3Z') + P('M12 8c-1-.6-2-.8-3-.5-2.4.7-3.6 3.4-2.8 6.4.5 1.9 2 5 4 5 .9 0 1.2-.5 2.3-.5s1.4.5 2.3.5c2 0 3.4-3.4 3.8-4.9-2.6-1-2.9-4.6-.1-5.9-.8-1.1-2.1-1.6-3.4-1.2-.9.3-1.4.6-2.4.6')),
    watch:  S(`<rect x="7" y="7" width="10" height="10" rx="3"/>` + P('M9 7l.7-4h4.6L15 7M9 17l.7 4h4.6l.7-4')),
    lock:   S(`<rect x="4.5" y="10" width="15" height="10" rx="2.5"/>` + P('M8 10V7a4 4 0 0 1 8 0v3')),
    logo:   S(`<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3.4"/>`, 'stroke-width="1.8"'),
    palette:S(P('M12 3a9 9 0 0 0 0 18c1.4 0 2-1 2-2 0-1.4-1.3-1.6-1.3-3 0-.8.7-1.5 1.8-1.5H16a5 5 0 0 0 5-5c0-3.6-4-6.5-9-6.5Z') + P('M7.5 12h.01M9.5 8.5h.01M13.5 7.5h.01')),
    download:S(P('M12 3v12M12 15l-4-4M12 15l4-4') + P('M5 20h14')),
    shield: S(P('M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6Z') + P('M9 12l2 2 4-4')),
    flask:  S(P('M9 3h6M10 3v6l-4.5 8A2 2 0 0 0 7.3 20h9.4a2 2 0 0 0 1.8-3L14 9V3') + P('M8 15h8')),
    user:   S(`<circle cx="12" cy="8" r="4"/>` + P('M4.5 20a7.5 7.5 0 0 1 15 0')),
    arrowUp:S(P('M12 19V5M12 5l-5 5M12 5l5 5')),
    arrowDn:S(P('M12 5v14M12 19l-5-5M12 19l5-5')),
    minus:  S(P('M6 12h12')),
  };

  NS.icon = function (name, size) {
    const svg = I[name] || I.info;
    const s = size ? ` style="width:${size}px;height:${size}px"` : '';
    return svg.replace('<svg ', `<svg width="${size||20}" height="${size||20}"${s} `);
  };
  NS.icons = I;
})(window.NOOP = window.NOOP || {});
