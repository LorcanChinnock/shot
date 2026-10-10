import { defineConfig } from 'astro/config';
import { writeFile } from 'node:fs/promises';
import { visit } from 'unist-util-visit';
import { latestRelease } from './src/lib/release.ts';

const repo = 'https://github.com/LorcanChinnock/shot';

/** Points the repo-relative links in docs/usage.md and CHANGELOG.md at their homes on the site or GitHub. */
function rehypeRepoLinks() {
  const map = { '../README.md': '/', 'README.md': '/', 'docs/usage.md': '/docs/' };
  return (tree) =>
    visit(tree, 'element', (node) => {
      const href = node.tagName === 'a' && node.properties?.href;
      if (typeof href !== 'string' || /^(https?:|#|mailto:)/.test(href)) return;
      node.properties.href = map[href] ?? `${repo}/blob/main/${href.replace(/^\.\.\//, '')}`;
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
          `/releases ${repo}/releases 302`,
        ];
        await writeFile(new URL('_redirects', dir), lines.join('\n') + '\n');
      },
    },
  };
}

export default defineConfig({
  site: 'https://shot.lorcanchinnock.com',
  trailingSlash: 'ignore',
  integrations: [redirects()],
  markdown: {
    rehypePlugins: [rehypeRepoLinks],
    shikiConfig: { theme: 'github-light' },
  },
  vite: {
    // docs/usage.md, CHANGELOG.md and docs/media live outside the site folder.
    server: { fs: { allow: ['..'] } },
    // Keep scripts in files, so the Content-Security-Policy in public/_headers can stay at script-src 'self'.
    build: { assetsInlineLimit: 0 },
  },
});
