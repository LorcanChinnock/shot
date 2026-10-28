// Generates the favicons from docs/icon.png. Run after the icon changes: npm run icons (the social card is npm run og)
import sharp from 'sharp';

const icon = new URL('../../docs/icon.png', import.meta.url).pathname;
const out = (name) => new URL(`../public/${name}`, import.meta.url).pathname;

await sharp(icon).resize(64).toFile(out('favicon.png'));
await sharp(icon).resize(64).toFile(out('icon-64.png'));
await sharp(icon).resize(256).toFile(out('icon-256.png'));
await sharp(icon).resize(180).flatten({ background: '#ffd43b' }).toFile(out('apple-touch-icon.png'));
