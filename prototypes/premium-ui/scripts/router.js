/* ============================================================================
   NOOP · Premium UI — Router
   A tiny hash-free SPA router. Pages register themselves into NOOP.pages with
   { title, eyebrow, render() → html, mount(root), tint }. The router swaps the
   view with a directional transition, updates the top bar + bottom dock, keeps
   per-page scroll position, and runs each page's mount() to wire behaviour.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { $, $$, ripple } = NS.ui;

  const pages = NS.pages = NS.pages || {};
  const order = ['home', 'sleep', 'readiness', 'heart', 'coach', 'journal', 'trends', 'insights', 'settings'];
  const dockTabs = [
    { id: 'home', icon: 'home', label: 'Home' },
    { id: 'sleep', icon: 'moon', label: 'Sleep' },
    { id: 'heart', icon: 'heart', label: 'Heart' },
    { id: 'coach', icon: 'coach', label: 'Coach' },
    { id: 'trends', icon: 'trends', label: 'Trends' },
  ];

  const state = { current: null, scrollPos: {} };

  function els() {
    return {
      scroll: $('.scroll'),
      view: $('#view'),
      bar: $('.topbar'),
      dock: $('.dock'),
      app: $('.app'),
    };
  }

  function buildDock() {
    const { dock } = els();
    dock.innerHTML = `<span class="glow"></span>` + dockTabs.map((t) => `
      <button class="tab" data-tab="${t.id}">
        <span class="t-ico">${NS.icon(t.icon, 22)}</span>
        <span class="t-label">${t.label}</span>
      </button>`).join('');
    $$('.tab', dock).forEach((tab) => tab.addEventListener('click', (e) => {
      ripple(e, tab); NS.haptic && NS.haptic(); go(tab.dataset.tab);
    }));
  }

  function placeGlow(id) {
    const { dock } = els();
    const tab = $(`.tab[data-tab="${id}"]`, dock);
    const glow = $('.glow', dock);
    // Always clear stale highlights first — non-dock pages should light no tab.
    $$('.tab', dock).forEach((t) => t.classList.remove('active', 'just-active'));
    if (!tab) { glow.style.opacity = '0'; return; }
    glow.style.opacity = '1';
    glow.style.width = tab.offsetWidth + 'px';
    glow.style.transform = `translateX(${tab.offsetLeft - 6}px)`;
    tab.classList.add('active', 'just-active');
    setTimeout(() => tab.classList.remove('just-active'), 500);
  }

  function setHeader(page, id) {
    const { bar } = els();
    const showBack = !dockTabs.some((t) => t.id === id);
    bar.querySelector('.greeting').innerHTML =
      `<span class="eyebrow">${page.eyebrow || ''}</span>` +
      `<span class="title">${page.title || ''}</span>`;
    const back = bar.querySelector('.back-btn');
    if (back) back.style.display = showBack ? 'grid' : 'none';
  }

  // Navigate to a page id. dir: 'forward' | 'back'
  function go(id, dir) {
    id = pages[id] ? id : 'home';
    if (id === state.current) { els().scroll.scrollTo({ top: 0, behavior: 'smooth' }); return; }
    const { scroll, view, app } = els();
    const page = pages[id];

    // remember outgoing scroll
    if (state.current) state.scrollPos[state.current] = scroll.scrollTop;

    // outgoing animation
    const outgoing = view.firstElementChild;
    if (outgoing) {
      outgoing.classList.add('leave');
      setTimeout(() => outgoing.remove(), 220);
    }

    // build incoming
    const wrap = document.createElement('div');
    wrap.className = 'page-view page ' + (dir === 'back' ? 'enter-back' : 'enter');
    wrap.dataset.page = id;
    wrap.innerHTML = page.render();
    // slight delay so outgoing can begin leaving
    setTimeout(() => {
      view.appendChild(wrap);
      scroll.scrollTop = 0;
      app.classList.remove('scrolled');
      NS.ui.reveal(wrap);
      NS.ui.animateRings(wrap);
      NS.ui.countUp(wrap);
      NS.ui.initSegments(wrap);
      NS.ui.initExpandables(wrap);
      NS.ui.initChips(wrap);
      page.mount && page.mount(wrap);
      bindRoutes(wrap);
      setHeader(page, id);
      placeGlow(id);
      state.current = id;
      // theme accent hint on the frame
      document.querySelector('.device')?.style.setProperty('--page-tint', `var(--accent-${page.tint || 'gold'})`);
    }, outgoing ? 60 : 0);
  }

  // Any element with data-route navigates on click.
  function bindRoutes(root) {
    $$('[data-route]', root).forEach((el) => {
      if (el._route) return; el._route = true;
      el.addEventListener('click', (e) => {
        if (e.target.closest('[data-noroute]')) return;
        ripple(e, el); go(el.dataset.route);
      });
    });
  }

  // Track scroll for the frosted header.
  function bindScroll() {
    const { scroll, app } = els();
    scroll.addEventListener('scroll', () => {
      app.classList.toggle('scrolled', scroll.scrollTop > 8);
    }, { passive: true });
  }

  NS.router = { go, buildDock, bindScroll, placeGlow, bindRoutes, order, dockTabs, state };
})(window.NOOP = window.NOOP || {});
