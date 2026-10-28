import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseFrontmatter } from '@astrojs/markdown-remark';

/** The guide's parts, in order, each with its colour from the app's palette. */
export const groups = [
  { name: 'Get started', color: 'yellow' },
  { name: 'Capture', color: 'pink' },
  { name: 'Edit and share', color: 'sky' },
  { name: 'Reference', color: 'violet' },
  { name: 'Help', color: 'red' },
] as const;

export interface GuideFile {
  /** The Markdown file's name in src/guide/. */
  file: string;
  slug: string;
  title: string;
  summary: string;
  group: string;
  /** Slugs the page used to have, which redirect to it. */
  aliases: string[];
  markdown: string;
}

const slugOf = (title: string) => title.toLowerCase().replace(/[^a-z0-9 -]/g, '').trim().replace(/ +/g, '-');

/** Reads src/guide/, one Markdown file per page in file name order, each with its title, summary and group in front matter, and optionally the `aliases` it used to have. */
export function readGuide(siteDir = process.cwd()): GuideFile[] {
  const dir = resolve(siteDir, 'src/guide');
  const pages = readdirSync(dir)
    .filter((name) => name.endsWith('.md'))
    .sort()
    .map((name) => {
      const { frontmatter, content } = parseFrontmatter(readFileSync(resolve(dir, name), 'utf8'));
      const { title, summary, group, aliases = [] } = frontmatter as Partial<GuideFile>;
      if (!title || !summary || !groups.some((g) => g.name === group)) {
        throw new Error(`src/guide/${name} needs a title, a summary and one of these groups: ${groups.map((g) => g.name).join(', ')}`);
      }
      return { file: name, slug: slugOf(title), title, summary, group: group!, aliases, markdown: content };
    });
  // An alias that is a real page's address, or two pages' alias, would redirect away a live page or be ambiguous.
  const owners = new Map(pages.map((page) => [page.slug, page.file]));
  for (const page of pages) {
    for (const alias of page.aliases) {
      const owner = owners.get(alias);
      if (owner) throw new Error(`src/guide/${page.file} lists the alias "${alias}", which is already the address of ${owner}`);
      owners.set(alias, page.file);
    }
  }
  return pages;
}
