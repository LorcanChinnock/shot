// Renders scroll scenarios in headless Chrome: a truth image of the whole page, and the frames a screen capture would
// see at each scroll position. Usage: node frames.cjs <outDir> [scenario-name-filter]
// Needs puppeteer-core (NODE_PATH) and Google Chrome.
const fs = require('fs'), path = require('path');
const puppeteer = require('puppeteer-core');
const { pages } = require('./pages.cjs');

const VIEW = { width: 640, height: 440 }, DPR = 2;

// Scroll paths in css px, one entry per captured frame (30 a second). Each returns [{x, y}].
const steps = (n, dx, dy, x0 = 0, y0 = 0) => Array.from({ length: n }, (_, i) => ({ x: x0 + dx * (i + 1), y: y0 + dy * (i + 1) }));
const profiles = {
  steady: () => steps(70, 0, 12),
  slow: () => steps(120, 0, 3),
  // wheel notches: 100 px each, eased over 9 frames, with a rest between
  notches: () => { const o = []; let y = 0; for (let n = 0; n < 9; n++) { for (let f = 1; f <= 9; f++) o.push({ x: 0, y: y + 100 * (1 - Math.pow(1 - f / 9, 3)) }); y += 100; for (let k = 0; k < 4; k++) o.push({ x: 0, y }); } return o; },
  // trackpad flick: speed decays by 7% a frame
  flick: () => { const o = []; let y = 0, v = 70; while (v > 0.4) { y += v; v *= 0.93; o.push({ x: 0, y: Math.round(y * 2) / 2 }); } return o; },
  // down, back up, down again, never leaving the area's range
  reversal: () => { const o = []; let y = 0; for (const d of [260, -140, 330, -200, 420]) { const n = 18; for (let i = 1; i <= n; i++) o.push({ x: 0, y: y + d * i / n }); y += d; } return o; },
  // steady with a dropped frame (a double step) every fifth frame
  drops: () => { const o = []; let y = 0; for (let i = 0; i < 60; i++) { y += i % 5 === 4 ? 70 : 14; o.push({ x: 0, y }); } return o; },
  // big jumps, each under three quarters of the view
  jumps: () => steps(14, 0, 270),
  // fractional steps, as a trackpad gives
  fractional: () => Array.from({ length: 80 }, (_, i) => ({ x: 0, y: Math.round(i * 9.37 * 2) / 2 + 9 })),
  sideways: () => steps(60, 14, 0),
  diagonal: () => steps(60, 9, 11),
  // starts part way down, scrolls up
  upward: () => steps(45, 0, -12, 0, 560),
};

const scenarios = [
  ['article-steady', 'article', 'steady'], ['article-slow', 'article', 'slow'], ['article-notches', 'article', 'notches'],
  ['article-flick', 'article', 'flick'], ['article-reversal', 'article', 'reversal'], ['article-drops', 'article', 'drops'],
  ['article-jumps', 'article', 'jumps'], ['article-fractional', 'article', 'fractional'], ['article-upward', 'article', 'upward'],
  ['glass-notches', 'article:translucent', 'notches'], ['glass-flick', 'article:translucent', 'flick'],
  ['table-steady', 'table', 'steady'], ['table-sideways', 'table', 'sideways'], ['table-diagonal', 'table', 'diagonal'], ['table-drops', 'table', 'drops'],
  ['chat-steady', 'chat', 'steady'], ['chat-flick', 'chat', 'flick'], ['chat-notches', 'chat', 'notches'], ['chat-reversal', 'chat', 'reversal'],
  ['feed-steady', 'feed', 'steady'], ['feed-flick', 'feed', 'flick'], ['feed-notches', 'feed', 'notches'],
  ['code-steady', 'code', 'steady'], ['code-flick', 'code', 'flick'], ['code-notches', 'code', 'notches'],
  ['settings-steady', 'settings', 'steady'], ['settings-notches', 'settings', 'notches'], ['settings-flick', 'settings', 'flick'],
  ['floaters-steady', 'floaters', 'steady'], ['floaters-notches', 'floaters', 'notches'], ['floaters-flick', 'floaters', 'flick'],
  ['timeline-sideways', 'timeline', 'sideways'], ['timeline-diagonal', 'timeline', 'diagonal'],
];

(async () => {
  const out = process.argv[2], filter = process.argv[3] || '';
  const browser = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--hide-scrollbars', '--force-color-profile=srgb'] });
  const page = await browser.newPage();
  await page.setViewport({ ...VIEW, deviceScaleFactor: DPR });
  const truths = new Map();
  for (const [name, spec, profile] of scenarios) {
    if (filter && !name.includes(filter)) continue;
    const dir = path.join(out, name);
    if (fs.existsSync(path.join(dir, 'manifest.json'))) continue;
    fs.mkdirSync(dir, { recursive: true });
    const [kind, variant] = spec.split(':');
    const html = `<!doctype html><meta charset=utf-8>${pages[kind](variant === 'translucent')}`;
    const truthPath = path.join(out, `truth-${spec.replace(':', '-')}.png`);
    await page.setViewport({ ...VIEW, deviceScaleFactor: DPR });
    await page.setContent(html, { waitUntil: 'load' });
    if (!truths.has(spec)) {
      await page.evaluate(() => document.body.classList.add('flat'));
      await page.setViewport({ ...VIEW, deviceScaleFactor: DPR });
      await page.screenshot({ path: truthPath, fullPage: true });
      await page.evaluate(() => document.body.classList.remove('flat'));
      truths.set(spec, truthPath);
    }
    const offsets = profiles[profile]();
    const max = await page.evaluate(() => ({ x: document.documentElement.scrollWidth - innerWidth, y: document.documentElement.scrollHeight - innerHeight }));
    // clamp, as a real scroller does
    const clamped = offsets.map(o => ({ x: Math.min(Math.max(o.x, 0), max.x), y: Math.min(Math.max(o.y, 0), max.y) }));
    // How much of the viewport's top and bottom the pinned parts take at rest, and where the page ends.
    const pins = await page.evaluate(() => { const v = innerHeight; let top = 0, bottom = 0; for (const e of document.querySelectorAll('.pin:not(.fixedonly)')) { const r = e.getBoundingClientRect(); const cs = getComputedStyle(e); if (cs.position !== 'sticky') continue; if (cs.top !== 'auto' && r.height < v / 2 && r.width > innerWidth / 2) top = Math.max(top, r.bottom); if (cs.bottom !== 'auto' && r.width > innerWidth / 2) bottom = Math.max(bottom, v - r.top); } return { top, bottom }; });
    const start = profile === 'upward' ? { x: 0, y: 560 } : { x: 0, y: 0 };
    const all = [start, ...clamped];
    await page.evaluate((s) => scrollTo(s.x, s.y), start);
    for (let i = 0; i < all.length; i++) {
      await page.evaluate((o) => scrollTo(o.x, o.y), all[i]);
      await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
      await page.screenshot({ path: path.join(dir, `f${String(i).padStart(4, '0')}.png`) });
    }
    fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ name, truth: truthPath, dpr: DPR, view: VIEW, offsets: all, pinTop: pins.top, pinBottom: pins.bottom, maxX: max.x, maxY: max.y }, null, 1));
    console.log('rendered', name, all.length, 'frames');
  }
  await browser.close();
})();
