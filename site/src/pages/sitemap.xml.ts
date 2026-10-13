import type { APIRoute } from 'astro';
import { pages as guide } from '../lib/guide';

const pages = ['/', '/docs/', ...guide.map((page) => `/docs/${page.slug}/`), '/changelog/', '/privacy/'];

export const GET: APIRoute = ({ site }) => {
  const urls = pages.map((path) => `  <url><loc>${new URL(path, site)}</loc></url>`).join('\n');
  return new Response(
    `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`,
    { headers: { 'Content-Type': 'application/xml' } },
  );
};
