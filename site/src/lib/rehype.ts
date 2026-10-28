import { visit } from 'unist-util-visit';

const repo = 'https://github.com/LorcanChinnock/shot';

/** Points the repo-relative links in the user guide and CHANGELOG.md at their homes on the site or GitHub. */
export function rehypeRepoLinks() {
  const map: Record<string, string> = { '../README.md': '/', 'README.md': '/' };
  return (tree: any) =>
    visit(tree, 'element', (node: any) => {
      const href = node.tagName === 'a' && node.properties?.href;
      if (typeof href !== 'string' || /^(https?:|#|\/|mailto:)/.test(href)) return;
      node.properties.href = map[href] ?? `${repo}/blob/main/${href.replace(/^\.\.\//, '')}`;
    });
}
