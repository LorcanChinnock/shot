# The site's design

The website is Shot's, so it uses Shot's design system: the `Brutal` tokens in `Sources/Shot/Design/BrutalStyle.swift`. This file says how the site stretches that system across a web page. The tokens themselves are at the top of `src/styles/global.css`.

## Mood

**Loud and handy.** The site should feel like the app: thick ink lines, hard shadows, bright fills on frosted glass, and things that press like buttons. It's playful because it moves, not because it jokes. Every bit of motion shows something Shot does.

## Palette

- Light and dark, following the visitor's system setting, as the app follows the Mac's. There's no toggle, because the default is the simplest state.
- Light: near-black ink on a warm off-white page, white `paper` fills and glass cards.
- Dark, as in the app: the page is darkest, glass cards a step lighter and `paper` lighter still. Lines and hard shadows stay near-black, text is a soft off-white, and the accents lose a little saturation. The backdrop's blobs drop to a third of their strength.
- Text on an accent fill (yellow buttons, chips, keycaps on colour) is always near-black, in both themes (`--on-accent`).
- Each guide group keeps its accent: yellow, pink, sky, mint, violet and red. The five audiences use the same accents on the home page.

## Type

System fonts only: SF Pro on a Mac, which is what Shot itself uses, and no web fonts to download. Headings are black weight (900) with tight tracking. Body text is 17px at 1.55. Code and commands are SF Mono.

## Shape

- 3px ink borders, 12px corners (`style: .circular` in the app, plain `border-radius` here), 4px hard shadows offset down and right.
- Small pieces use 2px borders and 2–3px shadows: keycaps, chips, callouts and code blocks.
- Hover lifts a button or card by 1px and grows its shadow, and pressing pushes it into its shadow. Keycaps press down the same way.

## Backdrop

Four slow colour blobs and a dot grid behind everything, as in the app's `GlassBackdrop`. Sections alternate between plain backdrop and an ink band, so a long page has a rhythm without boxes inside boxes.

## Motion

- **The hero** acts out the whole path in CSS: the ⌘⇧4 keys press, a selection is dragged out, the screen flashes, an arrow and a note are drawn, the Quick Access card slides into the corner and says Copied. The real recording of the same thing follows straight after, so nothing is promised that the app doesn't do.
- **Scroll reveals** fade and lift each section in as it enters the window (CSS scroll-driven animations, so no script). A browser without them just shows the content.
- **Micro-interactions**: buttons, cards and keycaps press. The copy button says Copied. The strip of shortcuts scrolls on its own.
- **Home steps**: three accent cards (capture, mark up, share) under the shortcut strip. They lift on hover, like the "Private / Speaks your language / Free" cards.
- **Guide details**: sidebar links slide right on hover, the current page's marker wipes in each time it moves, and the numbered steps pop in.
- **Page transitions** are the browser's own cross-document view transitions: the header stays put and the page fades through. Again no script, and a browser without them just loads the page.
- **Reduced motion** turns all of it off. The hero shows its last frame, loops show their poster with controls, the shortcut strip stands still and pages change instantly.

## The shared pieces

- **Install block**: the install command in a glass card with a Copy button that says Copied, or "Press ⌘C" if the clipboard is blocked.
- **Keycaps**: white (raised grey in dark) with an ink border and a hard 2px shadow, never plain text.
- **Guide**: a sidebar with the pages in their groups and a search box, an "On this page" list that marks where you are (a rail on the right of wide screens, under the page list on narrower ones), previous and next links, a back-to-top button, numbered steps, callouts, and a Copy button on every code block.
- **Footer**: ends with the "LC_" mark and "Made by Lorcan Chinnock", linked to lorcanchinnock.com, in Shot's ink with the underscore in yellow, and "Not affiliated with Apple."

## Social cards

`npm run og` renders each card from the site itself: the home card is the hero (`A better ⌘⇧4` beside the window with its last frame). A guide page's card swaps the headline for the page's title, with its group as a chip in the group's accent, and shows what the page is about in the window: the guide's own screenshot where it has one, otherwise a drawing in the site's style (keycaps for the shortcuts page, a command for removing Shot). The scenes are listed in `scripts/og.mjs`; a page without one shows the hero. Cards sit on the backdrop, in the system fonts, and reuse `global.css` and `HeroStage.astro`, so a change to either shows up the next time the cards are rendered.

## Rules

- No cards with one thick coloured edge (a coloured stripe along the top or side). It's a stock look that reads as generated. Colour a card with a fill, a chip or a button instead, and keep the same 3px ink border on every side. `scripts/lint.sh` rejects `border-top-color` and its kin, and `var(--accent)` or another colour on a one-edge border.
- No script where CSS will do. The only scripts are the copy buttons, search, the loops' play/pause and the guide's "On this page" marker.
- No web fonts, analytics or third-party requests, so the Content-Security-Policy in `public/_headers` stays at `'self'`.
- Phone width works: 16px side gutters and no sideways scrolling.
- Copy speaks to the quick sharer first. Technical words (JSON, URL scheme) stay in the reference pages.
