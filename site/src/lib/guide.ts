import { createMarkdownProcessor } from '@astrojs/markdown-remark';
import { visit } from 'unist-util-visit';
import { readGuide } from './guide-files.ts';
import { rehypeRepoLinks } from './rehype.ts';

export { groups } from './guide-files.ts';

export interface GuidePage {
  slug: string;
  title: string;
  /** One line under the title, and on the guide's start page. */
  summary: string;
  /** The part of the guide it's listed under. */
  group: string;
  html: string;
  headings: { depth: number; slug: string; text: string }[];
}

// Screenshots sit in docs/media, beside the README's; Astro hashes them into /_astro/ and gives their URLs here.
const media = import.meta.glob<string>('../../../docs/media/*.{png,jpg,gif}', { query: '?url', import: 'default', eager: true });
const mediaUrls = new Map(Object.entries(media).map(([path, url]) => [path.split('/').pop()!, url]));

const callouts: Record<string, string> = { TIP: 'Tip', NOTE: 'Good to know', WARNING: 'Watch out' };

/** Turns GitHub's alert syntax, a quote starting `[!TIP]`, into a callout box, so it reads the same on GitHub and the site. */
function rehypeCallouts() {
  return (tree: any) =>
    visit(tree, 'element', (node: any) => {
      if (node.tagName !== 'blockquote') return;
      const first = node.children.find((child: any) => child.type === 'element');
      const text = first?.tagName === 'p' && first.children[0];
      const match = text?.type === 'text' && /^\[!(\w+)\]\s*/.exec(text.value);
      if (!match || !callouts[match[1]]) return;
      text.value = text.value.slice(match[0].length);
      node.tagName = 'aside';
      node.properties = { className: ['callout', match[1].toLowerCase()] };
      node.children.unshift({ type: 'element', tagName: 'p', properties: { className: ['callout-label'] }, children: [{ type: 'text', value: callouts[match[1]] }] });
    });
}

const processor = await createMarkdownProcessor({
  rehypePlugins: [rehypeRepoLinks, rehypeCallouts],
  shikiConfig: { theme: 'github-light' },
});

const rendered = await Promise.all(
  readGuide().map(async (file) => {
    const { code, metadata } = await processor.render(file.markdown);
    return { ...file, html: code, headings: metadata.headings as GuidePage['headings'] };
  }),
);

/** Where each heading id lives, for links between pages and for /docs/#… links from when the guide was one page. */
export const anchors: Record<string, string> = {};
for (const { slug, aliases, anchors: moved } of rendered) {
  for (const id of [slug, ...aliases, ...moved]) anchors[id] ??= `/docs/${slug}/`;
}
for (const { slug, headings } of rendered) {
  for (const h of headings) anchors[h.slug] ??= `/docs/${slug}/#${h.slug}`;
}

/** A guide page, with its links to other sections and its screenshots pointed at the site. */
export const pages: GuidePage[] = rendered.map(({ slug, title, summary, group, headings, html }) => ({
  slug,
  title,
  summary,
  group,
  headings,
  html: html
    .replace(/href="#([^"]+)"/g, (match, id) => (anchors[id] ? `href="${anchors[id]}"` : match))
    .replace(/src="(?:\.\.\/)+docs\/media\/([^"]+)"/g, (match, file) => (mediaUrls.has(file) ? `src="${mediaUrls.get(file)}"` : match)),
}));
