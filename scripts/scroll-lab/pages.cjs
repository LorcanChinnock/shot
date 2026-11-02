// Made-up pages for the scroll lab. Each is plain HTML that looks like something people really scroll. `.pin` elements
// are sticky or fixed on screen and sit in the normal flow when body has class `flat`, which is how the truth image is
// drawn: the picture a perfect stitcher would give.
const words = 'ticket order refund mug shipped customer support balance card address delivery invoice note reply assign priority open closed pending escalated quarter budget roadmap launch review design ship migrate cache latency queue invoice region account policy renew trial upgrade seat export import report weekly monthly summary draft'.split(' ');
function rng(seed) { let s = seed >>> 0; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); }
function sentence(r, n) { const w = []; for (let i = 0; i < n; i++) w.push(words[Math.floor(r() * words.length)]); const t = w.join(' '); return t[0].toUpperCase() + t.slice(1) + '.'; }
function para(r, sentences = 4) { return Array.from({ length: sentences }, () => sentence(r, 8 + Math.floor(r() * 10))).join(' '); }

const base = `*{box-sizing:border-box}body{margin:0;font:15px/1.55 -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;color:#1d1d1f;background:#fff}
body.flat .pin{position:static!important;backdrop-filter:none!important}body.flat .fixedonly{display:none!important}`;

const pages = {
  // A blog post with an opaque sticky bar.
  article(translucent = false) {
    const r = rng(7); let body = '';
    for (let i = 0; i < 26; i++) {
      body += `<h2>${sentence(r, 4)}</h2><p>${para(r, 5)}</p>`;
      if (i % 4 === 1) body += `<pre>${Array.from({ length: 6 }, (_, k) => `const ${words[(i + k) % words.length]}${k} = load("${words[(i * 3 + k) % words.length]}");`).join('\n')}</pre>`;
      if (i % 5 === 3) body += `<div class="img" style="background:linear-gradient(${i * 37}deg,hsl(${i * 40},70%,70%),hsl(${i * 40 + 80},70%,55%))"></div><p class="cap">Figure ${i}: ${sentence(r, 6)}</p>`;
      if (i % 6 === 4) body += `<blockquote>${para(r, 2)}</blockquote>`;
    }
    return `<style>${base}.bar{position:sticky;top:0;height:56px;display:flex;align-items:center;padding:0 24px;font-weight:600;border-bottom:1px solid #ccc;background:${translucent ? 'rgba(255,255,255,.72)' : '#f4f6fb'};${translucent ? 'backdrop-filter:blur(14px);' : ''}z-index:5}
main{max-width:620px;margin:0 auto;padding:16px 24px}h2{margin:28px 0 6px}pre{background:#161b22;color:#c9d1d9;padding:12px;border-radius:8px;font:12px/1.5 Menlo,monospace;overflow:hidden}.img{height:170px;border-radius:10px;margin:14px 0 4px}.cap{color:#666;font-size:12px}blockquote{border-left:4px solid #6c7ae0;margin:16px 0;padding:2px 14px;color:#444}</style>
<div class="bar pin">Field Notes — ${translucent ? 'translucent' : 'opaque'} bar</div><main>${body}</main><div class="pin" style="position:sticky;bottom:0;height:40px;background:#fff6e5;border-top:1px solid #d9c9a3;display:flex;align-items:center;padding:0 24px;font-size:13px">Footer: 2026 Field Notes</div>`;
  },
  // A spreadsheet with a pinned header row and first column, and numbers that repeat.
  table() {
    const r = rng(3); let rows = '';
    for (let i = 1; i <= 300; i++) rows += `<tr><th class="pin">Row ${i}</th>${Array.from({ length: 14 }, (_, c) => `<td>${(Math.floor(r() * 90) + 10) * (c % 3 === 0 ? 100 : 1)}</td>`).join('')}</tr>`;
    return `<style>${base}table{border-collapse:separate;border-spacing:0;font-size:13px}td,th{padding:4px 10px;border-right:1px solid #ddd;border-bottom:1px solid #ddd;white-space:nowrap;min-width:84px;text-align:right}
thead th{position:sticky;top:0;background:#e9edf5;z-index:3;text-align:center}tbody th{position:sticky;left:0;background:#f5f5f5;z-index:2;text-align:left}thead th:first-child{left:0;z-index:4}</style>
<table><thead><tr><th class="pin">Sheet</th>${Array.from({ length: 14 }, (_, c) => `<th class="pin">Col ${String.fromCharCode(65 + c)}</th>`).join('')}</tr></thead><tbody>${rows}</tbody></table>`;
  },
  // A chat thread with short repeated messages, day chips and a pinned composer.
  chat() {
    const r = rng(11); let body = '';
    for (let i = 0; i < 90; i++) {
      if (i % 15 === 0) body += `<div class="day">Day ${i / 15 + 1}</div>`;
      const mine = r() < 0.45; const short = r() < 0.3;
      body += `<div class="m ${mine ? 'me' : ''}"><div class="b">${short ? ['ok', 'thanks!', 'yes', 'on it', 'sounds good'][Math.floor(r() * 5)] : para(r, 1 + Math.floor(r() * 2))}</div></div>`;
    }
    return `<style>${base}body{background:#f2f2f7}.m{display:flex;padding:3px 14px}.m.me{justify-content:flex-end}.b{max-width:70%;padding:8px 12px;border-radius:16px;background:#fff}.me .b{background:#2f7bf6;color:#fff}
.day{text-align:center;color:#888;font-size:12px;padding:14px}.comp{position:sticky;bottom:0;height:52px;background:#fff;border-top:1px solid #ccc;padding:12px 16px;color:#999}.top{position:sticky;top:0;height:48px;background:#fff;border-bottom:1px solid #ccc;font-weight:600;padding:13px 16px;z-index:5}</style>
<div class="top pin">Mug Co. team chat</div>${body}<div class="comp pin">Message…</div>`;
  },
  // Big flat blocks and few words: little to line up on.
  feed() {
    const r = rng(5); let cards = '';
    for (let i = 0; i < 18; i++) cards += `<section style="margin:20px auto;max-width:560px;border-radius:14px;overflow:hidden;box-shadow:0 1px 6px #0003"><div style="height:${160 + (i % 3) * 60}px;background:hsl(${i * 47},60%,${60 + (i % 3) * 8}%)"></div><div style="padding:14px 18px"><b>${sentence(r, 3)}</b><div style="color:#777">${sentence(r, 6)}</div></div></section>`;
    return `<style>${base}body{background:#eceff3}</style>${cards}`;
  },
  // Code with line numbers: every line looks alike.
  code() {
    const r = rng(9); let lines = '';
    for (let i = 1; i <= 420; i++) {
      const ind = '  '.repeat(Math.floor(r() * 3));
      const t = r() < 0.12 ? '' : r() < 0.5 ? `${ind}if (${words[Math.floor(r() * words.length)]} > ${Math.floor(r() * 9)}) {` : r() < 0.7 ? `${ind}}` : `${ind}${words[Math.floor(r() * words.length)]}(${i % 7});`;
      lines += `<div class="l"><span>${i}</span>${t.replace(/ /g, '&nbsp;')}</div>`;
    }
    return `<style>${base}body{background:#0d1117;color:#c9d1d9;font:12.5px/20px Menlo,monospace}.l span{display:inline-block;width:48px;color:#6e7681;text-align:right;margin-right:14px}.tab{position:sticky;top:0;height:34px;background:#161b22;border-bottom:1px solid #30363d;padding:7px 16px;z-index:5}</style><div class="tab pin">engine.swift</div>${lines}`;
  },
  // Settings: a pinned sidebar beside a list of near-identical rows.
  settings() {
    const r = rng(13); let rows = '';
    for (let i = 0; i < 70; i++) rows += `<div class="row"><div><b>${sentence(r, 3).replace('.', '')}</b><div class="sub">${sentence(r, 7)}</div></div><div class="sw ${r() < 0.5 ? 'on' : ''}"></div></div>`;
    return `<style>${base}body{display:flex;background:#f6f6f6}.side{position:sticky;top:0;align-self:flex-start;height:100vh;width:180px;background:#e8e8ee;padding:16px;border-right:1px solid #ccc}.side div{padding:6px 0}
.list{flex:1;padding:12px 24px}.row{display:flex;justify-content:space-between;align-items:center;background:#fff;border:1px solid #ddd;padding:12px 16px;margin-bottom:-1px}.sub{color:#777;font-size:12px}.sw{width:34px;height:20px;border-radius:10px;background:#ccc}.sw.on{background:#34c759}</style>
<div class="side pin"><b>Settings</b><div>General</div><div>Capture</div><div>Shortcuts</div><div>Recording</div><div>About</div></div><div class="list">${rows}</div>`;
  },
  // Article with a floating button, a cookie banner and a macOS-style overlay scroll bar.
  floaters() {
    const inner = pages.article(false).replace(/<div class="bar pin">.*?<\/div>/, '');
    return inner + `<style>.fab{position:fixed;right:28px;bottom:70px;width:48px;height:48px;border-radius:24px;background:#e0338e;color:#fff;font:700 26px/48px sans-serif;text-align:center;box-shadow:0 2px 8px #0005;z-index:9}
.cookie{position:fixed;left:16px;bottom:12px;width:300px;background:#222;color:#fff;border-radius:10px;padding:10px 14px;font-size:12px;z-index:9}.sb{position:fixed;right:2px;width:7px;border-radius:4px;background:#0006;z-index:10}</style>
<div class="fab pin fixedonly">+</div><div class="cookie pin fixedonly">We use cookies. Accept all?</div><div class="sb fixedonly" id="sb"></div>
<script>const sb=document.getElementById('sb');function f(){const h=innerHeight,H=document.documentElement.scrollHeight;sb.style.height=Math.max(30,h*h/H)+'px';sb.style.top=(scrollY/(H-h))*(h-parseFloat(sb.style.height))+'px'}addEventListener('scroll',f);f()</script>`;
  },
  // A wide timeline for sideways scrolling: pinned labels at the left.
  timeline() {
    const r = rng(17); let rows = '';
    for (let i = 0; i < 18; i++) {
      let cells = ''; for (let d = 0; d < 60; d++) cells += `<div class="c" style="${r() < 0.35 ? `background:hsl(${(i * 31 + Math.floor(d / 6) * 7) % 360},60%,75%)` : ''}">${r() < 0.3 ? Math.floor(r() * 99) : ''}</div>`;
      rows += `<div class="r"><div class="lab pin">${sentence(r, 2).replace('.', '')}</div>${cells}</div>`;
    }
    let head = ''; for (let d = 0; d < 60; d++) head += `<div class="c h">W${d + 1}</div>`;
    return `<style>${base}.r{display:flex;width:max-content}.c{width:70px;height:46px;border-right:1px solid #e0e0e0;border-bottom:1px solid #e0e0e0;padding:12px 6px;font-size:12px}.c.h{height:34px;background:#eef;font-weight:600;position:sticky;top:0;z-index:3}
.lab{position:sticky;left:0;width:150px;height:46px;background:#f7f7f7;border-right:1px solid #bbb;border-bottom:1px solid #e0e0e0;padding:12px;font-weight:600;z-index:4;flex:none}</style><div class="r"><div class="lab pin" style="height:34px;background:#dde">Task</div>${head}</div>${rows}`;
  },
  // A long list of rows that look alike: the same sentence with a different number, each in its own pastel tint, under an
  // opaque sticky bar. Seen live in Chrome (#1030): the stitched image repeated and skipped rows.
  list() {
    let rows = '';
    for (let i = 1; i <= 300; i++) rows += `<p class="row" style="background:hsl(${(i * 37) % 360} 60% 90%)"><b>Row ${String(i).padStart(3, '0')}</b> — the quick brown fox jumps over the lazy dog, line ${i}.</p>`;
    return `<style>${base}.bar{position:sticky;top:0;height:64px;display:flex;align-items:center;padding:0 24px;font-weight:700;border-bottom:1px solid #ccc;background:#fff;z-index:5}.row{margin:0;padding:18px 24px;font-family:Times,serif;font-size:16px}</style>
<div class="bar pin">Sticky header</div>${rows}`;
  },
  // The rows of a scrolling pane (#1030): near-identical lines in their own tints, about 50 points apart, with nothing
  // pinned. A move of a row or so lines up with a neighbour.
  rows() {
    let rows = '';
    for (let i = 1; i <= 200; i++) rows += `<p class="row" style="background:hsl(${(i * 37) % 360} 60% 90%)"><b>Item ${i}</b> — pane content line ${i}, rows that look alike.</p>`;
    return `<style>${base}.row{margin:0;padding:13px 20px}</style>${rows}`;
  },
};
module.exports = { pages };
