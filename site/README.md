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
- The download button and `/download` redirect use the latest published GitHub release, read at build time (`src/lib/release.ts`). `release.yml` redeploys the site after each release.
- The look follows the app's design system (`Sources/Shot/Design/BrutalStyle.swift`); the tokens are at the top of `src/styles/global.css`.
- `npm run media` turns the README's GIFs into the looping videos in `public/media/` (needs ffmpeg). `npm run icons` regenerates the favicons and the social card from `docs/icon.png`. Run them after changing those files and commit the output.

## Deploying

`.github/workflows/site.yml` builds every PR that touches the site, docs or changelog, and deploys from `main`. It needs two repository secrets:

- `CLOUDFLARE_API_TOKEN`: an API token with the **Workers Scripts: Edit** and **Workers Routes: Edit** permissions on the account, and **Zone: Read** plus **DNS: Edit** on `lorcanchinnock.com`.
- `CLOUDFLARE_ACCOUNT_ID`

`lorcanchinnock.com` must be a zone on the same Cloudflare account; the first deploy creates the `shot` custom domain and its DNS record. To deploy by hand: `npx wrangler login`, then `npm run deploy`.
