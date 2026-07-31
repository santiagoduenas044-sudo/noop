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

  // Sleep stages for last night → minutes per stage + a hypnogram
  const sleep = {
    inBed: '11:12 PM', outBed: '7:04 AM',
    asleep: 449,           // minutes
    needed: 498,
    efficiency: 93,
    latency: 9,
    consistency: 82,
    debt: 42,              // minutes accumulated
    restorative: 71,       // % (deep+rem)
    stages: [              // {stage, minutes}  awake/light/rem/deep
      { stage: 'Awake', minutes: 31,  key: 'awake' },
      { stage: 'REM',   minutes: 118, key: 'rem' },
      { stage: 'Light', minutes: 205, key: 'light' },
      { stage: 'Deep',  minutes: 126, key: 'deep' },
    ],
    // hypnogram: sequence of {key, from(min index), to} across ~475 min
    hypnogram: buildHypnogram(),
  };

  function buildHypnogram() {
    const order = ['awake','rem','light','deep'];
    const rows = []; let t = 0; const total = 475;
    const pattern = ['light','deep','light','rem','light','deep','light','rem','light','awake','rem','light','rem','awake'];
    const segLen = total / pattern.length;
    pattern.forEach((k) => { rows.push({ key: k, from: t, to: t + segLen }); t += segLen; });
    return rows;
  }

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

  NS.data = {
    today, DAYS,
    recovery, strain, strainTarget, sleepScore, hrv, rhr, respiratory, spo2, skinTemp, liveHR,
    hrvSeries, rhrSeries, recSeries, strainSeries, sleepSeries, last7,
    dayHR, sleep, drivers, hrZones, insights, coachThread, journal, week,
    band, bandColor, rr, ri, walk,
  };
})(window.NOOP = window.NOOP || {});
