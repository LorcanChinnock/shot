import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseFrontmatter } from '@astrojs/markdown-remark';

/** The guide's parts, in order, each with its colour from the app's palette. */
export const groups = [
  { name: 'Get started', color: 'yellow' },
  { name: 'Capture', color: 'pink' },
  { name: 'Edit and share', color: 'sky' },
  { name: 'AI agents', color: 'mint' },
  { name: 'Reference', color: 'violet' },
  { name: 'Help', color: 'red' },
] as const;

export interface GuideFile {
  slug: string;
  title: string;
  summary: string;
  group: string;
  /** A renamed page's old slugs, which redirect here and still work as /docs/#… links. */
  aliases: string[];
  /** Section ids from the old single-page guide whose content now lives here, so /docs/#… links to them still land here. */
  anchors: string[];
  markdown: string;
}

const slugOf = (title: string) => title.toLowerCase().replace(/[^a-z0-9 -]/g, '').trim().replace(/ +/g, '-');

/** Reads src/guide/, one Markdown file per page in file name order, each with its title, summary and group in front matter. */
export function readGuide(siteDir = process.cwd()): GuideFile[] {
  const dir = resolve(siteDir, 'src/guide');
  return readdirSync(dir)
    .filter((name) => name.endsWith('.md'))
    .sort()
    .map((name) => {
      const { frontmatter, content } = parseFrontmatter(readFileSync(resolve(dir, name), 'utf8'));
      const { title, summary, group, aliases = [], anchors = [] } = frontmatter as Partial<GuideFile>;
      if (!title || !summary || !groups.some((g) => g.name === group)) {
        throw new Error(`src/guide/${name} needs a title, a summary and one of these groups: ${groups.map((g) => g.name).join(', ')}`);
      }
      return { slug: slugOf(title), title, summary, group: group!, aliases, anchors, markdown: content };
    });
}
