/* ============================================================================
   NOOP · Premium UI — Journal
   Log the behaviours behind the numbers: mood, training, alcohol, caffeine,
   meals, stress, medication, symptoms. Toggle behaviours and see their measured
   impact on recovery. Add a photo / note. Everything reacts.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, icon } = NS;

  const moods = [
    { key: 'great', label: 'Great', ic: 'smile', tint: 'recovery' },
    { key: 'good', label: 'Good', ic: 'smile', tint: 'gold' },
    { key: 'ok', label: 'Okay', ic: 'wave', tint: 'strain' },
    { key: 'low', label: 'Low', ic: 'drop', tint: 'heart' },
  ];
  const logTypes = [
    { key: 'training', label: 'Training', ic: 'flame', tint: 'strain' },
    { key: 'caffeine', label: 'Caffeine', ic: 'coffee', tint: 'gold' },
    { key: 'alcohol', label: 'Alcohol', ic: 'wine', tint: 'sleep' },
    { key: 'meals', label: 'Meals', ic: 'plate', tint: 'recovery' },
    { key: 'medication', label: 'Medication', ic: 'pill', tint: 'hrv' },
    { key: 'symptoms', label: 'Symptoms', ic: 'thermo', tint: 'heart' },
    { key: 'stress', label: 'Stress', ic: 'wave', tint: 'hrv' },
    { key: 'photo', label: 'Photo', ic: 'photo', tint: 'gold' },
  ];

  NS.pages.journal = {
    title: 'Journal', eyebrow: 'Today · Jul 31', tint: 'gold',
    render() {
      const j = data.journal;
      return `
      <!-- Mood selector -->
      <section class="card" data-reveal>
        <div class="card-head"><h3>How do you feel?</h3><span class="eyebrow">Tap one</span></div>
        <div class="mood-row" data-moods>
          ${moods.map((m, i) => `
            <button class="mood ${i===1?'on':''}" data-mood="${m.key}" style="--tint:var(--accent-${m.tint})">
              <span class="mood-ic">${icon(m.ic, 22)}</span>
              <span class="mood-label">${m.label}</span>
            </button>`).join('')}
        </div>
      </section>

      <!-- Quick log grid -->
      <div class="section-title" data-reveal><h2>Log</h2><span class="link">${logTypes.length} types</span></div>
      <section class="log-grid" data-reveal>
        ${logTypes.map((t) => `
          <button class="log-tile" data-log="${t.key}" data-label="${t.label}" style="--tint:var(--accent-${t.tint})">
            <span class="glyph tint">${icon(t.ic, 18)}</span>
            <span class="log-name">${t.label}</span>
          </button>`).join('')}
      </section>

      <!-- Today's entries -->
      <div class="section-title" data-reveal><h2>Today's entries</h2></div>
      <section class="card" data-reveal>
        <div class="rows" data-entries>
          ${j.entries.map(entryRow).join('')}
        </div>
      </section>

      <!-- Behaviours & impact -->
      <div class="section-title" data-reveal><h2>Behaviours & impact</h2><span class="link">Measured</span></div>
      <section class="card" data-reveal>
        ${j.behaviours.map(behaviourRow).join('')}
      </section>

      <!-- Note -->
      <section class="card" data-reveal style="margin-top:16px">
        <div class="card-head"><h3 style="font-size:15px">Recovery note</h3></div>
        <textarea class="note" data-note placeholder="Anything worth remembering about today…" rows="3"></textarea>
        <button class="btn primary block" data-save style="margin-top:12px">${icon('check',16)} Save entry</button>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      // mood single-select
      ui.$$('[data-mood]', root).forEach((b) => b.addEventListener('click', (e) => {
        ui.$$('[data-mood]', root).forEach((x) => x.classList.remove('on'));
        b.classList.add('on'); ui.ripple(e, b); NS.haptic && NS.haptic();
      }));
      // log tiles → open a sheet
      ui.$$('[data-log]', root).forEach((b) => b.addEventListener('click', (e) => {
        ui.ripple(e, b); openLog(b.dataset.log, b.dataset.label);
      }));
      // behaviour toggles
      ui.initSwitches(root, () => {});
      ui.$$('[data-behaviour] .switch', root).forEach((sw) => sw.addEventListener('click', () => {
        ui.toast('Behaviour updated');
      }));
      // save
      ui.$('[data-save]', root)?.addEventListener('click', (e) => { ui.ripple(e, e.currentTarget);
        ui.toast('Entry saved to device'); });
    },
  };

  function entryRow(e) {
    return `<div class="row" style="--tint:var(--accent-${e.tint})">
      <span class="glyph tint">${icon(e.icon, 16)}</span>
      <div class="r-body"><div class="r-title">${e.label}</div></div>
      <div class="r-val" style="color:var(--ink-2);font-weight:600">${e.value}</div></div>`;
  }
  function behaviourRow(b) {
    return `<div class="row" data-behaviour>
      <div class="r-body"><div class="r-title" style="font-weight:500">${b.label}</div>
        <div class="r-sub" style="color:${b.impact.startsWith('+') ? 'var(--band-high)' : 'var(--band-low)'}">${b.impact}</div></div>
      <div class="switch ${b.on ? 'on' : ''}"></div></div>`;
  }
  function openLog(key, label) {
    const opts = {
      training: ['Zone 2 run', 'Intervals', 'Strength', 'Yoga', 'Walk', 'Cycling'],
      caffeine: ['1 cup', '2 cups', '3+ cups', 'Pre-workout', 'None'],
      alcohol: ['None', '1 drink', '2 drinks', '3+ drinks'],
      meals: ['On plan', 'High protein', 'Late dinner', 'Fasted', 'Off plan'],
      medication: ['Supplement', 'Magnesium', 'Prescription', 'None'],
      symptoms: ['None', 'Sore', 'Congested', 'Headache', 'Fatigued'],
      stress: ['Low', 'Moderate', 'High', 'Very high'],
      photo: null,
    }[key];
    const body = opts
      ? `<div class="chip-row" style="margin:6px 0 4px">${opts.map((o, i) => ui.chip(o, 'gold', i === 0)).join('')}</div>
         <button class="btn primary block" data-sheet-save style="margin-top:16px">Add to journal</button>`
      : `<div class="photo-drop">${icon('photo', 30)}<p>Attach a photo from this device</p></div>
         <button class="btn primary block" data-sheet-save style="margin-top:16px">Attach</button>`;
    const { close } = ui.sheet(label, body);
    setTimeout(() => {
      const sheet = document.querySelector('.sheet');
      ui.initChips(sheet);
      // single-select within sheet
      ui.$$('.chip', sheet).forEach((c) => c.addEventListener('click', () => {
        ui.$$('.chip', sheet).forEach((x) => x.classList.remove('on')); c.classList.add('on');
      }));
      sheet.querySelector('[data-sheet-save]')?.addEventListener('click', () => { close(); ui.toast(label + ' logged'); });
    }, 40);
  }
})(window.NOOP = window.NOOP || {});
