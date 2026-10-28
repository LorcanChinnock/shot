import type { APIRoute } from 'astro';
import { readGuide } from '../lib/guide-files.ts';
import { lastModified } from '../lib/lastmod.ts';
import { latestRelease } from '../lib/release.ts';

export const GET: APIRoute = async ({ site }) => {
  const release = await latestRelease();
  const pages = [
    { path: '/', lastmod: release.date?.slice(0, 10) },
    ...readGuide().map(({ slug, file }) => ({ path: `/docs/${slug}/`, lastmod: lastModified(`src/guide/${file}`) })),
    { path: '/screenshot-apps/', lastmod: lastModified('src/pages/screenshot-apps') },
    { path: '/changelog/', lastmod: lastModified('../CHANGELOG.md') },
    { path: '/privacy/', lastmod: lastModified('src/pages/privacy') },
  ];
  const urls = pages
    .map(({ path, lastmod }) => `  <url><loc>${new URL(path, site)}</loc>${lastmod ? `<lastmod>${lastmod}</lastmod>` : ''}</url>`)
    .join('\n');
  return new Response(
    `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`,
    { headers: { 'Content-Type': 'application/xml' } },
  );
};
