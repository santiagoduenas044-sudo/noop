/* Bundles the multi-file prototype into ONE self-contained HTML file.
   Two outputs:
   - dist/index.html            full standalone (open from disk / any static host)
   - dist/artifact-body.html    body-only (for claude.ai Artifact skeleton)
   Pure concatenation; load order is preserved so the IIFE modules still work. */
const fs = require('fs');
const path = require('path');
const root = __dirname;
const R = (p) => fs.readFileSync(path.join(root, p), 'utf8');

const cssFiles = ['tokens', 'base', 'components', 'pages', 'animations'].map((n) => `styles/${n}.css`);
const jsFiles = [
  'scripts/data.js', 'scripts/icons.js', 'scripts/charts.js', 'scripts/components.js',
  'scripts/router.js',
  'pages/home.js', 'pages/sleep.js', 'pages/readiness.js', 'pages/heart.js', 'pages/coach.js',
  'pages/journal.js', 'pages/trends.js', 'pages/insights.js', 'pages/settings.js',
  'scripts/app.js',
];
const css = cssFiles.map((f) => `/* ===== ${f} ===== */\n` + R(f)).join('\n\n');
const js = jsFiles.map((f) => `/* ===== ${f} ===== */\n` + R(f)).join('\n\n');

// Extract the body markup from index.html (everything inside <body>…</body>,
// minus the <script> tags we're inlining separately).
const idx = R('index.html');
let body = idx.slice(idx.indexOf('<body>') + 6, idx.indexOf('</body>'));
body = body.replace(/<script[^>]*src=[^>]*><\/script>\s*/g, '')
           .replace(/\s*<!--[^>]*Scripts:[\s\S]*?ethos\.\s*-->/g, '');

const bundleBody = `<style>\n${css}\n</style>\n${body.trim()}\n<script>\n${js}\n</script>`;

const standalone = `<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
<meta name="theme-color" content="#06070A" />
<title>NOOP — Premium UI</title>
</head>
<body>
${bundleBody}
</body>
</html>`;

fs.mkdirSync(path.join(root, 'dist'), { recursive: true });
fs.writeFileSync(path.join(root, 'dist/index.html'), standalone);
fs.writeFileSync(path.join(root, 'dist/artifact-body.html'), bundleBody);
console.log('standalone bytes:', standalone.length);
console.log('artifact-body bytes:', bundleBody.length);
