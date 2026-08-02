/* ============================================================================
   NOOP · Premium UI — Data layer
   A self-contained, deterministic mock of on-device health data. Mirrors the
   shape of NOOP's real signals (recovery / strain / HRV / sleep / heart rate)
   so the UI reads like the shipping product. No network, no storage — pure JS,
   exactly in the spirit of NOOP's offline, on-device philosophy.
   ============================================================================ */
(function (NS) {
  'use strict';

  // Seeded PRNG so the "story" is stable across reloads (deterministic mock).
  function mulberry32(a) {
    return function () {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const rnd = mulberry32(20260731);
  const rr = (min, max) => min + rnd() * (max - min);
  const ri = (min, max) => Math.round(rr(min, max));

  // Build a smooth-ish random walk within [min,max] around a baseline.
  function walk(n, base, spread, min, max) {
    const out = []; let v = base;
    for (let i = 0; i < n; i++) {
      v += rr(-spread, spread);
      v = Math.max(min, Math.min(max, v));
      out.push(Math.round(v * 10) / 10);
    }
    return out;
  }

  const DAYS = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
  const today = new Date(2026, 6, 31); // 31 Jul 2026 (matches session date)

  // -------------------------------------------------------------- Core today
  const recovery = 78;      // %
  const strain = 12.4;      // 0–21 WHOOP-style
  const strainTarget = 14.5;
  const sleepScore = 84;    // %
  const hrv = 96;           // ms (rMSSD)
  const rhr = 48;           // bpm
  const respiratory = 14.2; // rpm
  const spo2 = 97;
  const skinTemp = +0.3;    // °C deviation
  const liveHR = 62;

  // -------------------------------------------------------- Historical series
  const hrvSeries   = walk(30, 88, 6, 62, 118).map(v => Math.round(v));
  const rhrSeries   = walk(30, 50, 1.6, 44, 58).map(v => Math.round(v));
  const recSeries   = walk(30, 70, 9, 28, 99).map(v => Math.round(v));
  const strainSeries= walk(30, 12, 2.4, 4, 20);
  const sleepSeries = walk(30, 82, 7, 55, 98).map(v => Math.round(v));

  // Last 7 days digest (for weekly cards)
  function last7(series) { return series.slice(-7); }

  // Day-in-the-life heart rate (per-5-min, 288 samples)
  function dayHR() {
    const pts = [];
    for (let i = 0; i < 288; i++) {
      const h = i / 12; // hour of day
      let base = 58;
      if (h >= 0 && h < 6) base = 49 + Math.sin(h) * 3;              // deep sleep dip
      else if (h >= 6 && h < 8) base = 62;                          // waking
      else if (h >= 8 && h < 12) base = 74;                        // morning
      else if (h >= 12 && h < 13.5) base = 96 + Math.sin(h*3)*10;  // a run
      else if (h >= 17 && h < 18) base = 88;                       // evening walk
      else if (h >= 21) base = 60;                                 // wind-down
      else base = 72;
      pts.push(Math.max(44, Math.round(base + rr(-4, 5))));
    }
    return pts;
  }

  // ---- Sleep: a realistic multi-cycle night, everything derived from it ----
  // A genuine hypnogram (deep-heavy early, REM-heavy toward morning, brief wakes)
  // so each per-stage density lane populates with well-distributed blocks.
  const SLEEP_START = 23 * 60 + 16; // 11:16 PM (minutes past midnight)
  function buildHypnogram() {
    const segs = []; let t = 0;
    const push = (key, dur) => { segs.push({ key, from: t, to: t + dur }); t += dur; };
    push('awake', 8);                       // sleep onset
    // [light, deep, light, rem, wake-after] per ~90-min cycle
    [[12, 42, 8, 16, 3], [16, 34, 10, 24, 0], [16, 24, 12, 28, 5],
     [18, 16, 12, 32, 2], [18, 10, 10, 34, 7]].forEach(([l1, d, l2, r, aw]) => {
      push('light', l1); push('deep', d); push('light', l2); push('rem', r);
      if (aw) push('awake', aw);
    });
    push('light', 9);                        // drift before waking
    return segs;
  }
  // Inverted-depth curve (higher = lighter/restless, lower = deep) at 1-min res —
  // the wavy ribbon that sits above the lanes.
  function buildDepthCurve(segs, total) {
    const center = { awake: 92, rem: 80, light: 69, deep: 58 };
    const out = [];
    for (let m = 0; m < total; m++) {
      const seg = segs.find((s) => m >= s.from && m < s.to) || segs[segs.length - 1];
      const n = seg.key === 'awake' ? rr(-4, 9) : rr(-3.2, 3.2);
      out.push(Math.max(53, Math.min(100, Math.round(center[seg.key] + n))));
    }
    return out;
  }
  function fmtSleepTime(elapsed) {
    let mm = (SLEEP_START + Math.round(elapsed)) % 1440;
    let h = Math.floor(mm / 60), m = mm % 60, ap = h < 12 ? 'AM' : 'PM', hh = h % 12 || 12;
    return `${hh}:${String(m).padStart(2, '0')} ${ap}`;
  }

  const _hyp = buildHypnogram();
  const _inBed = _hyp[_hyp.length - 1].to;
  const _by = { awake: 0, light: 0, deep: 0, rem: 0 };
  _hyp.forEach((s) => { _by[s.key] += s.to - s.from; });
  const _asleep = _inBed - _by.awake;
  const _restMin = _by.deep + _by.rem;

  const sleep = {
    startMin: SLEEP_START,
    inBed: fmtSleepTime(0), outBed: fmtSleepTime(_inBed),
    inBedMin: _inBed,
    asleep: _asleep,               // minutes asleep
    hoursMin: _asleep,             // alias for the "Hours of sleep" headline
    needed: 498,
    efficiency: Math.round(_asleep / _inBed * 100),
    latency: 9,
    consistency: 82,
    debt: 42,                      // minutes accumulated
    restorative: Math.round(_restMin / _asleep * 100), // % of sleep (deep+rem)
    restorativeMin: _restMin,
    // 30-day typical baselines for the "typically …" comparisons
    hoursTypicalMin: 413,          // 6h 53m
    restorativeTypicalMin: 273,    // 4h 33m
    byStage: _by,                  // minutes per stage
    // typical stage mix (% of time in bed) for tap-to-compare
    typical: { awake: 8, light: 40, deep: 20, rem: 22 },
    times: { bed: fmtSleepTime(0), mid: fmtSleepTime(_inBed / 2), wake: fmtSleepTime(_inBed) },
    stages: [                      // awake/rem/light/deep (order kept for consumers)
      { stage: 'Awake', minutes: _by.awake, key: 'awake' },
      { stage: 'REM',   minutes: _by.rem,   key: 'rem' },
      { stage: 'Light', minutes: _by.light, key: 'light' },
      { stage: 'Deep',  minutes: _by.deep,  key: 'deep' },
    ],
    hypnogram: _hyp,               // [{key, from(min), to(min)}]
    depth: buildDepthCurve(_hyp, _inBed),
    fmtTime: fmtSleepTime,
  };

  // The sleep stage active at a given minute-offset into the night.
  sleep.stageAt = function (minute) {
    const seg = _hyp.find((s) => minute >= s.from && minute < s.to) || _hyp[_hyp.length - 1];
    return seg.key;
  };

  // ---- Overnight physiological series (mock), sampled every `step` minutes and
  //      ALIGNED to the sleep timeline so they can be scrubbed against the stages.
  //      Values track the stage the body was in (HR dips in deep, HRV rises, etc.).
  (function buildOvernight() {
    const step = 3, n = Math.ceil(_inBed / step);
    const cHR   = { awake: 66, rem: 58, light: 54, deep: 49 };
    const cHRV  = { awake: 52, rem: 62, light: 70, deep: 82 };
    const cRESP = { awake: 15.4, rem: 15.1, light: 14.0, deep: 13.4 };
    const cSPO2 = { awake: 97, rem: 96, light: 96, deep: 95 };
    const hr = [], hrv = [], resp = [], spo2 = [], temp = [], minutes = [];
    let dHR = 0, dHRV = 0;   // slow drifts so the lines wander realistically
    for (let i = 0; i < n; i++) {
      const m = i * step, k = sleep.stageAt(m), frac = m / _inBed;
      dHR = Math.max(-3, Math.min(3, dHR + rr(-0.6, 0.6)));
      dHRV = Math.max(-4, Math.min(4, dHRV + rr(-0.8, 0.8)));
      minutes.push(m);
      hr.push(Math.round(cHR[k] + dHR + rr(-1.4, 1.4)));
      hrv.push(Math.round(cHRV[k] + dHRV + rr(-3, 3)));
      resp.push(Math.round((cRESP[k] + rr(-0.5, 0.5)) * 10) / 10);
      spo2.push(Math.max(93, Math.min(99, Math.round(cSPO2[k] + rr(-0.6, 0.9)))));
      // wrist temp deviation: settles below baseline mid-night, rises toward waking
      const t = -0.15 + 0.5 * frac - 0.3 * Math.sin(frac * Math.PI);
      temp.push(Math.round((t + rr(-0.05, 0.05)) * 100) / 100);
    }
    sleep.overnight = {
      step, n, minutes, hr, hrv, resp, spo2, temp,
      baseline: { hr: 52, hrv: 68, resp: 14.2, spo2: 96, temp: 0.0 },
    };
  })();

  // Recovery / readiness contributors (name, contribution %, direction, note)
  const drivers = [
    { name: 'HRV',            value: 96,  unit: 'ms', pct: 88, dir: 'up',   tint: 'hrv',      note: '12% above your 30-day baseline' },
    { name: 'Resting HR',     value: 48,  unit: 'bpm',pct: 82, dir: 'up',   tint: 'heart',    note: '2 bpm lower than yesterday' },
    { name: 'Sleep',          value: 84,  unit: '%',  pct: 84, dir: 'flat', tint: 'sleep',    note: '7h 29m of 8h 18m needed' },
    { name: 'Respiratory',    value: 14.2,unit: 'rpm',pct: 90, dir: 'flat', tint: 'recovery', note: 'Steady and in range' },
    { name: 'Skin temp',      value: '+0.3',unit:'°C',pct: 76, dir: 'down', tint: 'gold',     note: 'Slightly elevated overnight' },
    { name: 'Prior strain',   value: 15.1,unit: '',   pct: 68, dir: 'down', tint: 'strain',   note: 'Yesterday ran hot — factor in rest' },
  ];

  // Heart-rate zones for today
  const hrZones = [
    { name: 'Peak',   sub: '171–190', min: 171, color: 'heart',    minutes: 6  },
    { name: 'Cardio', sub: '152–170', min: 152, color: 'strain',   minutes: 18 },
    { name: 'Aerobic',sub: '133–151', min: 133, color: 'gold',     minutes: 34 },
    { name: 'Fat burn',sub:'114–132', min: 114, color: 'recovery', minutes: 52 },
    { name: 'Resting',sub: '< 114',   min: 0,   color: 'hrv',      minutes: 1170 },
  ];

  // AI coach conversation seeds + insight cards
  const insights = [
    { icon: 'sparkles', tint: 'recovery', title: 'HRV climbed overnight',
      body: 'Your HRV rose to <b>96 ms</b>, up 12% from your baseline. The most likely driver is an earlier bedtime — you fell asleep 41 minutes sooner than your weekly average.',
      tags: ['HRV', 'Sleep timing'] },
    { icon: 'moon', tint: 'sleep', title: 'Consistency is paying off',
      body: 'You’ve kept your sleep-wake window within 30 minutes for <b>5 nights running</b>. Restorative sleep is trending up +8% this week.',
      tags: ['Consistency', 'Deep + REM'] },
    { icon: 'flame', tint: 'strain', title: 'Room to push today',
      body: 'Recovery is green at <b>78%</b>. Your body can absorb a strain of <b>14–16</b> without cutting into tomorrow. A tempo session fits well.',
      tags: ['Strain target', 'Training'] },
    { icon: 'thermo', tint: 'gold', title: 'Skin temp nudged up',
      body: 'Overnight skin temperature was <b>+0.3°C</b> above baseline. Nothing alarming — often tied to a warm room or a later meal. Worth a glance if it persists.',
      tags: ['Temperature', 'Watch'] },
  ];

  const coachThread = [
    { who: 'coach', text: 'Morning. You’re recovered at 78% — solidly in the green. How are you feeling?' },
    { who: 'you', text: 'Pretty good, a little tight in the legs.' },
    { who: 'coach', text: 'Makes sense after yesterday’s 15.1 strain. Your HRV held up though, so this is soreness, not fatigue. I’d keep today aerobic — a Zone 2 effort around strain 12–14 — and save intensity for tomorrow.' },
  ];

  // Journal entries (behaviours) — today
  const journal = {
    date: 'Today',
    entries: [
      { key: 'mood',    label: 'Mood',        icon: 'smile',   value: 'Good',   tint: 'recovery' },
      { key: 'training',label: 'Training',    icon: 'flame',   value: 'Tempo run', tint: 'strain' },
      { key: 'alcohol', label: 'Alcohol',     icon: 'wine',    value: 'None',   tint: 'sleep' },
      { key: 'caffeine',label: 'Caffeine',    icon: 'coffee',  value: '2 cups', tint: 'gold' },
      { key: 'stress',  label: 'Stress',      icon: 'wave',    value: 'Low',    tint: 'hrv' },
      { key: 'meals',   label: 'Meals',       icon: 'plate',   value: 'On plan',tint: 'recovery' },
    ],
    behaviours: [
      { label: 'Slept in a cool room', on: true,  impact: '+4% recovery' },
      { label: 'Screen-free hour before bed', on: true, impact: '+6% deep sleep' },
      { label: 'Late caffeine', on: false, impact: '−7% sleep latency' },
      { label: 'Alcohol', on: false, impact: '−12% HRV' },
      { label: 'Hydrated well', on: true, impact: '+3% recovery' },
      { label: 'Read before sleep', on: true, impact: '+2% consistency' },
    ],
  };

  // Weekly overview strip
  const week = DAYS.map((d, i) => ({
    day: d,
    recovery: recSeries.slice(-7)[i],
    strain: strainSeries.slice(-7)[i],
    sleep: sleepSeries.slice(-7)[i],
    isToday: i === 5,
  }));

  function band(v) { return v >= 67 ? 'high' : v >= 34 ? 'mid' : 'low'; }
  function bandColor(v) { return v >= 67 ? 'var(--band-high)' : v >= 34 ? 'var(--band-mid)' : 'var(--band-low)'; }

  // ============================================================ EXPANSION v2
  // Everything below is additional mock health data for the richer prototype.
  // It stays PURE + DETERMINISTIC and is clearly separated from any real
  // HealthKit logic — these are demonstration values only.

  const mean = (a) => a.reduce((s, v) => s + v, 0) / a.length;
  const round = (v, d = 0) => { const m = 10 ** d; return Math.round(v * m) / m; };

  // ------- Energy / calories (Active + Resting, from HealthKit conceptually) -
  const activeKcal = 612;                 // today, active energy
  const restingKcal = 1685;               // today, basal energy
  const totalKcal = activeKcal + restingKcal;
  const activeSeries = walk(30, 540, 130, 180, 1050).map((v) => Math.round(v));  // 30d active kcal
  const stepsSeries = walk(30, 8600, 2600, 2200, 16000).map((v) => Math.round(v / 50) * 50);
  const stepsToday = 9240;
  const stepGoal = 10000;
  const exerciseMin = 46;                  // Apple "exercise minutes" today
  const distanceKm = 6.8;
  const flights = 12;

  // Cumulative active-energy curve across the day (kcal burned so far by hour).
  function calDayCurve() {
    const pts = []; let acc = 0;
    for (let h = 0; h < 24; h++) {
      let rate = 6;                        // resting-ish baseline per hour (active only)
      if (h >= 7 && h < 9) rate = 34;      // morning movement
      else if (h >= 12 && h < 14) rate = 120; // a run
      else if (h >= 17 && h < 18) rate = 60;  // evening walk
      else if (h >= 9 && h < 18) rate = 28;
      else if (h >= 22 || h < 6) rate = 2;
      acc += rate + rr(-3, 3);
      pts.push(Math.max(0, Math.round(acc)));
    }
    return pts;
  }
  // Active-calorie contribution by activity source (adds to ~activeKcal).
  const activitySplit = [
    { label: 'Tempo run', kcal: 340, tint: 'strain', icon: 'run' },
    { label: 'Walking',   kcal: 165, tint: 'recovery', icon: 'steps' },
    { label: 'Daily movement', kcal: 107, tint: 'hrv', icon: 'flame' },
  ];

  // ------- Blood oxygen (SpO2) — nightly averages -----------------------------
  const spo2Available = true;              // flip to false to preview the empty state
  const spo2Series = walk(30, 96.5, 0.6, 94, 99).map((v) => Math.round(v));  // nightly avg %
  const spo2Latest = 97;
  const spo2NightAvg = 96;
  const spo2Low = 94, spo2High = 98;

  // ------- Respiratory-rate history -------------------------------------------
  const respSeries = walk(30, 14.4, 0.5, 12.6, 16.4).map((v) => round(v, 1));

  // ------- Stress (CONCEPTUAL / future feature — not a shipping algorithm) ----
  // A day-long "physiological load" timeline (0–3 scale) with sleep vs awake.
  function stressDay() {
    const pts = [];
    for (let i = 0; i < 96; i++) {          // 15-min buckets
      const h = i / 4;
      let base = 1.0;
      if (h < 6.5) base = 0.4;              // asleep — low
      else if (h < 8) base = 1.2;           // waking
      else if (h >= 12 && h < 13.5) base = 2.5; // a run — high
      else if (h >= 9 && h < 11) base = 1.9;    // work block
      else if (h >= 15 && h < 17) base = 1.7;
      else if (h >= 21) base = 0.8;             // wind-down
      else base = 1.1;
      pts.push(Math.max(0, Math.min(3, round(base + rr(-0.25, 0.25), 2))));
    }
    return pts;
  }
  const stressNow = 1.3;
  const stressDist = { low: 61, medium: 27, high: 12 };  // % of day
  const stressSeries = walk(14, 1.4, 0.35, 0.4, 2.6).map((v) => round(v, 1));

  // ------- Personalised baselines (30-day means for comparisons) --------------
  const baselines = {
    hrv: Math.round(mean(hrvSeries)),
    rhr: Math.round(mean(rhrSeries)),
    recovery: Math.round(mean(recSeries)),
    sleep: Math.round(mean(sleepSeries)),
    strain: round(mean(strainSeries), 1),
    respiratory: round(mean(respSeries), 1),
    spo2: Math.round(mean(spo2Series)),
    // Fixed, sensible personal baselines so "today vs typical" narratives stay coherent
    // regardless of where the seeded random series happens to land.
    active: 540,
    steps: 8600,
  };

  // ------- Metric registry — powers the REUSABLE Metric Detail screen ---------
  // One entry per drillable signal. `higherBetter` colours the delta correctly.
  const metrics = {
    hrv: {
      key: 'hrv', name: 'Heart Rate Variability', short: 'HRV', unit: 'ms', tint: 'hrv', icon: 'hrv',
      value: hrv, series: hrvSeries, baseline: baselines.hrv, decimals: 0, higherBetter: true,
      explain: 'HRV is the beat-to-beat variation in your heart rhythm. Higher values usually mean your nervous system is well-recovered and adaptable.',
      insight: 'Today’s HRV is 12% above your 30-day baseline — most likely from an earlier, more consistent bedtime.',
    },
    rhr: {
      key: 'rhr', name: 'Resting Heart Rate', short: 'Resting HR', unit: 'bpm', tint: 'heart', icon: 'heart',
      value: rhr, series: rhrSeries, baseline: baselines.rhr, decimals: 0, higherBetter: false,
      explain: 'Your lowest heart rate at rest. A lower resting heart rate generally reflects good cardiovascular fitness and recovery.',
      insight: 'Resting HR is 2 bpm below yesterday and sits at the low end of your normal range — a good recovery signal.',
    },
    respiratory: {
      key: 'respiratory', name: 'Respiratory Rate', short: 'Respiratory', unit: 'rpm', tint: 'recovery', icon: 'lungs',
      value: respiratory, series: respSeries, baseline: baselines.respiratory, decimals: 1, higherBetter: false,
      explain: 'Breaths per minute during sleep. It’s very stable night to night, so small changes can hint at strain, illness or a warm room.',
      insight: 'Steady at 14.2 rpm — right on your baseline, with no unusual overnight elevation.',
    },
    spo2: {
      key: 'spo2', name: 'Blood Oxygen', short: 'Blood Oxygen', unit: '%', tint: 'strain', icon: 'spo2',
      value: spo2Latest, series: spo2Series, baseline: baselines.spo2, decimals: 0, higherBetter: true,
      explain: 'The percentage of oxygen carried in your blood, sampled overnight. Healthy readings typically sit between 95–100%.',
      insight: 'Nightly average of 96% sits comfortably in the normal range, with a stable 30-day trend.',
    },
    active: {
      key: 'active', name: 'Active Energy', short: 'Active Calories', unit: 'kcal', tint: 'flame', icon: 'flame',
      value: activeKcal, series: activeSeries, baseline: baselines.active, decimals: 0, higherBetter: true,
      explain: 'Calories burned through movement and exercise, on top of the energy your body uses at rest.',
      insight: 'You’ve burned 612 active kcal — about 13% above your daily average, driven mostly by a midday run.',
    },
    steps: {
      key: 'steps', name: 'Steps', short: 'Steps', unit: '', tint: 'recovery', icon: 'steps',
      value: stepsToday, series: stepsSeries, baseline: baselines.steps, decimals: 0, higherBetter: true,
      explain: 'Total steps counted across the day. A simple, reliable proxy for everyday movement.',
      insight: 'At 9,240 steps you’re on pace to clear your 10k goal — 7% ahead of a typical Thursday.',
    },
    recovery: {
      key: 'recovery', name: 'Recovery', short: 'Recovery', unit: '%', tint: 'recovery', icon: 'recovery',
      value: recovery, series: recSeries, baseline: baselines.recovery, decimals: 0, higherBetter: true,
      explain: 'A daily readiness score blending HRV, resting heart rate, sleep and respiratory rate into one number.',
      insight: 'Recovery is green at 78% — your body can absorb a solid training load today.',
    },
    strain: {
      key: 'strain', name: 'Day Strain', short: 'Strain', unit: '', tint: 'strain', icon: 'strain',
      value: strain, series: strainSeries, baseline: baselines.strain, decimals: 1, higherBetter: true,
      explain: 'Cardiovascular load accumulated across the day on a 0–21 scale, weighted by time spent in each heart-rate zone.',
      insight: 'Currently 12.4 — below your 14.5 target, so there’s room to add an aerobic block.',
    },
    sleep: {
      key: 'sleep', name: 'Sleep Performance', short: 'Sleep', unit: '%', tint: 'sleep', icon: 'moon',
      value: sleepScore, series: sleepSeries, baseline: baselines.sleep, decimals: 0, higherBetter: true,
      explain: 'How much of the sleep your body needed you actually got, factoring in duration, efficiency and restorative stages.',
      insight: 'An 84% night — you met most of your sleep need, with restorative sleep trending up this week.',
    },
  };

  // Recovery "why" contributions — each with its own share of the score + reason.
  const recoveryContribs = [
    { key: 'hrv', name: 'HRV', value: 96, unit: 'ms', share: 38, dir: 'up', tint: 'hrv',
      note: '96 ms · 12% above your 88 ms baseline' },
    { key: 'rhr', name: 'Resting HR', value: 48, unit: 'bpm', share: 27, dir: 'up', tint: 'heart',
      note: '48 bpm · 2 below yesterday, low in range' },
    { key: 'sleep', name: 'Sleep', value: 84, unit: '%', share: 26, dir: 'flat', tint: 'sleep',
      note: '7h 45m of 8h 18m needed · 84%' },
    { key: 'respiratory', name: 'Respiratory', value: 14.2, unit: 'rpm', share: 9, dir: 'flat', tint: 'recovery',
      note: '14.2 rpm · steady, on baseline' },
  ];

  // Today's workouts (for Strain screen).
  const workouts = [
    { name: 'Tempo run', icon: 'run', tint: 'strain', dur: 38, strain: 9.1, kcal: 340, avgHr: 152, peakHr: 176, time: '12:24 PM' },
  ];

  // ============================================================ EXPANSION v3
  // Deeper Sleep / Heart / Stress / Trends / Journal / Coach / Home datasets —
  // the product-experience pass. Deterministic mock only, clearly separated
  // from the v1/v2 data above so it's obvious what's new.

  // ---- Sleep: bedtime / wake-time / consistency / debt / awakenings --------
  const bedtimeSeries = walk(30, 23 * 60 + 15, 22, 22 * 60 + 30, 24 * 60 + 15).map((v) => Math.round(v));
  const waketimeSeries = walk(30, 6 * 60 + 50, 18, 6 * 60, 7 * 60 + 45).map((v) => Math.round(v));
  const consistencySeries = walk(30, 82, 6, 55, 97).map((v) => Math.round(v));
  const awakeningsSeries = walk(30, 2.4, 1.1, 0, 6).map((v) => Math.max(0, Math.round(v)));
  const deepPctSeries = walk(30, 19, 3, 9, 28).map((v) => Math.round(v));
  const remPctSeries = walk(30, 23, 3.4, 12, 33).map((v) => Math.round(v));
  const lightPctSeries = deepPctSeries.map((dp, i) => Math.max(30, 100 - dp - remPctSeries[i] - 8));
  const awakePctSeries = deepPctSeries.map((dp, i) => Math.max(2, 100 - dp - remPctSeries[i] - lightPctSeries[i]));
  // Nightly AGGREGATE trend series (one value per night) — distinct from the per-minute
  // `sleep.overnight` arrays, which only cover LAST night at high (3-min) resolution.
  const hrvNightlySeries = hrvSeries.slice();
  const respNightlySeries = respSeries.slice();
  const spo2NightlySeries = spo2Series.slice();
  const skinTempNightlySeries = walk(30, 0.1, 0.25, -0.6, 1.1).map((v) => round(v, 2));
  // A rolling 14-night sleep-debt ledger: personal need vs actual, running balance in minutes.
  const sleepDebtLedger = (() => {
    const need = 498; // 8h18m — matches sleep.needed
    const out = []; let bal = 0;
    const last14 = sleepSeries.slice(-14).map((v) => Math.round((6 + v / 100 * 2.6) * 60));
    last14.forEach((mins, i) => {
      const delta = mins - need; bal += delta;
      out.push({ day: i, actualMin: mins, needMin: need, deltaMin: delta, balanceMin: bal });
    });
    return out;
  })();

  // ---- Heart: baselines, weekday pattern, distribution ----------------------
  const hrvBaselineRange = { lo: Math.round(mean(hrvSeries) - 14), hi: Math.round(mean(hrvSeries) + 14) };
  const rhrBaselineRange = { lo: Math.round(mean(rhrSeries) - 4), hi: Math.round(mean(rhrSeries) + 4) };
  const hrByWeekday = DAYS.map((dn, i) => ({ day: dn, avg: 58 + Math.round(Math.sin(i * 1.3) * 4 + rr(-2, 2)) }));
  const hrHistogram = (() => {
    const samples = dayHR(); const lo = Math.min(...samples), hi = Math.max(...samples);
    const buckets = 8, span = (hi - lo) / buckets || 1; const counts = Array(buckets).fill(0);
    samples.forEach((v) => { const i = Math.min(buckets - 1, Math.max(0, Math.floor((v - lo) / span))); counts[i]++; });
    return { lo, hi, counts };
  })();

  // ---- Stress: rest vs elevated + phase breakdown (concept only) -----------
  const stressRestVsElevated = { restPct: 64, elevatedPct: 36 };
  const stressByPhase = { sleep: 0.6, awake: 1.5 };

  // ---- Trends: correlation pairs + notable changes --------------------------
  const correlationPairs = [
    { a: 'hrv', b: 'sleep', an: 'HRV', bn: 'Sleep', r: 0.68, tint: 'hrv',
      note: 'Nights with higher sleep performance are reliably followed by higher HRV.', confidence: 'consistent' },
    { a: 'rhr', b: 'recovery', an: 'Resting HR', bn: 'Recovery', r: -0.61, tint: 'heart',
      note: 'A lower resting heart rate lines up with a higher recovery score.', confidence: 'consistent' },
    { a: 'sleep', b: 'recovery', an: 'Sleep', bn: 'Recovery', r: 0.74, tint: 'sleep',
      note: 'Sleep performance is the strongest single driver of next-day recovery in your data.', confidence: 'consistent' },
    { a: 'strain', b: 'recovery', an: 'Effort', bn: 'Next-day recovery', r: -0.52, tint: 'strain',
      note: 'Higher strain days tend to be followed by a softer recovery the next morning.', confidence: 'emerging' },
    { a: 'stress', b: 'sleep', an: 'Stress', bn: 'Sleep', r: -0.58, tint: 'gold',
      note: 'Higher daytime physiological load tends to precede a lower sleep score that night.', confidence: 'emerging' },
  ];
  const notableChanges = [
    { metric: 'HRV', change: '+12%', when: 'last 7 days', dir: 'up', tint: 'hrv',
      note: 'Climbed after 3 consecutive earlier bedtimes.' },
    { metric: 'Resting HR', change: '−2 bpm', when: 'last 14 days', dir: 'down', tint: 'heart',
      note: 'Trending down alongside the HRV gain.' },
    { metric: 'Sleep debt', change: '+18 min', when: 'last 7 days', dir: 'up', tint: 'sleep',
      note: 'Two shorter nights this week added to the running balance.' },
  ];

  // ---- Journal v2: quick chips, history, streak, correlations ---------------
  const behaviorCatalog = [
    { key: 'caffeine', label: 'Caffeine', ic: 'coffee', tint: 'gold', pinned: true },
    { key: 'alcohol', label: 'Alcohol', ic: 'wine', tint: 'sleep', pinned: true },
    { key: 'lateMeal', label: 'Late meal', ic: 'plate', tint: 'strain', pinned: true },
    { key: 'exercise', label: 'Exercise', ic: 'flame', tint: 'strain', pinned: true },
    { key: 'intenseExercise', label: 'Intense exercise', ic: 'run', tint: 'heart', pinned: false },
    { key: 'stressHigh', label: 'Stress', ic: 'wave', tint: 'hrv', pinned: true },
    { key: 'illness', label: 'Illness', ic: 'thermo', tint: 'heart', pinned: false },
    { key: 'travel', label: 'Travel', ic: 'run', tint: 'gold', pinned: false },
    { key: 'lateBedtime', label: 'Late bedtime', ic: 'moon', tint: 'sleep', pinned: true },
    { key: 'hydration', label: 'Hydration', ic: 'drop', tint: 'recovery', pinned: false },
    { key: 'screenBeforeBed', label: 'Screen before bed', ic: 'zzz', tint: 'sleep', pinned: false },
    { key: 'nap', label: 'Nap', ic: 'moon', tint: 'hrv', pinned: false },
    { key: 'medication', label: 'Medication', ic: 'pill', tint: 'hrv', pinned: false },
    { key: 'soreness', label: 'Soreness', ic: 'thermo', tint: 'strain', pinned: false },
  ];
  const moodCatalog = [
    { key: 'great', label: 'Great', ic: 'smile' }, { key: 'good', label: 'Good', ic: 'smile' },
    { key: 'ok', label: 'Okay', ic: 'wave' }, { key: 'low', label: 'Low', ic: 'drop' },
  ];
  // 14-night history: which behaviours were logged + mood that day (deterministic pseudo-pattern).
  const journalHistory = (() => {
    const out = [];
    for (let i = 0; i < 14; i++) {
      const seed = i * 7 + 3;
      const on = behaviorCatalog.filter((_, bi) => (Math.sin(seed * 1.7 + bi * 2.3) + 1) / 2 > 0.72);
      out.push({
        dayIndex: i, behaviours: on.map((b) => b.key),
        mood: moodCatalog[Math.floor(Math.abs(Math.sin(seed)) * moodCatalog.length) % moodCatalog.length].key,
      });
    }
    return out;
  })();
  const journalStreak = 6;
  const journalCorrelations = [
    { behavior: 'lateMeal', behaviorLabel: 'Late meals', metric: 'hrv', metricLabel: 'HRV', effectPct: -8,
      occurrences: 12, confidence: 'emerging',
      text: 'On days after late meals, your HRV has been lower than your baseline.' },
    { behavior: 'exercise', behaviorLabel: 'exercise', metric: 'recovery', metricLabel: 'recovery',
      pairedWithLabel: 'an earlier bedtime', effectPct: 6, occurrences: 9, confidence: 'consistent',
      text: 'Your recovery tends to be higher following days when you logged exercise and an earlier bedtime.' },
    { behavior: 'alcohol', behaviorLabel: 'Alcohol', metric: 'hrv', metricLabel: 'HRV', effectPct: -12,
      occurrences: 5, confidence: 'early',
      text: 'On the few nights you logged alcohol, HRV read lower the next morning — too few occurrences yet to be sure.' },
  ];

  // ---- Coach v2: richer example thread, tagged fact / association / hypothesis / general ---
  const coachThreadV2 = [
    { who: 'you', text: 'Why has my recovery been lower lately?' },
    { who: 'coach', kind: 'fact', text: 'Over the last 7 days your recovery averaged <b>64%</b>, down from a 30-day average of <b>78%</b>. That’s a measured drop against your own history.' },
    { who: 'coach', kind: 'association', text: 'It lines up with 3 nights you logged a <b>late meal</b> and one <b>late bedtime</b> — in your data, those two show up together with a lower next-day HRV about 70% of the time.' },
    { who: 'coach', kind: 'hypothesis', text: 'My best guess is the combination of later meals and shorter sleep windows is the main driver, not any one factor alone — but that’s an inference, not a confirmed cause.' },
    { who: 'you', text: 'What should I focus on improving?' },
    { who: 'coach', kind: 'fact', text: 'Sleep performance has the strongest relationship with your recovery of anything I track (r = 0.74).' },
    { who: 'coach', kind: 'general', text: 'In general, a consistent bedtime and a cool, dark room are the most reliable levers for sleep quality — that’s well-established sleep science, not specific to your data.' },
    { who: 'coach', kind: 'association', text: 'Specifically for you: your 5 earliest nights this month all preceded an HRV reading above baseline. Protecting that bedtime window looks like your highest-leverage change.' },
  ];

  // ---- Home: full metric catalog + default layout + weekly narrative -------
  const metricCatalog = [
    { key: 'heartRateNow', name: 'Heart Rate', unit: 'bpm', ic: 'heart', tint: 'heart', group: 'Heart' },
    { key: 'rhr', name: 'Resting HR', unit: 'bpm', ic: 'heart', tint: 'hrv', group: 'Heart' },
    { key: 'hrv', name: 'HRV', unit: 'ms', ic: 'hrv', tint: 'hrv', group: 'Heart' },
    { key: 'respiratory', name: 'Respiratory Rate', unit: 'rpm', ic: 'lungs', tint: 'recovery', group: 'Sleep' },
    { key: 'spo2', name: 'Blood Oxygen', unit: '%', ic: 'spo2', tint: 'strain', group: 'Sleep', sometimes: true },
    { key: 'skinTemp', name: 'Skin Temperature', unit: '°C', ic: 'thermo', tint: 'gold', group: 'Sleep', sometimes: true },
    { key: 'steps', name: 'Steps', unit: '', ic: 'steps', tint: 'recovery', group: 'Activity' },
    { key: 'active', name: 'Active Energy', unit: 'kcal', ic: 'flame', tint: 'flame', group: 'Activity' },
    { key: 'resting', name: 'Resting Energy', unit: 'kcal', ic: 'flame', tint: 'gold', group: 'Activity' },
    { key: 'totalEnergy', name: 'Total Energy', unit: 'kcal', ic: 'flame', tint: 'flame', group: 'Activity' },
    { key: 'workouts', name: 'Workouts', unit: '', ic: 'run', tint: 'strain', group: 'Activity' },
    { key: 'sleepDuration', name: 'Sleep Duration', unit: 'h', ic: 'moon', tint: 'sleep', group: 'Sleep' },
    { key: 'sleepEfficiency', name: 'Sleep Efficiency', unit: '%', ic: 'check', tint: 'sleep', group: 'Sleep' },
    { key: 'restorative', name: 'Restorative Sleep', unit: '%', ic: 'moon', tint: 'sleep', group: 'Sleep' },
    { key: 'recovery', name: 'Recovery', unit: '%', ic: 'recovery', tint: 'recovery', group: 'Recovery' },
    { key: 'strain', name: 'Effort / Strain', unit: '', ic: 'strain', tint: 'strain', group: 'Recovery' },
    { key: 'stress', name: 'Stress', unit: '', ic: 'stress', tint: 'gold', group: 'Recovery', sometimes: true, preview: true },
    { key: 'sleepConsistency', name: 'Sleep Consistency', unit: '%', ic: 'calendar', tint: 'hrv', group: 'Sleep' },
    { key: 'bedtime', name: 'Bedtime', unit: '', ic: 'moon', tint: 'sleep', group: 'Sleep' },
    { key: 'waketime', name: 'Wake Time', unit: '', ic: 'today', tint: 'gold', group: 'Sleep' },
    { key: 'sleepDebt', name: 'Sleep Debt', unit: 'min', ic: 'timer', tint: 'heart', group: 'Sleep' },
  ];
  const defaultHomeLayout = ['hrv', 'rhr', 'respiratory', 'spo2', 'active', 'steps'];

  function weekNarrative() {
    const rec7 = recSeries.slice(-7), sleep7 = sleepSeries.slice(-7);
    const recUp = rec7.filter((v, i) => i > 0 && v >= rec7[i - 1]).length;
    const sleepDelta = sleep7[sleep7.length - 1] - sleep7[0];
    const sleepDir = sleepDelta > 2 ? 'increased' : sleepDelta < -2 ? 'decreased' : 'held steady';
    return `Recovery improved on ${recUp} of the last 7 days while sleep ${sleepDir}.`;
  }

  NS.data = {
    today, DAYS,
    recovery, strain, strainTarget, sleepScore, hrv, rhr, respiratory, spo2, skinTemp, liveHR,
    hrvSeries, rhrSeries, recSeries, strainSeries, sleepSeries, respSeries, last7,
    dayHR, sleep, drivers, hrZones, insights, coachThread, journal, week,
    band, bandColor, rr, ri, walk, mean, round,
    // expansion v2
    activeKcal, restingKcal, totalKcal, activeSeries, stepsSeries, stepsToday, stepGoal,
    exerciseMin, distanceKm, flights, calDayCurve, activitySplit,
    spo2Available, spo2Series, spo2Latest, spo2NightAvg, spo2Low, spo2High,
    stressDay, stressNow, stressDist, stressSeries,
    baselines, metrics, recoveryContribs, workouts,
    // expansion v3 — product-experience pass
    bedtimeSeries, waketimeSeries, consistencySeries, awakeningsSeries,
    deepPctSeries, remPctSeries, lightPctSeries, awakePctSeries,
    hrvNightlySeries, respNightlySeries, spo2NightlySeries, skinTempNightlySeries, sleepDebtLedger,
    hrvBaselineRange, rhrBaselineRange, hrByWeekday, hrHistogram,
    stressRestVsElevated, stressByPhase,
    correlationPairs, notableChanges,
    behaviorCatalog, moodCatalog, journalHistory, journalStreak, journalCorrelations,
    coachThreadV2,
    metricCatalog, defaultHomeLayout, weekNarrative,
  };
})(window.NOOP = window.NOOP || {});
