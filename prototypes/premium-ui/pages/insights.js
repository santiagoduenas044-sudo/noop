/* ============================================================================
   NOOP · Premium UI — Insights
   AI insight cards that explain WHY, not just what. Each card expands to show
   the evidence and the recommended action. Filterable by domain.
   ============================================================================ */
(function (NS) {
  'use strict';
  const { ui, data, icon } = NS;

  const filters = [
    { key: 'all', label: 'All', tint: 'gold' },
    { key: 'recovery', label: 'Recovery', tint: 'recovery' },
    { key: 'sleep', label: 'Sleep', tint: 'sleep' },
    { key: 'strain', label: 'Strain', tint: 'strain' },
  ];

  NS.pages.insights = {
    title: 'Insights', eyebrow: 'Why, explained', tint: 'gold',
    render() {
      return `
      <section class="ai-card" data-reveal>
        <div class="ai-head"><span class="ai-orb"></span><span class="ai-title">This week in one line</span></div>
        <p class="ai-body">Your body responded best when you <b>slept before 11 PM</b> and kept alcohol off — those two behaviours explain most of this week's recovery gains.</p>
      </section>

      <section data-reveal style="margin-top:14px">
        <div class="chip-row" data-filters>
          ${filters.map((f, i) => `<button class="chip ${i===0?'on':''}" data-filter="${f.key}" style="--tint:var(--accent-${f.tint})"><span class="swatch"></span>${f.label}</button>`).join('')}
        </div>
      </section>

      <div class="stack" data-insight-list style="margin-top:16px">
        ${data.insights.map(insightCard).join('')}
      </div>

      <!-- Correlation callout -->
      <div class="section-title" data-reveal><h2>Discovered pattern</h2></div>
      <section class="card" data-reveal style="--tint:var(--accent-hrv)">
        <div class="corr">
          <div class="corr-num"><span class="count" data-to="0.72">0</span></div>
          <div class="corr-body">
            <div class="corr-title">Bedtime ↔ next-day HRV</div>
            <div class="corr-sub">Strong correlation over 30 days. Earlier nights reliably precede higher HRV.</div>
          </div>
        </div>
        <div class="corr-scatter" data-scatter></div>
      </section>
      <div style="height:8px"></div>`;
    },

    mount(root) {
      ui.initExpandables(root);
      // filter
      ui.$$('[data-filter]', root).forEach((b) => b.addEventListener('click', (e) => {
        ui.$$('[data-filter]', root).forEach((x) => x.classList.remove('on'));
        b.classList.add('on'); ui.ripple(e, b);
        const k = b.dataset.filter;
        ui.$$('[data-insight]', root).forEach((card) => {
          const show = k === 'all' || card.dataset.insight === k;
          card.style.display = show ? '' : 'none';
        });
      }));
      // scatter
      const sc = ui.$('[data-scatter]', root);
      if (sc) renderScatter(sc);
    },
  };

  function insightCard(ins) {
    return `
    <div class="card expandable insight" data-insight="${ins.tint}" data-reveal style="--tint:var(--accent-${ins.tint})">
      <button class="ins-head" data-toggle>
        <span class="glyph tint">${icon(ins.icon, 18)}</span>
        <div class="ins-title-wrap"><div class="ins-title">${ins.title}</div>
          <div class="ins-tags">${ins.tags.map((t) => `<span class="tag">${t}</span>`).join('')}</div></div>
        <span class="chev-tog">${icon('chevD', 16)}</span>
      </button>
      <div class="expand-body"><div class="inner">
        <p class="ins-body">${ins.body}</p>
        <div class="ins-actions"><button class="btn ghost" data-noroute>${icon('info',15)} See evidence</button></div>
      </div></div>
    </div>`;
  }

  function renderScatter(host) {
    host.style.cssText = 'position:relative;height:120px;margin-top:14px;border-radius:14px;background:var(--surface);border:1px solid var(--hairline);overflow:hidden';
    // deterministic-ish points with upward trend
    let html = '';
    for (let i = 0; i < 22; i++) {
      const x = 8 + (i / 21) * 84 + (Math.sin(i) * 3);
      const y = 78 - (i / 21) * 56 + (Math.cos(i * 1.7) * 9);
      html += `<span style="position:absolute;left:${x}%;top:${y}%;width:8px;height:8px;border-radius:50%;
        background:var(--accent-hrv);box-shadow:0 0 10px var(--accent-hrv);opacity:0;transform:scale(0);
        animation:reveal .5s var(--ease-spring) forwards;animation-delay:${i*35}ms"></span>`;
    }
    // trend line
    html += `<span style="position:absolute;left:6%;right:6%;top:64%;height:2px;transform:rotate(-24deg);transform-origin:left;
      background:linear-gradient(90deg,transparent,var(--accent-hrv));opacity:.6"></span>`;
    host.innerHTML = html;
  }
})(window.NOOP = window.NOOP || {});
