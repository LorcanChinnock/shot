// Generates the favicons and the 1200×630 social card from docs/icon.png. Run after the icon changes: npm run icons
import sharp from 'sharp';

const icon = new URL('../../docs/icon.png', import.meta.url).pathname;
const out = (name) => new URL(`../public/${name}`, import.meta.url).pathname;

await sharp(icon).resize(64).toFile(out('favicon.png'));
await sharp(icon).resize(64).toFile(out('icon-64.png'));
await sharp(icon).resize(256).toFile(out('icon-256.png'));
await sharp(icon).resize(180).flatten({ background: '#ffd43b' }).toFile(out('apple-touch-icon.png'));

const dots = Array.from({ length: 34 * 67 }, (_, i) => {
  const x = 9 + (i % 67) * 18, y = 9 + Math.floor(i / 67) * 18;
  return `<circle cx="${x}" cy="${y}" r="1.1" fill="#12121a" fill-opacity="0.12"/>`;
}).join('');
const card = `
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630">
  <defs>
    <radialGradient id="p"><stop offset="0" stop-color="#ff7ab6" stop-opacity=".6"/><stop offset="1" stop-color="#ff7ab6" stop-opacity="0"/></radialGradient>
    <radialGradient id="s"><stop offset="0" stop-color="#6fc3ff" stop-opacity=".6"/><stop offset="1" stop-color="#6fc3ff" stop-opacity="0"/></radialGradient>
    <radialGradient id="m"><stop offset="0" stop-color="#4fe3b5" stop-opacity=".5"/><stop offset="1" stop-color="#4fe3b5" stop-opacity="0"/></radialGradient>
  </defs>
  <rect width="1200" height="630" fill="#ffd43b"/>
  <circle cx="80" cy="40" r="420" fill="url(#p)"/>
  <circle cx="1150" cy="620" r="460" fill="url(#s)"/>
  <circle cx="120" cy="640" r="300" fill="url(#m)"/>
  ${dots}
  <rect x="64" y="64" width="1072" height="502" rx="24" fill="#12121a"/>
  <rect x="56" y="56" width="1072" height="502" rx="24" fill="#fffdf7" stroke="#12121a" stroke-width="5"/>
  <text x="380" y="250" font-family="Inter, Helvetica, Arial, sans-serif" font-weight="900" font-size="112" fill="#12121a" letter-spacing="-4">Shot</text>
  <text x="384" y="330" font-family="Inter, Helvetica, Arial, sans-serif" font-weight="700" font-size="38" fill="#12121a">A screenshot app that sits</text>
  <text x="384" y="380" font-family="Inter, Helvetica, Arial, sans-serif" font-weight="700" font-size="38" fill="#12121a">in your Mac's menu bar.</text>
  <text x="384" y="470" font-family="Inter, Helvetica, Arial, sans-serif" font-weight="800" font-size="28" fill="#12121a" fill-opacity=".6">Free and open source</text>
</svg>`;
await sharp({ create: { width: 1200, height: 630, channels: 4, background: '#ffd43b' } })
  .composite([
    { input: Buffer.from(card) },
    { input: await sharp(icon).resize(280).toBuffer(), left: 80, top: 150 },
  ])
  .png({ compressionLevel: 9 })
  .toFile(out('og.png'));
