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
7. **No handwriting in the app.** Empty states and onboarding use the app's own type. On the website, handwriting appears in sticky notes only, never in text you need to read.
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
| Toast | A 36 pt dark pill in the Quick Access corner (see Toast), `rgba(26,26,30,0.90)` with a 0.5 pt `rgba(255,255,255,0.14)` edge and the system window shadow. Message in 13 medium white. One button: a `rgba(255,255,255,0.16)` pill in 12 semibold, with its key faded after it (Undo ⌘Z) | `Toast` |
| Progress bar | 6 pt, the progress track `rgba(22,22,26,0.08)` (dark `0.12` white) filled in ink. In a toast it sits after the message with the percentage in tabular figures | `BrutalProgressBar`, `Toast.progress(_:fraction:)` |
| Empty state | A 44 pt accent tile with a 1.5 pt ink outline and 2 pt drop, a 14 bold title, a 12 pt tertiary line and any buttons | `EmptyState` |

- **No handwritten note.** The boards put a note in Caveat above the empty gallery and empty Layers. #1169 took it out, so an empty state is the tile, the title and what to do next.
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

Edits and drags are always instant. Sounds follow the capture sound setting.

#1074 builds these on shared helpers. ShotCore's `Moment` holds each length and its Reduce Motion stand-in, with tests that keep every moment except the ambient loops under 300 ms. `Motion` in `Design/Motion.swift` turns them into animations, and `Motion.arrive` and `Motion.leave` replace Quick Access's own springs.

| Moment | Code | Notes |
| --- | --- | --- |
| Press | `BrutalButtonStyle` | Built by #1070, now timed by `Motion` |
| Viewfinder snap | `Capture/ViewfinderSnap.swift` | 4 pt ink brackets with a white edge fly in 14 pt from outside each corner, overshoot 2 pt and settle, with a 30% white flash. They hold for 180 ms, then fade. Shape layers, so a full-screen capture adds no memory |
| Copied tick | `Toast.done(_:drawsTick:)` | A 20 pt accent disc with an ink tick, for every copy and save. The toast rises 8 pt as it fades in. After a capture the snap is that action's moment, so the toast shows its tick already drawn |
| Marks land | `Editor/EditorCanvasView.swift` | A new counter grows to 122% and settles. An arrow is already whole when you let go of the drag, so it doesn't draw again |
| Countdown, recording pulse | `Design/BrandMark.swift` (`MenuBarAnimation`) | The digit folds flat and the next unfolds over 160 ms. While recording, the menu bar shows the time instead, and a ring breathes out of its stop square. A frame loop runs only while one plays. The countdown panel's ring is #1078 (see Countdown), and the recording controls' dot and the menu bar time are #1089 (see Recording controls) |
| Click ring | `Recording/ClickRings.swift` | Not on the Moments board. A click's ring holds for 0.4 s, then fades over 240 ms; Reduce Motion drops the fade (see Recording border and clicks) |

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
- **Modes.** ShotCore's `CaptureBarMode` maps the overlay's three targets and the browser page onto Area, Window, Full Screen and Browser. Browser is a window pick of just the page. Tab steps through Area, Window and Full Screen as before, and lands on Window rather than Browser, as Window's keycap says. Space does the same. B switches to Browser or back to Window from any mode. Browser asks for Accessibility the first time, as B did.
- **Layout.** `CaptureBarLayout` places the buttons and dividers, with tests. Sizes scale with Settings › Text size. `OverlayBarPlacement` and the 4 s fade are unchanged, and the fade now takes `Moment.panelArrive`'s length, or Reduce Motion's fade.
- **VoiceOver** finds each button as an element the overlay draws: modes as radio buttons, Scroll and the toggles as toggles, Delay as a button, each with its key in the help. A press shows the bar again. The crosshair and loupe aren't drawn while the pointer is on the bar, so they don't cover its buttons.
- **Increase Contrast and Reduce Transparency** make the bar and tooltip solid, take the edge to 40% white and the dividers to 60%.

### Area capture

#1076 builds Capture › Area capture: what you see while dragging out an area after ⌘⇧4. AppKit draws all of it into the overlay view, so nothing adds a screen-sized layer.

| Part | Look |
| --- | --- |
| Dim | `rgba(12,12,16,0.42)` outside the area while it's made, and 10% black before, as #1075 left it |
| Edge | 1 pt `rgba(255,255,255,0.95)` just outside the area, then 1 pt `rgba(0,0,0,0.35)` outside that |
| Handles | 10 pt white circles with a 1.5 pt ink edge, at the corners and the middle of each side of 48 pt or more. An area under 12 pt both ways has none |
| Size chip | The size in pixels, as the image will be, in 12 pt bold SF Mono, white |
| Ratio chip | "Free ratio", or the ratio such as "16:9" or "9:16", in Small type at 75% white (100% with Increase Contrast). Holding Shift shows 1:1 |
| Chips | `rgba(26,26,30,0.88)`, radius 8, 0.5 pt floating-panel edge, 3 × 9 pt padding, 6 pt apart, 14 pt above the area's top-left corner |
| Loupe | 132 pt circle showing 11 × 11 device pixels, so the pointer's pixel is in the middle. 3 pt white ring, 1.5 pt ink ring, `0 12px 28px rgba(0,0,0,0.4)`. Grid lines one device pixel wide in mid-grey at 30%. The pointer's row and column in accent (`#FFD43B`) at 35%. The pointer's pixel outlined in 1.5 pt ink with a white hairline outside |
| Position chip | The pointer's pixel, from the screen's top-left, in 10 pt medium SF Mono on the 0.88 fill, radius 5, 10 pt above the loupe's bottom |
| Cursor | 18 pt crosshair, white 3 pt under ink 1.2 pt, with a 4 pt gap in the middle. Replaces the system crosshair everywhere on the overlay |
| Guides | The crosshair toggle (C): lines across the screen, 1 pt white at 90% over 3 pt black at 25%, stopping 12 pt short of the pointer |

- **No key-hint strip.** The board draws ⇧ Square, R Ratio, X Turn, Space Move and Esc Cancel in a floating strip at the bottom. The bar already hides while you drag, so the strip wouldn't collide with it. It's left out anyway, because rule 2 and the mantra keep extra panels closed by default. It would also flash across the screen on every capture for a quick sharer who never uses those keys. The keys stay in the overlay's VoiceOver help and the guide's table, and the ratio chip shows when a ratio is in force.
- **Toggles stay as they were.** Size (I) shows both chips. A ratio other than Free shows its chip even with Size off, since it changes what you get. Magnifier (M) and Crosshair (C) show the loupe and guides. All three start off, as before.
- **Loupe and guides while dragging.** The board draws them at the drag corner, so they now show while dragging as well as before it, which is when an exact edge matters. They don't show for an area made with the arrow keys, since the pointer is elsewhere, or while the pointer is on the bar.
- **Placement.** `AreaLabelPlacement` puts the chips above the area, else below it, else inside its top-left corner, kept 8 pt inside the screen and off the bar. `Loupe.frame` puts the loupe 22 pt from the pointer on the side away from where the drag started (below and right before dragging), and turns to the next corner at a screen edge or when it would cover the chips or the bar. Both are in ShotCore with tests.
- **Departures from the board.** The board's grid is ink at 7%, which vanishes over dark pixels, so it's mid-grey. The lit row and column skip the pointer's own pixel, so its true colour shows, and that pixel's ink outline gains a white hairline so it shows over dark pixels. The coordinates are in pixels rather than points, matching the size chip.
- **Text size.** The chips, the position chip and the loupe scale with Settings › Text size. The handles and cursor don't.
- **Increase Contrast and Reduce Transparency** make the chips solid with the 40% edge, and the position chip solid.

### Pick Colour

#1080 builds the colour loupe on Capture › Permission card, colour loupe…. Shot draws it over a still of every display, taken with its own windows in, so the editor's eyedropper can pick from the image open in it. `ColorPickerOverlay` in `Overlay/` draws it, and `ColorSampler.sample(for:)` opens it.

| Part | Look |
| --- | --- |
| Loupe | 121 pt circle (the board's 120, in 11 whole-point cells) showing 11 × 11 device pixels, centred on the pointer, which is hidden. 3 pt white ring, 1.5 pt ink ring, `0 12px 28px rgba(0,0,0,0.3)` |
| Grid | Lines one device pixel wide in mid-grey at 30% |
| Middle pixel | 1.5 pt ink round it, then 1.5 pt white, both outside it |
| Label | 10 pt below the rings. Floating-panel fill at 0.92 with its 0.5 pt edge, radius 9, padding 4 10 4 5. A 16 pt swatch, radius 4, with a 1 pt white edge at 40%, then the hex in 12.5 pt bold SF Mono |
| Hint | 10 pt below the label. "Click to copy · Esc to cancel" in 11.5 pt `#3A393F` on white at 85%, radius 8, padding 2 8. From the editor's eyedropper it says "Click to pick" |

- **Picking.** A click, Return or Space picks the middle pixel, as sRGB. The arrow keys move the pointer one device pixel, or ten with Shift, and VoiceOver says each new hex. Esc or a right-click cancels. From the menu, the hex is copied and the toast says "Copied #1E90FF".
- **Placement.** `ColorLoupe.layout` in ShotCore centres the loupe on the pointer and puts the label and hint below it, or above it near the bottom of the screen, each kept 8 pt inside the screen. The loupe itself can run off the edge, so its middle stays on the pixel picked. `PixelColor` converts the pixel from the display's colour space to sRGB. `ColorLoupeTests` covers both.
- **Without Screen Recording** Shot can't take the still, so the system loupe shows instead, as before. It needs no permission.
- **Departures from the board.** The board's grid is ink at 6%, which vanishes over dark pixels, so it's mid-grey, as in the area overlay's loupe. The label gains the floating panel's 0.5 pt edge so it shows over dark content.
- **Text size.** The loupe, label and hint scale with Settings › Text size.
- **Increase Contrast and Reduce Transparency** make the label solid with the 40% edge. Increase Contrast also makes the hint solid white with a 40% ink edge, and the swatch's edge 80%.

### Window pick

#1077 builds the highlights on Capture › Window pick and delay: what you see over the window, browser page or screen a click would capture, after Tab, B or Full Screen on the overlay. AppKit draws it into the overlay view, as it does the area.

| Part | Look |
| --- | --- |
| Dim | `rgba(12,12,16,0.34)` outside a highlighted window or page. None for a screen, which fills the view |
| Tint | Accent (`#FFD43B`) at 16% over what's highlighted |
| Edge | 3 pt accent just inside the edge, then 1.5 pt ink inside that, on whole device pixels |
| Corners | Panel radius (14) on a whole window, close to the window's own corners. A page and a screen are square, as captured |
| Camera | A 64 pt circle at the floating-panel fill (0.86) with its 0.5 pt edge and shadow, holding a 24 pt white `camera` symbol |
| Name panel | The window's title in Window type, white, cut short past 420 pt. Under it the size in pixels in 11.5 pt medium SF Mono at 75% white, then "· with shadow" when Settings › Capture › Window shadow is on. Floating-panel fill, panel radius, 8 × 14 pt padding |
| Hint | "Click or press Return to capture", then "Arrows: next window" for a window, in 12 pt ink on a `rgba(255,255,255,0.9)` pill |
| Stack | Camera, name panel and hint, 10 pt apart, in the middle of what's highlighted |

- **Accent, not selection blue.** The board and the issue both draw the highlight in the accent. Rule 6 keeps selection blue for marks, layers and files inside Shot's windows, while the overlay is choosing what to capture, the same job as the picked mode on the bar. The highlight is never in the image, so rule 5's ban on fills behind windows doesn't apply.
- **Names.** A window shows its title, else its app's name (the title needs Screen Recording access), else "Window". A screen shows the display's name, else "Screen". The size is the window's, page's or screen's in pixels, as the area's size chip gives it, and doesn't include the shadow.
- **Fewer parts in a small window.** `WindowPickLabel.layout` in ShotCore drops the camera when the stack doesn't fit 12 pt inside what's highlighted, then the hint, leaving the name panel. It centres the stack on the part that's on screen, keeps it 8 pt inside the screen, and moves it just above or below the bar or its tooltip when it would cover them. `WindowPickTests` covers it.
- **The hint stays.** Unlike the area's key strip, it sits inside the window being picked and says how to finish, so it is the first thing a quick sharer needs. Delay's countdown is #1078 (see Countdown).
- **Keyboard.** The arrow keys step through windows as before. VoiceOver reads the name and size of each window it steps to, and the overlay's value holds the highlighted window's name and size. Stepping in Browser now finds the page of the window it lands on.
- **Text size.** The camera, the name panel and the hint scale with Settings › Text size. The tint and edges don't.
- **Increase Contrast and Reduce Transparency** make the camera and name panel solid with the 40% edge, take the size to full white, and make the hint pill solid white with a 1 pt edge of ink at 40%.

### Countdown

#1078 builds the countdown on Capture › Quick Access, pin, menu and toasts: the panel you see after picking an area, window or screen with Delay on, and before a recording when Settings › Recording sets a countdown. It is SwiftUI in its own `FloatingPanelWindow`, about 180 pt square, so it adds no screen-sized layer.

| Part | Look |
| --- | --- |
| Panel | Standard floating panel with the system shadow, radius 22, 20 pt above the ring and 14 pt below Cancel, 12 pt between parts |
| Ring | A 92 pt frame holding an 80 pt circle drawn 6 pt wide: the track in white at 14% (40% with Increase Contrast), and the accent over it with round ends, starting at the top and running clockwise |
| Seconds | 40 pt bold, tabular figures, white, in the middle of the ring |
| Hint | "Open the menu you need" in 12 pt at 75% white (100% with Increase Contrast). A screenshot only |
| Cancel | "Cancel · Esc" as a floating secondary button, `BrutalButtonStyle(floating: true)` |

- **The ring empties with real time.** At each tick it shows the seconds left as a share of the whole delay, so 3 of 5 seconds leaves 60% of it, as on the board. It then drains one second's worth, linearly over that second, and reaches empty as the capture is taken. `CountdownRing` in ShotCore works out both values, with tests. The drain is `Moment.countdownRing`, a 1 s loop counted with the ambient moments, since rule 3 lets the countdown tick with real time.
- **The number rolls down** over `Moment.countdownFlip`'s 160 ms, the same length as the menu bar digit's flip. The menu bar is unchanged from #1074.
- **Reduce Motion** stops the ring's drain and the roll. The ring steps to the seconds left at each tick, and the number changes in place.
- **Bold, not heavy.** The board sets the seconds at weight 800. Rule 9 keeps heavy weights to the app icon, onboarding and empty states, so they're bold.
- **Cancel is the standard floating button.** The board draws a smaller 12 pt button on a 14% fill. It uses the floating secondary button instead (12% fill, group radius), so it matches Cancel everywhere else on a floating panel.
- **Where it sits.** A screenshot's countdown stays at the bottom middle of the screen with the pointer, 170 pt up, clear of the menu bar and of whatever menu you're about to open. A recording's sits in the middle of the area being recorded. Both leave the screen before the capture is taken.
- **Recording** shares the panel without the hint, since there's no menu to open, and VoiceOver says "Recording in 3 seconds" instead of "Capturing in 3 seconds".
- **VoiceOver** reads the panel's label with the seconds left, which updates each second. It announces the whole label when the countdown starts, then each number. Cancel is read as "Cancel".
- **Keyboard.** Esc works while the panel is key. Shot isn't activated, so a menu you open stays open, and Cancel always works with the pointer.
- **Text size.** The ring, the number, the hint and Cancel scale with Settings › Text size, and the panel grows to fit.
- **Increase Contrast and Reduce Transparency** make the panel solid with the 40% edge, and Increase Contrast also brightens the track and the hint.

### Scrolling capture

#1086 builds Capture › Scrolling capture: the panel beside the area while you scroll it yourself. It is SwiftUI in its own `FloatingPanelWindow` with the system shadow, 300 pt wide, and grows to fit what it shows.

| Part | Look |
| --- | --- |
| Panel | Radius 16, `#FAF9F6` in light and the popover grey `#2C2C30` in dark, with a 0.5 pt edge at black 25% (white 14% in dark) |
| Header | An 8 pt status dot, then the heading in 14 pt bold, and the detail under it in 12 pt tertiary text. 16 pt padding, 12 pt below, and a separator under it |
| Status dot | Success green with a 3 pt ring of it at 22% while frames are being added; tertiary text otherwise |
| Preview | 150 × 280 pt at group corners and Group depth. The image so far sits against the side away from the frontier, over hatching of 6 pt stripes every 12 pt at ink 10% on the Window colour. The room past the frontier stays hatched with a "Not yet" label, and at least 40 pt of it is kept while the image can still grow. A 2 pt accent line with a 0.5 pt ink edge marks the area's frontier side |
| Facts | Size and Frames kept in 13 pt bold tabular SF Mono, Sticky header in 12 pt semibold, each under a 12 pt tertiary label, 14 pt apart |
| Warning card | At the foot of the facts column: `#FFF4D6` (accent at 14% in dark), a 1 pt `#8A6A00` edge at 25%, control corners, the title in 12 pt semibold and the advice in 12 pt, both `#6B4F00` (`#F2CC4A` in dark) |
| Footer | "Esc discards" in 11 pt tertiary text, Cancel as a secondary button and "Done ↩" as the main button. 12 × 16 pt padding under a separator |
| Outline | 1.5 pt accent against the area, with 1.5 pt ink outside it |

- **The frontier is where the image grows.** `ScrollFrontier` in ShotCore follows the side the image last grew on, so scrolling up puts "Not yet" and the edge at the top and scrolling sideways puts them at the side. `ScrollPreviewLayout` places the image, the room and the edge, and `ScrollPreviewLayoutTests` covers it. Once the image reaches the size limit, nothing is marked "Not yet".
- **Frames kept and the sticky header come from the stitcher.** Frames kept counts the frames the saved image is built from, or every frame painted when those had to be given up. Sticky header reads "Kept once" from the first time a band sticks to the top edge, and "None found" until then.
- **Headings.** "Start scrolling" before anything moves, "Keep scrolling" while capturing and during a warning, and "Full size" at the size limit, each with its own detail line. The warnings keep their titles, Scrolled too far, Can't line up and Nothing to line up, with shorter advice that fits the card.
- **It follows the appearance.** The other floating panels are dark in both appearances, but the board draws this one light, and it holds a preview and facts to read, like a popover. In dark it takes the popover grey.
- **Solid, not 96%.** The board's fill is 96% opaque. Text behind the panel showed through it, so the fill is solid in every mode, which also covers Increase Contrast and Reduce Transparency.
- **The outline doesn't change colour.** It used to turn red for a warning and green while capturing. Rule 6 keeps red for recording and loss, and the warning card says what's wrong, so the outline stays the board's accent and ink.
- **No dimmed screen.** The board dims everything outside the area. That would need a screen-sized window over the content being scrolled, so it's left out.
- **Keyboard.** Return, Enter and the screenshot shortcut finish, and Esc cancels, while the content's app keeps the keyboard. Cancel shows "Esc" in its tooltip and Done shows "↩".
- **VoiceOver** reads the panel as "Scrolling capture", the header as one element, each fact as one element and the preview as "Preview of the image so far". A warning is announced with its title and advice when it appears.
- **Text size.** The header, facts, card and buttons scale with Settings › Text size, and the panel grows to fit. A long size shrinks to 70% before it would wrap. The preview stays 150 × 280.
- **Increase Contrast** takes the panel's edge to 50% black (40% white in dark), the warning card's edge to 60%, and the hatching to 22%.

### Browser permission card

#1087 builds the card on Capture › Permission card, colour loupe…: what you see after picking Browser on the capture bar, by click or `B`, while Shot has no Accessibility access. It used to close the overlay and open macOS's prompt with no word of why. It is SwiftUI in its own `FloatingPanelWindow` with the system shadow, just above the overlay's level, so it adds no screen-sized layer.

| Part | Look |
| --- | --- |
| Card | Floating panel, 300 pt wide, panel radius 14, 18 pt padding, 10 pt between parts. The fill is `FloatingPanel.Opacity.card`, 92%, as on the board |
| Icon | `globe` at 18 pt semibold, white, in a 36 pt tile of white at 12% with group corners |
| Title | "Browser needs Accessibility" in 15 pt bold, white |
| Detail | What Shot uses the permission for, in 12.5 pt at 75% white |
| Buttons | Use Window as the floating secondary button and Grant Access as the floating main button, 8 pt apart and 4 pt below the detail. Grant Access is 1.3 times as wide, as on the board |

- **Where it sits.** Centred on the bar and 16 pt above it, or below it when the bar is at the top. After `B` with the bar faded, it sits in the middle of the screen with the pointer. `PermissionCardPlacement` in ShotCore keeps it 8 pt inside the screen, with tests.
- **The overlay waits.** The mode doesn't change under the card. Use Window switches to Window and gives the keyboard back, Esc or a click anywhere on the overlay closes the card in the mode you were in, and that click doesn't capture.
- **Grant Access closes the overlay first,** then shows macOS's prompt, which would otherwise sit behind the overlay. The next capture can use Browser once access is on.
- **Panel corners.** The board rounds the card at 16 and its buttons at 9. It uses the panel and group tokens, 14 and 10.
- **Keyboard.** The card is key while it shows. Return grants access and Esc closes it. With keyboard navigation on, Tab moves between the buttons, which show the accent focus halo.
- **VoiceOver** announces the title and detail when the card appears, since VoiceOver stays on the overlay under it. The card is a group named by its title, the title is a heading, and both buttons are read by name, with tooltips saying what each does.
- **Text size.** The card is 300 pt times Settings › Text size wide, so the detail wraps as on the board, and it grows to fit the text.
- **Increase Contrast and Reduce Transparency** make the card solid with the 40% edge. Increase Contrast also takes the detail to full white and the icon tile to 24%.

### Quick Access card

#1081 builds the card on Capture › Quick Access, pin, menu and toasts: the picture of each capture that slides into a bottom corner of the screen. The cards share one `FloatingPanelWindow` with the system shadow, so the shadow follows each card and no margin catches clicks.

| Part | Look |
| --- | --- |
| Card | 280 pt wide, panel radius (14), white, with a 0.5 pt edge of black at 30%. Its height follows the capture's shape from 158 to 210 pt, and the capture fills it, cropped to the middle rather than letterboxed |
| Scrim | On hover, `FloatingPanel.scrim` over the whole card, fading in over `Motion.fade` |
| Copy | The one ink control, a floating main button, 14 pt semibold, at least 132 pt wide |
| Save As… | A white secondary button, 14 pt medium, as wide and tall as Copy, 8 pt below it |
| Corner buttons | 26 pt circles at the corner-button opacity (0.78) with the floating-panel edge, 8 pt in from the card's edges. Close top left, Annotate top right, Pin to Screen bottom right. A recording has Edit Video and Export GIF top right instead, and no Pin |
| Drag chip | "Drag into any app" in 10.5 pt at 85% white after a 10 pt move symbol, on a capsule at the corner-button opacity, bottom left |
| Length | A recording's length as a strong badge in tabular figures, bottom right, shown at rest and on hover |

- **The resting card is just the capture.** The scrim, buttons and drag chip show on hover only, as before, so the quick sharer sees the picture and nothing else until they reach for it. A recording's length is the one exception, since it's what tells a recording from a screenshot now the play disc is gone.
- **Pin replaces Show in Finder.** The board puts Pin to Screen in the bottom-right corner, so Show in Finder moves to the right-click menu, which keeps every action: Copy, Copy Path, Save As…, Annotate (or Edit Video and Export GIF), Pin and Show in Finder.
- **Save As… is the light secondary button.** The board draws it white at 94% with a soft shadow and group corners. It uses `BrutalButtonStyle()` in the light appearance instead, white with the Rest edge and control corners, so it keeps the focus halo and matches secondary buttons elsewhere. The floating secondary button, white at 12%, would be too faint over a bright capture.
- **Corner buttons keep the floating-panel edge.** The board draws their edge at 20% white. They use `floatingPanel`'s 14%, so they match every other floating panel.
- **Card size.** `QuickAccessLayout` in ShotCore holds the width and the height limits, and `cardHeight(for:)` works the height out from the capture's size, with tests.
- **Shadow.** The system shadow is worked out again once a card has slid in and whenever the panel changes size, so it doesn't lag behind a new card.
- **Reduce Motion** slides nothing: cards fade in and out, and the scrim appears at once.
- **VoiceOver** reads the card as "Screenshot" or "Recording" and the file name, with "Drag into any app" as its hint. Each corner button reads its name, and the drag chip and length badge are hidden from it.
- **Text size.** Copy, Save As…, the drag chip's label and the length badge scale with Settings › Text size. The card and the corner buttons don't.
- **Dark appearance** changes nothing: the card is the capture, the scrim and corner buttons are floating panels, and Save As… stays white.
- **Increase Contrast and Reduce Transparency** make the corner buttons and drag chip solid. Increase Contrast also takes their edge to 40% white and the card's edge to 1 pt of black at 60%.

### Quick Access stack

#1082 builds the stack on Capture › Quick Access, pin, menu and toasts: how cards pile up when you take captures back to back. All the cards stay in the one `FloatingPanelWindow`, which is only as tall as what's drawn.

| Part | Look |
| --- | --- |
| Front card | The newest capture, as the card above, 10 pt in from the panel's corner |
| Cards behind | Every older card, at 94% of the front card's size, shrunk towards its bottom middle, with its top edge 14 pt above the front card's. Covered in `#2A2A2E` (`FloatingPanel.cardBehind`), with the card's 0.5 pt edge |
| Fanned out | While the pointer is on the stack, every card shows in full at its own height, 14 pt apart, the newest lowest and the oldest at the top |
| Movement | A new card slides in from its corner and the old front card moves behind it, on `Motion.arrive`. Fanning out uses `Motion.arrive`, and folding back and closing use `Motion.leave` |

- **Older cards fan out on hover.** Pointing at the front card or the edge behind it fans the stack out, and the front card stays where it was, so Copy never moves under the pointer. Each card then has its own hover buttons, drag and right-click menu. The stack folds back once the pointer leaves the panel, through a gap between cards included. With one card nothing changes.
- **All the older cards share one place.** The board draws one card behind. Every older card sits there, so the stack never shows more than one edge however many cards wait, and the next card is already in place when the front one closes.
- **The cards behind are the board's dark fill.** Their 14 pt edge is too thin to show the capture or a recording's length badge, which the board places on the card behind, so both show once the stack fans out.
- **The board's card behind would be hidden.** Its CSS puts the back card's top 1.6 px below the front card's, so it would never show. The build keeps the 0.94 scale and uses the board's 14 pt lift as the edge that shows. The card behind also takes the front card's height, so none of it shows below a shorter front card.
- **Timers wait while the pointer is on the stack.** Each card still has its own timer, but none closes a card while the pointer is anywhere on the panel, so a fanned-out card never moves under the pointer. Leaving a card restarts its timer, as before. Five cards at most, and a sixth closes the oldest.
- **Layout.** `QuickAccessLayout(cardHeights:fannedOut:)` in ShotCore places each card (its height, scale and drawn frame) and sizes the panel, and `card(at:)` finds the frontmost card at a point, with tests. The panel grows at once and shrinks only after the cards stop moving, so nothing is clipped mid-move, and the system shadow is worked out again then.
- **Reduce Motion** fades a new card in and out and puts every other card in place at once, fanned or folded, with no slide.
- **VoiceOver** reads the newest card first. Each card offers Close and the right-click menu's actions as VoiceOver actions, so any card can be used or closed without hovering, folded or not.
- **Text size.** The stack's sizes and gaps don't scale. The labels on each card do, as above.
- **Dark appearance** changes nothing, as for the card.
- **Increase Contrast** takes the edge of a card behind to 1 pt of white at 40%, since it's dark.

### Pinned capture

#1083 builds the pin on Capture › Quick Access, pin, menu and toasts: a capture floated above other windows from a card's Pin to Screen. Each pin is its own `FloatingPanelWindow` with the system shadow, and the bar is drawn inside it, so no margin catches clicks.

| Part | Look |
| --- | --- |
| Pin | The capture at the size `PinLayout` gives it, with group corners (10) and a 1 pt edge of `#16161A` at 18% |
| Bar | 6 pt in from the pin's left, right and top, padding 3, gap 4, a `floatingPanel` at the pin-bar opacity (0.82) with group corners |
| Close | A floating toolbar button with a 10 pt bold ✕ |
| Label | "Pinned · 100%" in 10.5 pt tabular figures at `FloatingPanel.secondaryText`, before the spare width |
| Opacity slider | A floating `BrutalSlider`, 60 pt wide: a 3 pt track of white at 25%, filled in white up to a 12 pt white knob. It runs from 20% to 100% |
| Click Through | A floating toolbar button with a 12 pt pointer, filled at white 16% while it's on |

- **The bar starts hidden.** It shows while the pointer is on the pin or the pin is focused, and fades over `Motion.fade`, as Close did before. A pin at rest is just the capture, so Rule 2 holds.
- **A pin starts solid.** The board shows 80% as an example, and a new pin is 100%. Opacity changes the capture only, so the bar stays readable at 20%. `PinOpacity` in ShotCore clamps it, steps it and makes the label's percentage, with tests.
- **Click Through lets clicks reach the window under the pin.** The bar's strip still takes clicks while it's on, so the same button turns it off again. While it's on, the pin watches the pointer with event monitors, which need no permission, to show the bar and to take clicks in the strip only. `PinLayout.barStrip(in:barHeight:)` gives the strip, with tests. The monitors stop when Click Through goes off or the pin closes.
- **The buttons are the floating toolbar buttons.** The board draws 22 pt transparent squares with control corners. `BrutalButtonStyle(.toolbar, floating: true)` is 36 × 32 with group corners, so the bar is 38 pt tall rather than 28, and the buttons stay above the 24 pt minimum target size and match the other floating bars.
- **The slider has a knob.** The board draws only a track. The knob shows the slider can be dragged and holds the focus ring.
- **The bar keeps the floating-panel edge.** The board draws none. It uses `floatingPanel`'s 0.5 pt edge at 14%, so it matches every other floating panel and stays apart from a dark capture.
- **A narrow pin drops the label, then the slider,** so Close and Click Through always fit.
- **See-through captures float as they are.** A styled capture, or one with transparent pixels such as a window with its shadow, has no frame and no window shadow, and its transparent margin shows the screen through it. This fixes the margin showing as black. The bar is inset from the image's edge, margin included. A capture with no transparency gets the board's frame in place of the 2 pt ink frame on black.
- **Keyboard.** The first click on a pin focuses it and also reaches what's under the pointer, so the slider moves on that click. Once focused, Esc closes it, ↑ and ↓ step its opacity by 10%, and Full Keyboard Access reaches the bar's buttons and slider, whose arrow keys step by 1%, ⇧ by 10%. macOS gives no way to focus a pin without clicking it, since it never takes focus from the app in front.
- **Reduce Motion** shows and hides the bar at once.
- **VoiceOver** reads "Pinned" and the file name, with the opacity as its value. The image is adjustable, so swiping up or down steps the opacity, and it offers Close and Click Through as actions, so a pin can be used without hovering. The slider reads "Opacity".
- **Text size.** The label scales with Settings › Text size, and the bar grows to fit it. The buttons, the slider and the frame don't.
- **Dark appearance** changes nothing: the pin is the capture and the bar is a floating panel.
- **Increase Contrast and Reduce Transparency** make the bar solid. Increase Contrast also takes its edge to 40% white, the slider's track to 50% white and the pin's edge to 60%.

### Menu bar menu

#1084 builds the menu on Capture › Quick Access, pin, menu and toasts: the menu that opens from Shot's icon in the menu bar. It stays a native `NSMenu`, so macOS draws the status item's highlight and the whole menu around Shot's items, and keyboard navigation, type-to-select and VoiceOver work as in any other menu. `StatusMenu` is an AppKit `NSStatusItem` rather than SwiftUI's `MenuBarExtra`, because only AppKit lets a menu item hold a view, which the Recent row needs.

| Part | Look |
| --- | --- |
| Top rows | Screenshot (`viewfinder`), Record (`record.circle` in record red), Pick Colour (`eyedropper`) and Gallery (`square.grid.2x2`), each with a 13 pt regular SF Symbol and the shortcut set in Settings |
| Recent | A divider, the native "Recent" section header, and a row of up to four 60 × 40 thumbnails, 6 pt apart, the first lined up with the icons above |
| Thumbnail | The capture cropped to fill, tiny corners (4), a 1 pt edge of ink at 12% (white at 12% in dark), and a badge bottom right: PNG, JPG or GIF, or a recording's length, in 8 pt bold white on ink at 75% |
| Bottom rows | Settings… (⌘,), Check for Updates… (Update to Shot N… when one is waiting) and Quit Shot (⌘Q), with the icon column left empty |
| Recording | Stop Recording and Pause Recording (Resume Recording while paused) come first, and Record and Pick Colour are left out, as before |

- **The board's yellow Screenshot row is the hover state on a mock.** A native menu draws its own highlight in the system accent colour, so no row is yellow and Rule 6 is unaffected. Its 11 pt menu radius, 6 pt row radius and the status item's 30 × 22 highlight are also drawn by macOS.
- **Icons are templates, so the menu tints them.** They take the menu's text colour rather than the board's `#3A393F`, and turn white on the highlight. Record keeps its red, as on the board.
- **Pick Colour uses an eyedropper.** The board draws a palette, but the action samples a colour from the screen and copies its hex.
- **"Open Gallery" is now "Gallery",** as on the board, and it sits with the actions rather than after a divider.
- **The Recent row shows one thumbnail for each capture.** An image saved again from the editor as "X (2).png" stands in for "X.png", as `Gallery.latest` does for Copy Path. `RecentCaptures` in ShotCore picks the four and makes each badge, with tests.
- **The row never holds the menu up.** `RecentCapturesStore` reads the save folder and decodes 240-pixel thumbnails off the main thread at launch and each time the menu opens, and keeps what it found. The menu shows the last pictures at once and swaps in anything newer while it's open. The section is hidden while the save folder has no captures.
- **Thumbnail corners are tiny (4).** The board draws 5, and the tiny token is the one for thumbnails. The badge keeps the board's 3, since 4 would make it a pill at its 11 pt height.
- **Click opens, drag shares.** Clicking a thumbnail opens it in the image editor, or the video editor for a recording or an exported GIF. Dragging one gives another app the file, and the menu closes when the drop lands. The thumbnail under the pointer gets a 2 pt ring in the system accent colour, to match the row highlight.
- **Keyboard.** A menu keeps the arrow keys and Return to itself, so a view inside it can't take them. Down reaches the Recent row like any other row, and it draws the native row highlight behind the thumbnails. Right then opens a native submenu listing the same captures, each with a small thumbnail and a name such as "Screenshot, 5 minutes ago", and Return opens the one picked. The submenu is attached only when the keyboard lands on the row, so it never pops out while the pointer aims at a thumbnail.
- **Reduce Motion** changes nothing: the menu has no motion of its own.
- **VoiceOver** reads the row as "Recent captures" and each thumbnail as a button named by its kind and age, such as "Screenshot, 5 minutes ago", with a hint that it opens to edit and can be dragged into another app. The keyboard's submenu reads the same names.
- **Text size.** The menu is native, so Settings › Text size doesn't reach it, as it doesn't reach any AppKit menu. It follows macOS's own menu size.
- **Dark appearance.** A status menu follows the menu bar's appearance, not Settings › Appearance, as it did before. The thumbnail edge and the record red follow it.
- **Increase Contrast and Reduce Transparency** are handled by macOS, which draws the menu solid. The thumbnails' edge and badge stay as they are.

### Toast

#1085 builds the toast on Capture › Quick Access, pin, menu and toasts: the dark pill that confirms a copy or save, offers Undo after a discarded recording, and shows how far a GIF export has got. Every toast reuses one SwiftUI `FloatingPanelWindow` sized to the pill, with the system shadow, so no margin catches clicks.

| Part | Look |
| --- | --- |
| Pill | 36 pt tall, Full radius, `rgba(26,26,30,0.90)` with a 0.5 pt `rgba(255,255,255,0.14)` edge. 9 pt in from the left before a tick and 14 pt otherwise, 14 pt in from the right (6 pt after a button), and 10 pt between parts |
| Tick | A 20 pt accent disc holding the board's tick, `M5 12l5 5 9-10` drawn 11 pt square with a 1.6 pt `#16161A` stroke and round ends. It leads every `Toast.done` and draws itself over 240 ms (`Moment.tick`) |
| Message | One line of 13 pt medium white, such as "Copied" or "Saved Screenshot 2026-11-07 at 10.42.png" |
| Button | One `rgba(255,255,255,0.16)` pill in 12 pt semibold: Undo with ⌘Z faded after it, Cancel, or Show |
| Progress | A 96 pt `BrutalProgressBar` after the message, then the percentage in tabular figures |
| Place | The Quick Access corner chosen in Settings, left by default, with the pill's outer edge in line with the cards'. With cards showing on the same display it rests 22 pt above them, and otherwise it sits where a card would |

- **The board's 24 pt from the right and 236 pt from the bottom** are where its card stack happens to sit on a 1280 × 800 mock. Shot keeps how the toast relates to the cards rather than the numbers: its edge lines up with theirs, 30 pt in from the screen's side (`QuickAccessController.inset` plus the stack's 10 pt padding), and it rests 22 pt above their top, as on the board. `ToastLayout` in ShotCore works out the frame and keeps it on screen above a tall fanned-out stack, with tests. Toasts used to sit in the bottom middle of the screen.
- **A toast that changes size keeps its edge.** When a progress toast's text or bar changes width, it grows away from the screen's side rather than from its middle.
- **36 pt rather than 34.** The board pads the 20 pt disc by 8 pt above and below, so the pill grew 2 pt. Its radius stays the Full token: the board's 20 is more than half of 36, so it draws a pill too.
- **The shadow is the system window shadow,** as for every floating panel, in place of the board's `0 10px 28px rgba(0,0,0,0.35)`.
- **The tick is thinner and smaller than before.** It used to be its own 2.2 pt path filling most of the disc. It now draws the board's path and its 3.4-unit stroke, which the Moments of delight board shares.
- **One moment per action.** After a capture with Quick Access off, the viewfinder snap is the moment, so the toast's tick shows already drawn.
- **Reduce Motion** swaps the 8 pt rise for a 120 ms fade (`Moment.reducedFade`), and the tick shows already drawn.
- **VoiceOver** announces each toast's message at high priority, as the board's `role="status"` would. A progress toast updates in place without reading every step. The button is a button, and the tick is hidden.
- **Keyboard.** The panel never becomes key, so ⌘Z presses Undo from any app while an undo toast shows. The pointer holds a toast, and a click dismisses it.
- **Text size** scales the message, button and percentage. The pill stays 36 pt tall, which fits 13 pt at Larger (17 pt), and the disc and tick keep their size.
- **Dark appearance** changes nothing: the toast is a floating panel, dark in both.
- **Increase Contrast and Reduce Transparency** make the pill solid. Increase Contrast also takes its edge to 40% white and the percentage to full white.

### Check before recording

#1088 builds Record › Check before recording: what you see after picking an area, window or screen to record when Settings › Recording › Adjust before recording is on, or when ⌥ is held as the pick ends. The frame is one panel the size of the screen, which ignores the mouse, and the bar is SwiftUI in its own `FloatingPanelWindow` with the system shadow. The camera bubble is #1091 (see Camera bubble).

| Part | Look |
| --- | --- |
| Dim | `rgba(12,12,16,0.46)` outside the frame, on the screen it's on. Four plain layer colours, so a large screen costs no bitmap |
| Edge | 1 pt `rgba(255,255,255,0.95)` just outside the frame, then 1 pt `rgba(0,0,0,0.35)` outside that, as on the area overlay |
| Handles | 10 pt white circles with a 1.5 pt ink edge at the corners and the middle of each side, each in a 20 pt panel you can grab |
| Chip | The size in pixels, then the ratio when the area was picked with one ("1040 × 1040 · 1:1"), in 12 pt bold SF Mono, white, on the floating fill at 88% with its 0.5 pt edge, radius 8, 3 × 9 pt padding, 14 pt above the frame's top-left corner |
| Bar | Standard floating panel, radius 16, 7 pt padding, 6 pt between parts, 22 pt under the frame. It grows to fit its labels and stays centred under the frame |
| Mode | `BrutalSegmented` with Area, Window and Full Screen |
| Microphone | The microphone's name in Small type over ten 5 × 4 pt level bars: success green, amber `#FFB648` for the top two, and white at 18% unlit |
| Toggles | Camera, Mac sound and Cursor, each a symbol and its name. On: the 16% white fill, white and semibold. Off: no fill, 70% white, and the symbol struck through |
| Frame rate | "60 fps" in 12 pt bold SF Mono with a chevron, opening a `BrutalDropdown` of the rates the screen offers |
| Buttons | Cancel as the floating secondary button, and Record as the floating main button: a 13 pt red dot with a 1.5 pt ink ring, "Record", and a faded ↩. Both 38 pt tall, as are the toggles |

- **Choices for this recording only.** The toggles and the frame rate start from Settings › Recording and change only the recording about to start, as the camera, microphone and cursor toggles did before. `Recorder.Options` now carries Mac sound and the frame rate too. Picking a screen that can't refresh as fast steps the rate down to the fastest it offers.
- **The meter runs before you record.** Turning the microphone on starts it through `DevicePreview`, so the bars move as you speak, and it stops before a countdown or the recording opens the microphone. macOS asks for the permission here the first time, and a refusal turns the toggle off. `LevelBars` in ShotCore works out how many bars are lit, with tests.
- **The dim.** `RecordSetupFrame.dimRects` in ShotCore lays out the four rects around the frame, and `RecordSetupFrame.label` writes the chip's text, with tests. The chip uses `AreaLabelPlacement`, kept below the menu bar and off the bar and the move grip. Clicks go through the dim to the apps under it, so you can still set them up.
- **The move grip stays.** The board draws no way to move the frame. The grip above its top edge is now a small dark pill in the chip's colours, kept below the menu bar.
- **Camera can't be turned on for a window recording,** since the bubble would never appear in it. Its tooltip says so.
- **Departures from the board.** The bar's radius is 16 like the capture bar's, rather than 18, and its buttons take group corners (10) rather than 11. Cancel is the floating secondary button, as on the countdown and the browser permission card, rather than plain text. Off toggles strike through their symbol, so on and off differ by more than the fill. The mode control is `BrutalSegmented`, a little shorter than the board's, and says Full Screen, as the capture bar does. Mac sound keeps the board's name, and #1115 decides whether Settings › Recording's "System audio" row follows it.
- **Keyboard.** The bar is key while it shows. Return, Enter and the record shortcut start the recording, and Esc cancels. With keyboard navigation on, Tab moves between the controls, which show the accent focus halo, and the arrow keys move the mode.
- **VoiceOver** reads the bar as "Check before recording" with the frame's size as its value. Each toggle reads its name and On or Off, the microphone adds its name, the frame rate is a menu button with the rate as its value, and Record and Cancel read by name. Tooltips say what each control does, with its key.
- **Text size.** The bar's labels, the level bars, the record dot and the chip scale with Settings › Text size, and the bar grows to fit. The handles and edges don't.
- **Increase Contrast and Reduce Transparency** make the bar and the chip solid with the 40% edge. Increase Contrast also takes off toggles to 90% white and the unlit level bars to 40%.

### Recording controls

#1089 builds Record › While recording: the bar under the area while it records, and the time in the menu bar. The bar is SwiftUI in its own `FloatingPanelWindow` with the system shadow, and grows to fit what it shows. The border is #1090, the camera bubble #1091, and the discard toast #1092.

| Part | Look |
| --- | --- |
| Bar | Standard floating panel, radius 16, 6 pt padding, 4 pt between parts, 22 pt under the area and centred on it. You can drag it aside |
| Status | Recording: a 10 pt record red (`#FF453A`) dot, then the time in 15 pt bold SF Mono with tabular figures, 9 pt apart, padded 10 pt left and 12 pt right. Paused: two 3 × 10 pt amber `#FFB648` bars in place of the dot, and the time at 70% white |
| Divider | `FloatingDivider` |
| Microphone | Its symbol and four 3 pt columns rising from 5 to 14 pt, lit success green as the level rises with the tallest amber, and white at 25% unlit. Muted: the symbol struck through, at 70% white, and every column unlit. Shown only when the recording has the microphone |
| Camera | The floating toolbar toggle, on with the 16% fill, the symbol struck through when off. Hidden for a window recording |
| Pause, Discard | Floating toolbar buttons, 36 pt tall, symbol only |
| Stop | Recording: the floating main button in record red, with a 10 pt white square and "Stop". Paused: the floating secondary button, "Stop" alone |
| Resume | Paused only, in Pause's place: the floating main button with ▶ and "Resume" |
| Menu bar | Recording: the time in 12 pt bold SF Mono, white on a record red (`#E5352B`) pill 20 pt tall at radius 6, after a 7 pt white stop square. Paused: the pause marks and the time as a template image, in the menu bar's own colour |

- **The pulse.** A halo of record red breathes out of the dot over `Moment.recordingPulse` (1.6 s), using `Moment.pulse`, the same breath as the menu bar's. Its frame loop runs at 30 fps and only while recording. Reduce Motion holds the board's steady 4 pt halo at 25%. In the menu bar a white ring breathes out of the stop square.
- **The timer never jitters.** `RecordingSessionModel.seconds` ticks once on each whole second recorded, and `RecordingClock` in ShotCore writes "0:07", "12:34" or "1:02:03", with tests. The time sits over hidden zeroes at least "00:00" wide in tabular figures, so the bar keeps its width until the recording passes an hour. The menu bar and the bar read the same clock, so they always agree.
- **Red only while recording.** The menu bar pill, the dot and Stop's red go when you pause (rule 6). Resume is then the one ink button, in the accent, and Stop turns secondary.
- **Departures from the board.** The board's paused bar shows only the time, Resume and Stop. Shot keeps the microphone, camera and Discard while paused, so you can discard or hide the camera before resuming, and Resume lands where Pause was. The board's microphone columns are drawn at uneven heights; Shot draws a rising row lit by the level, which reads at a glance. Buttons take group corners (10), as the board draws them. The camera toggle that's on uses the 16% fill rather than the board's 12%, as every floating toggle does. The board leaves out changing the bubble's size, which used to have its own button; double-clicking the bubble still does it, and the camera button's tooltip says so. The menu bar's paused look isn't on the board.
- **Keyboard.** The bar never takes the keyboard, so the app you're recording keeps it. The record shortcut stops, and the menu bar menu has Pause and Stop.
- **VoiceOver** reads the bar as "Recording" or "Recording paused". The status reads its state with the time as its value, such as "Recording, 7 seconds". The microphone reads "Microphone" with On or Muted, the camera "Camera bubble" with On or Off, and Pause, Resume, Discard and Stop by name. The menu bar item reads "Shot, recording, 7 seconds", or "Shot, recording paused at 7 seconds".
- **Text size.** The time, symbols, dot, pause marks, level columns and buttons scale with Settings › Text size, and the bar grows to fit, keeping its middle and top edge. The menu bar doesn't scale.
- **Increase Contrast and Reduce Transparency** make the bar solid with the 40% edge. Increase Contrast also takes the paused time and a muted microphone to 90% white, unlit columns to 40%, and Stop's red to `#C4271E`.

### Recording border and clicks

#1090 builds the border and click rings on Record › While recording. Both are AppKit panels drawn with shape layers, so neither adds a bitmap the size of the area. The border is left out of the video like Shot's other windows, and the click ring is let in.

| Part | Look |
| --- | --- |
| Border | 2 pt record red (`#FF453A`) hugging the area, then a 4 pt glow of the same red at 22% outside it. Both sit outside the area, so neither covers what's recorded. Shown when Settings › Recording › Region border is on |
| Paused border | The same 2 pt line in amber `#FFB648`, dashed 10 on and 6 off, with no glow |
| Click ring | A 34 pt circle edged by a 3 pt accent ring at 95%, then a 6 pt accent halo at 30%, centred on the pointer's tip. Shown for clicks inside the area when Show clicks is on |

- **The ring is in the video.** macOS's own click circles can't be restyled, so Shot draws the ring in one small panel that the recording's filter lets in, as it does the camera bubble. The pointer is drawn over it, as on the board. Event monitors catch the clicks, which needs no permission. `ClickRing` and `RecordingBorder` in ShotCore hold the sizes and timing and decide which clicks get a ring, with tests.
- **The ring holds, then fades.** It shows at once on the click, stays whole for `ClickRing.hold` (0.4 s) so it reads in a video, then fades over `Moment.clickRing` (240 ms). A new click moves it.
- **Nothing red while paused.** The board shows no paused border. Shot dashes it in the paused marks' amber and drops the glow, so paused differs from recording by more than colour (rule 6), and clicks while paused get no ring, since nothing is recorded.
- **Departures from the board.** The area's corners stay square, since the recording is, so the ring's inner edge follows the area exactly and only its outer corners round, rather than taking the board's radius 2. A window recording captures only its window, so Shot's ring can't reach it; there macOS draws its own click circles instead.
- **Keyboard and VoiceOver.** Neither panel takes the mouse, the keyboard or focus, and VoiceOver skips both, since they mark what the recording controls already announce.
- **Reduce Motion** keeps the ring but drops its fade: it shows for the same 0.4 s and then goes at once. The border doesn't move.
- **Text size** changes neither, since they mark the screen rather than hold text.
- **Increase Contrast** takes the border's glow to 40% and the ring's halo to 45%, and adds a 1 pt ink edge inside the ring so it reads on white.

### Camera bubble

#1091 builds the bubble on Record › Check before recording and While recording: your camera in a circle inside the recorded area. It is one AppKit panel just larger than the circle, drawn with shape layers, and the recording's filter lets it in, so the bubble is in the video.

| Part | Look |
| --- | --- |
| Bubble | The camera, mirrored and clipped to a circle as wide as the size picked in Settings › Recording, from 160 pt for small to 300 pt for large |
| Ring | 3 pt white outside the circle, so it never covers the picture |
| Shadow | macOS's own window shadow, which follows the circle |
| Place | 18 pt in from the area's left and bottom edges to start, and kept 18 pt inside the area as you drag it |
| Handle | Checking before recording only: a 16 pt white circle with a 1.5 pt ink edge, centred on the circle's lower edge at 45°, on the side facing the middle of the area |

- **Resizing.** Dragging the handle snaps to small, medium or large, whichever is nearest the circle through the pointer, and never past the largest that fits the area. Double-clicking still steps through the three, and the bubble keeps its centre either way. The size you pick becomes the default. `CameraBubbleStyle` and `CameraBubbleLayout` in ShotCore hold the sizes, where the handle sits and which size a drag asks for, with tests.
- **The handle goes when the recording starts.** It's for setting up, so the countdown and the recording show the bubble with only its ring, as the While recording board does.
- **Departures from the board.** The boards place the bubble bottom-right. Shot keeps it bottom-left, where it has always started, since the bottom right of most windows holds the buttons and scroll bars people are recording. The handle mirrors with it, so it always points at the room the bubble can grow into. The boards draw one 120 pt bubble; Shot keeps the three sizes Settings offers. The shadow is macOS's window shadow rather than the board's `0 10px 24px` at 35%, because a drawn shadow would sit in the panel and catch clicks around the circle. The board clips the handle to the circle; Shot draws it whole, on the ring.
- **Keyboard.** The bubble's panel never takes the keyboard. While the check-before-recording bar shows with the camera on, ⌘+ and ⌘− step the bubble larger and smaller, and the camera toggle's tooltip says so. While recording, the bar never takes the keyboard, so only the mouse and VoiceOver resize it.
- **VoiceOver** reads the bubble as "Camera bubble" with its size as the value, such as "Medium". Its actions Make larger and Make smaller step the size, offered only when a step would fit, and increment and decrement do the same.
- **Text size** changes nothing, since the bubble holds no text and its sizes come from Settings.
- **Dark appearance** changes nothing: the white ring is drawn over the screen in both.
- **Reduce Motion** changes nothing, since the bubble never animates. Moving and resizing are instant.
- **Increase Contrast** adds a 1 pt ink line outside the white ring, so the bubble reads on a white page.

### Discard and recovery

#1092 builds the discard toast on Record › While recording and the dialog on Capture › Permission card… › Recovering a recording. Discard was already undoable, so the toast is the shared one (see Toast). The dialog replaces the old silent recovery at launch, which joined the parts without asking and only then showed a toast. It is SwiftUI in a borderless panel sized to the card, with the system shadow, centred on the screen with the pointer.

| Part | Look |
| --- | --- |
| Discard toast | The shared toast: "Recording discarded" with Undo and a faded ⌘Z, for 5 seconds. The parts stay on disk until it goes, and Undo joins them as Stop would |
| Card | 320 pt wide, the group fill (white, dark `#2C2C30`), panel radius 14, 20 pt padding, 10 pt between parts, everything centred. A 0.5 pt edge of black at 20% (dark: white at 14%) |
| Icon | `record.circle` at 22 pt in the Recording sidebar tint, `#C4271E` on a 44 pt `#FFE1DE` tile with group corners (dark: `#FF7B72` on `#4A2220`) |
| Title | "Recover your last recording?" in 15 pt bold text colour |
| Detail | "Shot stopped while recording. 1:42 was saved in 3 parts, and Shot can join them now." in 12.5 pt secondary text. One part reads "0:42 was saved, and Shot can put it in your save folder now" |
| Buttons | Show Parts as the secondary button and Recover as the main button, equal widths, 8 pt apart and 6 pt further below the detail. One part says Show File |
| Discard recording | A destructive plain button under them, in `#C4271E` (dark `#FF7B72`) |

- **What each choice does.** Recover joins the parts into "… (recovered).mp4" in the save folder, or moves them there as separate parts when they can't be joined, and a toast offers Show. Show Parts selects them in Finder and leaves the dialog open. Discard recording closes the dialog behind the discard toast, whose Undo opens it again; once the toast goes, the parts are deleted.
- **Nothing is lost by waiting.** Esc closes the dialog and leaves the parts where they are, so Shot asks again the next time it opens. Quitting while a discard toast shows commits the discard, so a recording you threw away isn't offered back.
- **The length.** `SegmentRecovery.Leftover` in ShotCore adds up the parts' lengths to the nearest second, never under one, and writes it as the recording timer would, with tests.
- **Red while something may be lost.** The tile takes the Recording tint, as the board does. It fits rule 6, since the recording is lost unless you recover it.
- **Departures from the board.** The board rounds the tile at 12 and the buttons at 8; Shot uses the group and control tokens, 10 and 6. Discard recording is the shared plain button, 13 pt medium rather than the board's 12 pt. The shadow is the system window shadow rather than the board's `0 20px 44px` at 22%. The board shows light only; dark takes the group fill, the dark Recording tint and the Float edge's dark value. The toast keeps the shared toast's 10 pt gap, 4 pt button padding and faded ⌘Z, where the board's discard toast has 12, 3 and a white key.
- **Keyboard.** The dialog takes the keyboard when Shot is brought forward. Return recovers and Esc puts it off. With keyboard navigation on, Tab moves between the buttons, which show the accent focus halo. macOS can refuse to bring a menu bar app forward at launch, so the panel floats above other windows either way. The toast never takes the keyboard, so ⌘Z presses Undo from any app.
- **VoiceOver** announces the title and detail when the dialog appears. The dialog is a group named by its title, the title is a heading, and each button reads by name, with a tooltip saying what it does.
- **Text size.** The card is 320 pt times Settings › Text size wide, so the detail wraps as on the board, and it grows to fit. The tile scales with it.
- **Reduce Motion.** The dialog rises 8 pt as it fades in over the panel arrival's 240 ms, and Reduce Motion makes that a 120 ms fade. The toast follows Toast.
- **Increase Contrast** takes the card's edge to 1 pt of 60% ink and the detail to the text colour.

### Image editor toolbar

#1093 builds the editor's title bar on Edit › Image editor · annotate, and its Share menu on Capture › Permission card… › Menus and tooltips. The title bar and the toolbar were two rows; now they're one, beside the traffic lights. Copy is the window's one main button, and what you need less often moves into Share. The style bar (#1094, see Style bar) replaced the row of colour and width options under it.

| Part | Look |
| --- | --- |
| File | The file name in Window type (13 semibold), and under it the size the image saves at, "1,040 × 600", in Caption type and tertiary text, after "Edited ·" while there are unsaved changes. Up to 190 pt wide; the name truncates in the middle |
| Tool group | Centred between the file and the buttons. Field fill, group radius 10, 3 pt padding, 1 pt between buttons. Select, Arrow, Line, Shape, Pen, Text, Sticky note, Highlight, Spotlight, Redact and Counter, a 1 × 18 pt control-edge divider with 4 pt either side, then Add image and Crop. Each is a tool tile (`Tile(tool: true)`), 30 × 28, so the selected tool is the accent with a 1.5 pt ink outline and 1.5 pt drop |
| Buttons | Undo, Style and Layers as toolbar tiles, 4 pt apart. Style and Layers fill while their popover or panel shows. Then a 1 × 20 pt control-edge divider with 6 pt either side |
| Share | A secondary button with a 9 pt chevron in secondary text. It opens the shared menu (`BrutalDropdown`): Copy Image ⌘C, Copy Path, a divider, Save As…, Show in Finder and Pin to Screen, each with its symbol |
| Save, Copy | Save is a secondary button and Copy the main button, 4 pt further apart than the tiles, with Copy last |

- **What Share does.** Copy Image copies the annotated image, as Copy does. Copy Path and Show in Finder save unsaved changes first, without the save's own toast, so the file they point at has the marks. Copy Path's toast then says "Saved as … and copied its path". Save As… writes the annotated image to a file the user names, PNG or JPEG by its extension, next to the file to start, and leaves the editor on its own file. It won't replace the file being edited, since Save does that and keeps the original. A JPEG with transparent padding takes a white background. Pin to Screen floats the annotated image as Quick Access's Pin does. `EditorShareAction` in ShotCore holds the order, the divider, the shortcut and which actions save first, with tests.
- **Which tools have buttons.** `EditorToolbarLayout` in ShotCore lists them, with tests that every tool but the hand has one and each keeps its key. The hand tool has no button, as on the board. H still picks it, and Space-drag, a middle-drag and scrolling still move around. While it's in use no button shows as selected.
- **Window width.** The title bar needs 1,060 pt, so that's the editor's new minimum, up from 980.
- **Departures from the board.** Redo has no button, as on the board, and the Undo tooltip says ⇧⌘Z redoes. The zoom menu and the Canvas menu left the title bar, which has no room for them on the board: zoom is the canvas's zoom control (#1095), and the Canvas menu sits beside it until its new place (#1099). The board rounds the tool buttons at 7 and the Share, Save and Copy buttons at 7; Shot uses the control token, 6. The tools keep their SF Symbols, and Highlight and Redact keep their names, which the guide and Settings use, where the board says Highlighter and Blur. Style keeps its palette symbol and Layers takes `sidebar.right`, the board's panel icon. The board's menu highlights its row in selection blue; the shared menu highlights in the accent, as every Shot menu does.
- **Keyboard.** Every tool keeps its key, and its tooltip shows it on a keycap with what the tool does. Undo shows ⌘Z, Layers ⌘L, Add image ⇧⌘I, Save ⌘S and Copy ⌘C. With keyboard navigation on, Tab reaches each button, which shows the accent focus halo, and the Share menu takes the arrow keys, Return and Esc.
- **VoiceOver** reads the tool group as "Tools" and each tool by name, with the selected one as selected. The file name and size read as one element. Share reads as a button that opens a menu.
- **Text size** scales the type and icons. At Larger the file name truncates first; the buttons and tools keep their size.
- **Reduce Motion** keeps the main button's drop still and darkens it on press, as every button does. Nothing else in the title bar moves.
- **Increase Contrast** takes the size line to the text colour and the secondary buttons' edges to 60% ink.

### Style bar

#1094 builds the style bar on Edit › Image editor · annotate: a small floating bar beside the selected mark with its colour and width. It replaces the row of options under the title bar, so the canvas starts right under it. It is SwiftUI over the canvas, so it costs nothing until the editor opens, and nothing on the capture → copy path.

| Part | Look |
| --- | --- |
| Bar | 5 × 7 pt padding, 8 pt between parts, group radius 10. Fill `rgba(255,255,255,0.97)` (dark `rgba(44,44,48,0.97)`) at the Float depth: a 0.5 pt edge of black at 20% (dark white at 14%) and `0 8px 24px` |
| Swatches | Red, Orange, Yellow, Green, Blue and Black, 20 pt circles in the preset colours marks use. The chosen one has a 1.5 pt ink ring outside a 2 pt gap, and the others an inner 1 pt edge of black at 12% (dark white at 18%) |
| Divider | 1 × 18 pt in the control edge colour |
| Widths | Thin, Medium and Thick on the shared segmented control (`BrutalSegmented` with pictures): 26 × 20 pt segments holding 12 pt lines 2, 4 and 6 pt tall, ink when chosen and 85% ink otherwise. Text, notes and counters show Small, Medium and Large as three sizes of "A" |
| More style | `…` as a toolbar button. It opens a popover with what the bar has no room for: the shape, every colour with white and a custom one, the fill, the text's alignment, a redaction's amount, a spotlight's strength and soft edge, and Reset last |

- **Where it sits.** Centred 10 pt above the mark and its handles, or else below, right or left of it, whichever first fits 12 pt inside the canvas, sliding along that edge to stay in. With nothing selected it styles the tool's next mark from the top centre of the canvas. Only a mark that fills the view on every side is covered, by the bar at the top. `StyleBarPlacement` in ShotCore decides this, with tests. The canvas reports the mark's frame in view points to `EditorModel.styleBarMark`, so the bar follows zoom, scrolling and edits.
- **What it shows.** `StyleBarContent` in ShotCore picks the parts in the order the options row used. Arrows, lines, shapes, pens, text, notes, highlights and counters get the swatches and widths. A redaction gets blur or pixelate, and a spotlight its shape and its darken or blur. The select tool with nothing selected, an image or several marks shows no bar, and Style in the title bar styles those.
- **Out of the way.** It hides while a drag draws, moves, resizes or crops, and comes back beside the mark when you let go. More style closes with it.
- **Temporary homes.** The crop's aspect and Reset sit in the bar, at the top of the canvas, until the crop bar (#1097).
- **Clear of the foot.** The bar keeps clear of the zoom control and hint along the canvas's foot as it does the canvas's edges (see Editor canvas).
- **Departures from the board.** The board rounds the bar at 11, the segmented track at 7 and its thumb at 5; Shot uses the group radius 10 and the segmented control's 8 and 6. The board's shadow is 18%, and Shot uses the Float depth's 16%. The board's swatches use the interface colours (`#E5352B` and so on), while Shot's are the preset colours an arrow is drawn in, so the swatch matches the mark. More style is a 30 × 28 toolbar button, the toolbar's minimum, rather than 26 × 22, so the bar is 38 pt tall rather than 32. A colour that isn't one of the six, such as white or a custom one, shows no swatch as chosen, and More style shows it.
- **Keyboard.** With keyboard navigation on, Tab reaches each swatch, the width control and More style, each with the 4 pt accent focus halo, and the arrow keys move the width. Every tool's key still works while the bar shows.
- **VoiceOver** reads the bar as a group named "Style", each swatch by its colour name with the chosen one as selected, the widths as a segmented control (Thin, Medium, Thick), and More style as a button.
- **Text size** scales the line and letter pictures and the popover's type, while the swatches and segments keep their size.
- **Reduce Motion.** The bar arrives with the panel moment, a 240 ms spring fading in from 96%, and Reduce Motion makes that a 120 ms fade. Following the mark is always instant, as edits are.
- **Increase Contrast and Reduce Transparency** make the bar solid in the group colour. Increase Contrast adds a 1 pt edge of 60% ink and gives the segmented track its 60% edge.

### Editor canvas

#1095 builds the canvas on Edit › Image editor · annotate, and the Layers panel's empty state on Foundations › Components. The screenshot sits on a dotted backdrop with a soft shadow, the zoom control and the Canvas menu sit at its bottom left, and a hint at its bottom right says what the tool does or what's selected.

| Part | Look |
| --- | --- |
| Backdrop | `#ECEAE5` (dark `#151517`) with a 16 pt grid of 1 pt dots in ink at 8% (dark white at 7%) |
| Image | A 1 pt hairline of ink at 8% (dark 0.5 pt of white at 10%) and a `0 18px 40px` shadow, black at 16% (dark 50%) |
| Zoom control | 16 pt in from the bottom left. A pill with 3 pt padding and 2 pt between parts: −, the percentage in 12 pt tabular figures at least 44 pt wide, + and Fit. Fill white at 90% (dark `#2C2C30` at 92%) with a 1 pt edge of ink at 10% (dark 0.5 pt of white at 12%) and `0 2px 8px` at 8% (dark black at 30%) |
| Canvas menu | The same pill, 8 pt to the zoom control's right, holding Canvas with a 9 pt chevron. Fit to Content, Trim to Image and Background… |
| Hint | 16 pt in from the bottom right. 5 × 10 pt padding, the pill's fill and edge with no drop shadow. 12 pt secondary text with each key in 11 pt mono, the hint's grey in light and the ink in dark: "Arrow selected · ⌫ delete · ⇧ snap 45°" |
| Empty state | The Layers panel with nothing drawn: the shared `EmptyState`, "Nothing drawn yet" and "Pick a tool, or press A for an arrow." |

- **What the hint says.** `CanvasHint` in ShotCore decides, with tests. While text is typed it reads "Typing · esc done", and in crop mode "Cropping · ↩ apply · esc cancel". Several marks read "2 selected · ⌫ delete · esc deselect", and a locked one "Arrow locked · unlock it in Layers". One mark reads its kind, ⌫ delete and what Shift does to its handles: snap 45° for arrows and lines, resize freely for images, keep proportions for boxes and strokes, and esc deselect for text, notes and counters. With nothing selected the hint says what the tool does and what Shift or Option does while you draw, such as "Drag to draw an arrow · ⇧ snap 45°".
- **Zoom.** − and + step through the zoom steps as ⌘− and ⌘+ do, and grey out at the ends. Fit is ⌘0. The percentage opens the zoom menu, which keeps Actual Size (⌘1) one click away. Pinch, ⌘-scroll and the trackpad's double-tap still zoom about the pointer. `ZoomControl` in ShotCore rounds the percentage and says when − and + can step, with tests.
- **The style bar.** The foot's controls report their height to `EditorModel.canvasFootHeight`, and `StyleBarPlacement` keeps the bar that far from the canvas's bottom, so a mark low on the canvas gets its bar above or beside it rather than over the zoom control.
- **Drawing cost.** The backdrop is a view of its own under the canvas, and the shadow is a layer with a shadow path masked to outside the image, so the GPU draws the blur once and a drag redraws only the canvas. A see-through image, such as a window with its corners cut, doesn't show the shadow through it.
- **Departures from the board.** The pills round at the group radius 10, where the board uses 9. −, + and Fit are 30 × 28 toolbar buttons, the toolbar's minimum, rather than 26 × 24, so the zoom control is 34 pt tall rather than 30; − and + are SF Symbols rather than text. The board's hint says "snap 15°"; Shift snaps to 45° steps in Shot, so the hint says that. The screenshot keeps square corners, where the board rounds it at 8, so the canvas shows exactly what Copy makes; a style's rounded corners still show. The board's canvas fills the window under the title bar, while Shot's sits in its card with the window's 24 pt inset beside the Layers panel, until the panels are redrawn (#1098). The percentage is a button that opens the zoom menu, where the board shows plain text, so Actual Size keeps a home. The Canvas menu is a pill beside the zoom control until #1099.
- **Keyboard.** ⌘+, ⌘−, ⌘0 and ⌘1 work as before. With keyboard navigation on, Tab reaches −, the percentage, +, Fit and Canvas, each with the 4 pt accent focus halo, and the menus take the arrow keys, Return and Esc.
- **VoiceOver** reads the zoom control as a group named "Zoom", − and + as Zoom Out and Zoom In, and the percentage as the Zoom menu button with its value. The hint reads as one element with each key by its name, "Arrow selected. Delete: delete. Shift: snap 45°", and VoiceOver announces it when it changes.
- **Text size** scales the percentage, the hint, its keys and the Canvas menu's label. The hint truncates first when the canvas is narrow.
- **Reduce Motion.** Nothing on the canvas's foot moves; the percentage and hint change in place.
- **Increase Contrast and Reduce Transparency** make the pills solid in the group colour. Increase Contrast gives them a 1 pt edge of 60% ink, takes the hint and its keys to the ink, and the image's hairline to 50% ink (dark 50% white).

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
| Area capture | #1076 | `Overlay/SelectionOverlayView.swift` (edge, handles, chips, loupe, guides, cursor), `Overlay/SelectionOverlayController.swift` (cursor), ShotCore `AreaOverlay.swift` (`AreaHandles`, `AreaLabelPlacement`, `Loupe`) | ☐ |
| Window pick and delay | #1077 highlights | `Overlay/SelectionOverlayView.swift` (tint, edge, label), `Overlay/SelectionOverlayController.swift` (stepping finds the page), ShotCore `WindowPick.swift` (`WindowPickLabel`, `WindowInfo.pickName`) | ☐ |
| Window pick and delay | #1075 capture bar with delay | `Overlay/SelectionOverlayView.swift` (the bar, Delay's seconds and the tooltip) | ☐ |
| Scrolling capture | #1086 | `Capture/ScrollingCaptureController.swift` (`ScrollCaptureView`), `Recording/RecordingBorderPanel.swift` (`.scrolling`), ShotCore `ScrollPreviewLayout.swift`, `ScrollCapture.swift` (headings and warnings), `ScrollStitcher.swift` (`framesKept`, `hasStickyHeader`) | ☐ |
| Quick Access, pin, menu and toasts › card | #1081 | `QuickAccess/QuickAccessView.swift`, `QuickAccess/QuickAccessController.swift`, ShotCore `QuickAccessLayout.swift` | ☐ |
| Quick Access, pin, menu and toasts › stack | #1082 | `QuickAccess/QuickAccessController.swift`, `QuickAccess/QuickAccessView.swift`, ShotCore `QuickAccessLayout.swift`, `Design/GlassWindow.swift` (`FloatingPanel.cardBehind`) | ☐ |
| Quick Access, pin, menu and toasts › pin | #1083 | `QuickAccess/PinController.swift` (`PinState`, `PinBar`, `PinFrame`), ShotCore `PinOpacity.swift`, `PinLayout.swift` (`barStrip`), `Design/BrutalControls.swift` (`BrutalSlider(floating:)`) | ☐ |
| Quick Access, pin, menu and toasts › menu | #1084 | `MenuBar/StatusMenu.swift`, `MenuBar/RecentRowView.swift`, `MenuBar/RecentCapturesStore.swift`, `ShotCore/RecentCaptures.swift`, `Design/BrandMark.swift` | ☐ |
| Quick Access, pin, menu and toasts › toast | #1085 | `Toast.swift` (`ToastView`, `ToastTickMark`), ShotCore `ToastLayout.swift`, `QuickAccess/QuickAccessController.swift` (`cardsTop(on:)`, `cardEdgeInset`) | ☐ |
| Quick Access, pin, menu and toasts › countdown | #1078 | `Recording/RecordingSetupController.swift` (`CountdownPanel`, `CountdownView`), ShotCore `CountdownRing.swift`, `Moment.countdownRing`, `Design/Motion.swift` | ☐ |
| Quick Access, pin, menu and toasts › floating panels | #1073 | `Design/GlassWindow.swift` (`FloatingPanel`, `FloatingPanelWindow`), `Toast.swift`, `Overlay/SelectionOverlayView.swift`, `Recording/RecordingControlPanel.swift`, `Recording/RecordingSetupController.swift`, `Capture/ScrollingCaptureController.swift`, `QuickAccess/QuickAccessView.swift` | ☐ |
| Permission card… › permission card | #1087 | `Overlay/BrowserPermissionCard.swift`, `Overlay/SelectionOverlayController.swift` (`showPermissionCard`), `Overlay/SelectionOverlayView.swift` (`barScreenFrame`, a click closes the card), `Design/GlassWindow.swift` (`FloatingPanel.Opacity.card`), ShotCore `PermissionCardPlacement.swift` | ☐ |
| Permission card… › colour loupe | #1080 | `ColorSampler.swift`, `Overlay/ColorPickerOverlay.swift`, ShotCore `ColorLoupe.swift` (`ColorLoupe`, `PixelColor`) | ☐ |
| Permission card… › recovery | #1092 | `Recording/RecordingRecovery.swift` (`RecordingRecoveryDialog`, `recover(_:)`), `AppDelegate.swift`, ShotCore `SegmentRecovery.swift` (`Leftover`) | ☐ |
| Permission card… › update prompt | #1117 | `Updater.swift` | ☐ |
| Permission card… › tooltips and menus | #1072 | `Design/BrutalTip.swift` | ☐ |
| Permission card… › Share menu | #1093 | `Editor/EditorRootView.swift` (`ShareMenu`), `Editor/EditorModel.swift` (`share(_:)`), ShotCore `EditorToolbarLayout.swift` (`EditorShareAction`) | ☐ |
| Permission card… › Move to Trash | #1110 | `Gallery/GalleryView.swift` | ☐ |

### Record

| Board | Issue | Files | QA |
| --- | --- | --- | --- |
| Check before recording | #1088 | `Recording/RecordingSetupController.swift`, `Recording/AudioMeter.swift` (`MicLevelBars`), `Recording/Recorder.swift` (`Options`), `Recording/RecordingBorderPanel.swift`, ShotCore `RecordSetupFrame.swift` (`RecordSetupFrame`, `LevelBars`) | ☐ |
| Check before recording | #1091 camera bubble | `Recording/CameraBubble.swift` (handle, `showsHandle`), `Recording/RecordingSetupController.swift` (⌘+ and ⌘−), ShotCore `CameraBubbleLayout.swift` (`CameraBubbleStyle`, `CameraBubbleLayout`) | ☐ |
| While recording | #1089 controls | `Recording/RecordingControlPanel.swift`, `Recording/AudioMeter.swift` (`MicLevelColumns`), `Recording/Recorder.swift` (`RecordingSessionModel.seconds`), `Design/BrandMark.swift` (`timerImage`), `MenuBar/StatusMenu.swift`, ShotCore `RecordingClock.swift` | ☐ |
| While recording | #1090 border and clicks | `Recording/RecordingBorderPanel.swift`, `Recording/ClickRings.swift`, `Recording/Recorder.swift` (`makeFilter`), ShotCore `RecordingMarks.swift` (`RecordingBorder`, `ClickRing`), `Moment.clickRing` | ☐ |
| While recording | #1091 camera bubble | `Recording/CameraBubble.swift`, ShotCore `CameraBubbleLayout.swift` | ☐ |
| While recording | #1092 discard toast | `Recording/RecordingControlPanel.swift` (Discard), `Recording/Recorder.swift` (`complete(discard:)`), `Toast.swift` (`commitPending()`) | ☐ |

### Edit

| Board | Issue | Files | QA |
| --- | --- | --- | --- |
| Image editor · annotate | #1093 toolbar | `Editor/EditorRootView.swift` (`EditorTitleBar`, `ShareMenu`), `Editor/EditorToolbar.swift` (`EditorToolGroup`), `Editor/EditorModel.swift` (`share(_:)`), `Editor/EditorWindowController.swift` (minimum width), ShotCore `EditorToolbarLayout.swift` (`EditorToolbarLayout`, `EditorShareAction`) | ☐ |
| Image editor · annotate | #1094 style bar | `Editor/StyleBar.swift` (`StyleBarOverlay`, `StyleBar`, `MoreStyle`), `Editor/EditorCanvasView.swift` (`updateStyleBar`), `Editor/EditorModel.swift` (`styleBarMark`, `styleBarContent`), `Editor/EditorRootView.swift`, `Design/BrutalStyle.swift` (`BrutalSegmented` pictures), ShotCore `StyleBar.swift` (`StyleBarPlacement`, `StyleBarContent`, `StyleBarSwatches`) | ☐ |
| Image editor · annotate | #1095 canvas | `Editor/CanvasControls.swift` (`CanvasFoot`, `EditorCanvasContainer`, the backdrop), `Editor/EditorCanvasView.swift` (image edge, `onImageRectChange`), `Editor/EditorRootView.swift`, `Editor/EditorModel.swift` (`canvasHint`, `canvasFootHeight`), `Design/LayersPanel.swift` (empty state), ShotCore `CanvasHint.swift` (`CanvasHint`, `ZoomControl`), ShotCore `StyleBar.swift` (`StyleBarPlacement` bottom) | ☐ |
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
| Gallery | #1106 own window | `MainWindowController.swift`, `Gallery/GalleryController.swift`, `MenuBar/StatusMenu.swift`, `AppDelegate.swift` (`shot://gallery`) | ☐ |
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
