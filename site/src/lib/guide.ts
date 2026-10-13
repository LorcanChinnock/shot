import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createMarkdownProcessor } from '@astrojs/markdown-remark';
import { rehypeRepoLinks } from './rehype.ts';

export interface GuidePage {
  slug: string;
  title: string;
  html: string;
  headings: { depth: number; slug: string; text: string }[];
}

// The build runs from the site folder, and the guide's source stays in docs/ so it changes in the same PR as the feature.
const source = readFileSync(resolve(process.cwd(), '../docs/usage.md'), 'utf8');

// Screenshots sit in docs/media; Astro hashes them into /_astro/ and gives their URLs here.
const media = import.meta.glob<string>('../../../docs/media/*.{png,jpg,gif}', { query: '?url', import: 'default', eager: true });
const mediaUrls = new Map(Object.entries(media).map(([path, url]) => [path.split('/').pop()!, url]));

/** Splits the guide at each "## " heading outside a code fence, and moves each heading up a level so it becomes its page's title. */
function sections() {
  const out: { title: string; lines: string[] }[] = [];
  let fenced = false;
  for (const line of source.split('\n')) {
    if (/^\s*(```|~~~)/.test(line)) fenced = !fenced;
    const heading = !fenced && /^(#{1,6}) (.*)$/.exec(line);
    if (heading && heading[1] === '##') out.push({ title: heading[2], lines: [] });
    // Lines before the first "## " (the title and the contents list) are replaced by the start page.
    if (!out.length) continue;
    out.at(-1)!.lines.push(heading ? line.slice(1) : line);
  }
  return out;
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
    .replace(/src="media\/([^"]+)"/g, (match, file) => (mediaUrls.has(file) ? `src="${mediaUrls.get(file)}"` : match)),
}));
