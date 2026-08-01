/* ============================================================================
   NOOP · Premium UI — App bootstrap
   Builds the shell, restores preferences, wires global micro-interactions
   (ripples, press feedback, haptics), and launches the router on Home.
   ============================================================================ */
(function (NS) {
  'use strict';

  // Tiny preference store (in-memory + localStorage when available; degrades
  // gracefully to memory-only over file:// with storage disabled).
  const mem = {};
  NS.store = {
    get(k, d) { try { const v = localStorage.getItem('noop.' + k); return v == null ? (mem[k] ?? d) : v; }
      catch { return mem[k] ?? d; } },
    set(k, v) { mem[k] = v; try { localStorage.setItem('noop.' + k, v); } catch {} },
  };

  // Best-effort haptic (silent no-op where unsupported).
  NS.haptic = function () { try { navigator.vibrate && navigator.vibrate(8); } catch {} };

  function restorePrefs() {
    const theme = NS.store.get('theme', 'dark');
    document.documentElement.setAttribute('data-theme', theme);
    const accent = NS.store.get('accent', null);
    if (accent) {
      const root = document.documentElement;
      const v = getComputedStyle(root).getPropertyValue(`--accent-${accent}`).trim();
      const v2 = getComputedStyle(root).getPropertyValue(`--accent-${accent}-2`).trim();
      root.style.setProperty('--accent-gold', v);
      root.style.setProperty('--accent-gold-2', v2 || v);
    }
  }

  // Global ripple + press-scale for tappable surfaces.
  function globalInteractions() {
    document.addEventListener('pointerdown', (e) => {
      const b = e.target.closest('.btn, .icon-btn, .chip:not([data-chip]), .log-tile, .mood, .accent-dot');
      if (b && !b._noRipple) NS.ui.ripple(e, b);
    });
    // theme quick-toggle from the header
    document.addEventListener('click', (e) => {
      const t = e.target.closest('[data-theme-toggle]');
      if (t) {
        const cur = document.documentElement.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
        document.documentElement.setAttribute('data-theme', cur);
        NS.store.set('theme', cur);
        NS.ui.toast(cur === 'dark' ? 'Midnight' : 'Daylight', false);
      }
    });
  }

  function boot() {
    restorePrefs();
    // Stamp the new NOOP mark into the header (hidden on detail pages by the router).
    const brand = NS.ui.$('.topbrand');
    if (brand && NS.logomark) brand.innerHTML = NS.logomark(26, 'var(--accent-sleep)');
    NS.router.buildDock();
    NS.router.bindScroll();
    globalInteractions();
    // header back button
    const back = NS.ui.$('.back-btn');
    if (back) back.addEventListener('click', () => NS.router.go('home', 'back'));
    // launch
    NS.router.go('home');
    // subtle parallax on the ambient orbs as the app scrolls
    const scroll = NS.ui.$('.scroll');
    const orbs = NS.ui.$$('.ambient .orb');
    scroll.addEventListener('scroll', () => {
      const y = scroll.scrollTop;
      orbs.forEach((o, i) => { o.style.marginTop = (-y * (0.02 + i * 0.015)) + 'px'; });
    }, { passive: true });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})(window.NOOP = window.NOOP || {});
