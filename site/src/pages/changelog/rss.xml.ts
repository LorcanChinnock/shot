import type { APIRoute } from 'astro';
import { readChangelog, releaseURL } from '../../lib/changelog';

const escape = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** One feed item per release in CHANGELOG.md, with its changes as the text. */
export const GET: APIRoute = async ({ site }) => {
  const items = (await readChangelog()).slice(0, 30).map(({ version, date, entries, summary }) => {
    const link = releaseURL(version);
    const text = entries.length ? entries.map((e) => `• ${e.scope ? `${e.scope}: ` : ''}${e.text}`).join('\n') : (summary ?? '');
    return `    <item>
      <title>Shot ${escape(version)}</title>
      <link>${link}</link>
      <guid isPermaLink="true">${link}</guid>
      <pubDate>${new Date(`${date}T12:00:00Z`).toUTCString()}</pubDate>
      <description>${escape(text)}</description>
    </item>`;
  });
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
