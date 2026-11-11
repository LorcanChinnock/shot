// Renders the 1200×630 social cards in the site's own look: public/og.png for the site, and public/og/<slug>.png for each guide page.
// The cards load src/styles/global.css and reuse the hero scene's markup and styles from HeroStage.astro (its last frame, which is
// what reduced motion shows) and the pastel panel from Window.astro, so they follow the site. Fonts are the system's, as on the site. Run after the brand, the hero or a
// guide page's title changes: npm run og
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { groups, readGuide } from '../src/lib/guide-files.ts';

const chrome = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const url = (path) => new URL(path, import.meta.url).href;
const source = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const between = (text, start, end) => text.slice(text.indexOf(start) + start.length, text.indexOf(end));

// Astro's scoped CSS marks unscoped selectors with :global(…), which plain CSS doesn't know.
const unscope = (css) => css.replace(/:global\(([^)]*)\)/g, '$1');
const hero = source('../src/components/HeroStage.astro');
// HeroStage imports its screenshots and shows them with <Image src={name} … />; here each becomes a plain <img> of the file.
const heroImages = Object.fromEntries([...hero.matchAll(/^import (\w+) from '([^']+\.png)';$/gm)].map(([, name, path]) => [name, new URL(path, new URL('../src/components/', import.meta.url)).href]));
// The markup runs from the scene's first tag after the frontmatter (whose comment mentions both markers) to the style block.
const stage = hero
  .slice(hero.indexOf('<div class="hero-scene ', hero.indexOf('---', 3)), hero.lastIndexOf('<style>'))
  .replace(/ role="img" aria-label="[^"]*"/, '')
  .replace(/<Image src=\{(\w+)\}([^>]*?)\s*\/>/g, (_, name, attrs) => `<img src="${heroImages[name]}"${attrs.replace(/\s(widths|sizes|loading|fetchpriority)=(\{[^}]*\}|"[^"]*")/g, '')}>`);
const stageStyle = unscope(hero.slice(hero.lastIndexOf('<style>') + '<style>'.length, hero.lastIndexOf('</style>')));
const windowStyle = unscope(between(source('../src/components/Window.astro'), '<style>', '</style>'));
// Each guide group's chip colour picks the pastel panel behind its card's picture.
const tones = { yellow: 'sand', pink: 'blush', sky: 'sky', violet: 'lilac', red: 'sage' };

const media = (file) => url(`../../docs/media/${file}`);
const shot = (file, size, [x, y, w, h]) => `<div class="sc-crop" style="aspect-ratio: ${w} / ${h}"><img src="${media(file)}" style="width: ${(size[0] / w) * 100}%; left: ${(-x / w) * 100}%; top: ${(-y / h) * 100}%"></div>`;
const wide = [1600, 1000];
const editorWindow = [220, 39, 1160, 883];
const strip = (file) => `<div class="sc-strip"><img src="${media(file)}"></div>`;
const kbd = (keys) => keys.map((k) => `<kbd class="key">${k}</kbd>`).join('');
const code = (lines) => `<div class="sc-code">${lines.map((l) => `<p>${l}</p>`).join('')}</div>`;

// What each guide page's card shows beside its title: the page's own screenshot where the guide has one, otherwise a drawing of
// what the page is about. Anything not listed shows the hero scene.
const shortcuts = [['⌘⇧4', 'Area'], ['⌘⇧3', 'Whole screen'], ['⌘⇧5', 'Record'], ['A', 'Arrow'], ['B', 'Blur'], ['T', 'Text'], ['M', 'Highlight'], ['⌘C', 'Copy'], ['⌘Z', 'Undo']];
const languages = ['English', 'Deutsch', 'Français', 'Español', 'Italiano', 'Português', '日本語', '한국어', '简体中文'];
const scenes = {
  'get-started': shot('welcome.png', [1240, 940], [190, 150, 860, 583]),
  'take-a-screenshot': shot('capture-area.png', [2000, 1255], [340, 200, 1320, 1035]),
  'quick-access': `<img class="sc-plain" src="${media('quick-access.png')}">`,
  'record-your-screen': strip('recording-controls.png'),
  'annotate-a-screenshot': shot('editor.png', wide, editorWindow),
  'crop-and-arrange': shot('editor-crop.png', wide, editorWindow),
  'style-a-screenshot': shot('editor-style.png', wide, editorWindow),
  'combine-images': shot('editor-combine.png', wide, editorWindow),
  'edit-a-recording': strip('video-timeline.png'),
  'animate-and-annotate-a-recording': `<svg class="sc-chart" viewBox="0 0 520 280"><rect x="6" y="6" width="508" height="268" rx="14" fill="#fff"/><text x="30" y="40" font-weight="800" font-size="20" fill="#23232b">Revenue</text><text x="124" y="40" font-size="14" fill="#77777f">Last 14 days</text><rect x="40" y="170" width="22" height="50" rx="3" fill="#b7d3ca"/><rect x="72" y="158" width="22" height="62" rx="3" fill="#b7d3ca"/><rect x="104" y="168" width="22" height="52" rx="3" fill="#b7d3ca"/><rect x="136" y="140" width="22" height="80" rx="3" fill="#b7d3ca"/><rect x="168" y="148" width="22" height="72" rx="3" fill="#b7d3ca"/><rect x="200" y="132" width="22" height="88" rx="3" fill="#b7d3ca"/><rect x="232" y="120" width="22" height="100" rx="3" fill="#b7d3ca"/><rect x="264" y="150" width="22" height="70" rx="3" fill="#b7d3ca"/><rect x="296" y="156" width="22" height="64" rx="3" fill="#b7d3ca"/><rect x="328" y="135" width="22" height="85" rx="3" fill="#b7d3ca"/><rect x="360" y="125" width="22" height="95" rx="3" fill="#b7d3ca"/><rect x="392" y="130" width="22" height="90" rx="3" fill="#b7d3ca"/><rect x="424" y="110" width="22" height="110" rx="3" fill="#b7d3ca"/><rect x="456" y="70" width="22" height="150" rx="3" fill="#3f9c7c"/><line x1="30" y1="221" x2="490" y2="221" stroke="#d6d6dc" stroke-width="2"/><text x="296" y="58" font-weight="800" font-size="26" fill="#ff4d3d">Best day</text><path d="M 404 52 Q 430 52 449 70" fill="none" stroke="#ff4d3d" stroke-width="4" stroke-linecap="round"/><path d="M 445.5 59.6 L 449 70 L 438.4 67.1" fill="none" stroke="#ff4d3d" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  'export-a-video-or-gif': `<div class="sc-seg"><p><b>Format</b><span>MP4</span><span class=on>GIF</span></p><p><b>FPS</b><span>10</span><span class=on>15</span><span>24</span></p><p><b>Width</b><span>480</span><span class=on>720</span><span>1080</span><span>Full</span></p><p><b>Speed</b><span class=on>1x</span><span>1.5x</span><span>2x</span></p><p class="est">≈ 105 KB</p></div>`,
  'organise-your-captures': shot('gallery.png', wide, [170, 88, 1260, 786]),
  'find-your-captures': shot('gallery.png', wide, [170, 88, 1260, 786]),
  'keyboard-shortcuts': `<div class="sc-keys">${shortcuts.map(([k, l], i) => `<p style="--fill: var(--${['yellow', 'pink', 'mint'][i % 3]})">${kbd([k])}<span>${l}</span></p>`).join('')}</div>`,
  'automation-reference': code(['<b>open</b> "shot://capture-area"', '<b>open</b> "shot://capture-timer?seconds=5"', '<b>open</b> "shot://capture-window"', '<b>open</b> "shot://gallery"']),
  settings: shot('settings.png', wide, [170, 61, 1260, 840]),
  languages: `<div class="sc-langs">${languages.map((l, i) => `<span style="--fill: var(--${['yellow', 'pink', 'sky', 'mint', 'violet', 'orange'][i % 6]})">${l}</span>`).join('')}</div>`,
  updates: `<div class="sc-list"><p><span>Check for updates</span><i class="on"></i></p><p><span>Ask me before going online</span><i class="on"></i></p><p class="btn"><b>Check Now</b></p></div>`,
  privacy: `<div class="sc-list"><p class="no"><b>✕</b><span>No account</span></p><p class="no"><b>✕</b><span>No cloud</span></p><p class="no"><b>✕</b><span>No analytics</span></p><p class="fine">Goes online only to check for updates.</p></div>`,
  troubleshooting: `<div class="sc-list"><p class="q"><b>?</b><span>Captures fail after I turned on Screen Recording</span></p><p class="q"><b>?</b><span>Microphone says NOT ASKED</span></p><p class="q"><b>?</b><span>⌘⇧4 still opens the macOS tool</span></p></div>`,
  'removing-shot': code(['<b>$</b> curl -fsSL \\', '    shot.lorcanchinnock.com/uninstall.sh \\', '    | bash']),
};

const page = ({ chip, chipColor, headline, size, keys, scene }) => `<!doctype html>
<link rel="stylesheet" href="${url('../src/styles/global.css')}">
<style>
  ${stageStyle}
  ${windowStyle}
  body { width: 1200px; height: 630px; min-height: 0; overflow: hidden; position: relative; }
  .brand { position: absolute; left: 56px; top: 44px; }
  .brand img { width: 44px; height: 44px; }
  .brand { font-size: 30px; }
  .intro { position: absolute; left: 56px; top: 150px; width: 500px; display: grid; gap: 22px; justify-items: start; }
  .intro .chip { font-size: 17px; padding: 4px 14px; }
  h1 { font-size: ${size}px; line-height: 1.02; letter-spacing: -0.03em; }
  h1 .keys { display: flex; margin-top: 0.14em; gap: 0.12em; }
  h1 .key { font: inherit; font-size: 0.78em; font-weight: 800; min-width: 1.1em; padding: 0.02em 0.18em; border-radius: 0.18em; line-height: 1.2; box-shadow: 0 0 0 3px var(--line), 0 0.09em 0 var(--line); }
  h1 .key:nth-child(1) { rotate: -4deg; } h1 .key:nth-child(2) { rotate: 2deg; } h1 .key:nth-child(3) { rotate: -1deg; }
  .lede { margin: 0; font: 500 26px/1.35 var(--font); max-width: 17em; }
  .shot-panel { position: absolute; left: 590px; top: 50%; width: 560px; translate: 0 -50%; }
  .hero-scene { position: absolute; left: 590px; top: 50%; translate: 0 -50%; width: 570px; padding: 44px 30px 52px; border-radius: 28px; }
  .hero-scene .quick-anchor { left: -64px; }
  .sc { aspect-ratio: 16 / 10; display: grid; place-items: center; overflow: hidden; }
  .sc-crop { position: relative; width: 100%; overflow: hidden; } .sc-crop img { position: absolute; max-width: none; height: auto; }
  .sc:has(.sc-crop) { aspect-ratio: auto; display: block; } .sc-plain { width: 100%; }
  .sc-strip { padding: 0 24px; } .sc-strip img { border: 2px solid var(--line); border-radius: 8px; box-shadow: 3px 3px 0 var(--line); }
  .sc-code { width: 86%; padding: 26px 28px; background: #12121a; color: #f6f4ef; border: 3px solid var(--line); border-radius: 12px; box-shadow: 4px 4px 0 var(--line); font: 600 18px/1.8 var(--mono); }
  .sc-code p { margin: 0; white-space: nowrap; } .sc-code b { color: var(--yellow); }
  .sc-keys { width: 90%; display: grid; grid-template-columns: repeat(3, 1fr); gap: 22px 14px; }
  .sc-keys p { margin: 0; display: grid; gap: 8px; justify-items: start; font: 800 20px/1.2 var(--font); color: var(--on-accent); }
  .sc-keys kbd { font-size: 30px; background: var(--fill); color: var(--on-accent); border-color: #000; box-shadow: 3px 3px 0 #000; }
  .sc-langs { width: 88%; display: flex; flex-wrap: wrap; gap: 14px; justify-content: center; }
  .sc-langs span { padding: 8px 20px; font: 800 28px/1.2 var(--font); color: var(--on-accent); background: var(--fill); border: 3px solid var(--line); border-radius: 12px; box-shadow: 3px 3px 0 var(--line); }
  .sc-chart { width: 92%; filter: drop-shadow(4px 4px 0 var(--line)); }
  .sc-seg { width: 86%; display: grid; gap: 14px; }
  .sc-seg p { margin: 0; display: flex; align-items: center; gap: 10px; font: 800 22px/1.2 var(--font); color: var(--on-accent); }
  .sc-seg b { width: 100px; font-size: 16px; letter-spacing: 0.08em; text-transform: uppercase; }
  .sc-seg span { padding: 7px 16px; background: var(--paper); color: var(--ink); border: 3px solid var(--line); border-radius: 10px; box-shadow: 2px 2px 0 var(--line); }
  .sc-seg span.on { background: var(--mint); color: var(--on-accent); }
  .sc-seg .est { justify-content: flex-end; font-size: 20px; }
  .sc-list { width: 82%; display: grid; gap: 12px; }
  .sc-list p { margin: 0; display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 16px 20px; font: 800 24px/1.25 var(--font); background: var(--paper); color: var(--ink); border: 3px solid var(--line); border-radius: 12px; box-shadow: 4px 4px 0 var(--line); }
  .sc-list .no, .sc-list .q { justify-content: flex-start; } .sc-list p b { flex: none; width: 36px; height: 36px; display: grid; place-items: center; font-size: 20px; color: var(--on-accent); background: var(--red); border: 3px solid var(--line); border-radius: 50%; }
  .sc-list .q b { background: var(--yellow); } .sc-list .q { font-size: 21px; }
  .sc-list .fine { display: block; font-size: 18px; font-weight: 600; background: none; border: 0; box-shadow: none; color: var(--ink); padding: 0 4px; }
  .sc-list i { flex: none; width: 56px; height: 32px; border: 3px solid var(--line); border-radius: 99px; background: var(--well); position: relative; }
  .sc-list i.on { background: var(--mint); } .sc-list i::after { content: ""; position: absolute; top: 3px; left: 3px; width: 20px; height: 20px; border-radius: 50%; background: var(--paper); border: 2px solid var(--line); } .sc-list i.on::after { left: 27px; }
  .sc-list .btn b { width: auto; height: auto; background: none; border: 0; border-radius: 0; font-size: 24px; } .sc-list .btn { justify-content: center; background: var(--yellow); color: var(--on-accent); }
</style>
<div class="brand"><img src="${url('../public/icon-256.png')}"><span>Shot</span></div>
<div class="intro">
  <span class="chip" style="--chip: var(--${chipColor})">${chip}</span>
  <h1>${headline}${keys ? '<span class="keys"><kbd class="key">⌘</kbd><kbd class="key accent">⇧</kbd><kbd class="key">4</kbd></span>' : ''}</h1>
  ${keys ? '<p class="lede">A screenshot app that lives in your menu bar.</p>' : ''}
</div>
${scene ? `<figure class="shot-panel panel ${tones[chipColor]}"><div class="shot-anchor"><div class="shot-frame"><div class="sc">${scene}</div></div></div></figure>` : stage}`;

const dir = mkdtempSync(join(tmpdir(), 'shot-og-'));
const render = (html, out) => {
  const file = join(dir, 'card.html');
  writeFileSync(file, html);
  execFileSync(chrome, [
    '--headless=new', '--hide-scrollbars', '--allow-file-access-from-files', '--force-device-scale-factor=1',
    '--force-prefers-reduced-motion', '--window-size=1200,630', '--virtual-time-budget=3000',
    `--screenshot=${new URL(out, import.meta.url).pathname}`, `file://${file}`,
  ], { stdio: 'ignore' });
};

render(page({ chip: 'Free and open source', chipColor: 'yellow', headline: 'A <span class="hl">better</span>', size: 100, keys: true }), '../public/og.png');

// Cards of pages that no longer exist would otherwise stay behind.
rmSync(new URL('../public/og/', import.meta.url), { recursive: true, force: true });
mkdirSync(new URL('../public/og/', import.meta.url), { recursive: true });
for (const { slug, title, group } of readGuide()) {
  const longest = Math.max(...title.split(' ').map((w) => w.length));
  const size = title.length > 40 ? 52 : title.length > 22 || longest > 12 ? 64 : 84;
  render(page({ chip: `User guide · ${group}`, chipColor: groups.find((g) => g.name === group).color, headline: title, size, scene: scenes[slug] }), `../public/og/${slug}.png`);
}
