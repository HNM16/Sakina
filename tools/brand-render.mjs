#!/usr/bin/env node
// Renders the brand images that documents point at, so they cannot drift away
// from the documents again:
//
//   docs/brand/identity.png      the identity page, exactly as identity.html says
//   docs/brand/mark-check.png    the evidence behind the mark findings in
//                                docs/DESIGN-AUDIT.md
//   docs/brand/samani-frames.png every САМАНӢ variant sampled across one cycle
//
// mark-check is drawn from geometric first principles. The shapes it puts
// beside ours are *families* — "concentric rounded squares", "an octagram" —
// reconstructed from their definitions. No other company's mark is reproduced
// here, and none should be added.
//
// samani-frames asks samani.html's own painter for specific moments rather than
// screenshotting it mid-loop, because a screenshot of a running animation shows
// one arbitrary frame and proves nothing. It has already earned that: it caught
// БОФТ leaving the indicator visibly empty at the start of every repeat.
import { chromium } from 'playwright';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const out = (f) => resolve(root, 'docs/brand', f);

// Kept deliberately in step with _ChorkhonaPainter in apps/mobile/lib/src/theme.dart.
const PAINTER = String.raw`
const FIR = '#32BBC8', SAF = '#E3AC55';
function rr(g, c, half, unit, rot, fill, r) {
  g.save(); g.translate(c, c); g.rotate(rot);
  const w = half * 2 * unit;
  g.beginPath(); g.roundRect(-w / 2, -w / 2, w, w, r * unit);
  if (fill) { g.fillStyle = fill; g.fill(); } else g.stroke();
  g.restore();
}
function sakina(cv, px, solid) {
  const g = cv.getContext('2d'), u = px / 100, c = px / 2, R = Math.PI / 4;
  g.lineWidth = 5 * u; g.lineJoin = 'round'; g.strokeStyle = solid ? '#E8EEF7' : FIR;
  rr(g, c, 38, u, 0, 0, 3);
  if (px >= 24) rr(g, c, 26, u, R, 0, 3);
  if (px >= 40) rr(g, c, 17, u, 0, 0, 3);
  rr(g, c, 8, u, R, solid ? '#E8EEF7' : SAF, 2);
}
function octagram(cv, px, solid) {
  const g = cv.getContext('2d'), u = px / 100, c = px / 2, R = Math.PI / 4;
  g.lineWidth = 5 * u; g.lineJoin = 'round'; g.strokeStyle = solid ? '#E8EEF7' : FIR;
  rr(g, c, 34, u, 0, solid ? '#E8EEF7' : 0, 0);
  rr(g, c, 34, u, R, solid ? '#E8EEF7' : 0, 0);
}
function concentric(cv, px) {
  const g = cv.getContext('2d'), u = px / 100, c = px / 2;
  g.lineWidth = 5 * u; g.lineJoin = 'round'; g.strokeStyle = FIR;
  rr(g, c, 38, u, 0, 0, 3); rr(g, c, 26, u, 0, 0, 3); rr(g, c, 14, u, 0, 0, 3);
}
function turnLast(cv, px) {
  const g = cv.getContext('2d'), u = px / 100, c = px / 2, R = Math.PI / 4;
  g.lineWidth = 5 * u; g.lineJoin = 'round'; g.strokeStyle = FIR;
  rr(g, c, 26, u, R, 0, 3);
  if (px >= 24) rr(g, c, 38, u, 0, 0, 3);
  if (px >= 40) rr(g, c, 17, u, 0, 0, 3);
  rr(g, c, 8, u, R, SAF, 2);
}
function filled(cv, px) {
  const g = cv.getContext('2d'), u = px / 100, c = px / 2, R = Math.PI / 4;
  rr(g, c, 50, u, 0, FIR, 18);
  g.globalCompositeOperation = 'destination-out';
  rr(g, c, 30, u, R, '#000', 4);
  g.globalCompositeOperation = 'source-over';
  rr(g, c, 13, u, 0, SAF, 2);
}
// True pixel size, then magnified with smoothing off, so a reader sees the
// pixels a launcher actually gets rather than a resampled guess.
function ramp(host, fn, sizes, zoom) {
  for (const px of sizes) {
    const off = document.createElement('canvas');
    off.width = off.height = px; fn(off, px);
    const big = document.createElement('canvas');
    big.width = big.height = px * zoom;
    const bg = big.getContext('2d');
    bg.imageSmoothingEnabled = false;
    bg.drawImage(off, 0, 0, px * zoom, px * zoom);
    const f = document.createElement('figure');
    f.appendChild(big);
    const cap = document.createElement('figcaption');
    cap.textContent = px + ' px';
    f.appendChild(cap); host.appendChild(f);
  }
}
`;

const SHEET = String.raw`<!doctype html><html lang="en"><meta charset="utf-8">
<title>Sakina — mark check</title>
<style>
 body{margin:0;background:#0A1220;color:#E8EEF7;
      font:14px/1.55 "Noto Sans",system-ui,sans-serif;padding:44px 48px 56px}
 h1{font:600 26px/1.2 system-ui;margin:0 0 6px}
 h1+p{color:#8496B3;margin:0 0 8px;max-width:80ch}
 h2{font:600 16px/1.3 system-ui;color:#32BBC8;margin:40px 0 4px}
 p.n{color:#8496B3;margin:0 0 18px;max-width:80ch}
 .row{display:flex;gap:32px;align-items:flex-end;flex-wrap:wrap}
 figure{margin:0;text-align:center}
 figcaption{color:#8496B3;margin-top:8px;font-size:12px;max-width:22ch}
 canvas{display:block}
 .squint{filter:blur(6px)}
 footer{color:#8496B3;margin-top:44px;font-size:12px;max-width:80ch}
</style><body>
<h1>Does the mark hold up?</h1>
<p>Evidence for the “The mark” findings in <code>docs/DESIGN-AUDIT.md</code>.
Regenerate with <code>pnpm brand:render</code>.</p>

<h2>1 · What we draw, and what its outline actually is</h2>
<p class="n">The mark as shipped, then the same geometry filled solid. The
silhouette is a rounded square. Only <em>overlapping</em> squares make an
octagram — and an octagram is the Turkic star on three neighbouring state
emblems, so the distinction is worth keeping.</p>
<div class="row">
  <figure><canvas id="a" width="200" height="200"></canvas><figcaption>Sakina, as shipped</figcaption></figure>
  <figure><canvas id="asil" width="200" height="200"></canvas><figcaption>its silhouette — a square</figcaption></figure>
  <figure><canvas id="oct" width="200" height="200"></canvas><figcaption>two overlapping squares</figcaption></figure>
  <figure><canvas id="octsil" width="200" height="200"></canvas><figcaption>its silhouette — eight points</figcaption></figure>
</div>

<h2>2 · The family next door</h2>
<p class="n">Concentric rounded squares is well-trodden ground. The 45°
alternation and the two-colour core are what separate ours from it.</p>
<div class="row">
  <figure><canvas id="conc" width="200" height="200"></canvas><figcaption>concentric, no rotation</figcaption></figure>
  <figure><canvas id="a2" width="200" height="200"></canvas><figcaption>ours — rotation alternates</figcaption></figure>
</div>

<h2>3 · The squint test</h2>
<p class="n">Blurred to roughly what peripheral vision gets. The three families
resolve differently: a lit centre, a hollow frame, a rosette.</p>
<div class="row">
  <figure><canvas class="squint" id="b1" width="150" height="150"></canvas><figcaption>ours</figcaption></figure>
  <figure><canvas class="squint" id="b2" width="150" height="150"></canvas><figcaption>concentric family</figcaption></figure>
  <figure><canvas class="squint" id="b3" width="150" height="150"></canvas><figcaption>octagram</figcaption></figure>
</div>

<h2>4 · The size ramp — as shipped</h2>
<p class="n">This is the finding. Under 32 px the strokes go sub-pixel and the
tiers merge; at 16 px the mark is a hollow square with a dot.</p>
<div class="row" id="r1"></div>

<h2>5 · If the 45° turn were dropped last instead of first</h2>
<p class="n">Better ordering — the tier carrying the identity survives longer —
but it only trades a square-and-dot for a diamond-and-dot.</p>
<div class="row" id="r2"></div>

<h2>6 · A solid-fill variant, drawn as a test</h2>
<p class="n">A firuza tile with the opening knocked out and the core in saffron.
Holds to 12 px. Not adopted — it is a design change, and design changes get
asked about first.</p>
<div class="row" id="r3"></div>

<footer>Every shape beside ours is a family reconstructed from its geometric
definition. No other company’s mark is reproduced here.</footer>
<script>` + PAINTER + String.raw`
sakina(a, 200); sakina(asil, 200, 1); octagram(oct, 200); octagram(octsil, 200, 1);
concentric(conc, 200); sakina(a2, 200);
sakina(b1, 150); concentric(b2, 150); octagram(b3, 150);
ramp(r1, sakina,   [96, 48, 32, 24, 16, 12], 4);
ramp(r2, turnLast, [96, 48, 32, 24, 16, 12], 4);
ramp(r3, filled,   [96, 48, 32, 24, 16, 12], 4);
</script></body></html>`;

const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });

// Dark is the design's home, and the page follows prefers-color-scheme, so a
// default Playwright context would quietly render the light swap instead.
const identity = await browser.newPage({
  viewport: { width: 1100, height: 900 },
  deviceScaleFactor: 1,
  colorScheme: 'dark',
});
await identity.goto(pathToFileURL(resolve(root, 'docs/brand/identity.html')).href);
// The mark animates in with fill-mode `both`, so a screenshot taken on load
// catches it at frame zero — invisible. Wait for every animation to finish.
await identity.evaluate(() =>
  Promise.all(document.getAnimations().map((a) => a.finished.catch(() => {}))));
await identity.screenshot({ path: out('identity.png'), fullPage: true });
console.log('  docs/brand/identity.png');

const sheet = await browser.newPage({ viewport: { width: 1240, height: 900 }, deviceScaleFactor: 2 });
await sheet.setContent(SHEET);
await sheet.screenshot({ path: out('mark-check.png'), fullPage: true });
console.log('  docs/brand/mark-check.png');

// A filmstrip of every САМАНӢ variant, sampled at fixed moments. A screenshot
// of a running loop catches one arbitrary frame and tells you nothing, so
// samani.html exposes its own painter and this asks it for specific times.
const STRIP = [
  // The loop at three of its six mixes, each sampled across one of its own
  // laps, so the range the presets cover is visible in the still as well.
  ['ОРОМ', 'loop', [0, 0.36, 0.72, 1.08, 1.44, 1.80, 2.16, 2.52], 'orom'],
  ['КОР', 'loop', [0, 0.26, 0.52, 0.78, 1.04, 1.30, 1.56, 1.82], 'kor'],
  ['ЗАРБ', 'loop', [0, 0.23, 0.46, 0.69, 0.92, 1.15, 1.38, 1.61], 'zarb'],
  ['НАВБАТ', 'navbat', [0, 0.26, 0.52, 0.78, 1.04, 1.30, 1.56, 1.82]],
  ['ГУЗАР', 'guzar', [0, 0.28, 0.55, 0.83, 1.1, 1.38, 1.65, 1.93]],
  ['МАВҶ', 'mavj', [0, 0.18, 0.35, 0.53, 0.7, 0.88, 1.05, 1.23]],
  ['БОФТ', 'boft', [0.05, 0.22, 0.4, 0.58, 0.76, 0.95, 1.3, 1.8]],
  ['НАФАС', 'nafas', [0, 0.11, 0.23, 0.34, 0.45, 0.56, 0.68, 0.79]],
  ['ЧАРХ', 'charkh', [0, 0.1, 0.2, 0.45, 0.62, 0.72, 0.82, 1.07]],
  ['ГИРЕҲ', 'gireh', [0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4]],
  ['ТОБ', 'tob', [0, 0.04, 0.08, 0.12, 0.16, 0.2, 0.26, 0.32]],
];

const strip = await browser.newPage({
  viewport: { width: 900, height: 980 },
  deviceScaleFactor: 2,
  colorScheme: 'dark',
});
await strip.goto(pathToFileURL(resolve(root, 'docs/brand/samani.html')).href);
await strip.evaluate((rows) => {
  const board = document.createElement('div');
  board.id = 'filmstrip';
  board.style.cssText =
    'position:fixed;inset:0;z-index:99;background:#0A1220;padding:28px 32px;' +
    'display:flex;flex-direction:column;gap:18px;' +
    'font:13px/1.4 "Noto Sans",system-ui,sans-serif;color:#8496B3';
  const title = document.createElement('div');
  title.textContent = 'САМАНӢ — every variant, sampled across one cycle';
  title.style.cssText = 'color:#E8EEF7;font-size:16px;font-weight:700;margin-bottom:2px';
  board.appendChild(title);
  for (const [label, id, times, presetId] of rows) {
    const line = document.createElement('div');
    line.style.cssText = 'display:flex;align-items:center;gap:16px';
    const name = document.createElement('div');
    name.textContent = label;
    name.style.cssText = 'width:74px;flex:none;letter-spacing:.06em';
    line.appendChild(name);
    for (const t of times) {
      const cv = document.createElement('canvas');
      window.SakinaSamani.paint(cv, id, 56, t, presetId);
      line.appendChild(cv);
    }
    board.appendChild(line);
  }
  document.body.appendChild(board);
}, STRIP);
await strip.locator('#filmstrip').screenshot({ path: out('samani-frames.png') });
console.log('  docs/brand/samani-frames.png');

await browser.close();
