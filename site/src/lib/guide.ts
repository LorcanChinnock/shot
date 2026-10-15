import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createMarkdownProcessor } from '@astrojs/markdown-remark';
import { rehypeRepoLinks } from './rehype.ts';

export interface GuidePage {
  slug: string;
  title: string;
  html: string;
  headings: { depth: number; slug: string; text: string }[];
}

// One file per page, in file name order; each starts with its "# " title.
const dir = resolve(process.cwd(), 'src/guide');
const files = readdirSync(dir).filter((name) => name.endsWith('.md')).sort();

// Screenshots sit in docs/media, beside the README's; Astro hashes them into /_astro/ and gives their URLs here.
const media = import.meta.glob<string>('../../../docs/media/*.{png,jpg,gif}', { query: '?url', import: 'default', eager: true });
const mediaUrls = new Map(Object.entries(media).map(([path, url]) => [path.split('/').pop()!, url]));

function sections() {
  return files.map((name) => {
    const text = readFileSync(resolve(dir, name), 'utf8');
    const title = /^# (.*)$/m.exec(text)?.[1];
    if (!title) throw new Error(`src/guide/${name} has no "# " title`);
    return { title, lines: text.split('\n') };
  });
}

const processor = await createMarkdownProcessor({
  rehypePlugins: [rehypeRepoLinks],
  shikiConfig: { theme: 'github-light' },
});

const rendered = await Promise.all(
  sections().map(async ({ title, lines }) => {
    const { code, metadata } = await processor.render(lines.join('\n'));
    return { title, html: code, headings: metadata.headings as GuidePage['headings'] };
  }),
);

const slugOf = (title: string) => title.toLowerCase().replace(/[^a-z0-9 -]/g, '').trim().replace(/ +/g, '-');

/** Where each heading id of the old single-page guide lives now, for links between pages and for old /docs/#… links. */
export const anchors: Record<string, string> = {};
for (const { title, headings } of rendered) {
  for (const h of headings) anchors[h.slug] ??= `/docs/${slugOf(title)}/${h.depth === 1 ? '' : `#${h.slug}`}`;
}

/** A guide page, with its links to other sections and its screenshots pointed at the site. */
export const pages: GuidePage[] = rendered.map(({ title, html, headings }) => ({
  slug: slugOf(title),
  title,
  headings,
  html: html
    .replace(/href="#([^"]+)"/g, (match, id) => (anchors[id] ? `href="${anchors[id]}"` : match))
    .replace(/src="(?:\.\.\/)+docs\/media\/([^"]+)"/g, (match, file) => (mediaUrls.has(file) ? `src="${mediaUrls.get(file)}"` : match)),
}));
