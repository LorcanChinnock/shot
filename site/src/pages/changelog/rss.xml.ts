import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import type { APIRoute } from 'astro';

const repo = 'https://github.com/LorcanChinnock/shot';
const escape = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** One feed item per release in CHANGELOG.md, with its changes as the text. */
export const GET: APIRoute = async ({ site }) => {
  // From the site folder, which builds run in: once bundled, import.meta.url points inside dist/.
  const changelog = await readFile(resolve(process.cwd(), '../CHANGELOG.md'), 'utf8');
  const items = changelog
    .split(/^## /m)
    .slice(1)
    .flatMap((section) => {
      const head = /^\[([^\]]+)\]\([^)]*\) \((\d{4}-\d{2}-\d{2})\)/.exec(section) ?? /^\[?([^\]\s]+)\]? \((\d{4}-\d{2}-\d{2})\)/.exec(section);
      if (!head) return [];
      const [, version, date] = head;
      const changes = section
        .split('\n')
        .filter((line) => line.startsWith('* '))
        .map((line) => line.slice(2).replace(/\s*\(\[#\d+\]\([^)]*\)\)/g, '').replace(/\s*\(\[[0-9a-f]+\]\([^)]*\)\)/g, '').replace(/\[([^\]]+)\]\([^)]*\)/g, '$1').replace(/\*\*/g, ''));
      const link = `${repo}/releases/tag/v${version}`;
      return [`    <item>
      <title>Shot ${escape(version)}</title>
      <link>${link}</link>
      <guid isPermaLink="true">${link}</guid>
      <pubDate>${new Date(`${date}T12:00:00Z`).toUTCString()}</pubDate>
      <description>${escape(changes.map((change) => `• ${change}`).join('\n'))}</description>
    </item>`];
    })
    .slice(0, 30);
  return new Response(
    `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Shot releases</title>
    <link>${new URL('/changelog/', site)}</link>
    <description>What changed in each Shot release.</description>
    <language>en</language>
${items.join('\n')}
  </channel>
</rss>
`,
    { headers: { 'Content-Type': 'application/rss+xml; charset=utf-8' } },
  );
};
