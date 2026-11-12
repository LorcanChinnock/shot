# The site's design

The website is Shot's, so it uses Shot's design system. The values come from the redesign's **Website** boards, recorded in `docs/redesign/spec.md` under Website values. This file says how the site uses them. The tokens themselves are at the top of `src/styles/global.css`.

## Mood

**Quiet page, loud captures.** The page is calm and neutral, so Shot's screenshots and its own marks are the most colourful things on it. The ink outline, the hard drop and the yellow go on the one action a section wants you to take, as in the app. The playful moments are Shot's own tools drawn on the page: a highlighter under a word, a numbered badge, an arrow and a sticky note.

## Palette

- Light and dark, following the visitor's system setting, as the app follows the Mac's. There's no toggle, because the default is the simplest state.
- Light: near-black ink (`#16161A`) on a warm off-white page (`#F7F6F3`), with white cards.
- Dark: the app's dark neutrals (page `#1C1C1F`, cards `#2C2C30`, raised fills `#3A3A3F`), off-white text and the dark accent `#F2CC4A`. Ink outlines and drops go near-black (`#050507`). The Website boards are drawn in light only, so this follows the app until a dark board exists.
- Yellow is the only accent. Text on it is near-black in both themes (`--on-accent`).
- Five pastel panels (sand, lilac, sky, blush, sage) sit behind product shots, never behind text alone. In dark they're mixed into the card colour so they don't glare.
- Sticky notes, the guide's callouts and the changelog's scope tags keep their light colours in dark, like paper.
- One dark band (`#16161A`) holds the install command, the scrolling strip and dark cards.
- There is no backdrop: the coloured blobs and dot grid are gone.

## Type

System fonts: SF Pro on a Mac, which is what Shot itself uses. Headings are black weight (900) with tight tracking: H1 `clamp(36px, 4.6vw, 56px)`, H2 30px. The landing page's hero alone is bigger, `clamp(52px, 8.5vw, 112px)`, as the board draws it. Body text is 16.5px at 1.65 and the lede 20px. Code and commands are SF Mono. The one web font is Caveat, self-hosted in `public/fonts/` under the SIL Open Font License, and it's used for sticky notes only, never for text you need to read.

## Shape

- Corners: buttons 12px, small buttons 10px, cards 18px, ink cards 20px, pastel panels 26px.
- Ink: a 2px outline with a 4px drop straight down on large buttons, ink cards and big key caps; 1.5px with a 2–3px drop on small buttons, badges and key caps in text.
- Everything that isn't the action is quiet: cards are white (or `#2C2C30`) with a hairline, and secondary buttons have a soft edge and no ink.

## The shared pieces

All of them are classes in `src/styles/global.css`, so each page uses them without its own CSS.

- **Buttons**: `.button` is the ink button and `.button.small` the header's. `.button.secondary` is the quiet one beside it, and `.go` is a plain link with an arrow.
- **Install block** (`Copy.astro`): the command on the dark band with a white Copy button that turns green and says Copied ✓, or says "Press ⌘C" and selects the command when the clipboard is blocked.
- **Key caps**: `kbd.key` in text and `kbd.key.big` in headings, `.accent` for a yellow one. They press into their shadow on hover, never plain text.
- **Badges and tags**: `.badge` (Latest), `.badge.dark` (Free), `.badge.quiet` (beta), and the changelog's `.tag.capture`, `.editor`, `.gallery` and `.release`. A `.tag` with none of these is light grey, and every tag stays light in dark.
- **Cards**: `.card` is quiet, `.ink-card` has ink, and `.tilt` tilts a card at rest (`--tilt`) and straightens and lifts it on hover. `.panel.sand` and the other pastels hold product shots.
- **Tabs and questions**: `.tabs` with `role="tab"` buttons, or with radio `<label>`s for tabs that need no script: the labels look like tabs, the arrow keys move between them, and the page shows the checked one's panel with `:has()` (the landing page's Capture section). `details.faq` opens without a script.
- **Product shots** (`Window.astro`): a screenshot or loop on a pastel panel, tilted with a deep shadow, straightening on hover. Marks go in its `marks` slot so they're placed against the shot. The landing hero (`HeroStage.astro`) is the editor screenshot on the sand panel, with the capture bar under it, the Quick Access card floating beside it, badges 1–3 on the capture bar, the arrow and Copy, and a Copied toast.
- **Shot's marks**: `.hl` is the highlighter under one word per heading. `.counter` is the red numbered badge, `<Arrow from to bend />` (`Arrow.astro`) is a drawn arrow, whose head it computes from the shaft's end so it always sits on the tip and points along the curve (never hand-write the SVG; `make lint` checks), and `.note` is a sticky note. Each mark sits inside an `.anchor` next to what it labels, carries `.deco` and `aria-hidden="true"`, and is hidden under 860px.
- **Header**: Features, Guide, FAQ and GitHub, and a small Download free button. On guide pages the wordmark reads "Shot guide", with "guide" in red in the system font, and the guide's search sits beside it. Under 720px the links move into a Menu button (a `<details>`), and the logo and Download stay.
- **Footer**: the product with a line about it, then Product, Help and Project columns, stacking to one on a phone. It ends with the "LC_" mark and "Made by Lorcan Chinnock", linked to lorcanchinnock.com, in Shot's ink with the underscore in yellow, and "Not affiliated with Apple."
- **Guide** (`layouts/Prose.astro` and `pages/docs/[page].astro`, from the board **Site · guide page**): three columns in the 1360px container.
  - Left: the pages under their groups, each group with a colour marker (Get started the accent, Capture `--tag-capture`, Edit and share `--tag-editor`, Reference `--tag-release`, Help `--tag-gallery`). The current page is a yellow ink chip.
  - Middle: the group and reading time, the title with the highlighter under its last word, and the lede. Screenshots sit on the group's pastel panel (sand, blush, sky, lilac, sage, as on the social cards). Steps are white cards on red counter badges. The Tip is a tilted sticky note, the Note a blue callout and Watch out a red one. Tables are quiet cards, with an ink outline when the first column holds key caps. The page ends with a GitHub link for reporting a gap, an edit link, and the previous and next pages, where Next is the yellow ink card.
  - Right: "On this page", with the section you're reading marked in red, and a dark "Try it now" card with ⌘⇧4 or ⌘⇧5 on pages about screenshots or recordings.
  - The search is in the header, opens its results under the field, and takes `/` to focus. Code blocks have a Copy button that says Copied ✓ in green, or "Press ⌘C" with the code selected.
  - Between 1000 and 1280px "On this page" moves under the page list. Under 1000px both lists become cards that open, above the article, and the "Try it now" card is hidden.

- **Changelog** (`pages/changelog/index.astro` and `components/ChangelogRelease.astro`, from the board **Site · changelog**): "What's new" with the highlighter under "new", an RSS feed link, and Everything, New and Fixes filters. The filters are radio labels styled as one segmented control, and `:has()` hides the other entries, so they need no script.
  - Each release is a row on a timeline: the version in SF Mono with its date on the left, beside a dot on a grey line, and its changes in a card on the right. The latest has the ink outline, a pulsing red dot and the Latest badge. The rest are quiet cards. Under 760px the version and date sit in a row above the card.
  - Each change has a kind pill (New in ink, Fixed and Faster quiet, Changed outlined), its text, a scope tag and its pull request number. `src/lib/changelog.ts` maps release-please's headings and `**scope:**` prefixes, and gives capture, editor, gallery and release areas their tag colours. Other areas get the neutral tag.
  - A release can have a "Big one" sticky note across the top of its card, from `src/data/changelog-highlights.ts`. It's on the sticky-note yellow, so its Caveat label follows the sticky-notes-only rule.
  - The eight newest releases show, and the rest open under "Show older releases".

- **Long-form pages** (`/privacy/` and `/screenshot-apps/`, through `layouts/Prose.astro` without `pages`, from the board **Site · guide page**): the guide's article in one centred 760px column, with no side columns or card. Each page opens with a `.longform-head`: a meta line (when it was last updated, or how long it takes to read), the title with the highlighter under one word, and the lede. Sections are H2s, and the install command uses `Copy.astro`.
- **404** (`pages/404.astro`, from **Site · components and motion**): the yellow ink panel, with a 2px outline and a 5px drop, holding "404", "Nothing here to capture." as the H1, a line saying why, and a white Back home button. Under it, a line links to the guide and What's new. The page is `noindex`.

## Motion

Every token is in `global.css` and listed in the spec:

- **Press**, 80ms linear: ink buttons drop 3px into their shadow.
- **Pop**, 400ms spring (`.pop`, staggered with `--delay`): badges, notes and counters arrive with a small overshoot. `.pop.on-view` waits until it scrolls into view.
- **Sweep**, 700ms: the highlighter draws under its word.
- **Draw**, 500ms ease-out: an arrow draws towards what it points at, then its head appears.
- **Rise** (`.reveal`): sections fade up 36px as they enter, on a CSS scroll timeline.
- **Ambient** loops: key caps press in turn (`kbd.key.press`), the counter pulses (`.counter.pulse`), notes wobble (`.note.wobble`), things float (`.float`), and the band scrolls (`.marquee`, 32s, paused on hover).
- **Hover**, 350ms: tilted cards straighten and lift 4px.
- **Page transitions** are the browser's own cross-document view transitions: the header stays put and the page fades through.

The page needs no animation script, and a browser without scroll timelines or view transitions just shows the page. **Reduce Motion** turns all of it off: every animation sits behind `prefers-reduced-motion: no-preference`, so the page shows its last frame. Colour changes stay as a 120ms fade, and a pressed button darkens instead of dropping.

## Social cards

`npm run og` renders each card from the site itself: the home card is the hero (`A better ⌘⇧4` beside the hero scene, as Reduce Motion shows it). A guide page's card swaps the headline for the page's title, with its group as a chip, and shows what the page is about in the window: the guide's own screenshot where it has one, otherwise a drawing in the site's style (keycaps for the shortcuts page, a command for removing Shot). The scenes are listed in `scripts/og.mjs`, each on its group's pastel panel; a page without one shows the hero scene. Cards reuse `global.css` and `HeroStage.astro`, so a change to either shows up the next time the cards are rendered.

## Rules

- One ink control per section: the action you'd take next. Everything else is quiet.
- No cards with one thick coloured edge (a coloured stripe along the top or side). It's a stock look that reads as generated. Colour a card with a fill, a badge or a button instead. `scripts/lint.sh` rejects `border-top-color` and its kin, and an accent or other colour on a one-edge border.
- No gradient washes or coloured backdrops behind the page.
- Handwriting appears in sticky notes only.
- No script where CSS will do. The only scripts are the copy buttons, search, the loops' play/pause, the guide's "On this page" marker and closing the phone menu with Escape.
- No analytics or third-party requests, so the Content-Security-Policy in `public/_headers` stays at `'self'`. Fonts are self-hosted.
- Phone width works: 16px side gutters and no sideways scrolling.
- Copy speaks to the quick sharer first. Technical words (JSON, URL scheme) stay in the reference pages.
