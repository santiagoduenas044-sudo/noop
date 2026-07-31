/* ============================================================================
   NOOP · Premium UI — Coach
   A conversational AI coach: prediction cards, a chat thread with typing, quick
   prompt chips, and training / recovery / sleep guidance. Fully interactive —
   tap a suggestion and the coach "replies".
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, icon } = NS;

  NS.pages.coach = {
    title: 'Coach', eyebrow: 'Your on-device guide', tint: 'gold',
    render() {
      return `
      <!-- Forecast strip -->
      <section data-reveal>
        <div class="coach-forecasts">
          ${fcCard('Today', 'Ready to push', 'flame', 'recovery', 'Strain 14–16')}
          ${fcCard('Tomorrow', 'Recovery green', 'shield', 'sleep', 'If you rest tonight')}
          ${fcCard('This week', 'Build phase', 'trends', 'gold', '3 hard · 4 easy')}
        </div>
      </section>

      <!-- Primary recommendation -->
      <section class="ai-card" data-reveal style="margin-top:6px">
        <div class="ai-head"><span class="ai-orb"></span><span class="ai-title">Plan for today</span></div>
        <p class="ai-body">You're recovered at <b>78%</b>. Best return today is an <b>aerobic base</b> session — 45–60 min in Zone 2. It builds fitness without denting tomorrow's recovery.</p>
        <div class="rec-actions" style="margin-top:14px">
          <button class="btn primary" data-quick="Build me a Zone 2 plan">${icon('bolt',16)} Build the plan</button>
          <button class="btn ghost" data-quick="Why Zone 2 today?">Why?</button>
        </div>
      </section>

      <!-- Advice tiles -->
      <div class="section-title" data-reveal><h2>Guidance</h2></div>
      <div class="stack">
        ${advice('Training', 'Zone 2 today, intervals tomorrow', 'flame', 'strain')}
        ${advice('Recovery', 'Hydrate + 10 min mobility this evening', 'shield', 'recovery')}
        ${advice('Sleep', 'Lights out by 10:50 PM to clear debt', 'moon', 'sleep')}
      </div>

      <!-- Conversation -->
      <div class="section-title" data-reveal><h2>Ask the coach</h2></div>
      <section class="card chat" data-reveal>
        <div class="thread" data-thread>
          ${data.coachThread.map(bubble).join('')}
        </div>
        <div class="chip-row quick" data-quicks style="margin-top:14px">
          ${['How hard can I go today?', 'Should I nap?', 'Analyze my HRV', 'Plan my week'].map((q) => `<button class="chip" data-quick="${q}">${q}</button>`).join('')}
        </div>
        <form class="composer" data-composer>
          <input type="text" placeholder="Message your coach…" aria-label="Message" />
          <button type="submit" class="icon-btn send">${icon('arrowUp', 18)}</button>
        </form>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      const thread = ui.$('[data-thread]', root);
      const form = ui.$('[data-composer]', root);
      const input = form.querySelector('input');

      const push = (who, text) => {
        const b = ui.h(bubble({ who, text }));
        b.style.opacity = '0'; b.style.transform = 'translateY(10px)';
        thread.appendChild(b);
        requestAnimationFrame(() => { b.style.transition = 'all .4s var(--ease-out)'; b.style.opacity = '1'; b.style.transform = 'none'; });
        thread.scrollTop = thread.scrollHeight;
        ui.$('.scroll')?.scrollTo({ top: 99999, behavior: 'smooth' });
      };
      const typing = () => {
        const t = ui.h(`<div class="bubble coach typing"><span></span><span></span><span></span></div>`);
        thread.appendChild(t); thread.scrollTop = thread.scrollHeight;
        ui.$('.scroll')?.scrollTo({ top: 99999, behavior: 'smooth' });
        return t;
      };
      const reply = (q) => {
        const t = typing();
        setTimeout(() => { t.remove(); push('coach', answer(q)); }, 900 + Math.random() * 500);
      };

      const ask = (q) => { push('you', q); setTimeout(() => reply(q), 260); };

      root.addEventListener('click', (e) => {
        const b = e.target.closest('[data-quick]');
        if (b) { ui.ripple(e, b); ask(b.dataset.quick); }
      });
      form.addEventListener('submit', (e) => {
        e.preventDefault(); const v = input.value.trim(); if (!v) return; input.value = ''; ask(v);
      });
    },
  };

  function bubble(m) {
    return `<div class="bubble ${m.who}">${m.text}</div>`;
  }
  function fcCard(day, title, ic, tint, sub) {
    return `<div class="fc-card" style="--tint:var(--accent-${tint})">
      <span class="glyph tint">${icon(ic, 16)}</span>
      <div class="fc-day2">${day}</div>
      <div class="fc-title">${title}</div>
      <div class="fc-sub2">${sub}</div></div>`;
  }
  function advice(kind, text, ic, tint) {
    return `<div class="card tap advice" data-reveal style="--tint:var(--accent-${tint})">
      <span class="glyph tint">${icon(ic, 18)}</span>
      <div class="adv-body"><div class="adv-kind">${kind}</div><div class="adv-text">${text}</div></div>
      <span class="chev">${icon('chevR', 16)}</span></div>`;
  }
  // Canned but context-aware "AI" answers.
  function answer(q) {
    const s = q.toLowerCase();
    if (s.includes('hard') || s.includes('push') || s.includes('go today'))
      return "At 78% recovery you can handle a strain of <b>14–16</b>. That's a steady tempo or a long Zone 2 — challenging but not draining. I'd keep max effort for tomorrow.";
    if (s.includes('nap'))
      return "A 20-minute nap before 3 PM would top up your 42-min sleep debt without hurting tonight's sleep. Keep it short — past 30 min you risk grogginess.";
    if (s.includes('hrv'))
      return "Your HRV is <b>96 ms</b>, up 12% on baseline and trending up 4 nights running. The biggest lever has been consistent bedtimes — keep the window tight and it should hold.";
    if (s.includes('week') || s.includes('plan'))
      return "Here's a balanced build week: <b>Mon</b> Zone 2 · <b>Tue</b> intervals · <b>Wed</b> easy · <b>Thu</b> tempo · <b>Fri</b> rest · <b>Sat</b> long · <b>Sun</b> recovery. I'll adapt it each morning to your recovery.";
    if (s.includes('zone 2') || s.includes('why'))
      return "Zone 2 builds aerobic base and mitochondrial density with minimal recovery cost — so you gain fitness while staying green for tomorrow's harder session. Keep HR roughly 114–132 bpm.";
    if (s.includes('sleep'))
      return "Aim for lights-out by <b>10:50 PM</b>. You've a 42-min debt; an earlier night plus a cool, dark room should clear most of it and lift tomorrow's recovery a few points.";
    return "Good question. Based on today's signals — 78% recovery, HRV 96 ms, low stress — you've room to train moderately. Want me to turn that into a concrete session?";
  }
})(window.NOOP = window.NOOP || {});
