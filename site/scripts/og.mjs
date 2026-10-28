// Renders the 1200×630 social cards in the site's own look: public/og.png for the site, and public/og/<slug>.png for each guide page.
// The cards load src/styles/global.css and reuse the hero's markup and styles from HeroStage.astro (its last frame, which is what
// reduced motion shows), so they follow the site. Fonts are the system's, as on the site. Run after the brand, the hero or a
// guide page's title changes: npm run og
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
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

const page = ({ chip, chipColor, headline, size, keys }) => `<!doctype html>
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
  h1 .key { font-size: 0.62em; padding: 0.05em 0.3em; border-width: 3px; border-radius: 12px; box-shadow: 4px 4px 0 var(--line); }
  .lede { margin: 0; font: 500 26px/1.35 var(--font); max-width: 17em; }
  .window { position: absolute; left: 590px; top: 118px; width: 560px; }
</style>
<div class="backdrop"><div class="blob pink"></div><div class="blob yellow"></div><div class="blob mint"></div><div class="blob sky"></div></div>
<div class="brand"><img src="${url('../public/icon-256.png')}"><span>Shot<sup>beta</sup></span></div>
<div class="intro">
  <span class="chip" style="--chip: var(--${chipColor})">${chip}</span>
  <h1>${headline}${keys ? '<span class="keys"><kbd class="key">⌘</kbd><kbd class="key">⇧</kbd><kbd class="key">4</kbd></span>' : ''}</h1>
  ${keys ? '<p class="lede">A screenshot app that lives in your menu bar.</p>' : ''}
</div>
<figure class="window card" style="--tint: var(--yellow)">
  <div class="titlebar"><span class="lights"><i></i><i></i><i></i></span></div>
  <div class="pane">${stage}</div>
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

mkdirSync(new URL('../public/og/', import.meta.url), { recursive: true });
for (const { slug, title, group } of readGuide()) {
  const size = title.length > 40 ? 52 : title.length > 22 ? 64 : 84;
  render(page({ chip: `User guide · ${group}`, chipColor: groups.find((g) => g.name === group).color, headline: title, size }), `../public/og/${slug}.png`);
}
