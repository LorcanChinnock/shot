// Renders the 1200×630 social cards in the site's own look: public/og.png for the site, and public/og/<slug>.png for each guide page.
// The cards load src/styles/global.css and reuse the hero's markup and styles from HeroStage.astro (its last frame, which is what
// reduced motion shows), so they follow the site. Fonts are the system's, as on the site. Run after the brand, the hero or a
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

const hero = source('../src/components/HeroStage.astro');
const stage = hero.slice(hero.indexOf('<div class="stage"'), hero.indexOf('<style>')).replace(/ role="img" aria-label="[^"]*"/, '');
const stageStyle = between(hero, '<style>', '</style>');
const windowStyle = between(source('../src/components/Window.astro'), '<style>', '</style>');

const media = (file) => url(`../../docs/media/${file}`);
const shot = (file, size, [x, y, w, h]) => `<div class="sc-crop" style="aspect-ratio: ${w} / ${h}"><img src="${media(file)}" style="width: ${(size[0] / w) * 100}%; left: ${(-x / w) * 100}%; top: ${(-y / h) * 100}%"></div>`;
const wide = [1600, 1000];
const editorWindow = [230, 56, 1140, 850];
const marks = (extra = '') => `<div class="sc-marks ${extra}">${stage}</div>`;
const strip = (file) => `<div class="sc-strip"><img src="${media(file)}"></div>`;
const kbd = (keys) => keys.map((k) => `<kbd class="key">${k}</kbd>`).join('');
const code = (lines) => `<div class="sc-code">${lines.map((l) => `<p>${l}</p>`).join('')}</div>`;

// What each guide page's card shows beside its title: the page's own screenshot where the guide has one, otherwise a drawing of
// what the page is about. Anything not listed shows the hero's last frame.
const shortcuts = [['⌘⇧4', 'Area'], ['⌘⇧3', 'Whole screen'], ['⌘⇧5', 'Record'], ['A', 'Arrow'], ['B', 'Blur'], ['T', 'Text'], ['H', 'Highlight'], ['⌘C', 'Copy'], ['⌘Z', 'Undo']];
const languages = ['English', 'Deutsch', 'Français', 'Español', 'Italiano', 'Português', '日本語', '한국어', '简体中文'];
const scenes = {
  'get-started': shot('welcome.png', [1240, 940], [190, 150, 860, 600]),
  'take-a-screenshot': { stage: '.selection, .size, .cursor { opacity: 1; } .marks, .quick, .copied { display: none; }' },
  'quick-access': `<img class="sc-plain" src="${media('quick-access.png')}">`,
  'record-your-screen': strip('recording-controls.png'),
  'annotate-a-screenshot': marks('only'),
  'crop-and-arrange': shot('editor-crop.png', wide, editorWindow),
  'style-a-screenshot': shot('editor-style.png', wide, editorWindow),
  'combine-images': shot('editor-combine.png', wide, editorWindow),
  'edit-a-recording': shot('video-editor.png', wide, [350, 670, 900, 285]),
  'animate-and-annotate-a-recording': shot('video-editor.png', wide, [350, 12, 900, 640]),
  'export-a-video-or-gif': `<div style="width: 66%">${shot('video-editor.png', wide, [350, 12, 900, 940])}</div>`,
  'find-your-captures': shot('gallery.png', wide, [170, 56, 1260, 850]),
  'keyboard-shortcuts': `<div class="sc-keys">${shortcuts.map(([k, l], i) => `<p style="--fill: var(--${['yellow', 'pink', 'mint'][i % 3]})">${kbd([k])}<span>${l}</span></p>`).join('')}</div>`,
  'automation-reference': code(['<b>open</b> "shot://capture-area"', '<b>open</b> "shot://capture-timer?seconds=5"', '<b>open</b> "shot://copy-text"', '<b>open</b> "shot://gallery"']),
  settings: shot('settings.png', wide, [170, 56, 1260, 850]),
  languages: `<div class="sc-langs">${languages.map((l, i) => `<span style="--fill: var(--${['yellow', 'pink', 'sky', 'mint', 'violet', 'orange'][i % 6]})">${l}</span>`).join('')}</div>`,
  updates: `<div class="sc-list"><p><span>Check for updates</span><i class="on"></i></p><p><span>Ask me before going online</span><i class="on"></i></p><p class="btn"><b>Check Now</b></p></div>`,
  privacy: `<div class="sc-list"><p class="no"><b>✕</b><span>No account</span></p><p class="no"><b>✕</b><span>No cloud</span></p><p class="no"><b>✕</b><span>No analytics</span></p><p class="fine">Goes online only to check for updates.</p></div>`,
  troubleshooting: `<div class="sc-list"><p class="q"><b>?</b><span>Captures fail after I turned on Screen Recording</span></p><p class="q"><b>?</b><span>Microphone says NOT ASKED</span></p><p class="q"><b>?</b><span>⌘⇧4 still opens the macOS tool</span></p></div>`,
  'removing-shot': code(['<b>$</b> brew uninstall --zap shot']),
};

const page = ({ chip, chipColor, headline, size, keys, scene }) => `<!doctype html>
<link rel="stylesheet" href="${url('../src/styles/global.css')}">
<style>
  ${stageStyle}
  ${scene?.stage ?? ''}
  ${windowStyle}
  body { width: 1200px; height: 630px; min-height: 0; overflow: hidden; position: relative; }
  .brand { position: absolute; left: 56px; top: 44px; }
  .brand img { width: 44px; height: 44px; }
  .brand { font-size: 30px; }
  .intro { position: absolute; left: 56px; top: 150px; width: 500px; display: grid; gap: 22px; justify-items: start; }
  .intro .chip { font-size: 17px; padding: 4px 14px; }
  h1 { font-size: ${size}px; line-height: 1.02; letter-spacing: -0.03em; }
  h1 .keys { display: flex; margin-top: 0.14em; gap: 0.12em; }
  h1 .key { font-size: 0.62em; padding: 0.05em 0.3em; border-width: 3px; border-radius: 12px; box-shadow: 4px 4px 0 var(--line); }
  .lede { margin: 0; font: 500 26px/1.35 var(--font); max-width: 17em; }
  .window { position: absolute; left: 590px; top: 50%; width: 560px; translate: 0 -50%; }
  .sc { aspect-ratio: 16 / 10; display: grid; place-items: center; overflow: hidden; }
  .sc-crop { position: relative; width: 100%; overflow: hidden; } .sc-crop img { position: absolute; max-width: none; height: auto; }
  .sc:has(.sc-crop) { aspect-ratio: auto; display: block; } .sc-plain { width: 100%; } .sc-marks.only .quick, .sc-marks.only .copied { display: none; } .sc-marks { width: 100%; overflow: hidden; }
  .sc-strip { padding: 0 24px; } .sc-strip img { border: 2px solid var(--line); border-radius: 8px; box-shadow: 3px 3px 0 var(--line); }
  .sc-code { width: 86%; padding: 26px 28px; background: #12121a; color: #f6f4ef; border: 3px solid var(--line); border-radius: 12px; box-shadow: 4px 4px 0 var(--line); font: 600 18px/1.8 var(--mono); }
  .sc-code p { margin: 0; white-space: nowrap; } .sc-code b { color: var(--yellow); }
  .sc-keys { width: 90%; display: grid; grid-template-columns: repeat(3, 1fr); gap: 22px 14px; }
  .sc-keys p { margin: 0; display: grid; gap: 8px; justify-items: start; font: 800 20px/1.2 var(--font); color: var(--on-accent); }
  .sc-keys kbd { font-size: 30px; background: var(--fill); color: var(--on-accent); border-color: #000; box-shadow: 3px 3px 0 #000; }
  .sc-langs { width: 88%; display: flex; flex-wrap: wrap; gap: 14px; justify-content: center; }
  .sc-langs span { padding: 8px 20px; font: 800 28px/1.2 var(--font); color: var(--on-accent); background: var(--fill); border: 3px solid var(--line); border-radius: 12px; box-shadow: 3px 3px 0 var(--line); }
  .sc-list { width: 82%; display: grid; gap: 12px; }
  .sc-list p { margin: 0; display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 16px 20px; font: 800 24px/1.25 var(--font); background: var(--paper); color: var(--ink); border: 3px solid var(--line); border-radius: 12px; box-shadow: 4px 4px 0 var(--line); }
  .sc-list .no, .sc-list .q { justify-content: flex-start; } .sc-list p b { flex: none; width: 36px; height: 36px; display: grid; place-items: center; font-size: 20px; color: var(--on-accent); background: var(--red); border: 3px solid var(--line); border-radius: 50%; }
  .sc-list .q b { background: var(--yellow); } .sc-list .q { font-size: 21px; }
  .sc-list .fine { display: block; font-size: 18px; font-weight: 600; background: none; border: 0; box-shadow: none; color: var(--ink); padding: 0 4px; }
  .sc-list i { flex: none; width: 56px; height: 32px; border: 3px solid var(--line); border-radius: 99px; background: var(--well); position: relative; }
  .sc-list i.on { background: var(--mint); } .sc-list i::after { content: ""; position: absolute; top: 3px; left: 3px; width: 20px; height: 20px; border-radius: 50%; background: var(--paper); border: 2px solid var(--line); } .sc-list i.on::after { left: 27px; }
  .sc-list .btn b { width: auto; height: auto; background: none; border: 0; border-radius: 0; font-size: 24px; } .sc-list .btn { justify-content: center; background: var(--yellow); color: var(--on-accent); }
</style>
<div class="backdrop"><div class="blob pink"></div><div class="blob yellow"></div><div class="blob mint"></div><div class="blob sky"></div></div>
<div class="brand"><img src="${url('../public/icon-256.png')}"><span>Shot</span></div>
<div class="intro">
  <span class="chip" style="--chip: var(--${chipColor})">${chip}</span>
  <h1>${headline}${keys ? '<span class="keys"><kbd class="key">⌘</kbd><kbd class="key">⇧</kbd><kbd class="key">4</kbd></span>' : ''}</h1>
  ${keys ? '<p class="lede">A screenshot app that lives in your menu bar.</p>' : ''}
</div>
<figure class="window card" style="--tint: var(--${chipColor})">
  <div class="titlebar"><span class="lights"><i></i><i></i><i></i></span></div>
  <div class="pane">${typeof scene === 'string' ? `<div class="sc">${scene}</div>` : stage}</div>
</figure>`;

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

render(page({ chip: 'Free and open source', chipColor: 'yellow', headline: 'A better', size: 100, keys: true }), '../public/og.png');

// Cards of pages that no longer exist would otherwise stay behind.
rmSync(new URL('../public/og/', import.meta.url), { recursive: true, force: true });
mkdirSync(new URL('../public/og/', import.meta.url), { recursive: true });
for (const { slug, title, group } of readGuide()) {
  const longest = Math.max(...title.split(' ').map((w) => w.length));
  const size = title.length > 40 ? 52 : title.length > 22 || longest > 12 ? 64 : 84;
  render(page({ chip: `User guide · ${group}`, chipColor: groups.find((g) => g.name === group).color, headline: title, size, scene: scenes[slug] }), `../public/og/${slug}.png`);
}
