# Shot website

The marketing site at [shot.lorcanchinnock.com](https://shot.lorcanchinnock.com): a static [Astro](https://astro.build) site served by Cloudflare Workers static assets. It ships no analytics, cookies or third-party requests.

```sh
cd site
npm install
npm run dev       # http://localhost:4321
npm run build     # static site in dist/
npm run preview   # build, then serve dist/ with wrangler, _redirects and _headers included
```

- `/docs/` renders `docs/usage.md` and `/changelog/` renders `CHANGELOG.md`, so they never drift from the repo.
- The download button and `/download` redirect use the latest published GitHub release, read at build time (`src/lib/release.ts`). `release.yml` rebuilds the site through a deploy hook after each release.
- The look follows the app's design system (`Sources/Shot/Design/BrutalStyle.swift`); the tokens are at the top of `src/styles/global.css`.
- `npm run media` turns the 2× recordings in `docs/media` (`hero.mp4`, `recording.mp4`) into the looping videos and posters in `public/media/` (needs ffmpeg). `npm run icons` regenerates the favicons and the social card from `docs/icon.png`. Run them after changing those files and commit the output.

## Deploying

Cloudflare Workers Builds builds and deploys the site from the GitHub repo, so it uses no GitHub Actions minutes. The `shot-site` Worker is connected to the repo with:

- Root directory: `site` (the build also reads `../docs`, `../CHANGELOG.md` and `../.release-please-manifest.json`)
- Build command: `npm run build`; deploy command: `npx wrangler deploy`
- Production branch `main`; build watch paths `site/*`, `docs/*`, `CHANGELOG.md`
- Build variable `GITHUB_TOKEN`: a read-only token, so `src/lib/release.ts` doesn't hit GitHub's anonymous rate limit on shared build IPs

`release.yml` POSTs to a deploy hook (Settings › Builds › Deploy Hooks, branch `main`) after publishing a release, so the download button moves to the new zip. Its URL is the repository secret `SITE_DEPLOY_HOOK`.

`lorcanchinnock.com` must be a zone on the same Cloudflare account; the first deploy creates the `shot` custom domain and its DNS record. To deploy by hand: `npx wrangler login`, then `npm run deploy`.
