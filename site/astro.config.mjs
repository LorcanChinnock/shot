import { defineConfig } from 'astro/config';
import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import * as pagefind from 'pagefind';
import { SKIP, visit } from 'unist-util-visit';
import { latestRelease } from './src/lib/release.ts';
import { rehypeRepoLinks } from './src/lib/rehype.ts';

const repo = 'https://github.com/LorcanChinnock/shot';

/** Drops release-please's "(abc1234)" commit links from CHANGELOG.md; the issue link is enough. */
function rehypeDropCommitLinks() {
  return (tree) =>
    visit(tree, 'element', (node, index, parent) => {
      if (node.tagName !== 'a' || !/\/commit\/[0-9a-f]+$/.test(node.properties?.href ?? '')) return;
      const before = parent.children[index - 1];
      const after = parent.children[index + 1];
      if (before?.type !== 'text' || !before.value.endsWith('(') || after?.type !== 'text' || !after.value.startsWith(')')) return;
      before.value = before.value.slice(0, -1).trimEnd();
      after.value = after.value.slice(1);
      parent.children.splice(index, 1);
      return [SKIP, index];
    });
}

/** Writes Cloudflare's _redirects, so /download is a real redirect to the latest release's zip. */
function redirects() {
  return {
    name: 'shot-redirects',
    hooks: {
      'astro:build:done': async ({ dir }) => {
        const release = await latestRelease();
        const lines = [
          `/download ${release.zip} 302`,
          `/github ${repo} 302`,
          '/sponsor https://github.com/sponsors/LorcanChinnock 302',
          `/releases ${repo}/releases 302`,
        ];
        await writeFile(new URL('_redirects', dir), lines.join('\n') + '\n');
      },
    },
  };
}

/** Indexes the guide's pages into dist/pagefind/ for its search box. The index is static files, so search needs no server. */
function search() {
  return {
    name: 'shot-search',
    hooks: {
      'astro:build:done': async ({ dir }) => {
        const { index } = await pagefind.createIndex();
        const { errors } = await index.addDirectory({ path: fileURLToPath(dir), glob: 'docs/*/index.html' });
        if (errors.length) throw new Error(`Pagefind: ${errors.join(', ')}`);
        await index.writeFiles({ outputPath: fileURLToPath(new URL('pagefind', dir)) });
        await pagefind.close();
      },
    },
  };
}

export default defineConfig({
  site: 'https://shot.lorcanchinnock.com',
  trailingSlash: 'ignore',
  integrations: [redirects(), search()],
  markdown: {
    rehypePlugins: [rehypeRepoLinks, rehypeDropCommitLinks],
    shikiConfig: { theme: 'github-light' },
  },
  vite: {
    // The user guide, CHANGELOG.md and docs/media live outside the site folder.
    server: { fs: { allow: ['..'] } },
    // Keep scripts in files, so the Content-Security-Policy in public/_headers can stay at script-src 'self'.
    build: { assetsInlineLimit: 0 },
  },
});
