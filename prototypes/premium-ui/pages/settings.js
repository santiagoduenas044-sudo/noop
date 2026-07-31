/* ============================================================================
   NOOP · Premium UI — Settings
   Apple-quality settings: profile, appearance (live theme + accent switch),
   notifications, health sources, export, privacy, experimental features, about.
   Reinforces NOOP's identity: offline, on-device, account-free.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, icon } = NS;

  NS.pages.settings = {
    title: 'Settings', eyebrow: 'NOOP · on-device', tint: 'gold',
    render() {
      return `
      <!-- Profile -->
      <section class="card profile" data-reveal>
        <div class="avatar" style="width:56px;height:56px;font-size:20px">SD</div>
        <div class="profile-body">
          <div class="profile-name">Santiago</div>
          <div class="profile-sub">WHOOP 5.0 · paired · 100% local</div>
        </div>
        <span class="chip" style="--tint:var(--accent-recovery)"><span class="swatch"></span>Synced</span>
      </section>

      <!-- Appearance -->
      ${group('Appearance', [
        rowToggle('theme', 'palette', 'Dark theme', 'Midnight glass', true),
      ])}
      <section class="card" data-reveal style="margin-top:-4px">
        <div class="eyebrow" style="margin-bottom:12px">Accent</div>
        <div class="accent-row" data-accents>
          ${['recovery','sleep','strain','heart','hrv','gold'].map((a, i) => `
            <button class="accent-dot ${a==='recovery'?'on':''}" data-accent="${a}" style="--a:var(--accent-${a})" aria-label="${a}"></button>`).join('')}
        </div>
      </section>

      <!-- Notifications -->
      ${group('Notifications', [
        rowToggle('n1', 'bell', 'Morning recovery', 'When your score is ready', true),
        rowToggle('n2', 'moon', 'Bedtime nudge', 'Based on sleep debt', true),
        rowToggle('n3', 'flame', 'Strain target', 'When you hit your goal', false),
      ])}

      <!-- Health sources -->
      ${group('Health sources', [
        rowNav('watch', 'WHOOP 5.0', 'Connected · battery 74%', 'recovery'),
        rowNav('apple', 'Apple Health', 'Import steps & workouts', 'heart'),
        rowNav('import', 'Import CSV', 'From a WHOOP export', 'strain'),
      ])}

      <!-- Data & privacy -->
      ${group('Data & privacy', [
        rowNav('export', 'Export data', '.noopbak · fully portable', 'gold', 'download'),
        rowNav('privacy', 'Privacy', 'No cloud. No account. No telemetry.', 'recovery', 'shield'),
        rowNav('lock', 'App lock', 'Face ID / passcode', 'sleep', 'lock'),
      ])}

      <!-- Experimental -->
      ${group('Experimental', [
        rowToggle('x1', 'flask', 'Oura import (beta)', 'Gated · off by default', false),
        rowToggle('x2', 'flask', 'PPG heart-rate estimate', 'Instrumentation only', false),
      ])}

      <!-- About & version -->
      <div class="section-title" data-reveal><h2 style="font-size:17px">About</h2></div>
      <section class="card list" data-reveal><div class="rows">
        <button class="row nav-row" data-route="whatsnew" style="--tint:var(--accent-gold)">
          <span class="glyph tint">${icon('sparkles', 16)}</span>
          <div class="r-body" style="text-align:left"><div class="r-title">What’s New</div>
            <div class="r-sub">Milestone ${NOOP.build.milestone} · what changed this build</div></div>
          <span class="chev">${icon('chevR', 16)}</span>
        </button>
        ${vrow('Prototype', NOOP.build.prototypeVersion)}
        ${vrow('Commit', NOOP.build.commit)}
        ${vrow('Build date', NOOP.build.buildDate)}
        ${vrow('Native app', 'v' + NOOP.build.appVersion + ' · build ' + NOOP.build.iosBuild)}
      </div></section>

      <section class="card about" data-reveal>
        <div class="about-logo">${icon('logo', 34)}</div>
        <div class="about-name">NOOP</div>
        <div class="about-ver">Premium Prototype ${NOOP.build.prototypeVersion} · Milestone ${NOOP.build.milestone}</div>
        <p class="about-note">Your strap. Your data. Your machine. Offline, on-device, no cloud.</p>
      </section>

      <div class="ver-footer" data-reveal>
        <div class="vf-name">NOOP PREMIUM PROTOTYPE</div>
        <div class="vf-line">Prototype ${NOOP.build.prototypeVersion} · Milestone ${NOOP.build.milestone} · ${NOOP.build.commit}</div>
        <div class="vf-line">Updated ${NOOP.build.updated}</div>
      </div>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      // theme toggle
      const themeSw = ui.$('[data-key="theme"] .switch, .switch[data-key="theme"]', root);
      ui.initSwitches(root, (key, on) => {
        if (key === 'theme') {
          document.documentElement.setAttribute('data-theme', on ? 'dark' : 'light');
          NS.store && NS.store.set('theme', on ? 'dark' : 'light');
          ui.toast(on ? 'Midnight theme' : 'Daylight theme', false);
        }
      });
      // accent picker → repaint gold token role (page tints stay, "gold" brand accent swaps)
      ui.$$('[data-accent]', root).forEach((b) => b.addEventListener('click', (e) => {
        ui.$$('[data-accent]', root).forEach((x) => x.classList.remove('on'));
        b.classList.add('on'); ui.ripple(e, b);
        const a = b.dataset.accent;
        const v = getComputedStyle(document.documentElement).getPropertyValue(`--accent-${a}`);
        const v2 = getComputedStyle(document.documentElement).getPropertyValue(`--accent-${a}-2`) || v;
        document.documentElement.style.setProperty('--accent-gold', v.trim());
        document.documentElement.style.setProperty('--accent-gold-2', (v2 || v).trim());
        NS.store && NS.store.set('accent', a);
        ui.toast('Accent updated', false);
      }));
      // nav rows
      ui.$$('[data-nav]', root).forEach((r) => r.addEventListener('click', (e) => {
        ui.ripple(e, r);
        const k = r.dataset.nav;
        if (k === 'export') ui.sheet('Export data', exportSheet());
        else if (k === 'privacy') ui.sheet('Privacy', privacySheet());
        else ui.toast(r.dataset.title + ' — nothing leaves this device');
      }));
    },
  };

  /* ---- partials ---- */
  function vrow(k, v) {
    return `<div class="row"><div class="r-body"><div class="r-title" style="font-weight:500">${k}</div></div>
      <div class="r-val" style="font-family:var(--font-mono);font-size:13px;color:var(--ink-2)">${v}</div></div>`;
  }
  function group(title, rows) {
    return `<div class="section-title" data-reveal><h2 style="font-size:17px">${title}</h2></div>
      <section class="card list" data-reveal><div class="rows">${rows.join('')}</div></section>`;
  }
  function rowToggle(key, ic, title, sub, on) {
    return `<div class="row" style="--tint:var(--accent-gold)">
      <span class="glyph tint">${icon(ic, 16)}</span>
      <div class="r-body"><div class="r-title">${title}</div><div class="r-sub">${sub}</div></div>
      <div class="switch ${on ? 'on' : ''}" data-key="${key}"></div></div>`;
  }
  function rowNav(key, title, sub, tint, ic) {
    return `<button class="row nav-row" data-nav="${key}" data-title="${title}" style="--tint:var(--accent-${tint})">
      <span class="glyph tint">${icon(ic || navIcon(key), 16)}</span>
      <div class="r-body" style="text-align:left"><div class="r-title">${title}</div><div class="r-sub">${sub}</div></div>
      <span class="chev">${icon('chevR', 16)}</span></button>`;
  }
  function navIcon(k){ return ({ watch:'watch', apple:'apple', import:'download' })[k] || 'chevR'; }
  function exportSheet() {
    return `<p class="ctr-note" style="margin:2px 0 16px">Everything stays yours. Export a portable <b>.noopbak</b> file — a byte-identical backup you can move between iPhone, Android and Mac.</p>
      <div class="rows">
        ${['Recovery & HRV','Sleep stages','Heart-rate history','Journal & behaviours','Settings whitelist'].map((t) => `<div class="row"><span class="glyph tint" style="--tint:var(--accent-recovery)">${icon('check',14)}</span><div class="r-body"><div class="r-title" style="font-weight:500">${t}</div></div></div>`).join('')}
      </div>
      <button class="btn primary block" style="margin-top:16px" onclick="NOOP.ui.toast('Export ready · saved locally')">${icon('download',16)} Export .noopbak</button>`;
  }
  function privacySheet() {
    return `<div class="privacy-hero">${icon('shield', 40)}</div>
      <p class="ctr-note" style="text-align:center;margin:8px 0 18px">NOOP is fully offline and on-device. There is <b>no server, no account, no cloud sync, and no telemetry</b>. Your health data never leaves this machine.</p>
      <div class="rows">
        ${[['No cloud','Data lives in on-device SQLite'],['Account-free','Nothing to sign up for'],['No tracking','Zero analytics that phone home'],['Clean-room','Interop with hardware you own']].map(([t,s]) => `<div class="row"><span class="glyph tint" style="--tint:var(--accent-recovery)">${icon('check',14)}</span><div class="r-body"><div class="r-title" style="font-weight:600">${t}</div><div class="r-sub">${s}</div></div></div>`).join('')}
      </div>`;
  }
})(window.NOOP = window.NOOP || {});
