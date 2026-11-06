# Redesign spec

The source of truth for the redesign (#1050) inside the repository. The [redesign canvas](https://claude.ai/artifact/L1RbfWST9segWkjfu4Kefs) shows how each screen looks. This page records the values and rules those boards use, so the build stays the same if the canvas changes later. When the canvas and this page disagree, this page wins. Change it in a PR, and redraw the board afterwards.

- **Values:** colours, shape, depth, type, ink and motion, from the Foundations and Website boards.
- **Rules:** what every screen follows.
- **Coverage:** every board and every guide page, each linked to the issue that builds or updates it. Nothing is done until its row is ticked.

The boards are HTML mock-ups. They stand Inter in for SF Pro and JetBrains Mono in for SF Mono, and draw in CSS pixels. In the app, read a pixel as a point and use the system fonts.

## Rules

1. **One ink control per screen.** The ink outline, the hard drop and the yellow mark the action you'll take next: Copy, Save, Record, Stop, Continue, or the selected tool. Each screen or panel has at most one. Everything else uses the secondary, plain or toolbar styles.
2. **Side panels start closed.** Style, Layers, Inspector and Export open only when you reach for them. The default view is the simplest one: the quick sharer sees capture, Copy and Save, and nothing else.
3. **Delight never waits.** A playful moment plays only after the work is done, so the capture → copy path is never delayed. There's one moment per action, each under 300 ms, except the menu bar's countdown and recording status, which tick with real time.
4. **Native where it's familiar.** Unified title bars with the toolbar in them, standard traffic lights, see-through sidebars, grouped forms, native menus, sheets and pop-up menus. Nothing a Mac user has to learn twice.
5. **Quiet chrome, loud captures.** No gradient washes, neon panels or coloured fills behind windows. Neutral surfaces leave the screenshot as the most colourful thing on screen.
6. **Each colour has one job.** Yellow is the only interface accent. Record red appears only while something is recording or about to be lost. Selection blue marks selected marks, layers and files. The tints are for sidebar icons only, never fills.
7. **Handwriting only in empty states and onboarding:** the empty gallery, empty Layers and the welcome window. On the website it appears in sticky notes only, never in text you need to read.
8. **Reduce Motion** turns every movement into a 120 ms fade, or nothing. **Increase Contrast** and **Reduce Transparency** give floating panels and sidebars solid backgrounds, with text at 4.5:1 and marks at 3:1.
9. **Heavy weights** (800 and above) appear only in the app icon, onboarding and empty states. Numbers that tick (timers, sizes, zoom, countdowns) use tabular figures.

Every PR also follows the checklist in #1050: matches its board in light and dark, Increase Contrast, the Larger text size, VoiceOver, keyboard only, Reduce Motion, strings catalog updated, and `make lint` and `make test` pass.

## App values

From **Foundations › Design language**, **Components**, **Capture bar** and **Moments of delight**. These replace the values in `Sources/Shot/Design/BrutalStyle.swift` (#1068). The `Brutal` name stays until #1133.

### Colour

| Role | Light | Dark | Used for |
| --- | --- | --- | --- |
| Window | `#F7F6F3` | `#1C1C1F` | Window and canvas background |
| Sidebar | `#ECE9E3` | `#242427` | Sidebars, under the see-through material |
| Group | `#FFFFFF` | `#2C2C30` | Grouped panels, cards, fields |
| Control fill | `#F1EFEA` | `#3A3A3F` | Secondary buttons in dark, quiet fills in light |
| Selected segment | `#FFFFFF` | `#4A4A50` | Thumb of a segmented control |
| Text | `#16161A` | `#EDEBE6` | Body text and icons |
| Secondary text | `#55545A` | `#A9A7AE` | Descriptions |
| Tertiary text | `#6B6A70` | `#A9A7AE` | Captions, section labels, key hints |
| Accent text | `#8A6A00` | `#F2CC4A` | Plain buttons and links, where yellow itself fails contrast |
| Ink | `#16161A` | `#050507` | Ink outlines and hard drops |
| Accent | `#FFD43B` | `#F2CC4A` | The ink control, selected tool, focus, toggles. 6% less chroma in dark so it doesn't glare |
| Record | `#E5352B` | `#FF453A` | Recording only, destructive buttons |
| Selection | `#2B7FFF` | `#2B7FFF` | Selected marks, layers and files |
| Success | `#34C759` | `#34C759` | Status dots ("Keep scrolling") and tags only |
| Hairline | `rgba(22,22,26,0.08)` | `rgba(255,255,255,0.08)` | Edges of groups and cards |
| Control edge | `rgba(22,22,26,0.14)` | `rgba(255,255,255,0.12)` | Edges of buttons and pop-up menus |
| Separator | `rgba(22,22,26,0.07)` | `rgba(255,255,255,0.08)` | Rows inside a group |
| Field fill | `rgba(22,22,26,0.06)` | `rgba(255,255,255,0.07)` | Search fields, segmented tracks, tag chips |
| Hover | `rgba(22,22,26,0.07)` | `rgba(255,255,255,0.08)` | Toolbar buttons on hover |
| Disabled text | `rgba(22,22,26,0.35)` | `rgba(237,235,230,0.35)` | Disabled controls |

**Sidebar icon tints** appear only as the tile behind a sidebar icon, never as a fill. The selected row's tile is `#FFFFFF` with a `#16161A` icon in both appearances.

| Section | Light tile | Light icon | Dark tile | Dark icon |
| --- | --- | --- | --- | --- |
| General | `#F0EDE6` | `#55545A` | `#3A3A3F` | `#CFCDD4` |
| Capture | `#FFE0EE` | `#C2306E` | `#4A2336` | `#FF8DBE` |
| Quick Access | `#DCEFFF` | `#1D6FB8` | `#1E3550` | `#7DBBFF` |
| Recording | `#FFE1DE` | `#C4271E` | `#4A2220` | `#FF7B72` |
| Shortcuts | `#FFE9D3` | `#B35A00` | `#4A3118` | `#FFB366` |
| About | `#EAF6D2` | `#4E7A0E` | `#2E3D1A` | `#A8D86A` |

The gallery sidebar draws its icons in the same colours without a tile: Screenshots `#5B4BD6` (dark `#A99BFF`), Recordings `#C4271E` (dark `#FF7B72`), GIFs `#1D6FB8` (dark `#7DBBFF`), folders in secondary text.

**Dark windows** follow the dark column above: the window's title bar, toolbar and canvas go dark, but the screenshot or recording in it keeps its own colours. Ink outlines and drops use dark ink `#050507`, and text on the yellow accent stays `#16161A`. Popovers, the style bar and the selection bar use `rgba(44,44,48,0.97)` with a 0.5 pt `rgba(255,255,255,0.14)` edge and `0 8px 24px rgba(0,0,0,0.45)`.

**Floating panels** (the capture bar, recording controls, countdown, toasts, Quick Access buttons, pin bar) are dark in both appearances (#1073):

| Part | Value |
| --- | --- |
| Background | `rgba(26,26,30,0.86)`; toasts `0.90`, pin bar `0.82`, Quick Access corner buttons `0.78` |
| Edge | 0.5 pt `rgba(255,255,255,0.14)` |
| Shadow | `0 14px 36px rgba(0,0,0,0.38)` |
| Text and icons | `#FFFFFF`; icons `rgba(255,255,255,0.82)`; off toggles `rgba(255,255,255,0.55)`; secondary text `rgba(255,255,255,0.75)` |
| On toggle, secondary button | `rgba(255,255,255,0.16)` (secondary `0.12`) |
| Ink button | Accent, 1.5 pt `#000000` outline and 2 pt `#000000` drop |
| Divider | 1 × 22 pt `rgba(255,255,255,0.16)` |
| Scrim behind Quick Access buttons | `rgba(18,18,22,0.46)` |

`FloatingPanel` in `Design/GlassWindow.swift` holds these values. `.floatingPanel(shape, opacity:)` draws the fill and edge and lays the content out in the dark appearance, so `BrutalBadge`, `BrutalSegmented` and the other quiet components pick up their dark values. Buttons inside take `BrutalButtonStyle(…, floating: true)`, and `FloatingDivider` draws the divider. Each panel lives in a `FloatingPanelWindow` sized to its shape. The shadow is the system window shadow, which follows the shape and needs no transparent margin to catch clicks, so it only approximates the board's. The capture bar is drawn by AppKit inside the overlay, so it draws the board's shadow itself, outside the bar only, from `FloatingPanel.shadowNS`. Increase Contrast and Reduce Transparency make every panel solid, and Increase Contrast takes the edge to 40% white and the divider to 60%. Panel layouts stay as they are until each board's own issue rebuilds them.

**Window chrome** (#1073): `GlassWindow` makes a standard titled window with a unified, transparent title bar and the toolbar content beside the standard traffic lights. The window background is the plain Window colour, and the system draws the corners and edge. `SidebarMaterial` is the see-through sidebar (`NSVisualEffectView`, `.sidebar` material), solid in the Sidebar colour with Increase Contrast or Reduce Transparency. Settings runs it from the window's edge to the middle of the gap beside the sidebar, with a separator on its right.

The menu bar menu is a native menu. The board draws it at `rgba(248,246,242,0.96)`, radius 11, with the highlighted row in accent and a 1 pt `rgba(22,22,26,0.4)` inner edge.

### Shape

| Token | Radius | Used for |
| --- | --- | --- |
| Control | 6 | Buttons, fields, pop-up menus, toolbar buttons, menu rows |
| Group | 10 | Grouped panels, tiles, thumbnails, buttons inside floating panels |
| Panel | 14 | Side panels, Quick Access cards, dialogs, cards |
| Full | height ÷ 2 | Floating panels, toasts, toggles, tag chips |

The boards round buttons at 7 and cards at 12 in places. Build with the four tokens. Two floating panels are too tall for a pill and use their own radius: the capture bar 16, the countdown panel 22. Corners are always `.circular` (`make lint`).

### Depth

| Level | Value | Used for |
| --- | --- | --- |
| Rest | 1 pt control edge + `0 1px 1px rgba(22,22,26,0.06)` | Secondary buttons, pop-up menus |
| Group | 1 pt hairline + `0 1px 2px rgba(22,22,26,0.04)` | Grouped panels, cards |
| Float | 0.5 pt `rgba(0,0,0,0.2)` + `0 8px 24px rgba(22,22,26,0.16)` | Popovers, menus, tooltips, the style bar |
| Ink | 1.5 pt ink outline + `0 2px 0` ink drop, no blur | The one ink control per screen |

In dark, Rest is a 0.5 pt `rgba(255,255,255,0.12)` edge with `0 1px 1px rgba(0,0,0,0.3)`.

### Ink

| Where | Outline | Drop |
| --- | --- | --- |
| Main button | 1.5 pt | 2 pt, sinks to 0 when pressed |
| Selected tool | 1.5 pt | 1.5 pt |
| Toggle (on), its knob | 1.5 pt | none |
| Checkbox (on) | 1.5 pt inner edge | none |
| App icon tile, empty-state tile | 1.5 pt | 2 pt |
| Recording border | 2 pt record red with a soft glow | none |
| Focus ring | 4 pt halo, accent at 60% (`rgba(255,212,59,0.6)`) | none |

Ink is drawn with `inkBorder`, crisp on 1× displays (`inkBorder` snaps the width to whole device pixels, and is the one way to draw it).

### Buttons

`BrutalButtonStyle` (#1070) draws every button. Pick the kind by the button's job, so a screen keeps one ink button.

| Kind | Rest | Hover, on | Pressed | Disabled |
| --- | --- | --- | --- | --- |
| Main | Accent, Ink depth, Window type (13 semibold) | No change | Sinks 2 pt into its drop over 80 ms | Draws as a disabled secondary button |
| Secondary | White (control fill in dark), Rest depth, Body type | Hover: no change. On: the focus halo, as a shortcut recorder shows while it listens | Hover fill over it | Hairline edge, disabled text |
| Plain | Accent text, 13 medium | No change | 60% opacity | Disabled text |
| Toolbar | No fill, icons at 85% ink, 12 medium, 30 × 28 minimum | Hover fill | Hover fill twice | Disabled text |
| Tool | As toolbar | Selected: accent with a 1.5 pt ink outline and 1.5 pt drop | As toolbar, or as main when selected | Disabled text |

- **Destructive** turns a main button record red with white text (`#C4271E` with Increase Contrast, where record red is under 4.5:1), and other kinds `#C4271E` text and a 40% edge of it (dark `#FF7B72`).
- **Floating** panels' buttons use group corners. The main button keeps the accent with `#000000` ink, secondary is `rgba(255,255,255,0.12)` with white text, and a toolbar toggle that's on is `rgba(255,255,255,0.16)`.
- **Focus** replaces the system ring with the 4 pt accent halo. **Reduce Motion** keeps the drop still and darkens the fill on press. **Increase Contrast** takes a secondary button's edge to 60% ink.

### Choice controls

#1071 restyles the switches, checkboxes, segmented controls, pop-up menus and sliders in `Design/`. None takes a colour: on states use the accent, and sidebar tints stay on sidebar icons.

| Control | Look | Code |
| --- | --- | --- |
| Switch | 38 × 22. On: accent, 1.5 pt ink outline, white 17 pt knob with a 1.5 pt ink edge. Off: `rgba(22,22,26,0.12)` track (dark `rgba(255,255,255,0.16)`), white 18 pt knob with a soft shadow | `BrutalToggleStyle()` |
| Checkbox | 16 pt, radius 4. On: accent, 1.5 pt ink inner edge, ink tick. Off: secondary fill with the Rest edge | `BrutalCheckboxStyle()`, `CheckboxMark` |
| Segmented | Field-fill track, radius 8, 2 pt padding. Selected: white thumb (dark `#4A4A50`), radius 6, `0 1px 2px`, Small type. Others: secondary text | `BrutalSegmented` |
| Pop-up menu | The secondary button's look, tighter, with up and down chevrons. Opens a menu at the group fill with the Float edge and a system shadow; the highlighted row is accent with a 1 pt inner edge at 40% ink | `BrutalPopUp`, `BrutalDropdown` for menus of commands |
| Slider | 4 pt track filled in ink to an 18 pt white knob. Colour sliders draw their gradient 8 pt tall | `BrutalSlider` |

- **Focus** shows the 4 pt accent halo around the switch, the box, the segmented track or the slider's knob. The segmented control takes focus as one control, and the arrow keys move its selection.
- **VoiceOver** reads each as its native control: a switch reads on or off, a segmented control its selected segment.
- **Reduce Motion** moves the switch's knob and the segmented thumb at once instead of sliding them.
- **Increase Contrast** gives the off switch, the segmented track and the slider a 60% ink edge.

### Feedback

#1072 adds the fields, tags, badges, keycaps, tooltips, toast, progress bar and empty state. Like the choice controls, none takes a colour.

| Component | Look | Code |
| --- | --- | --- |
| Text field | Group fill, the Rest edge, control radius, 8 pt side padding, Body type, 24 pt tall | `.brutalField(focused:)` on a `TextField` |
| Search field | Field fill with no edge, a tertiary magnifying glass and prompt, and a clear button once there's text | `BrutalSearchField` |
| Tag chip | Field-fill pill, 11.5 pt, with an 8 pt dot in the Finder tag's colour. A filter that's on is selection blue at 14% with a 1 pt edge at 35% | `TagChip` |
| Badge | 10.5 pt on a 4 pt radius. Quiet: `rgba(22,22,26,0.08)` (dark `rgba(255,255,255,0.1)`) with secondary text, beside titles and in rows. Strong: `#16161A` with white bold text, over thumbnails. A status badge can lead with a 6 pt success dot | `BrutalBadge` |
| Keycap | 11 pt SF Mono on the quiet badge fill, 4 pt radius, with a 1 pt bottom edge at 12% | `Keycap` |
| Tooltip | The group fill at Float depth, control radius. The name in Small type, then its keycap, with one line of explanation below in 12 pt tertiary text | `brutalTip(_:key:detail:)`, `Tile(help:key:detail:)` |
| Toast | A 34 pt dark pill, `rgba(26,26,30,0.90)` with a 0.5 pt `rgba(255,255,255,0.14)` edge and the system window shadow. Message in 13 medium white. One button: a `rgba(255,255,255,0.16)` pill in 12 semibold, with its key faded after it (Undo ⌘Z) | `Toast` |
| Progress bar | 6 pt, the progress track `rgba(22,22,26,0.08)` (dark `0.12` white) filled in ink. In a toast it sits after the message with the percentage in tabular figures | `BrutalProgressBar`, `Toast.progress(_:fraction:)` |
| Empty state | An optional handwritten note, a 44 pt accent tile with a 1.5 pt ink outline and 2 pt drop, a 14 bold title, a 12 pt tertiary line and any buttons | `EmptyState` |

- **Handwriting** is Bradley Hand Bold at 20 pt, which ships with macOS, in secondary text. It tilts −4° and wobbles to +1° over 4 s; Reduce Motion keeps it still at −4°. The boards use Caveat.
- **Focus** puts the 4 pt accent halo around a field. A tooltip shows on keyboard focus as well as hover, but only in the active window, and any click or key press hides it until the pointer leaves or focus moves on.
- **VoiceOver** hears every toast as an announcement, except progress, which updates in place without speaking each step. The progress bar reads as a native progress indicator.
- **Increase Contrast** gives fields and tag chips a 60% ink edge, badges ink text, the progress track 25% ink, and toasts a solid background with a 40% white edge. Reduce Transparency also makes toasts solid.

### Type

SF Pro at native sizes, through `ScaledFont`, so Settings › Text size still scales it.

| Style | Size | Weight | Notes |
| --- | --- | --- | --- |
| Display | 28 | Heavy (800), tracking −0.02 em | Onboarding and empty states only |
| Title | 20 | Bold, tracking −0.01 em | Window and page titles |
| Section | 15 | Bold | Settings section titles (#1111) |
| Window | 13 | Semibold | File names in title bars, main buttons |
| Body | 13 | Regular | Rows, labels, buttons |
| Small | 12 | Semibold | Floating-panel labels, segmented controls |
| Caption | 11 | Regular, tertiary text | Notes under rows, key hints |
| Numbers | 13 | Bold, SF Mono, tabular figures | Timers, sizes, zoom |
| Keycap | 11 | SF Mono | Keys in tooltips and hints, on a field-fill cap with a 1 pt bottom edge |

### Motion

| Moment | Duration | Where | Reduce Motion |
| --- | --- | --- | --- |
| Press | 80 ms | Ink buttons drop 2 pt into their shadow | No movement |
| Viewfinder snap | 180 ms, soft flash | Area, window and full-screen capture, after the image is copied | 120 ms fade |
| Copied tick | 240 ms | The toast springs up and its tick draws itself | 120 ms fade |
| Marks land | 200 ms | A new arrow draws its last few points; counters pop in with a small overshoot | Appear at once |
| Panel arrive | 240 ms spring | Panels and popovers; Quick Access slides in from its corner | 120 ms fade |
| Countdown | 1 s tick | Menu bar digits flip; the countdown ring empties | Number changes, no flip or ring animation |
| Recording pulse | 1.6 s loop | The red dot breathes in the menu bar and the recording controls | Steady dot |
| Empty-state note | 4 s wobble | Handwritten notes | Still |

Edits and drags are always instant. Sounds follow the capture sound setting.

#1074 builds these on shared helpers. ShotCore's `Moment` holds each length and its Reduce Motion stand-in, with tests that keep every moment except the ambient loops under 300 ms. `Motion` in `Design/Motion.swift` turns them into animations, and `Motion.arrive` and `Motion.leave` replace Quick Access's own springs.

| Moment | Code | Notes |
| --- | --- | --- |
| Press, empty-state note | `BrutalButtonStyle`, `HandwrittenNote` | Built by #1070 and #1072, now timed by `Motion` |
| Viewfinder snap | `Capture/ViewfinderSnap.swift` | 4 pt ink brackets with a white edge fly in 14 pt from outside each corner, overshoot 2 pt and settle, with a 30% white flash. They hold for 180 ms, then fade. Shape layers, so a full-screen capture adds no memory |
| Copied tick | `Toast.done(_:drawsTick:)` | A 20 pt accent disc with an ink tick, for every copy and save. The toast rises 8 pt as it fades in. After a capture the snap is that action's moment, so the toast shows its tick already drawn |
| Marks land | `Editor/EditorCanvasView.swift` | A new counter grows to 122% and settles. An arrow is already whole when you let go of the drag, so it doesn't draw again |
| Countdown, recording pulse | `Design/BrandMark.swift` (`MenuBarAnimation`) | The digit folds flat and the next unfolds over 160 ms. While recording, a ring breathes out of the mark. A frame loop runs only while one plays. The countdown ring is #1078 and the recording controls' dot is #1089 |

### Capture bar

#1075 builds Foundations › Capture bar, the strip on the selection overlay after ⌘⇧4 or ⌘⇧5. AppKit draws it into the overlay, so it uses `FloatingPanel`'s AppKit values and draws its own shadow outside the bar only.

| Part | Look |
| --- | --- |
| Bar | Standard floating panel, radius 16, 6 pt padding, 4 pt between buttons |
| Kind | An 8 pt dot and "Screenshot" or "Record" in Small type at 80% white. The dot is the accent for a screenshot and record red for a recording |
| Picked mode | The one ink control: accent fill, 1.5 pt black outline and 2 pt black drop, group radius, 34 pt tall. Its icon and name in 13 semibold `#16161A` |
| Other modes | 38 × 34, icon only, at 82% white. Hover fill `rgba(255,255,255,0.08)` |
| Delay, Scroll | 34 pt tall. Scroll always shows its name. Delay is icon only while off and shows its seconds in tabular figures while on. On: the 16% white fill |
| Toggles | Magnifier, crosshair and size, 34 × 34. On: 16% white fill and a white icon. Off: icon at 55% white (75% with Increase Contrast) |
| Dividers | The floating divider between modes, Delay and Scroll, and the toggles, with 4 pt either side |
| Tooltip | On hover: the button's name in 12 pt white and its keycap (10.5 pt bold SF Mono on 16% white, radius 4), on a `rgba(26,26,30,0.92)` panel with the 0.5 pt edge, radius 8, 8 pt above the bar (below it when the bar is at the top) |

- **Picked mode stays yellow.** The board draws it as the accent ink button, and rule 1 allows one ink control per screen, which on the overlay is the mode you're about to capture with. The 16% white fill is for toggles that are on (Delay, Scroll and the aids), so the picked mode and an on toggle never look alike. The accent is its dark value, `#F2CC4A`, as on every floating panel's ink button (`FloatingPanel.accentNS`).
- **Record red on the kind dot** marks a recording that's about to start, which rule 6 allows.
- **Modes.** ShotCore's `CaptureBarMode` maps the overlay's three targets and the browser page onto Area, Window, Full Screen and Browser. Browser is a window pick of just the page. Tab steps through Area, Window and Full Screen as before, and B switches to Browser or back to Window from any mode. Browser asks for Accessibility the first time, as B did.
- **Layout.** `CaptureBarLayout` places the buttons and dividers, with tests. Sizes scale with Settings › Text size. `OverlayBarPlacement` and the 4 s fade are unchanged, and the fade now takes `Moment.panelArrive`'s length, or Reduce Motion's fade.
- **VoiceOver** finds each button as an element the overlay draws: modes as radio buttons, Scroll and the toggles as toggles, Delay as a button, each with its key in the help. A press shows the bar again. The crosshair and loupe aren't drawn while the pointer is on the bar, so they don't cover its buttons.
- **Increase Contrast and Reduce Transparency** make the bar and tooltip solid, take the edge to 40% white and the dividers to 60%.

## Website values

From **Website › Site · components and motion**, **Site · landing page** and **Site · guide page**. The site uses the app's light colours above, plus these. The Website boards are drawn in light only: until a dark board exists, the site's dark mode uses the app's dark neutrals and dark accent (#1123).

### Colour

| Role | Value | Used for |
| --- | --- | --- |
| Page | `#F7F6F3` | Background (the coloured blob backdrop goes) |
| Pastel panels | sand `#F3D9B1`, lilac `#DCD6F2`, sky `#C9DCEB`, blush `#F2D3D8`, sage `#D8E8D0` | Behind product shots, never text-only content |
| Sticky note | `#FFF1A8`, text `#3D3000`, heading `#6B4F00` | Notes and the guide's Tip |
| Note callout | `#DCEBF7`, edge `rgba(29,95,184,0.18)`, icon `#1D5FB8`, text `#173E73` | The guide's Note |
| Scope tags | capture `#F9C6CE`, editor `#BFE3F5`, gallery `#D8E8D0`, release `#DCD6F2` | Changelog areas |
| Guide groups | Get started accent, Capture `#F9C6CE`, Edit and share `#BFE3F5`, Reference `#DCD6F2`, Help `#D8E8D0` | Group markers in the guide's page list |
| Step badge | `#E5352B` with a 2.5 px white ring | Numbered steps, counter marks |
| Red text | `#C4271E` | The handwritten "guide" in the header |
| Copied | `#7FD8A0` | The copy-command button after copying |
| Dark band | `#16161A`, text `#EDEBE6`, secondary `#B9B7BE` | Scrolling band, motion card, "Try it now" card |

### Shape, ink and type

| Token | Value |
| --- | --- |
| Radius | buttons 12, small buttons 10, cards and sections 18, ink cards 20, figure panels 26 |
| Ink | 2 px outline with a 4 px drop on large buttons, cards and keycaps (5 px on the 404 panel); 1.5 px with a 2–3 px drop on small buttons, chips and keycaps in text |
| Highlighter | `linear-gradient(transparent 56%, accent 56%, accent 94%, transparent 94%)` under one word per heading |
| H1 | `clamp(36px, 4.6vw, 56px)`, 900, tracking −0.04 em, line height 1.02 |
| H2 | 30 px, 900, tracking −0.03 em |
| Lede | 20 px, line height 1.5 |
| Body | 16.5 px, line height 1.65 |
| Notes | Caveat 700, notes only |
| Containers | guide 1360 px, landing page 1240 px; marks hidden under 860 px |

### Motion

| Token | Timing | Used for |
| --- | --- | --- |
| Press | 80 ms linear | Ink buttons drop 3 px into their shadow |
| Pop | 400 ms spring | Badges, notes and tab content, with a small overshoot |
| Sweep | 700 ms ease-in-out | The highlighter under one word per heading |
| Draw | 500 ms ease-out | Arrows draw towards what they point at |
| Rise | scroll timeline | Sections fade up 24–36 px as they enter (CSS `animation-timeline: view()`) |
| Ambient | 2–5 s loops | Key presses, pulse, float; the marquee takes 20–32 s |
| Hover | 350 ms ease-out | Tilted cards straighten and lift 4 px |

`prefers-reduced-motion: reduce` turns every one of these off, and the page needs no animation script.

## Coverage: boards

Every board on the canvas, the issue that builds it, and the files it touches. #1131 ticks **QA** after walking the board in light and dark with the MugCo sample. Where a board is built by several issues, each has its own row.

### Foundations

| Board | Issue | Files | QA |
| --- | --- | --- | --- |
| Design language | #1068 tokens | `Design/BrutalStyle.swift`, `Design/GlassWindow.swift` (wash removed) | ☐ |
| Design language | #1069 1.5 pt ink | `scripts/lint.sh`, `Design/BrutalStyle.swift` (`inkBorder`), `CLAUDE.md` | ☐ |
| Design language | #1074 motion | `Design/Motion.swift`, ShotCore `Moment`, `QuickAccess/QuickAccessView.swift` | ☐ |
| Components › Buttons | #1070 | `Design/BrutalStyle.swift` (`BrutalButtonStyle`) and its call sites | ☐ |
| Components › Choice | #1071 | `Design/BrutalControls.swift`, `Design/BrutalDropdown.swift` | ☐ |
| Components › Choice, Feedback | #1072 | `Design/BrutalFeedback.swift`, `Design/BrutalTip.swift`, `Design/BrutalControls.swift` (`Tile`), `Toast.swift` | ☐ |
| Sample desktop (shared scene) | #1131 | None: the backdrop behind the Capture and Record boards. QA uses MugCo | ☐ |
| Capture bar (shared component) | #1075 | `Overlay/SelectionOverlayView.swift`, `Overlay/SelectionOverlayController.swift`, ShotCore `OverlayBarPlacement`, `CaptureBar.swift` (`CaptureBarMode`, `CaptureBarLayout`), `FloatingPanel.accentNS` in `Design/GlassWindow.swift` | ☐ |
| Moments of delight | #1074 | `Design/Motion.swift`, `Design/BrandMark.swift`, `Toast.swift`, `Capture/ViewfinderSnap.swift`, `Editor/EditorCanvasView.swift` | ☐ |

### Capture

| Board | Issue | Files | QA |
| --- | --- | --- | --- |
| Area capture | #1076 | `Overlay/SelectionOverlayView.swift` | ☐ |
| Window pick and delay | #1077 highlights | `Overlay/SelectionOverlayView.swift`, `Overlay/SelectionOverlayController.swift` | ☐ |
| Window pick and delay | #1075 capture bar with delay | `Overlay/SelectionOverlayView.swift` (the bar, Delay's seconds and the tooltip) | ☐ |
| Scrolling capture | #1086 | `Capture/ScrollingCaptureController.swift` | ☐ |
| Quick Access, pin, menu and toasts › card | #1081 | `QuickAccess/QuickAccessView.swift` | ☐ |
| Quick Access, pin, menu and toasts › stack | #1082 | `QuickAccess/QuickAccessController.swift`, `QuickAccess/QuickAccessView.swift` | ☐ |
| Quick Access, pin, menu and toasts › pin | #1083 | `QuickAccess/PinController.swift` | ☐ |
| Quick Access, pin, menu and toasts › menu | #1084 | `ShotApp.swift`, `Design/BrandMark.swift` | ☐ |
| Quick Access, pin, menu and toasts › toast | #1085 | `Toast.swift` | ☐ |
| Quick Access, pin, menu and toasts › countdown | #1078 | `Capture/CaptureCoordinator.swift`, `Design/BrandMark.swift` | ☐ |
| Quick Access, pin, menu and toasts › floating panels | #1073 | `Design/GlassWindow.swift` (`FloatingPanel`, `FloatingPanelWindow`), `Toast.swift`, `Overlay/SelectionOverlayView.swift`, `Recording/RecordingControlPanel.swift`, `Recording/RecordingSetupController.swift`, `Capture/ScrollingCaptureController.swift`, `QuickAccess/QuickAccessView.swift` | ☐ |
| Permission card… › permission card | #1087 | `Overlay/SelectionOverlayController.swift`, `Permissions.swift` | ☐ |
| Permission card… › colour loupe | #1080 | `ColorSampler.swift` | ☐ |
| Permission card… › recovery | #1092 | `Recording/RecordingRecovery.swift` | ☐ |
| Permission card… › update prompt | #1117 | `Updater.swift` | ☐ |
| Permission card… › tooltips and menus | #1072 | `Design/BrutalTip.swift` | ☐ |
| Permission card… › Share menu | #1093 | `Editor/EditorToolbar.swift` | ☐ |
| Permission card… › Move to Trash | #1110 | `Gallery/GalleryView.swift` | ☐ |

### Record

| Board | Issue | Files | QA |
| --- | --- | --- | --- |
| Check before recording | #1088 | `Recording/RecordingSetupController.swift`, `Recording/AudioMeter.swift` | ☐ |
| Check before recording | #1091 camera bubble | `Recording/CameraBubble.swift` | ☐ |
| While recording | #1089 controls | `Recording/RecordingControlPanel.swift`, `Recording/AudioMeter.swift`, `Design/BrandMark.swift` | ☐ |
| While recording | #1090 border and clicks | `Recording/RecordingBorderPanel.swift` | ☐ |
| While recording | #1091 camera bubble | `Recording/CameraBubble.swift` | ☐ |
| While recording | #1092 discard toast | `Recording/RecordingControlPanel.swift`, `Toast.swift` | ☐ |

### Edit

| Board | Issue | Files | QA |
| --- | --- | --- | --- |
| Image editor · annotate | #1093 toolbar | `Editor/EditorToolbar.swift`, `Editor/EditorRootView.swift` | ☐ |
| Image editor · annotate | #1094 style bar | `Editor/EditorCanvasView.swift`, `Editor/EditorRootView.swift` | ☐ |
| Image editor · annotate | #1095 canvas | `Editor/EditorCanvasView.swift`, `Design/LayersPanel.swift` (empty state) | ☐ |
| Image editor · annotate | #1073 title bar | `Design/GlassWindow.swift` | ☐ |
| Image editor · style | #1096 | `Editor/StylePopover.swift` (replaced by a side panel), `Editor/EditorRootView.swift` | ☐ |
| Image editor · crop and combine | #1097 crop | `Editor/EditorCanvasView.swift` | ☐ |
| Image editor · crop and combine | #1098 layers | `Design/LayersPanel.swift` | ☐ |
| Image editor · crop and combine | #1099 combine | `Editor/EditorToolbar.swift`, `Editor/EditorModel.swift`, `Editor/EditorCanvasView.swift` | ☐ |
| Video editor and export (dark) | #1100 window and toolbar | `VideoEditor/VideoEditorView.swift`, `VideoEditor/VideoEditorWindowController.swift` | ☐ |
| Video editor and export (dark) | #1101 drawing tools | `VideoEditor/AnnotationPalette.swift`, `VideoEditor/AnnotationCanvas.swift` | ☐ |
| Video editor and export (dark) | #1102 timeline | `VideoEditor/TracksView.swift` | ☐ |
| Video editor and export (dark) | #1103 export panel | `VideoEditor/VideoEditorView.swift`, `VideoEditor/VideoEditorModel.swift` | ☐ |
| Video editor and export (dark) | #1104 inspectors | `VideoEditor/ClipInspector.swift`, `VideoEditor/VideoEditorView.swift` | ☐ |
| Video editor and export (dark) | #1105 crop and transform | `VideoEditor/VideoCropOverlay.swift`, `VideoEditor/TransformOverlay.swift` | ☐ |
| Video editor and export (light) | #1100 | `VideoEditor/VideoEditorView.swift`, `VideoEditor/VideoEditorWindowController.swift`, `VideoEditor/TracksView.swift` | ☐ |
| Image editor · annotate (dark) | #1119, after #1093–#1099 | `Design/BrutalStyle.swift` (dark values), `Editor/EditorToolbar.swift`, `Editor/EditorCanvasView.swift` | ☐ |

### Library & Settings

| Board | Issue | Files | QA |
| --- | --- | --- | --- |
| Gallery | #1106 own window | `MainWindowController.swift`, `Gallery/GalleryController.swift`, `ShotApp.swift`, `AppDelegate.swift` (`shot://gallery`) | ☐ |
| Gallery | #1107 sidebar | `Gallery/GallerySidebar.swift` | ☐ |
| Gallery | #1108 grid and selection bar | `Gallery/GalleryView.swift` | ☐ |
| Gallery · preview and empty state | #1109 preview | `Gallery/GalleryPreview.swift` | ☐ |
| Gallery · preview and empty state | #1110 empty state | `Gallery/GalleryView.swift` | ☐ |
| Welcome | #1118 | `WelcomeWindow.swift` | ☐ |
| Settings sidebar (shared component) | #1111 | `Settings/SettingsView.swift` | ☐ |
| Settings sidebar (shared component) | #1106 Open Gallery | `Settings/SettingsView.swift` | ☐ |
| Settings · General | #1112 | `Settings/SettingsView.swift` | ☐ |
| Settings · General | #1073 sidebar material | `Design/GlassWindow.swift` (`SidebarMaterial`), `Settings/SettingsView.swift` | ☐ |
| Settings · Capture | #1113 | `Settings/SettingsView.swift` | ☐ |
| Settings · Quick Access | #1114 | `Settings/SettingsView.swift` | ☐ |
| Settings · Recording | #1115 | `Settings/SettingsView.swift`, `Settings/DevicePreview.swift` | ☐ |
| Settings · Shortcuts | #1116 | `Settings/ShortcutRecorderView.swift`, `Settings/SettingsView.swift` | ☐ |
| Settings · About | #1117 | `Settings/SettingsView.swift`, `Updater.swift`, `Permissions.swift` | ☐ |
| Gallery (dark) | #1119, after #1106–#1110 | `Design/BrutalStyle.swift` (dark values), `Gallery/GallerySidebar.swift`, `Gallery/GalleryView.swift` | ☐ |
| Settings · General (dark) | #1119, after #1111–#1117 | `Design/BrutalStyle.swift` (dark values and sidebar tints), `Settings/SettingsView.swift` | ☐ |

### Website

| Board | Issue | Files | QA |
| --- | --- | --- | --- |
| Site · components and motion | #1123 | `site/src/styles/global.css`, `site/src/layouts/Base.astro`, `site/src/components/` | ☐ |
| Site · components and motion › 404 | #1127 | `site/src/pages/404.astro` | ☐ |
| Site · landing page | #1124 | `site/src/pages/index.astro`, `site/src/components/HeroStage.astro`, `Loop.astro`, `Copy.astro`, `Window.astro`, `ForMacs.astro` | ☐ |
| Site · guide page | #1125 | `site/src/layouts/Prose.astro`, `site/src/pages/docs/[page].astro`, `site/src/components/GuideSearch.astro` | ☐ |
| Site · guide page › long-form text | #1127 | `site/src/pages/privacy/`, `site/src/pages/screenshot-apps/` | ☐ |
| Site · changelog | #1126 | `site/src/pages/changelog/index.astro` | ☐ |

### Whole-app checks

These run once across every board after phases 1–9, and tick nothing above.

| Check | Issue |
| --- | --- |
| Dark mode | #1119 |
| Accessibility | #1120 |
| Languages | #1121 |
| Performance | #1122 |

## Coverage: guide pages

Every page in `site/src/guide/`. #1128 updates the text, ticking **Updated** for each page. The build issues are the ones whose changes the page has to describe. #1129 reshoots the media in `docs/media` that these pages and the README use, and #1125 restyles all of them without Markdown changes.

| Page | What changes | Issue | Build issues | Updated |
| --- | --- | --- | --- | --- |
| 01 Get started | The stepped welcome window; the menu bar menu | #1128 | #1118, #1084 | ☐ |
| 02 Take a screenshot | The capture bar with magnifier, crosshair and size toggles; area, window and page highlights; the countdown panel; scrolling capture; the browser permission card | #1128 | #1075, #1076, #1077, #1078, #1086, #1087 | ☐ |
| 03 Quick Access | Copy and Save As… on hover; stacked cards; the pin bar; toasts | #1128 | #1081, #1082, #1083, #1085, #1114 | ☐ |
| 04 Record your screen | The check-before-recording bar; recording controls and paused state; border and click rings; camera bubble; discard and recovery | #1128 | #1088, #1089, #1090, #1091, #1092 | ☐ |
| 05a Annotate a screenshot | One tool group; Copy before Save; the Share menu; the style bar beside the selection; zoom control and hints | #1128 | #1093, #1094, #1095 | ☐ |
| 05b Crop and arrange | The crop bar and handles; the Layers panel | #1128 | #1097, #1098 | ☐ |
| 05c Style a screenshot | The Style side panel replaces the popover | #1128 | #1096 | ☐ |
| 05d Combine images | The Canvas menu; crop badges; reopening saved versions | #1128 | #1099 | ☐ |
| 06a Edit a recording | Toolbar with Export as the main button; timeline; crop and transform handles | #1128 | #1100, #1102, #1105 | ☐ |
| 06b Animate and annotate a recording | The Draw toggle and tool column; the Inspector in the side panel | #1128 | #1101, #1104 | ☐ |
| 06c Export a video or GIF | Export moves to a side panel | #1128 | #1103 | ☐ |
| 07 Find your captures | The gallery in its own window; grid, search and sort; the preview's details panel; the empty gallery | #1128 | #1106, #1108, #1109, #1110 | ☐ |
| 07a Organise your captures | Library, Folders and Tags in the sidebar; the selection bar; the Move to Trash dialog | #1128 | #1107, #1108, #1110 | ☐ |
| 08a Share a capture with an AI assistant | "Copy path for an AI assistant" in the preview; Copy Path in the Share menu | #1128 | #1109, #1093 | ☐ |
| 09 Keyboard shortcuts | M, C and I on the capture bar; Settings › Shortcuts | #1128 | #1075, #1116 | ☐ |
| 10 Automation reference | `shot://gallery` and `shot://settings?section=gallery` open the gallery window; `shot://welcome` | #1128 | #1106, #1118 | ☐ |
| 11 Settings | Section and row names, the sidebar search, Open Gallery | #1128 | #1111, #1112, #1113, #1114, #1115, #1116, #1117 | ☐ |
| 12 Languages | Check only: no redesigned screen is described | #1128 | #1121 | ☐ |
| 13 Updates | The restyled update prompt; Settings › About › Updates | #1128 | #1117, #1084 | ☐ |
| 14 Privacy | Permissions in Settings › About show Allowed or Allow… | #1128 | #1117 | ☐ |
| 15 Troubleshooting | The browser permission card; permissions in Settings › About; the recovery dialog | #1128 | #1087, #1117, #1092 | ☐ |
| 16 Removing Shot | Settings row names (Open Shot at login, Reset all settings) | #1128 | #1112, #1117 | ☐ |
