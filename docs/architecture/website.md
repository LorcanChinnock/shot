# Website and user guide

Read this before changing `site/` or the user guide.

- `site/` is the Astro marketing site, built and deployed by Cloudflare Workers Builds (see `site/README.md`).
- `site/DESIGN.md` is its design direction: Shot's `Brutal` tokens in light and dark, and CSS-only motion with a still version for reduced motion.
- The user guide lives in `site/src/guide/`, one Markdown file per page at `/docs/<slug>/`, in file name order. Each file's front matter gives its `title`, a one-line `summary` and its `group` (the groups are in `site/src/lib/guide-files.ts`).
- A page's address comes from its title, so renaming a page changes its address, with no redirect from the old one.
- Write pages as tasks, in second person: numbered steps, `<kbd>⌘⇧4</kbd>` for keys, and `> [!TIP]` or `> [!NOTE]` callouts.
- Link to another page's section with just its id, `(#id)`, and the build points it at the right page.
- A new file becomes a new page. The site also renders `CHANGELOG.md` directly. release-please ignores `site/`.
