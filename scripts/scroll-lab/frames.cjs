// Renders scroll scenarios in headless Chrome: a truth image of the whole page, and the frames a screen capture would
// see at each scroll position. Usage: node frames.cjs <outDir> [scenario-name-filter]
// Needs puppeteer-core (NODE_PATH) and Google Chrome.
const fs = require('fs'), path = require('path');
const puppeteer = require('puppeteer-core');
const { pages } = require('./pages.cjs');

const VIEW = { width: Number(process.env.VIEW_W || 640), height: Number(process.env.VIEW_H || 440) }, DPR = Number(process.env.DPR || 2);

// Scroll paths in css px, one entry per captured frame (30 a second). Each returns [{x, y}].
const steps = (n, dx, dy, x0 = 0, y0 = 0) => Array.from({ length: n }, (_, i) => ({ x: x0 + dx * (i + 1), y: y0 + dy * (i + 1) }));
// Bounce: native scrolling lets the content go past its end and springs it back, showing the background beyond. A
// frame's `over` is how many points it is past the end: positive past the bottom, negative above the top.
const bounce = (n = 14, peak = 36) => Array.from({ length: n }, (_, i) => Math.round(peak * Math.sin(Math.PI * (i + 1) / (n + 1)) * 2) / 2);
const profiles = {
  bottomBounce: (max) => { const o = []; let y = 0; while (y < max.y) { y = Math.min(max.y, y + 120); o.push({ x: 0, y }); } for (const d of bounce()) o.push({ x: 0, y: max.y, over: d }); o.push({ x: 0, y: max.y }, { x: 0, y: max.y }); return o; },
  topBounce: (max) => { const o = []; let y = 300; while (y > 0) { y = Math.max(0, y - 20); o.push({ x: 0, y }); } for (const d of bounce(12, 30)) o.push({ x: 0, y: 0, over: -d }); o.push({ x: 0, y: 0 }, { x: 0, y: 0 }); return o; },
  // a flick that arrives at the end and bounces once
  flickToEnd: (max) => { const o = []; let y = max.y - 700, v = 60; while (y < max.y) { y = Math.min(max.y, y + v); v *= 0.97; o.push({ x: 0, y: Math.round(y * 2) / 2 }); } for (const d of bounce(16, 44)) o.push({ x: 0, y: max.y, over: d }); o.push({ x: 0, y: max.y }); return o; },
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
  // the fastest steps a flick makes at 30 frames a second: 150 points, a third of the area
  jumps: () => steps(30, 0, 150),
  // Chrome's smooth wheel scrolling on a 2x screen: moves of a whole device pixel but an odd one, so half a point, with a
  // rest or two between (#1030)
  halves: () => { const o = []; let y = 0; const moves = [17.5, 52.5, 52.5, 0, 17.5, 105.5, 52.5, 17.5, 0, 0, 52.5, 105.5, 17.5, 52.5, 0, 52.5, 17.5, 105.5, 52.5, 52.5, 17.5, 0, 105.5, 52.5, 17.5, 52.5, 105.5, 17.5, 52.5, 52.5, 17.5, 105.5, 52.5, 17.5, 52.5, 105.5, 52.5, 17.5, 52.5, 52.5]; for (const m of moves) { y += m; o.push({ x: 0, y }); } return o; },
  // The offsets (in device pixels at 2x) of a live Chrome capture of the `list` page on a 1920 x 1084 window (#1030),
  // four wheel notches at a time with 0.5 s between: a pause, a jump of a third of the area or so, small steps as the
  // animation settles, and moves of an odd number of device pixels. Scaled to the lab's view height, so the default
  // 640 x 440 view moves in the same proportions; VIEW_W=1920 VIEW_H=1084 plays it at its own size.
  chrome: () => [0, 12, 188, 300, 320, 356, 459, 580, 637, 958, 960, 1280, 1315, 1420, 1536, 1910, 1920, 1958, 2134, 2223, 2240, 2560, 2570, 2718, 2869, 2880, 3200, 3209, 3342, 3498, 3840, 3849, 3924, 4053, 4160, 4480, 4525, 4713, 4800, 5120, 5440, 5450, 5532, 5716, 5760, 5796, 5901, 6019, 6080, 6400].map(d => ({ x: 0, y: Math.round(d / 2 * VIEW.height / 1084 * 2) / 2 })),
  // The offsets (device pixels at 2x) of a live Chrome capture of the `rows` page in a 1679 x 994 area (#1030): four wheel
  // notches at a time, 160 points, with moves of an odd number of device pixels as the animation settles. Scaled to the
  // view's height; VIEW_W=1679 VIEW_H=994 plays it at its own size.
  pane: () => [0, 10, 94, 225, 311, 320, 357, 463, 617, 640, 676, 843, 937, 960, 1000, 1114, 1233, 1280, 1289, 1362, 1486, 1578, 1600, 1640, 1758, 1876, 1920, 1929, 2004, 2129, 2220, 2240, 2250, 2337, 2523, 2560, 2596, 2766, 2858, 2880, 2923, 3044, 3162, 3200, 3209, 3282, 3403, 3497, 3520, 3555, 3662, 3780, 3837, 3840, 3849, 3932, 4061, 4147, 4160, 4196, 4363, 4457, 4480, 4490, 4575, 4708, 4791, 4800, 4809, 4887, 5013, 5102, 5120].map(d => ({ x: 0, y: Math.round(d / 2 * VIEW.height / 994 * 2) / 2 })),
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
  ['feed-bottom-bounce', 'feed', 'bottomBounce'], ['chat-bottom-bounce', 'chat', 'bottomBounce'], ['code-bottom-bounce', 'code', 'bottomBounce'], ['article-flick-to-end', 'article', 'flickToEnd'], ['feed-top-bounce', 'feed', 'topBounce'], ['feed-flick-to-end', 'feed', 'flickToEnd'],
  ['table-steady', 'table', 'steady'], ['table-sideways', 'table', 'sideways'], ['table-diagonal', 'table', 'diagonal'], ['table-drops', 'table', 'drops'],
  ['chat-steady', 'chat', 'steady'], ['chat-flick', 'chat', 'flick'], ['chat-notches', 'chat', 'notches'], ['chat-reversal', 'chat', 'reversal'],
  ['feed-steady', 'feed', 'steady'], ['feed-flick', 'feed', 'flick'], ['feed-notches', 'feed', 'notches'],
  ['code-steady', 'code', 'steady'], ['code-flick', 'code', 'flick'], ['code-notches', 'code', 'notches'],
  ['settings-steady', 'settings', 'steady'], ['settings-notches', 'settings', 'notches'], ['settings-flick', 'settings', 'flick'],
  ['floaters-steady', 'floaters', 'steady'], ['floaters-notches', 'floaters', 'notches'], ['floaters-flick', 'floaters', 'flick'],
  ['timeline-sideways', 'timeline', 'sideways'], ['timeline-diagonal', 'timeline', 'diagonal'],
  ['list-steady', 'list', 'steady'], ['list-slow', 'list', 'slow'], ['list-notches', 'list', 'notches'], ['list-flick', 'list', 'flick'],  ['list-halves', 'list', 'halves'], ['list-chrome', 'list', 'chrome'], ['rows-pane', 'rows', 'pane'],
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
    const max = await page.evaluate(() => ({ x: document.documentElement.scrollWidth - innerWidth, y: document.documentElement.scrollHeight - innerHeight }));
    const offsets = profiles[profile](max);
    // clamp, as a real scroller does
    const clamped = offsets.map(o => ({ x: Math.min(Math.max(o.x, 0), max.x), y: Math.min(Math.max(o.y, 0), max.y), over: o.over || 0 }));
    // How much of the viewport's top and bottom the pinned parts take at rest, and where the page ends.
    const pins = await page.evaluate(() => { const v = innerHeight, w = innerWidth; let top = 0, bottom = 0, left = 0, right = 0; for (const e of document.querySelectorAll('.pin')) { const r = e.getBoundingClientRect(); const cs = getComputedStyle(e); if (e.classList.contains('fixedonly')) { if (r.bottom > v - 120) bottom = Math.max(bottom, v - r.top); continue; } if (cs.position !== 'sticky') continue; if (cs.top !== 'auto' && r.top <= 1 && r.height < v / 2) top = Math.max(top, r.bottom); if (cs.bottom !== 'auto' && r.bottom >= v - 1 && r.height < v / 2) bottom = Math.max(bottom, v - r.top); if (cs.left !== 'auto' && r.left <= 1 && r.width < w / 2) left = Math.max(left, r.right); if (cs.right !== 'auto' && r.right >= w - 1 && r.width < w / 2) right = Math.max(right, w - r.left); } return { top, bottom, left, right }; });
    const start = profile === 'upward' ? { x: 0, y: 560 } : profile === 'topBounce' ? { x: 0, y: 300 } : profile === 'flickToEnd' ? { x: 0, y: max.y - 700 } : { x: 0, y: 0 };
    const all = [start, ...clamped];
    await page.evaluate((s) => scrollTo(s.x, s.y), start);
    for (let i = 0; i < all.length; i++) {
      // Headless Chrome snaps a scroll offset to a whole point, but a real screen scrolls by device pixels, so a move of
      // half a point (one pixel at 2x) is drawn by scrolling to the point below and shifting the list's rows by the rest.
      await page.evaluate((o) => {
        const base = Math.floor(o.y), rest = o.y - base;
        scrollTo(o.x, base);
        for (const row of document.querySelectorAll('.row')) row.style.transform = rest ? `translateY(${-rest}px)` : '';
        document.body.style.transform = o.over ? `translateY(${-o.over}px)` : '';
      }, all[i]);
      await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
      await page.screenshot({ path: path.join(dir, `f${String(i).padStart(4, '0')}.png`) });
    }
    fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ name, truth: truthPath, dpr: DPR, view: VIEW, offsets: all, pinTop: pins.top, pinBottom: pins.bottom, pinLeft: pins.left, pinRight: pins.right, maxX: max.x, maxY: max.y }, null, 1));
    console.log('rendered', name, all.length, 'frames');
  }
  await browser.close();
})();
