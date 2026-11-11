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
  /** The Markdown file's name in src/guide/, for the page's "Edit this page" link. */
  file: string;
  /** Roughly how long the page takes to read, in whole minutes. */
  minutes: number;
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
// The Note's "i" and the Warning's "!", drawn in the callout's own colour. The Tip is a sticky note and needs none.
const icons: Record<string, string> = {
  NOTE: 'M12 11v6M12 7.5v.01',
  WARNING: 'M12 8v5M12 16.5v.01',
};
const icon = (d: string) => ({
  type: 'element',
  tagName: 'svg',
  properties: { className: ['callout-icon'], width: 16, height: 16, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 2.6, strokeLinecap: 'round', ariaHidden: 'true' },
  children: [{ type: 'element', tagName: 'circle', properties: { cx: 12, cy: 12, r: 9.5 }, children: [] }, { type: 'element', tagName: 'path', properties: { d }, children: [] }],
});

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
      node.properties = { className: ['callout', `callout-${match[1].toLowerCase()}`] };
      const label = { type: 'element', tagName: 'p', properties: { className: ['callout-label'] }, children: [{ type: 'text', value: callouts[match[1]] }] };
      if (icons[match[1]]) label.children.unshift(icon(icons[match[1]]) as any);
      node.children.unshift(label);
    });
}

const isImage = (node: any) => node.type === 'element' && node.tagName === 'img';
const isBlank = (node: any) => node.type === 'text' && !node.value.trim();

/** Puts each screenshot that stands on its own line on a pastel panel, as a figure. The page sets the panel's colour from its group. */
function rehypeFigures() {
  return (tree: any) => {
    // An <img> written as HTML (to give a 2x screenshot its width) reaches here as raw text.
    tree.children = tree.children.map((node: any) =>
      node.type === 'raw' && /^\s*<img\s[^>]*>\s*$/.test(node.value) ? { ...node, value: `<figure class="shot panel">${node.value.trim()}</figure>` } : node,
    );
    visit(tree, 'element', (node: any, index, parent: any) => {
      if (!parent || index === undefined || parent.type !== 'root') return;
      const image = isImage(node) ? node : node.tagName === 'p' && node.children.filter((c: any) => !isBlank(c)).length === 1 ? node.children.find(isImage) : undefined;
      if (!image) return;
      parent.children[index] = { type: 'element', tagName: 'figure', properties: { className: ['shot', 'panel'] }, children: [image] };
      return SKIP;
    });
  };
}

/** Wraps each table so a wide one scrolls sideways inside its card rather than widening the page. */
function rehypeTables() {
  return (tree: any) =>
    visit(tree, 'element', (node: any, index, parent: any) => {
      if (node.tagName !== 'table' || parent?.properties?.className?.includes('table')) return;
      parent.children[index!] = { type: 'element', tagName: 'div', properties: { className: ['table'] }, children: [node] };
      return [SKIP, index! + 1];
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
  rehypePlugins: [rehypeRepoLinks, rehypeCallouts, rehypeFigures, rehypeTables, rehypeCodeCopy],
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
export const pages: GuidePage[] = rendered.map(({ slug, title, summary, group, file, markdown, headings, html }) => {
  let images = 0;
  // About 220 words a minute, counting the Markdown's words without its tags and links' addresses.
  const words = markdown.replace(/<[^>]+>|\]\([^)]*\)/g, ' ').split(/\s+/).filter(Boolean).length;
  return {
    slug,
    title,
    summary,
    group,
    file,
    minutes: Math.max(1, Math.round(words / 220)),
    headings,
    html: html
      .replace(/href="#([^"]+)"/g, (match, id) => (anchors[id] ? `href="${anchors[id]}"` : match))
      .replace(/<img src="(?:\.\.\/)+docs\/media\/([^"]+)"([^>]*?)(?=\s*\/?>)/g, (match, file, rest) => mediaImage(match, file, rest, images++ === 0)),
  };
});
