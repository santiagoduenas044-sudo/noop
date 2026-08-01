/* ============================================================================
   NOOP · Premium UI — Build & version config
   The single place the prototype's version, milestone, commit and dates live.
   Surfaced in Settings and the What's New screen. `build-single.js` injects the
   real git short-SHA and timestamp at bundle time (the __PLACEHOLDER__ tokens);
   the fallbacks below keep the multi-file / direct-open version sensible.
   ============================================================================ */
(function (NS) {
  'use strict';
  NS.build = {
    prototypeVersion: '0.3.0',
    milestone: 4,
    milestoneName: 'Native migration + fixes · efficiency scale, swipe removal, Home ring, Home gating',
    commit: '__COMMIT__',
    buildDate: 'Aug 1, 2026',
    updated: '__UPDATED__',
    // The native app these milestones migrate into.
    appVersion: '9.1.3',
    iosBuild: 211,
    bundleId: 'com.noopapp.noop',
  };
  if (NS.build.commit.indexOf('__') === 0) NS.build.commit = '7d7914e';
  if (NS.build.updated.indexOf('__') === 0) NS.build.updated = 'Jul 31, 2026 · 20:05 UTC';
})(window.NOOP = window.NOOP || {});
