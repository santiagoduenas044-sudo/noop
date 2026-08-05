/* ============================================================================
   NOOP · Premium UI — Journal (v3, completely redesigned)
   A fast daily check-in, not a questionnaire: tap chips to log behaviours
   instantly (no sheets, no option lists), pin the ones you use often, add an
   optional note. Then the parts that make logging worth it — a streak,
   14-day history, a weekly overview, and real associations with your health
   metrics (framed as associations, never proven causes, each carrying a
   confidence level so a thin pattern never reads as a fact).
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, icon } = NS;

  NS.pages.journal = {
    _mood: null, _on: null, _pinned: null, _editing: false,
    title: 'Journal', eyebrow: 'Today · Jul 31', tint: 'gold',
    ensureState() {
      if (this._on) return;
      this._on = new Set();
      this._pinned = new Set(data.behaviorCatalog.filter((b) => b.pinned).map((b) => b.key));
    },
    render() {
      this.ensureState();
      const catalog = data.behaviorCatalog;
      const pinned = catalog.filter((b) => this._pinned.has(b.key));
      const rest = catalog.filter((b) => !this._pinned.has(b.key));
      return `
      <!-- Mood -->
      <section class="card" data-reveal>
        <div class="card-head"><h3>How do you feel?</h3><span class="eyebrow">Tap one</span></div>
        <div class="mood-row" data-moods>
          ${data.moodCatalog.map((m) => `
            <button class="mood ${this._mood === m.key ? 'on' : ''}" data-mood="${m.key}" style="--tint:var(--accent-${moodTint(m.key)})">
              <span class="mood-ic">${icon(m.ic, 22)}</span>
              <span class="mood-label">${m.label}</span>
            </button>`).join('')}
        </div>
      </section>

      <!-- Fast check-in -->
      <div class="section-title" data-reveal><h2>Quick check-in</h2>
        <button class="link" data-edit-pins style="background:none">${this._editing ? 'Done' : 'Edit'}</button></div>
      <section class="card" data-reveal>
        <div class="checkin-grid" data-checkin>
          ${pinned.map((b) => chipFor(b, this)).join('')}
        </div>
        ${rest.length ? `<button class="link" data-show-more style="margin-top:var(--s-3);display:${this._editing ? 'none' : 'inline-flex'}">+ ${rest.length} more</button>
          <div class="checkin-grid" data-checkin-more style="margin-top:var(--s-3);display:none">
            ${rest.map((b) => chipFor(b, this)).join('')}
          </div>` : ''}
        ${this._editing ? `<p class="note" style="margin-top:var(--s-3)">Tap the pin icon on any chip to change what shows by default.</p>` : ''}
      </section>

      <!-- Note -->
      <section class="card" data-reveal style="margin-top:16px">
        <div class="card-head"><h3 style="font-size:15px">Note</h3><span class="eyebrow">Optional</span></div>
        <textarea class="note" data-note placeholder="Anything worth remembering about today…" rows="2"></textarea>
        <button class="btn primary block" data-save style="margin-top:12px">${icon('check',16)} Save entry</button>
      </section>

      <!-- Streak + history -->
      <div class="section-title" data-reveal><h2>Your history</h2>
        <span class="streak-badge">${icon('flame',13)} ${data.journalStreak}-day streak</span></div>
      <section class="card" data-reveal>
        <p class="note" style="margin-bottom:var(--s-3)">Last 14 days — darker means more logged that day.</p>
        <div class="history-strip" data-history>
          ${data.journalHistory.map((h, i) => `<div class="history-cell ${h.behaviours.length ? 'has' : ''}" data-history-day="${i}"
            style="opacity:${h.behaviours.length ? Math.min(1, 0.35 + h.behaviours.length * 0.12).toFixed(2) : 1}">
            <span class="hc-count">${h.behaviours.length || ''}</span></div>`).join('')}
        </div>
      </section>

      <!-- Weekly overview -->
      <div class="section-title" data-reveal><h2>This week</h2></div>
      <section class="card" data-reveal>
        <div class="rows">
          ${weeklyOverviewRows()}
        </div>
      </section>

      <!-- Correlations with health metrics -->
      <div class="section-title" data-reveal><h2>Patterns</h2><span class="link" data-route="trends">See all in Trends ›</span></div>
      <div class="stack">
        ${data.journalCorrelations.map(patternCard).join('')}
      </div>
      <p class="note" style="margin:var(--s-3) 2px 0">These are associations from your own logged history, not proven causes — more logging sharpens them over time.</p>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      const page = this;
      // mood single-select
      ui.$$('[data-mood]', root).forEach((b) => b.addEventListener('click', (e) => {
        page._mood = page._mood === b.dataset.mood ? null : b.dataset.mood;
        ui.$$('[data-mood]', root).forEach((x) => x.classList.toggle('on', x.dataset.mood === page._mood));
        ui.ripple(e, b); NS.haptic && NS.haptic();
      }));
      wireChips(root, page);
      // show more
      ui.$('[data-show-more]', root)?.addEventListener('click', (e) => {
        const more = ui.$('[data-checkin-more]', root); more.style.display = 'flex';
        e.currentTarget.style.display = 'none';
      });
      // edit pins
      ui.$('[data-edit-pins]', root)?.addEventListener('click', (e) => {
        ui.ripple(e, e.currentTarget); page._editing = !page._editing; rerender(root, page);
      });
      // history cell tap → what was logged that day
      ui.$$('[data-history-day]', root).forEach((c) => c.addEventListener('click', (e) => {
        ui.ripple(e, c); openHistoryDay(+c.dataset.historyDay);
      }));
      // save
      ui.$('[data-save]', root)?.addEventListener('click', (e) => { ui.ripple(e, e.currentTarget);
        ui.toast(page._on.size ? `${page._on.size} behaviour${page._on.size === 1 ? '' : 's'} saved to device` : 'Entry saved to device'); });
    },
  };

  function rerender(root, page) {
    root.innerHTML = page.render();
    ui.reveal(root); ui.countUp(root); ui.animateRings(root);
    page.mount(root);
  }
  function wireChips(root, page) {
    ui.$$('[data-chip-key]', root).forEach((c) => {
      if (page._editing) {
        c.addEventListener('click', (e) => { ui.ripple(e, c);
          const k = c.dataset.chipKey;
          if (page._pinned.has(k)) page._pinned.delete(k); else page._pinned.add(k);
          rerender(root, page);
        });
      } else {
        c.addEventListener('click', (e) => { ui.ripple(e, c); NS.haptic && NS.haptic();
          const k = c.dataset.chipKey;
          if (page._on.has(k)) page._on.delete(k); else page._on.add(k);
          c.classList.toggle('on', page._on.has(k));
        });
      }
    });
  }
  function chipFor(b, page) {
    const on = page._on.has(b.key);
    const editing = page._editing;
    const pinIcon = editing ? (page._pinned.has(b.key) ? '📌 ' : '') : '';
    return `<button class="checkin-chip ${on ? 'on' : ''}" data-chip-key="${b.key}" style="--tint:var(--accent-${b.tint})">
      <span class="cc-ic">${icon(b.ic, 15)}</span>${pinIcon}${b.label}</button>`;
  }
  function moodTint(k) { return ({ great: 'recovery', good: 'gold', ok: 'strain', low: 'heart' })[k] || 'gold'; }

  function weeklyOverviewRows() {
    const last7 = data.journalHistory.slice(0, 7);
    const allKeys = {};
    last7.forEach((h) => h.behaviours.forEach((k) => { allKeys[k] = (allKeys[k] || 0) + 1; }));
    const top = Object.entries(allKeys).sort((a, b) => b[1] - a[1]).slice(0, 4);
    if (!top.length) return `<div class="row"><div class="r-body"><div class="r-title" style="font-weight:500">Nothing logged yet this week</div></div></div>`;
    return top.map(([key, count]) => {
      const b = data.behaviorCatalog.find((x) => x.key === key) || { label: key, ic: 'dot', tint: 'gold' };
      return `<div class="row" style="--tint:var(--accent-${b.tint})">
        <span class="glyph tint">${icon(b.ic, 16)}</span>
        <div class="r-body"><div class="r-title" style="font-weight:500">${b.label}</div>
          <div class="r-sub">Logged ${count} of the last 7 days</div></div>
        <div class="r-val">${count}<small>/7</small></div></div>`;
    }).join('');
  }
  function openHistoryDay(i) {
    const h = data.journalHistory[i];
    const items = h.behaviours.map((k) => data.behaviorCatalog.find((b) => b.key === k)).filter(Boolean);
    ui.sheet(i === 0 ? 'Today' : `${i} day${i === 1 ? '' : 's'} ago`, items.length
      ? `<div class="chip-row">${items.map((b) => `<span class="checkin-chip on" style="--tint:var(--accent-${b.tint})"><span class="cc-ic">${icon(b.ic,15)}</span>${b.label}</span>`).join('')}</div>`
      : `<p class="note">Nothing logged that day.</p>`);
  }
  function confLabel(c) { return ({ early: 'Early signal', emerging: 'Emerging pattern', consistent: 'Consistent pattern' })[c] || c; }
  function patternCard(j) {
    return `<div class="pattern-card" data-reveal style="--tint:var(--accent-gold)">
      <span class="glyph tint">${icon('insight', 16)}</span>
      <div class="pc-body">
        <div class="pc-head"><span class="pc-title">${j.behaviorLabel} ↔ ${j.metricLabel}</span>
          <span class="conf-tag ${j.confidence}"><i></i>${confLabel(j.confidence)}</span></div>
        <div class="pc-text">${j.text}</div>
        <div class="pc-meta">Observed across ${j.occurrences} logged occasions</div>
      </div>
    </div>`;
  }
})(window.NOOP = window.NOOP || {});
