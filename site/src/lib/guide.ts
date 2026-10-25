import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createMarkdownProcessor } from '@astrojs/markdown-remark';
import { SKIP, visit } from 'unist-util-visit';
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

/** A PNG's or GIF's size in pixels, read from its header, so the page can save the space before the image loads. */
function sizeOf(file: string): [number, number] | undefined {
  const bytes = readFileSync(resolve(process.cwd(), '../docs/media', file));
  if (bytes.toString('ascii', 1, 4) === 'PNG') return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
  if (bytes.toString('ascii', 0, 3) === 'GIF') return [bytes.readUInt16LE(6), bytes.readUInt16LE(8)];
}

/** Points a guide screenshot at its hashed URL and sizes it. All but a page's first image load only as they near the window. */
function mediaImage(match: string, file: string, rest: string, first: boolean) {
  const url = mediaUrls.get(file);
  if (!url) return match;
  // An explicit width in the Markdown (a 2x screenshot shown at half size) keeps its own width and sets the height to match.
  const size = sizeOf(file);
  const width = /\swidth="(\d+)"/.exec(rest)?.[1];
  const dims = !size ? '' : width ? ` height="${Math.round((size[1] * Number(width)) / size[0])}"` : ` width="${size[0]}" height="${size[1]}"`;
  return `<img src="${url}"${rest}${dims}${first ? '' : ' loading="lazy"'} decoding="async"`;
}

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

/** Wraps each code block with a Copy button. The button starts hidden, since it needs the script in docs/[page].astro. */
function rehypeCodeCopy() {
  return (tree: any) =>
    visit(tree, 'element', (node: any, index, parent: any) => {
      if (node.tagName !== 'pre' || parent?.properties?.className?.includes('code')) return;
      const button = {
        type: 'element',
        tagName: 'button',
        properties: { type: 'button', className: ['copy-code', 'button', 'small', 'white'], hidden: true, dataPagefindIgnore: '' },
        children: [{ type: 'text', value: 'Copy' }],
      };
      parent.children[index!] = { type: 'element', tagName: 'div', properties: { className: ['code'] }, children: [node, button] };
      return [SKIP, index! + 1];
    });
}

const processor = await createMarkdownProcessor({
  rehypePlugins: [rehypeRepoLinks, rehypeCallouts, rehypeCodeCopy],
  shikiConfig: { themes: { light: 'github-light', dark: 'github-dark' } },
});

const rendered = await Promise.all(
  readGuide().map(async (file) => {
    const { code, metadata } = await processor.render(file.markdown);
    return { ...file, html: code, headings: metadata.headings as GuidePage['headings'] };
  }),
);

/** Where each page and heading lives, so a guide page can link to another page's section with just its id, as `(#id)`. */
const anchors: Record<string, string> = {};
for (const { slug } of rendered) anchors[slug] = `/docs/${slug}/`;
for (const { slug, headings } of rendered) {
  for (const h of headings) anchors[h.slug] ??= `/docs/${slug}/#${h.slug}`;
}

/** A guide page, with its links to other sections and its screenshots pointed at the site. */
export const pages: GuidePage[] = rendered.map(({ slug, title, summary, group, headings, html }) => {
  let images = 0;
  return {
    slug,
    title,
    summary,
    group,
    headings,
    html: html
      .replace(/href="#([^"]+)"/g, (match, id) => (anchors[id] ? `href="${anchors[id]}"` : match))
      .replace(/<img src="(?:\.\.\/)+docs\/media\/([^"]+)"([^>]*?)(?=\s*\/?>)/g, (match, file, rest) => mediaImage(match, file, rest, images++ === 0)),
  };
});
