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

**Window chrome** (#1073): `GlassWindow` makes a standard titled window with a unified, transparent title bar and the toolbar content beside the standard traffic lights. The window background is the plain Window colour, and the system draws the corners and edge. `SidebarMaterial` is the see-through sidebar (`NSVisualEffectView`, `.sidebar` material), solid in the Sidebar colour with Increase Contrast or Reduce Transparency. Settings and the gallery run it the window's full height, under the traffic lights, with a separator on its right.

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
| Buttons | Undo, the Canvas menu (#1099, see Combining images), Style and Layers, 4 pt apart. Undo, Style and Layers are toolbar tiles, and Style and Layers fill while their panel shows (see Style panel). Then a 1 × 20 pt control-edge divider with 6 pt either side |
| Share | A secondary button with a 9 pt chevron in secondary text. It opens the shared menu (`BrutalDropdown`): Copy Image ⌘C, Copy Path, a divider, Save As…, Show in Finder and Pin to Screen, each with its symbol |
| Save, Copy | Save is a secondary button and Copy the main button, 4 pt further apart than the tiles, with Copy last |

- **What Share does.** Copy Image copies the annotated image, as Copy does. Copy Path and Show in Finder save unsaved changes first, without the save's own toast, so the file they point at has the marks. Copy Path's toast then says "Saved as … and copied its path". Save As… writes the annotated image to a file the user names, PNG or JPEG by its extension, next to the file to start, and leaves the editor on its own file. It won't replace the file being edited, since Save does that and keeps the original. A JPEG with transparent padding takes a white background. Pin to Screen floats the annotated image as Quick Access's Pin does. `EditorShareAction` in ShotCore holds the order, the divider, the shortcut and which actions save first, with tests.
- **Which tools have buttons.** `EditorToolbarLayout` in ShotCore lists them, with tests that every tool but the hand has one and each keeps its key. The hand tool has no button, as on the board. H still picks it, and Space-drag, a middle-drag and scrolling still move around. While it's in use no button shows as selected.
- **Window width.** The title bar needs 1,060 pt, so that's the editor's new minimum, up from 980.
- **Departures from the board.** Redo has no button, as on the board, and the Undo tooltip says ⇧⌘Z redoes. The zoom menu left the title bar, which has no room for it on the board: zoom is the canvas's zoom control (#1095). The Canvas menu sat beside it until #1099 brought it back to the title bar (see Combining images). The board rounds the tool buttons at 7 and the Share, Save and Copy buttons at 7; Shot uses the control token, 6. The tools keep their SF Symbols, and Highlight and Redact keep their names, which the guide and Settings use, where the board says Highlighter and Blur. Style keeps its palette symbol and Layers takes `sidebar.right`, the board's panel icon. The board's menu highlights its row in selection blue; the shared menu highlights in the accent, as every Shot menu does.
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
- **Crop mode** has no style bar. The crop bar takes its place at the canvas's foot (see Crop bar).
- **Clear of the foot.** The bar keeps clear of the zoom control and hint along the canvas's foot as it does the canvas's edges (see Editor canvas).
- **Departures from the board.** The board rounds the bar at 11, the segmented track at 7 and its thumb at 5; Shot uses the group radius 10 and the segmented control's 8 and 6. The board's shadow is 18%, and Shot uses the Float depth's 16%. The board's swatches use the interface colours (`#E5352B` and so on), while Shot's are the preset colours an arrow is drawn in, so the swatch matches the mark. More style is a 30 × 28 toolbar button, the toolbar's minimum, rather than 26 × 22, so the bar is 38 pt tall rather than 32. A colour that isn't one of the six, such as white or a custom one, shows no swatch as chosen, and More style shows it.
- **Keyboard.** With keyboard navigation on, Tab reaches each swatch, the width control and More style, each with the 4 pt accent focus halo, and the arrow keys move the width. Every tool's key still works while the bar shows.
- **VoiceOver** reads the bar as a group named "Style", each swatch by its colour name with the chosen one as selected, the widths as a segmented control (Thin, Medium, Thick), and More style as a button.
- **Text size** scales the line and letter pictures and the popover's type, while the swatches and segments keep their size.
- **Reduce Motion.** The bar arrives with the panel moment, a 240 ms spring fading in from 96%, and Reduce Motion makes that a 120 ms fade. Following the mark is always instant, as edits are.
- **Increase Contrast and Reduce Transparency** make the bar solid in the group colour. Increase Contrast adds a 1 pt edge of 60% ink and gives the segmented track its 60% edge.

### Editor canvas

#1095 builds the canvas on Edit › Image editor · annotate, and the Layers panel's empty state on Foundations › Components. The screenshot sits on a dotted backdrop with a soft shadow, the zoom control sits at its bottom left, and a hint at its bottom right says what the tool does or what's selected.

| Part | Look |
| --- | --- |
| Backdrop | `#ECEAE5` (dark `#151517`) with a 16 pt grid of 1 pt dots in ink at 8% (dark white at 7%) |
| Image | A 1 pt hairline of ink at 8% (dark 0.5 pt of white at 10%) and a `0 18px 40px` shadow, black at 16% (dark 50%) |
| Zoom control | 16 pt in from the bottom left. A pill with 3 pt padding and 2 pt between parts: −, the percentage in 12 pt tabular figures at least 44 pt wide, + and Fit. Fill white at 90% (dark `#2C2C30` at 92%) with a 1 pt edge of ink at 10% (dark 0.5 pt of white at 12%) and `0 2px 8px` at 8% (dark black at 30%) |
| Hint | 16 pt in from the bottom right. 5 × 10 pt padding, the pill's fill and edge with no drop shadow. 12 pt secondary text with each key in 11 pt mono, the hint's grey in light and the ink in dark: "Arrow selected · ⌫ delete · ⇧ snap 45°" |
| Empty state | The Layers panel with nothing drawn: the shared `EmptyState`, "Nothing drawn yet" and "Pick a tool, or press A for an arrow." |

- **What the hint says.** `CanvasHint` in ShotCore decides, with tests. While text is typed it reads "Typing · esc done". Crop mode has no hint, since the crop bar takes the foot and its buttons name their keys (see Crop bar). Several marks read "2 selected · ⌫ delete · esc deselect", and a locked one "Arrow locked · unlock it in Layers". One mark reads its kind, ⌫ delete and what Shift does to its handles: snap 45° for arrows and lines, resize freely for images, keep proportions for boxes and strokes, and esc deselect for text, notes and counters. With nothing selected the hint says what the tool does and what Shift or Option does while you draw, such as "Drag to draw an arrow · ⇧ snap 45°".
- **Zoom.** − and + step through the zoom steps as ⌘− and ⌘+ do, and grey out at the ends. Fit is ⌘0. The percentage opens the zoom menu, which keeps Actual Size (⌘1) one click away. Pinch, ⌘-scroll and the trackpad's double-tap still zoom about the pointer. `ZoomControl` in ShotCore rounds the percentage and says when − and + can step, with tests.
- **The style bar.** The foot's controls report their height to `EditorModel.canvasFootHeight`, and `StyleBarPlacement` keeps the bar that far from the canvas's bottom, so a mark low on the canvas gets its bar above or beside it rather than over the zoom control.
- **Drawing cost.** The backdrop is a view of its own under the canvas, and the shadow is a layer with a shadow path masked to outside the image, so the GPU draws the blur once and a drag redraws only the canvas. A see-through image, such as a window with its corners cut, doesn't show the shadow through it.
- **Departures from the board.** The pills round at the group radius 10, where the board uses 9. −, + and Fit are 30 × 28 toolbar buttons, the toolbar's minimum, rather than 26 × 24, so the zoom control is 34 pt tall rather than 30; − and + are SF Symbols rather than text. The board's hint says "snap 15°"; Shift snaps to 45° steps in Shot, so the hint says that. The screenshot keeps square corners, where the board rounds it at 8, so the canvas shows exactly what Copy makes; a style's rounded corners still show. The percentage is a button that opens the zoom menu, where the board shows plain text, so Actual Size keeps a home. The Canvas menu was a pill beside the zoom control until #1099 moved it to the title bar.
- **Keyboard.** ⌘+, ⌘−, ⌘0 and ⌘1 work as before. With keyboard navigation on, Tab reaches −, the percentage, + and Fit, each with the 4 pt accent focus halo, and the menus take the arrow keys, Return and Esc.
- **VoiceOver** reads the zoom control as a group named "Zoom", − and + as Zoom Out and Zoom In, and the percentage as the Zoom menu button with its value. The hint reads as one element with each key by its name, "Arrow selected. Delete: delete. Shift: snap 45°", and VoiceOver announces it when it changes.
- **Text size** scales the percentage, the hint and its keys. The hint truncates first when the canvas is narrow.
- **Reduce Motion.** Nothing on the canvas's foot moves; the percentage and hint change in place.
- **Increase Contrast and Reduce Transparency** make the pills solid in the group colour. Increase Contrast gives them a 1 pt edge of 60% ink, takes the hint and its keys to the ink, and the image's hairline to 50% ink (dark 50% white).

### Style panel

#1096 builds the Style panel on Edit › Image editor · style. It replaces the Style popover, which hung under the title bar and held only a shadow, border and corners. The panel sits beside the canvas, opened by the Style tile, and adds the screenshot's background, padding and size, so a screenshot can be dressed for a slide or a post without leaving the editor. It costs nothing until it opens, and nothing on the capture → copy path unless Use for new captures has saved a canvas.

| Part | Look |
| --- | --- |
| Panel | 288 pt wide, flush with the canvas on the side panel colour with a hairline left edge, as the Layers panel is (`sidePanel(width:)`) |
| Header | "Style" in 13 pt bold, and Reset on the right in 12 pt medium accent text (`Brutal.accentText`), disabled text when there's nothing to put back. 14 × 16 pt above, 10 pt below |
| Sections | 16 pt sides, 18 pt apart, in a scroll view. Headings in 11.5 pt semibold tertiary text. With a selection, its name ("Selected shape") in 12 pt bold heads its own sections, and a separator and "Canvas" head the rest |
| Background | A grid of 7 columns, 6 pt apart, of square swatches at the control radius 6: None (a grey and white check), Sand, Sky, Sage, Blush, Lilac, Graphite, White, Dusk, Sea, Citrus, Desktop and a rainbow custom colour. Others have an inner 1 pt edge of ink at 12% (dark white at 18%), and the chosen one a 1.5 pt ring in the text colour outside a 2 pt gap |
| Padding, Corners | The name in 12 pt semibold tertiary text and the value in 12 pt tabular figures ("72 pt") over the shared slider (`BrutalSlider`) the panel's width. Padding runs 0 to 120 pt, Corners 0 to 48 |
| Shadow, Border | 5 columns of tiles, 6 pt apart: a 26 × 18 pt card with the preset over its name in 10.5 pt. The chosen tile is the group fill with a 1.5 pt ring in the text colour and a semibold name, and hover takes the hover fill. A custom shadow adds the CUSTOM badge by its heading, and Elevation and Opacity sliders follow. A solid border or outline adds its S, M and L tiles and colour swatches |
| Size | The shared segmented control (`BrutalSegmented`), its segments sharing the panel's width: Auto, 16:9, 4:3, 1:1, 4:5 |
| Use for new captures | Pinned under the scroll view: a group-fill card at the Rest depth, radius 10, 10 × 12 pt padding, the label in 12.5 pt and the shared switch on the right. "New captures keep a different saved style." follows in Caption type when another style is saved |

- **What it styles.** With nothing selected it styles the screenshot, in the board's order: Background, Padding and Corners, Shadow, Border, Size, then Use for new captures. With an image, shape, arrow or text selected, that selection's Corners, Shadow and Border come first under its name, and Background, Padding and Size follow under Canvas, since they belong to the whole picture. A locked mark, several marks, or text being typed leave a note and the canvas. A window captured with the macOS shadow shows "Uses macOS window shadow" in place of its shadow, border and corners, and keeps its background, padding and size. `StylePanelLayout` in ShotCore decides the sections, with tests.
- **Background.** A colour is `EditorDocument.background`, as before. A gradient or Desktop is `backgroundFill`, drawn over a colour close to it, which the shadow tint, the JPEG rule and the editor's checkerboard read. Desktop draws the desktop picture of the screen in front, read once per document off the main actor at up to 2,400 pixels, filling the canvas. When Shot can't read one it draws the board's warm grey. A JPEG can't pick None.
- **Padding and Size.** `CanvasFrame` in ShotCore adds the padding on every side of the screenshot, or of its crop, and then grows the canvas to the size about its centre, on whole pixels, with the growing side rounded so 1:1 comes out square. Both only ever add canvas, so marks past the padding still fit. They're applied after the frame crop, so the crop still moves only within what the document holds. Trim to Image takes them off. Undo snapshots keep them, and snapshots saved before them open with none.
- **Taking turns with Layers.** Opening Style closes Layers and opening Layers (⌘L) closes Style, so the canvas keeps about 700 pt at the 1,060 pt minimum, where two panels would leave about 450. The Style panel starts closed in every window (rule 2), while Layers keeps remembering whether it was open.
- **Undo.** Every pick is one step, and so is each slider drag (`setDraggingStyle`). Reset is one step, and on the screenshot it also puts back the background its format starts with and takes off the padding, size and fill.
- **Use for new captures** saves the background, fill, padding in points and size with the style (`CopiedStyle.canvas`) when the screenshot has padding, a size or a fill, and new captures open and copy with them. A plain canvas saves nothing, so new captures keep their format's background, as before. Styles saved before this decode with no canvas.
- **The style bar.** The style bar (#1094) keeps colour and width beside a mark, and More style the mark's own options. The panel has no colour or width, so the two don't overlap. Only the shadow and glow of a mark live in the panel alone.
- **Departures from the board.** The board rounds the swatches at 7 and the tiles at 8, and Shot uses the control radius 6 and the group radius 10. The board has 12 swatches, and Shot adds a rainbow custom colour as the 13th, since the popover had one, which makes the grid 7 wide rather than 6. The board leaves out Border and the shadow sliders, which Shot keeps, since #1096 keeps every option. The board's chosen rings are ink, but Shot draws them in the text colour so they show on the dark panel. Glow keeps its blue swatch, as the popover had, where the board's is orange. The popover's arrow keys between tiles give way to Tab and Space, since the panel stays open beside the canvas and shouldn't take the tools' keys.
- **Keyboard.** Every tool key and shortcut keeps working while the panel is open. With keyboard navigation on, Tab reaches every swatch, tile, slider, segment and the switch, each with the accent focus halo. The sliders and the segmented control take the arrow keys.
- **VoiceOver** reads the panel as a group named "Style", its headings as headings, each swatch and tile by name with the chosen one as selected, the sliders with their value ("Padding, 72 pt"), Size as a segmented control and the switch by its label.
- **Text size** scales the type and the tiles' names. The swatches keep their size, and the sections scroll.
- **Reduce Motion.** The panel arrives with the panel moment, a 240 ms spring sliding in from the right as the canvas narrows, and Reduce Motion makes that a 120 ms fade. Previews and edits are instant.
- **Increase Contrast** takes the headings, names and notes to the text colour, Reset to the text colour, and gives the swatches and tiles a 1 pt edge of 60% ink.

### Crop bar

#1097 builds crop mode on Edit › Image editor · crop and combine. The crop gets the board's look, and a floating bar at the canvas's foot holds what crop mode needs: the aspect, the size the crop keeps, Reset, Cancel and Crop. The aspect and Reset leave the style bar, where #1094 parked them. The bar is SwiftUI over the canvas that exists only in crop mode, so it costs nothing on the capture → copy path.

| Part | Look |
| --- | --- |
| Outside the crop | A wash of the backdrop's colour at 72%: `#ECEAE5` (dark `#151517`), so what's cropped off fades into the canvas. It replaces the old black dim and greying |
| Crop | A 1.5 pt ink outline inside its edge with a 1 pt edge outside it, white in light and black in dark, so it shows on any screenshot. A thirds grid of 1 pt white lines at 80% |
| Corners | Ink L shapes, 4 pt thick and 18 pt long, starting 3 pt outside each corner, with the same 1 pt opposite edge. Dark mode draws the light ink `#EDEBE6` |
| Side bars | 26 × 5 pt ink bars rounded at 2.5 across the middle of each side, 4 pt outside it. A side too short to hold one clear of its corners goes without |
| Bar | Centred at the canvas's foot, 16 pt up, with 6 pt above and below, 12 pt on the left and 7 pt on the right, and 10 pt between parts. Group radius 10. Fill white at 96% (dark `#2C2C30` at 96%) at the Float depth |
| Aspect | "Aspect" in 12 pt semibold tertiary text, then the shared segmented control (`BrutalSegmented`): Free, 1:1, 4:3, 16:9 |
| Size | The pixels applying the crop keeps, "1,480 × 560", in 11.5 pt bold mono tabular figures at 85% ink. It changes as you drag |
| Reset | A plain button, in the accent text colour, disabled while there's no crop to take off |
| Cancel, Crop | A 1 × 18 pt control-edge divider, then Cancel as a secondary button and "Crop ↩" as the main button |

- **Where it sits.** Centred at the foot, as on the board. When a centred bar would reach the zoom control, it moves to the right, and when the canvas is too narrow for that, such as with a side panel open at the minimum width, it sits centred 8 pt above them. `CropBar.origin` in ShotCore decides this, with tests. The hint at the bottom right steps aside in crop mode, since the bar takes the foot.
- **The image stays clear.** The bar reports how much of the canvas's bottom it covers (`EditorModel.cropBarClearance`), and in crop mode the canvas fits and scrolls the image in the room above it, so the crop's bottom handles are never under the bar. Leaving crop mode gives the room back.
- **One main button.** While cropping, Crop is the next step, so Copy in the title bar becomes a secondary button and returns as the main button when crop mode ends (rule 1). Copy and Save still apply the crop first.
- **What's unchanged.** Snapping to the screenshot's edges, Shift keeping the shape, Delete and Reset taking the crop off, picking another tool or clicking outside the canvas to apply it, the remembered aspect, and applying as one undo step all work as before. `CropEditing` still decides what applying changes, and `CropBar.keptSize` gives the size the bar shows, on whole pixels within the content as the frame's crop is taken.
- **Departures from the board.** The board's bar sits 22 pt up and rounds at 13; Shot's sits 16 pt up, level with the zoom control, and uses the group radius 10. The board leaves out the zoom control in crop mode, while Shot keeps it, so zooming in to place a crop still works, and moves the bar to stay clear of them. The board's subtitle reads "Cropping · 2 images"; Shot's keeps the size the image saves at. The board's segmented track rounds at 8 with a 6 pt thumb, the shared control's own values. The board draws ink on a light canvas only; in dark mode Shot draws the light ink with a black edge, so the marks show on the dark wash. Increase Contrast takes the wash to 85% and the thirds grid to solid white, which the board doesn't draw.
- **Keyboard.** C, Return, Esc and Delete work as before: C takes up the crop, Return applies it, Esc cancels and Delete takes it off. Crop's tooltip shows ↩, Cancel's esc and Reset's ⌫ on a keycap. With keyboard navigation on, Tab reaches the aspect control, Reset, Cancel and Crop, each with the accent focus halo, and the arrow keys move the aspect.
- **VoiceOver** reads the bar as a group named "Crop", the aspect as a segmented control named "Aspect", the size as "Crop size, 1,480 by 560 pixels", and Reset, Cancel and Crop as buttons.
- **Text size** scales the bar's type, so at Larger the bar is wider and moves right or above the foot sooner. The crop's marks keep their size.
- **Reduce Motion.** The bar arrives with the panel moment, a 240 ms spring rising 8 pt as it fades in, and Reduce Motion makes that a 120 ms fade. Dragging the crop and the size it shows are instant, as edits are.
- **Increase Contrast and Reduce Transparency** make the bar solid in the group colour. Increase Contrast adds a 1 pt edge of 60% ink, takes "Aspect" and the size to the ink, and strengthens the wash and grid as above.

### Layers panel

#1098 redraws the Layers panel on Edit › Image editor · crop and combine. It becomes a standard side panel flush with the canvas, and the Style panel moves to the same look, so the canvas runs edge to edge under the title bar rather than sitting in its own card. Rows follow the board: a drag handle, the kind's icon, the name and the eye, with the selected row in selection blue and the Frame row in yellow and ink while cropping. Reordering, renaming and the right-click menu work as before. The panel costs nothing until ⌘L opens it.

| Part | Look |
| --- | --- |
| Window | The title bar over a 1 pt hairline, then the canvas from edge to edge, with the open side panel flush against its right. The window's 24 pt inset and the canvas's card are gone |
| Panel | 256 pt wide on the side panel colour, `#F1EFEA` (dark `#242427`), with a 1 pt hairline down its left edge. 12 pt above and below, 10 pt at the sides (`sidePanel(width:)` in `Design/SidePanel.swift`, which the Style panel shares) |
| Header | "Layers" in 13 pt bold, and "⌘L" in 11 pt tertiary text on the right. 2 × 6 pt above and at the sides, 10 pt below |
| Frame row | Pinned at the top while the screenshot has a crop: the crop icon, "Frame" and its detail in 11 pt medium on the right, then a 1 pt hairline 6 pt above and below, 4 pt in from the sides. While the crop tool adjusts it, it's the accent with a 1.5 pt ink edge and a semibold name |
| Rows | 28 pt tall, 1 pt apart, 8 pt in from the left and 9 pt between parts: a 2 × 3 grid of 2.4 pt dots in ink at 40%, the kind's icon at 85% ink, the name in 13 pt, truncating at its end, then the eye at 50% ink |
| Crop badge | On a placed image with a crop of its own: "Crop" in 10 pt semibold on ink at 8%, radius 4, 5 pt at the sides. Clicking it adjusts that crop |
| Selected row | Selection blue at 14% with a 1 pt inner edge of selection blue at 35%, and a semibold name |
| Hidden row | 50% opacity, with the eye crossed out |
| Lock and bin | The lock shows while it's set; the lock and bin of an unlocked row show while the pointer is on it. Hover gives the row the hover fill |
| Footer | After a hairline, the screenshot under every layer: the image icon, "Screenshot" in 13 pt secondary text, and a lock in tertiary text |

- **What the Frame row says.** The crop's shape when it's one the crop tool offers, landscape or portrait ("16:9", "3:4", "1:1"), else the pixels it keeps ("1,480 × 560"). The board's "16:9" is the crop's own shape, not the Style panel's Size, since the Frame row stands for the crop. A side within a pixel of the shape counts, since crops land on whole pixels. While the crop tool adjusts the frame, it follows the crop being dragged, as the crop bar's size does. `FrameRowDetail` in ShotCore decides, with tests.
- **What's unchanged.** Clicking, ⌘-click and ⇧-click select; dragging the handle reorders, carrying a multiple selection, with Esc or a drop outside the list cancelling; ↑ and ↓ move the selection; Return or a double-click renames in place; Delete deletes; tool keys still pick tools while the list has focus; the right-click menu renames, crops a placed image, resets its crop, duplicates, deletes, locks and hides. The Frame row still takes the crop tool on a click, and hides or deletes the crop.
- **Taking turns with Style.** As before, opening one closes the other, so the canvas keeps about 700 pt at the 1,060 pt minimum. Both arrive and leave with the panel moment, and Layers keeps remembering whether it was open.
- **The canvas's foot.** The zoom control, hint, style bar and crop bar all sit inside the canvas, so they keep their 16 pt inset from its new edges and stay clear of the panel. The canvas is clipped to its bounds, since its scroll view otherwise draws over the title bar.
- **Departures from the board.** The board rounds rows at 7; Shot uses the control radius 6. The board shows the Frame row only in yellow; when the crop tool isn't on it, Shot draws it as a plain row, with the hover fill. The board leaves out the lock and bin, which Shot keeps on hover and keeps the lock showing while it's set, so the guide's Lock and Delete still have buttons. The Frame row keeps its eye, and its bin on hover. The board's dark panel isn't drawn, so dark uses `#242427`, the sidebar's dark value, between the window and the canvas backdrop. Increase Contrast takes the hairlines to 60% ink, which the board doesn't draw.
- **Keyboard.** ⌘L opens and closes the panel. With the list focused, ↑ and ↓ move the selection, Return renames, Delete deletes, and Esc cancels a drag or a rename.
- **VoiceOver** reads the panel as a group named "Layers" with its header as a heading. Each row reads its name, as selected when it is, with its eye, lock and bin as buttons, and Rename, Lock or Unlock and Delete as actions, so the buttons that hide until hover stay in reach. The Frame row reads "Frame, 16:9" as a button, and the footer "Screenshot, locked". The drag handle reads "Drag to reorder".
- **Text size** scales the header, names, Frame detail, badge and footer. Rows keep their 28 pt height, and names truncate first.
- **Reduce Motion.** The panel arrives with the panel moment, a 240 ms spring sliding in from the right, and Reduce Motion makes that a 120 ms fade. Selecting, hiding and locking are instant; a dragged row follows the pointer as before.
- **Increase Contrast and Reduce Transparency.** The panel is already solid. Increase Contrast takes the hairlines and the panel's edge to 60% ink, the grip, icons, detail, header shortcut and footer to the ink, the selected row's edge to solid selection blue, and a hidden row to 80% so its eye keeps 3:1.

### Combining images

#1099 finishes Edit › Image editor · crop and combine. Placed images get the board's soft shadow, and a placed image with a crop of its own gets a round crop badge on its corner that adjusts that crop. The Canvas menu moves from the canvas's foot back to the title bar, where the board puts it. Reopening a saved version keeps every mark and placed image editable, as before. None of this runs until an image is placed or the menu opens, so the capture → copy path is unchanged.

| Part | Look |
| --- | --- |
| Canvas menu | In the title bar after Undo, 4 pt apart from the tiles: "Canvas" in 12 pt at 85% ink with a 9 pt chevron in secondary text, on a toolbar button 28 pt tall. It holds Fit to Content, Trim to Image, a divider and Background…, which opens the Style panel |
| Compact Canvas menu | When the title bar is short of room, a 30 × 28 toolbar button with the `rectangle.dashed` symbol in the tool icon size, opening the same menu |
| Placed image | Starts with the Style panel's Soft shadow: 12 pt of elevation at 10% in the canvas's own shadow tint. It's part of the image, so Copy and Save include it |
| Crop badge | An 18 pt circle on the image's top-right corner, white (dark `#2C2C30`) with a 1 pt edge of ink at 20% (dark white at 18%) and a `0 1px 3px` drop of black at 20% (dark 40%). The `crop` symbol in 9 pt bold, 85% ink (dark the light ink) |

- **When the Canvas menu is compact.** The title bar uses the text menu when it fits with the file name at its 100 pt floor, and the tile otherwise (`ViewThatFits`). At the default text size that's any window wider than about 1,075 pt, so the tile shows at the 1,060 pt minimum width and at Larger text. The file name then grows into whatever room is left, up to 190 pt, as before.
- **The soft shadow.** In the image editor a placed image starts with the last style given to an image, and with Soft until one has been given (`EditorStyle.editorObjectStyle`, with `StyleKind.editorDefaultStyle` in ShotCore). Picking None keeps the next image plain too, and the Style panel's Reset puts Soft back and greys out while an image has it. Reset forgets the remembered image style rather than saving Soft, since the video editor reads the same preference and its clips should start plain. Images already placed, in documents and saved versions, keep their style. The video editor's clips are images too, and keep starting plain with a plain Reset, since #1099 covers the image editor only.
- **When the crop badge shows.** On a visible, unlocked placed image with a crop of its own, while the pointer is over it or it's selected. It steps 12 pt out along the corner's diagonal while the image's resize handles show, so the corner handle and the badge are both clear to click. It hides in crop mode, while text is typed, while a drag moves or resizes something, and while the image is scrolled wholly out of view; an image partly in view keeps all of its badge inside the canvas's edge. `CanvasCropBadge` in ShotCore decides, with tests. The canvas draws it over the marks, never into a copy or save.
- **What the badge does.** A click adjusts that image's crop with any tool, as the Layers panel's Crop badge does, and the pointer becomes a hand over it with a "Crop Image" tooltip. Double-click, C and Crop Image in the right-click menu still do the same, and Reset Crop in the right-click menu and in Layers takes the crop off.
- **The canvas's foot.** With the Canvas menu gone, the zoom control alone reports its size to `EditorModel.canvasFootLeading`, so the crop bar stays centred in narrower canvases before it moves right or up.
- **Reopening a saved version.** Unchanged: a version opens with its marks and placed images live, through the layers kept in Application Support, and Edit › Flatten makes it one plain image.
- **Departures from the board.** The board's title bar has no Undo or Style tiles beside the Canvas menu; Shot keeps them, puts Canvas after Undo so it sits next to Style, which its Background… opens, and falls back to a tile when the room runs out. The board rounds placed images at 10 with a hairline; a new image in Shot keeps square corners and no border, so it's the shadow alone, and the Style panel adds the rest. The board shows the badge while the screenshot's crop is adjusted; Shot hides it in crop mode, where the crop's handles take the canvas, and shows it on hover or selection rather than always, so the canvas stays quiet. The board's subtitle reads "Cropping · 2 images"; Shot's keeps the size the image saves at (see Crop bar).
- **Keyboard.** C crops the selected image, Return applies and Esc cancels, as before. With keyboard navigation on, Tab reaches the Canvas menu in either form with the accent focus halo, and the menu takes the arrow keys, Return and Esc. The badge has no keyboard stop, since C does the same for the selected image.
- **VoiceOver** reads the Canvas menu as "Canvas", a button that opens a menu, in either form. The badge is drawn on the canvas and isn't an element; the Layers row's Crop badge and its Crop Image action reach the same crop.
- **Text size** scales the Canvas menu's label, so at Larger the tile shows sooner. The badge keeps its size.
- **Reduce Motion.** Nothing here moves: the badge appears and goes in place, and the menu opens as every menu does.
- **Increase Contrast** takes the Canvas label and chevron to the ink, and the badge's edge to 60% ink (dark 60% light ink).

### Video editor toolbar

#1100 builds the video editor's title bar on Edit › Video editor and export, in light and dark. The file name, a times label, More tools, Copy, Export and Save used to share one row with a TRIMMED or EDITED badge. Now the title bar follows the image editor's (see Image editor toolbar): the file and what's changed beside the traffic lights, a few tiles, then Save or Save Copy and Export, the one main button, over a hairline. The window follows the appearance setting, as every Shot window does. Nothing here runs until the editor opens, so the capture → copy path is unchanged.

| Part | Look |
| --- | --- |
| File | The file name in Window type (13 semibold), truncating in the middle. Under it, in Caption type and tertiary text with tabular figures, the recording's length ("0:10.00") until something changes, then "Edited" and what the edit is: "Edited · trimmed · 1 cut · 2 annotations · 1 clip added · cropped", each part only when it applies |
| Tiles | Undo, a toolbar tile 30 × 28. #1102 removed More tools, since the lanes always show |
| Draw | A toolbar button 28 pt tall: the `pencil` symbol in the tool icon size and "Draw" in 12 pt semibold, 6 pt apart. It fills while a drawing tool is picked. Then a 1 × 20 pt control-edge divider with 6 pt either side |
| Save, Export | Save, or Save Copy once the edit is more than trims and cuts, is a secondary button; Export is the main button, last. While exporting, Cancel takes Save's place and Export dims |

- **What the subtitle counts.** `VideoEditSummary` in ShotCore reads the project, with tests: trimmed when the recording's start or end is off, a cut for each gap between the recording's clips on the main track, every annotation, every clip from another file (an added video's own sound isn't counted again), and cropped when the frame is. An edit it can't name, such as a moved or styled recording, reads "Edited" alone. The counts use the catalog's plural forms.
- **What Draw does.** It picks the last drawing tool, Arrow to start, or stops drawing when it's on. #1101 moved the drawing tools beside the video, so Draw no longer opens the tracks (see Video editor drawing tools). The tracks' own Annotate button is gone, since Draw replaces it.
- **One main button.** Export is the ink control. In crop mode the crop bar's Apply is the next step, so Export steps back to secondary, as Copy does in the image editor. The yellow Play button is #1102's; the light board draws it plain.
- **Window width.** Unchanged at 880 pt, which the export options row needed; #1103 moved them into a panel and kept 880 so the controls row fits beside it (see Video editor export panel). At Larger text the title bar still leaves about half its width empty at the window's opening size, so it needs no fallback form.
- **Departures from the board.** Copy has no button, as on the board; ⌘C still copies the edited video, and Save, Save Copy and Export each copy the file they write. More tools (T) stayed as a tile until #1102 made the lanes always show and removed it, as the board has none. The board's button reads Save Copy; Shot keeps Save while the edit is only trims and cuts, since then it replaces the recording, as before. The times label ("0:00.00 – 0:10.00 · 0:10.00") leaves the title bar; the length shows under the file name until something changes, and #1102's controls row brings the playhead's time back. The board rounds Draw, Save Copy and Export at 7; Shot uses the control token, 6. Draw keeps the toolbar's 12 pt label and pads 3 pt more each side to reach the board's 10.
- **Keyboard.** Shortcuts are unchanged: ⌘Z undoes and ⇧⌘Z redoes, ⌘S saves, ⌘C copies, Esc cancels an export. Undo's tip shows ⌘Z and Save ⌘S on keycaps. With keyboard navigation on, Tab reaches each button with the accent focus halo.
- **VoiceOver** reads the file name and subtitle as one element, Undo by name, Draw as "Draw", selected while it's on, and Save, Save Copy, Export and Cancel by their text.
- **Text size** scales the type and icons. At Larger the file name truncates first; the buttons keep their size.
- **Reduce Motion** keeps the main button's drop still and darkens it on press. Nothing else moves; the window grows and shrinks for the tracks as before.
- **Increase Contrast** takes the subtitle to the text colour, the hairline to 60% ink, and the secondary buttons' edges to 60% ink.

### Video editor drawing tools

#1101 moves the video editor's drawing tools out of the tracks, from Edit › Video editor and export, in light and dark. They used to be a row of tiles above the tracks, which Draw had to open. Now Draw shows a floating column of tools over the left of the video and one row of drawing options under it, and the tracks stay as they were. The column only shows while Draw is on, so the default view is unchanged, and nothing here runs before the editor opens.

| Part | Look |
| --- | --- |
| Column | A floating panel 16 pt from the video's left edge, centred top to bottom, with 4 pt padding and group corners (10). Fill white at 97% in light and `#2C2C30` at 92% in dark, with the Float depth's 0.5 pt edge and soft shadow. It's solid under Increase Contrast or Reduce Transparency |
| Tools | Select, Arrow, Line, Shape, Pen, Text, Sticky note, Highlight, Spotlight, Redact, Counter and Add image, then a 18 × 1 control-edge divider and Crop video, 2 pt apart. Each is a tool tile 32 × 30, the tool icon size, in the faded text colour. The selected tool is the ink button: accent fill, 1.5 pt ink edge and a 1.5 pt drop |
| Options | The drawing options sat in one row under the video while a tool was picked. #1104 replaced the row with the image editor's style bar at the top of the well (see Video editor inspector) |

- **What Draw does.** Draw shows the column and the options row with the last tool picked, Arrow to start, and hides them again. It no longer opens the tracks, and hiding the tracks no longer stops drawing. A new annotation still goes on a lane at the playhead, and #1102 made the lanes always show.
- **Crop video.** It leaves the drawing tool for crop mode, with the column still up and Crop video selected, then picks the tool again when the crop is applied, cancelled or undone. C does the same while drawing; outside drawing C crops as before. Picking another tool, or turning Draw off, keeps the crop, as in the image editor. Clicking Crop video again cancels it.
- **Short windows.** The column is about 440 pt tall at the default text size. When the video is shorter than that plus 12 pt above and below, the column scrolls.
- **Window height.** The options row added one row to the window while drawing, until #1104 moved the options into the style bar over the video, which adds none.
- **Departures from the board.** The board shows 8 tools; Shot keeps all 13 buttons, as the image editor's tool group does, so Line, Pen, Sticky note, Counter and Add image keep a place. Highlight and Redact keep their names, which the guide and Settings use, where the board says Highlighter and Blur. The tools keep their SF Symbols in the toolbar's 13 pt icon size rather than 15 px drawings. The board rounds the panel at 12 and the buttons at 8; Shot uses the group and control tokens, 10 and 6. The board sets the column in a well beside a smaller video. The well, `#151517` in dark and `#ECEAE5` in light with the video centred at radius 4, belongs to #1102, which added it, so the column now sits beside the video (see Video editor timeline).
- **Keyboard.** Only Crop video has a key, C, shown on a keycap in its tip. The drawing tools take no letter keys in the video editor, as before, since S splits, T shows the tracks and N turns snapping on and off. Esc stops drawing, or cancels a crop and returns to the tool. With keyboard navigation on, Tab reaches each tile with the accent focus halo.
- **VoiceOver** reads the column as "Draw tools", each tile by its tool's name, with the selected one marked selected, and Crop video and Add an image by name.
- **Text size** scales the icons; at Larger the column is a little taller and scrolls sooner.
- **Reduce Motion** fades the column in and out over 120 ms instead of sliding it in from the left.
- **Increase Contrast** makes the panel solid, adds a 1 pt ink edge at 60%, and keeps the selected tool's ink edge.

### Video editor timeline

#1102 redraws everything under the video editor's title bar, from Edit › Video editor and export, in light and dark: the well the video sits in, the controls row and the lanes. The video used to fill the window's width with a 2 pt ink edge, over a round yellow Play button and a trim strip, with the lanes behind More tools. Now the video sits in a well with the drawing tools beside it, and the controls area under it always shows the lanes, so trimming, cutting and splitting happen in one timeline. Nothing here runs until the editor opens, so the capture → copy path is unchanged.

| Part | Look |
| --- | --- |
| Well | `#ECEAE5` in light and `#151517` in dark, filling the height the controls leave. The video is centred at its own shape with 64 pt either side, room for the draw column at 16 pt in, and 20 pt above and below. It has tiny corners (4) and a soft shadow, plus a 1 pt edge at 8% ink in light (`VideoWell` in ShotCore) |
| Controls area | White in light and `#1F1F22` in dark, under a 1 pt hairline, with padding 10 above, 14 at the sides and below, and 10 between the row and the lanes |
| Row | Play, a bordered button 34 × 30. The time, "0:02.40 / 0:10.50", in 13 pt bold mono with tabular figures, the length in medium weight and tertiary text. A 1 × 18 divider, then Split, Cut, Trim idle and Add media as toolbar buttons with 13 pt icons. On the right, Snap as a toolbar tile, a divider, and zoom: − and + either side of an 80 pt slider |
| Ruler | 14 pt tall: 10 pt medium mono labels in tertiary text, each beside a 4 pt tick |
| Lane names | A 70 pt column on the left, pinned while the lanes scroll sideways: Draw, Text, Video or Sound in 10.5 pt secondary text. Hovering a lane shows its lock, hide or mute switches beside its name, and a switch that's on always shows |
| Annotation lanes | 22 pt tall, control corners (6). Each annotation is `#DCD6F2` with `#2E2660` text in light and `#4A3D7A` with light text in dark, with a 1 pt edge, its symbol and name. The selected one is selection blue with white semibold text and a 1.5 pt white edge |
| Video lane | 46 pt tall, control corners, each clip a filmstrip of the recording with a 1 pt hairline edge, 1 pt in from each end so clips that meet show a gap. The selected clip has a 2 pt selection-blue edge. Yellow trim handles, 8 pt wide and rounded on their outer side, sit at the lane's ends, with a 1.5 pt ink edge in light. What's trimmed off shows greyed |
| Cut badge | "CUT 1.2s" at each cut, centred on it at the top of the Video lane, in 9.5 pt bold white on ink with tiny corners |
| Sound lanes | 26 pt tall, control corners, a green waveform (`#248A3D` light, `#34C759` dark) over a 12% tint of it |
| Playhead | A 2 pt line with a 12 pt cap in the ruler, rounded 2 at the top and 6 at the bottom: ink in light, white with a faint shadow in dark |

- **The lanes always show.** A plain recording shows the ruler, the Video lane and, if it has sound, the Sound lane; there are no empty lanes. Annotation, picture and sound lanes appear once the project has them. The trim strip is gone, since the Video lane trims, cuts, splits and Shift-selects as the lanes did. More tools and its T key are gone too.
- **What the actions do.** Split (S) splits at the playhead. Cut (⌫) cuts out the selected section, or else the selected clip, and closes the gap; it dims while nothing is selected. Trim idle runs Edit › Trim Idle Time, shows a spinner while it looks, and dims when the edit is more than trims and cuts. Add media opens the menu the tracks' Import button had: Add Video or Audio at Playhead… and Add Video to End…. Snap (N) moved here from the tracks' toolbar. The Inspector was a tile here too until #1104 moved it to the title bar and a side panel.
- **Zoom.** The slider runs evenly per zoom step from the whole project to the closest, through `TimelineZoom.sliderPosition(for:)`. − and + step it, as ⌘− and ⌘+ do, and ⌘0 fits the project again. Pinching still zooms.
- **Narrow windows.** When the row doesn't fit, which happens at Larger text in a window near its 880 pt minimum, the four actions drop their names and keep their icons and tips.
- **Window height.** `chromeHeight` counts the well's insets and the controls area with the ruler and Video lane; #1103 took out the export options' row. Every other lane, the drawing options and the inspector add to `tracksExtraHeight`, which grows the window as before. The lanes scroll once the video would drop under 200 pt.
- **Departures from the board.** Play is a plain bordered button in both appearances, as the light board draws it, since Export is the screen's ink button (rule 1); the dark board draws it yellow. The cut badge is ink rather than record red, since a cut can be undone and red is kept for recording (rule 6). It sits inside the top of the Video lane rather than above it, so it never covers the lane above. The selected video clip has the selection-blue edge every selected clip has, where the board rings it in yellow in dark and ink in light; the yellow stays on the trim handles at the lane's ends. Shot names the board's Mic lane Sound, since it holds the recording's sound or an added sound file, whichever it is. Board radii 7 and 8 become the control token (6); the lane names come from what each lane holds, so a lane of text reads Text. Snap has a tile the board doesn't draw, so it keeps a place. The zoom slider is the shared `BrutalSlider` with its standard knob. Clips that meet show a 2 pt gap rather than the board's wider one.
- **Keyboard.** Space plays and pauses, ← and → step a frame, ⇧← and ⇧→ a second, Home and End jump to the ends, S splits, ⌫ cuts, N snaps, and ⌘−, ⌘+ and ⌘0 zoom. Play, Split, Cut, Snap and the zoom buttons show their keys on keycaps in their tips. With keyboard navigation on, Tab reaches each control with the accent focus halo, and the zoom slider takes the arrow keys.
- **VoiceOver** reads Play or Pause, the time as "Playhead", with the time and length as its value, each action by name, Add media as a button that opens a menu, and Snap as selected while it's on. The lanes are one element, "Timeline", whose value is the playhead and which adjusts by a second.
- **Text size** scales the type and icons. At Larger the lane names stay whole and the switches give way, since the lane's right-click menu has them; in a narrow window the actions drop their names.
- **Reduce Motion.** Nothing here moves except the draw column, which fades instead of sliding, and the playhead, which follows the time.
- **Increase Contrast** takes the hairline to 60% ink, and the lane names, the length after the time and the lane switches that are off to the text colour.

### Video editor export panel

#1103 moves the video editor's export options into a side panel, from Edit › Video editor and export, in light and dark. They used to be a row under the timeline that every recording showed, with Export in the title bar writing the file straight away. Now Export opens a panel on the right with the format and its options, the speed, and a card at its foot with the estimated size, the length and the button that writes the file. The panel starts closed (rule 2), so the default view is the video and its timeline, and the size estimate, which reads frames, runs only while the panel shows.

| Part | Look |
| --- | --- |
| Panel | 272 pt wide on the side panel colour with a hairline down its left edge (`sidePanel(width:)`), right of both the well and the controls area, from the title bar's hairline to the window's foot |
| Header | "Export" in 13 pt bold, and Reset on the right in 12 pt medium accent text (`PanelLinkStyle`, shared with the Style panel), disabled text when every option is at its default. 16 pt above and at the sides, 18 pt below |
| Groups | 16 pt sides, 18 pt apart, in a scroll view. Each is a heading in 11.5 pt semibold tertiary text over the shared segmented control (`BrutalSegmented`) the panel's width, 7 pt apart: Format (MP4, GIF), Frames per second (10, 15, 24) and Width (480, 720, 1080, Full) for a GIF, and Speed (1×, 1.5×, 2×). An MP4 shows Mute, "Mute" in 12.5 pt with the shared switch on the right, in place of the GIF's two groups |
| Speed note | While Speed is locked, a note in Caption type and tertiary text under it says why |
| Summary card | Pinned under the scroll view, 16 pt in: the group fill at the Group depth, radius 10, padding 12, 10 pt between parts. "Estimated size" and "Length" in 12 pt secondary text, their values on the right in 12 pt mono with tabular figures, the size in bold ("≈ 4.2 MB", "0:10.00") |
| Export button | Export GIF or Export MP4, the main button the card's width with 2 pt more padding above and below. Under it, "Saved beside the recording and copied" in Caption type and tertiary text, centred |
| Exporting | The button gives way to "Exporting…" in 12 pt semibold with the percentage in mono on the right (a small spinner while the export can't tell), the shared progress bar while it can, and Cancel, a secondary button the card's width |

- **What Export does.** The title bar's Export opens and closes the panel; it no longer writes a file itself. The panel's Export GIF or Export MP4 writes a new file next to the recording and copies it, as Export did. The panel stays open afterwards, so a second export with other options is one click.
- **One main button.** While the panel is closed, the title bar's Export is the ink control. Once it opens, the panel's button is the next step, so the title bar's Export steps back to secondary, and in crop mode both are secondary while the crop bar's Apply is the ink. The selected drawing tool stays an allowed ink in its column.
- **Options.** Every change is one undo step and is remembered, as before, so the next export and Quick Access's Export GIF use it. Reset puts the defaults back in one step. The options are disabled while anything exports, including Save and Save Copy, and the card shows "Exporting…" and Cancel for those too.
- **Length.** `VideoExportPanel.length(of:options:isComposite:)` in ShotCore, with tests: the kept length at the chosen speed, or at 1× for a drawn MP4, which ignores the speed, and a GIF's first 60 seconds, with a note ("A GIF keeps the first 60 seconds.") when it stops there. `VideoExportPanel` also lists the groups for each format and decides the speed lock.
- **Window size.** The panel takes its width from the video and the timeline, as the image editor's panels take it from the canvas, so the window doesn't move. The minimum stays 880 pt, which leaves the video side 608 pt; there the controls row drops the actions' names (see Video editor timeline). `chromeHeight` no longer counts the export row, so the window opens 52 pt shorter and can be made that much shorter. The panel's groups scroll when the window is too short for them.
- **Departures from the board.** The board shows a GIF's options only; Shot shows Mute for an MP4, as the row had. The light board draws Export GIF plain and the dark board yellow; Shot makes it the ink button in both, with the title bar's Export stepping back, since the panel's button is the next step once it's open (rule 1). The title bar's Export doesn't take the secondary button's on look, the accent halo, which would read as keyboard focus and add a second yellow mark beside the panel's button. The light board's panel is `#ECE9E3`; Shot uses the side panel colour, `#F1EFEA`, as Style and Layers do. The board rounds the button at 9 and pads it 7; Shot uses the main button's control radius, 6, with 7 pt padding. The board's Length is "0:09.3"; Shot writes hundredths, as the title bar and controls row do. The board has no locked Speed, progress or truncation states, which Shot adds as notes and the card's exporting state.
- **Keyboard.** Esc cancels an export, then clears the selection, then stops drawing, then closes the panel. Every other shortcut keeps working while it's open. With keyboard navigation on, Tab reaches Reset, each segmented control, the switch and the button with the accent focus halo, and the segmented controls take the arrow keys. Cancel's tip shows Esc on a keycap.
- **VoiceOver** reads the panel as a group named "Export", with its header and group headings as headings, each segmented control by its selected segment, Mute as a switch, each card row as one element ("Estimated size, ≈ 4.2 MB"), and the button by its text. The title bar's Export reads as selected while the panel is open. The progress reads as a progress indicator with its percentage.
- **Text size** scales the type. At Larger the note under the button wraps to two lines, and the groups scroll sooner.
- **Reduce Motion.** The panel arrives with the panel moment, a 240 ms spring sliding in from the right as the video narrows, and Reduce Motion makes that a 120 ms fade. Changing an option is instant.
- **Increase Contrast** takes the headings, card labels and notes to the text colour, Reset to the text colour, and the panel's hairline and the segmented tracks to 60% ink. The panel is already solid.

### Video editor inspector

#1104 moves the video editor's Inspector into the side panel the Export panel uses, from Edit › Video editor and export, in light and dark. It used to be two rows of controls under the video, with its shadow, border and corners in the Style popover, and a sliders tile beside zoom opened it. Now a tile in the title bar, or ⌥⌘I, opens a panel on the right with the selection's properties and keyframes, its animations, the image editor's style sections and a clip's crop. The drawing options row under the video gives way to the image editor's style bar, so neither drawing nor the Inspector changes the window's height. The boards draw neither, so the panel follows the Export panel and the Style panel. Nothing here runs until the editor opens, so the capture → copy path is unchanged.

| Part | Look |
| --- | --- |
| Inspector tile | A 30 × 28 toolbar tile with the `slider.horizontal.3` symbol in the title bar after Draw, filled while the panel is open. Its tip shows ⌥⌘I on a keycap |
| Panel | 272 pt wide on the side panel colour with a hairline down its left edge (`sidePanel(width:)`), where the Export panel sits |
| Header | "Inspector" in 13 pt bold, and Reset on the right in 12 pt medium accent text (`PanelLinkStyle`), disabled text when there's nothing to put back. 16 pt above and at the sides, 18 pt below |
| Sections | 16 pt sides, 18 pt apart, in a scroll view. The selection's name ("Selected clip", "Selected annotation", "Selected sound") in 12 pt bold, then headings in 11.5 pt semibold tertiary text (`panelHeading()`) |
| Position | "Position" in 12 pt semibold tertiary text with its diamond on the right, over X and Y fields sharing the panel's width, each a shared field with 12 pt mono tabular figures |
| Sliders | Scale, Turn, Opacity, Volume or Drawn: the name, the value in 12 pt tabular figures ("1.50×", "45°", "80%") and the diamond over the shared slider (`BrutalSlider`) the panel's width (`PanelSliderRow`, shared with the Style panel) |
| Diamond | 22 × 20, control radius 6. A keyframe at the playhead: the accent with a 1 pt ink edge and an ink `diamond.fill`. Keyframes elsewhere: a `diamond` outline at 85% with a 3 pt dot. None: the outline at 45% |
| Keyframes | Once the selection has any: Easing with a pop-up menu (`BrutalPopUp`) while a keyframe is selected, or a note saying how to select one, then Clear Keyframes as a secondary button |
| Animations | Fade In, Fade Out, Pop, Slide In and Draw On, whichever suit the selection, as secondary buttons two to a row |
| Style | A separator, "Style" in 12 pt bold with its own Reset, then the Style panel's Corners, Shadow and Border (`StyleSection`), whichever the selection takes |
| Crop | A clip's Crop, and Reset Crop once it has one, as secondary buttons |
| Frame | With nothing selected: the video's size in 12 pt bold mono ("1280 × 720") with Crop on the right, then a note in Caption type |
| Keyframe marks | On the lane's bottom edge, 9 pt squares turned 45°: the accent with a 1.5 pt ink edge, or selection blue with a 1.5 pt white edge when selected |
| Style bar | While Draw is on, the image editor's style bar (`StyleBar`) centred 12 pt down from the top of the well, with More style holding the rest (see Style bar) |

- **What it shows.** `VideoInspectorPanel.sections` in ShotCore decides, with tests: the properties, then Keyframes once there are any, then Animations when any preset suits, Style when the selection takes a shadow, and Crop for a clip. A sound gets its volume and keyframes only, and nothing selected gets Frame. `VideoInspectorPanel` also maps each slider to its property (doublings for the scale, degrees for the turn) and writes its value.
- **Reset.** The header's Reset puts the selection's position, scale, turn, opacity, volume and drawn amount back and clears its keyframes, leaving the crop and style. With nothing selected it takes the frame's crop off. The Style section's Reset puts the shadow, border and corners back. Each is one undo step, and so is each slider drag.
- **Taking turns with Export.** Opening the Inspector closes the Export panel and the reverse (`VideoSidePanel.toggling`), so the video keeps 608 pt at the 880 pt minimum, where two panels would leave about 330. Export starts closed in every window (rule 2). The Inspector reopens if it was open when the last window closed (`videoEditorShowsInspector`), as Layers does; opening Export forgets that.
- **One main button.** The Inspector has no ink control, so the title bar's Export stays the main button while it's open. The selected drawing tool stays an allowed ink in its column.
- **Drawing options.** The style bar replaces the row under the video. It holds six swatches and the widths, or a blur's or spotlight's main choices, and More style holds the shape, the fill, white and custom colours, alignment, a blur's amount, a spotlight's strength and soft edge, and Reset, which the row didn't have. The select tool with nothing selected and crop mode show no bar. The tool's one-line summary, which the row showed for tools without options, stays in the draw column's tips.
- **Window height.** Neither the drawing options nor the Inspector adds to `tracksExtraHeight` any more, so the window keeps its height when Draw or the Inspector is turned on.
- **Handles stay in the well.** A clip scaled past the video drew its handles clipped to the well, but they still caught clicks over the title bar and the controls. The well now has a content shape as well as its clip, so clicks outside it reach what's there.
- **Departures from the board.** The boards draw no Inspector, so its look comes from the Export and Style panels. The Inspector tile has no board either; it sits after Draw, as Style and Layers sit in the image editor's title bar. Easing is a pop-up menu rather than a segmented control, since its five names don't fit 240 pt. The selected keyframe on the lane is selection blue rather than the old pink, since it's a selected thing (rule 6). The style bar sits at the top centre of the well rather than beside the mark, as the image editor's does for the next mark, since a video's marks move over time. The popover's arrow keys between style tiles give way to Tab and Space, as in the Style panel.
- **Keyboard.** ⌥⌘I opens and closes the Inspector, and K keys every property at the playhead. Every other shortcut keeps working while it's open. With keyboard navigation on, Tab reaches Reset, each field, slider, diamond, pop-up, button and tile with the accent focus halo, and the sliders take the arrow keys.
- **VoiceOver** reads the panel as a group named "Inspector", with its header, selection name and section headings as headings. Each slider reads its name and value ("Scale, 1.50×"), each field "Horizontal position" or "Vertical position", and each diamond "Add Scale keyframe" or "Remove Scale keyframe". Easing reads as a pop-up button with its value, and the frame's size as "Frame size, 1280 by 720 pixels". The title bar's tile reads "Inspector", selected while the panel is open.
- **Text size** scales the type, the diamonds' symbols and the tile's icon. The sections scroll sooner, and the animation buttons shrink their names a little before they'd clip.
- **Reduce Motion.** The panel arrives with the panel moment, a 240 ms spring sliding in from the right as the video narrows, and Reduce Motion makes that a 120 ms fade. The style bar fades in from 96% over the same moment, or over 120 ms. Edits are instant.
- **Increase Contrast** takes the headings, names, notes and Reset to the text colour, gives the style tiles a 1 pt edge of 60% ink, and the panel's hairline and the sliders their 60% ink. The panel is already solid, and the style bar becomes solid with a 60% ink edge, as in the image editor.

### Video editor crop and transform

#1105 gives the video editor's crop mode and clip handles the image editor's look, from Edit › Image editor · crop and combine, in light and dark. Crop mode used to draw a white outline with yellow square handles over a black dim, under a "CROP FRAME" or "CROP CLIP" bar at the top of the video. Now it has the image editor's wash, ink outline, thirds, corners and side bars, and the image editor's crop bar at the well's foot. The selected clip's yellow box and pink rotate knob become the selection style the annotations on the same video use. The video boards draw neither, so both follow the image editor. Nothing here runs until crop mode starts or a clip is selected, so the capture → copy path is unchanged.

| Part | Look |
| --- | --- |
| Outside the crop | A wash of the well's colour at 72%, `#ECEAE5` (dark `#151517`), the image editor's backdrop colour, over everything the crop can reach |
| Crop | As in the image editor: a 1.5 pt ink outline inside its edge with a 1 pt edge outside it, white in light and black in dark, and a thirds grid of 1 pt white lines at 80%. Turned with the clip when it's a clip's crop |
| Corners, side bars | ShotCore's `CropMarks`, shared with the image editor: 4 × 18 pt ink Ls starting 3 pt outside each corner, and 26 × 5 pt bars rounded at 2.5 across each side long enough to hold one. Dark mode draws the light ink `#EDEBE6` |
| Handles | Invisible 24 pt squares on each corner and side, turned with the crop |
| Crop bar | The image editor's (`CropBarOverlay`, now generic over `CropBarEditing`), centred 16 pt up from the well's foot: Aspect, the size the crop keeps, Reset, Cancel and "Crop ↩" |
| Clip outline | A 1.5 pt dashed line, 4 on and 3 off, in the system accent colour round the part of the clip a crop leaves (`SelectionStyle`) |
| Clip handles | 8 pt white squares with a 1.5 pt accent edge on the corners, in 20 pt hit areas (`SelectionHandle`) |
| Rotate handle | The same handle as a dot, 22 pt above the top edge's middle on a 1 pt accent stem |

- **Where the bar sits.** `CropBar.origin` places it, as in the image editor, with the draw column's 40 pt as the foot to keep clear of when a crop started from the drawing tools keeps the column up. The bar reports how much of the well it covers (`cropBarClearance`), and `VideoWell.videoRect(showing:in:bottomClearance:)` fits the video above it with an 8 pt gap, so the crop's bottom handles are never under it. Leaving crop mode gives the room back.
- **What the bar shows.** The size is the frame's crop as `VideoFrameCrop.outputRect` exports it, on even pixels, or a clip's crop in its picture's pixels (`CropBar.keptSize(videoDraft:croppingFrame:canvas:)`). Reset greys out while the crop shows everything.
- **One main button.** Crop is the ink while cropping, so the title bar's Export and the Export panel's button stay secondary, as before (rule 1).
- **The rotate handle stays in reach.** On a clip that fills the video, 22 pt above its top edge is past the well's 20 pt margin, where the handle was clipped and out of reach. `TransformHandles.rotateHandle` in ShotCore moves it 22 pt inside the top edge whenever above would leave the well, with tests.
- **What's unchanged.** C, Inspector › Crop, Frame's Crop and a double-click on the clip start a crop. Shift keeps the shape, the remembered aspect holds the crop to it, and applying is one undo step. Moving, scaling about the centre and rotating are one undo step each. The handles hide in crop mode and while the playhead is off the clip, and the well's content shape still stops a scaled-up clip's handles catching clicks over the title bar.
- **Departures from the board.** The boards draw no video crop or clip handles. The clip's outline uses `SelectionStyle`, the system accent colour, as the annotations in both editors do, rather than the boards' fixed `#2B7FFF` 1 pt dashed outline 3 pt out, so a clip and an annotation selected on the same video look alike; the accent is blue unless someone changes it in System Settings. The video crop has no hint and no zoom control, so its bar centres in the well. The wash uses the well's colour, which is the image editor's backdrop colour. The bar names its target to VoiceOver ("Crop Frame" or "Crop Clip") instead of the old visible caption, since the crop's position on the video already shows which is being cropped. Delete now resets the crop in crop mode, as in the image editor, so Reset's ⌫ keycap is true.
- **Keyboard.** C, Return and Esc work as before, and Delete resets the crop. Crop's tip shows ↩, Cancel's esc and Reset's ⌫ on a keycap. With keyboard navigation on, Tab reaches the aspect control, Reset, Cancel and Crop with the accent focus halo. The clip handles have no keyboard stop; the Inspector's Position, Scale and Turn do the same from the keyboard.
- **VoiceOver** reads the bar as a group named "Crop Frame" or "Crop Clip", with the aspect, size and buttons as in the image editor, and the crop over the video as one element of the same name.
- **Text size** scales the bar's type, so at Larger it's wider and the video fits a little higher. The crop's marks and the clip's handles keep their size.
- **Reduce Motion.** The bar arrives with the panel moment, a 240 ms spring rising 8 pt as it fades in, and Reduce Motion makes that a 120 ms fade. The video's refit as crop mode starts and ends is instant, as in the image editor. Drags are instant.
- **Increase Contrast** takes the wash to 85% and the thirds grid to solid white, and makes the bar solid in the group colour with a 1 pt edge of 60% ink, as in the image editor. The clip handles keep the accent colour on white.

### Gallery window

#1106 moves the gallery out of the Settings window into a window of its own, from Library & Settings › Gallery and the Settings sidebar's "Open Gallery". The gallery used to be the first section of Settings, so opening Settings showed the gallery and its folder watching started with it. Now Settings opens on General, and the gallery window does the gallery's work only while it's open. The grid, sidebar, preview and empty state inside it are unchanged until #1107–#1110, so this section covers the window and the ways in.

| Part | Look |
| --- | --- |
| Gallery window | A standard window titled "Gallery", 1224 × 764 pt at first as on the board, 640 × 420 pt at the smallest. Since #1107 the title bar shows no title: the sidebar runs under the traffic lights and the toolbar names what's shown (Gallery sidebar) |
| Settings window | Titled "Settings", 1080 × 720 pt at first as before, with no Gallery section; it opens on General |
| Open Gallery | A row at the foot of the Settings sidebar: the `square.grid.2x2` symbol on a tile, "Open Gallery", and a small `arrow.up.right`. #1111 redrew it and dropped the icons-only rail (Settings window and sidebar) |

- **Ways in.** The menu bar menu's Gallery row, `shot://gallery`, Open Gallery in Settings and `shot://settings?section=gallery` all open the gallery window. ShotCore's `ShotURL` turns the last into `.gallery`, with a test, so older links and scripts keep working.
- **Its size and place.** The window saves its frame under "Gallery" with AppKit's frame autosave, so it opens where it was last closed, at the same size, across launches. The first time, it opens centred, no larger than the screen under the pointer.
- **Two windows.** Settings and the gallery open, close and come forward on their own. ⌘W closes the one in front, ⌘, opens Settings from either, and Shot leaves the Dock once both are closed, as before.
- **Kept in captures.** Screenshots, scrolling captures and recordings keep both windows in, as they kept the old one, and leave Shot's overlays and panels out (`ShotWindows.capturable`).
- **Memory.** Closing the gallery stops watching the folder and drops its views, as closing the old window did, so a closed gallery costs nothing. Closing Settings stops a microphone test or camera preview and drops its views.
- **Departures from the board.** The board's sidebar runs under the traffic lights and puts the title, "All Captures" and its count, in the toolbar; #1107 and #1108 build those. #1106 showed "Gallery" in the title bar until #1107 put the heading in the toolbar. The Settings sidebar's Open Gallery row kept the old sidebar rows' look, with a 28 pt tile and the 2 pt ink edge, until #1111 redrew the whole sidebar with the board's 22 pt white tile (Settings window and sidebar). At larger text sizes, or in a long translation, the arrow hides so the label stays on one line.
- **Keyboard.** The gallery's keys work in its window as they did in Settings (Keyboard shortcuts › Gallery). With keyboard navigation on, Tab reaches Open Gallery in the Settings sidebar, and Space opens the gallery.
- **VoiceOver** reads Open Gallery as a button of that name. The arrow is hidden from it. The windows are named "Gallery" and "Settings", which VoiceOver and Mission Control show.
- **Text size** scales Open Gallery's label and symbols. At Larger its label still fits on one line in the default sidebar width.
- **Reduce Motion.** Nothing here moves. The windows open with the system's own window animation.
- **Increase Contrast** changes nothing here. Since #1111, Open Gallery's arrow turns ink (Settings window and sidebar).

### Gallery sidebar

#1107 gives the gallery window the board's see-through sidebar from Library & Settings › Gallery, in light and dark. It used to be a folder list that started closed, with All, Screenshots, Videos and GIFs as a segmented control in the toolbar and the tags as a row of chips under it. Now Library, Folders and Tags are sections of one sidebar that starts open, one row is picked at a time, and the foot shows how much room the captures take. Nothing here runs during a capture, so the capture → copy path is unchanged.

| Part | Look |
| --- | --- |
| Sidebar | 220 pt wide by default, 150–360 pt by dragging its edge, the full window height under the traffic lights, on `SidebarMaterial` (solid `#ECE9E3`, dark `#242427`, with Increase Contrast or Reduce Transparency) with a 1 pt separator on its right |
| Sidebar button | `sidebar.left` in a toolbar button just after the traffic lights. With the sidebar hidden, the toolbar starts after it |
| Headings | Library, Folders and Tags in 11 pt semibold tertiary text. Folders has a New Folder button (`folder.badge.plus`) and Tags a "Rename or remove tags" button (`ellipsis.circle`) at the end, each 12 pt tertiary with a hover fill |
| Rows | 13 pt regular text, 5 × 8 pt padding, a 9 pt gap after an 18 pt icon slot and the count in 11.5 pt tertiary tabular figures. Hover fills with `Brutal.hover` |
| Picked row | Yellow, `#FFD43B` (dark `#F2CC4A`), with a 1.5 pt ink edge and semibold text. Its icon and count turn ink, which stays dark on yellow in dark mode (`inkOnFill`) |
| Library | All Captures (`square.grid.2x2` in ink), Screenshots (`photo`, `#5B4BD6`, dark `#A99BFF`), Recordings (`video`, `#C4271E`, dark `#FF7B72`) and GIFs (`play.rectangle.on.rectangle`, `#1D6FB8`, dark `#7DBBFF`), at 13 pt medium |
| Folders | The save folder, then its folders indented 16 pt a level, each with `folder` in secondary text. A chevron in the indent opens the folders inside one. Hover or picking shows the "…" menu over the count |
| Tags | A 10 pt dot in the tag's Finder colour, or tertiary grey for a tag that isn't named after one, then the tag and its count |
| Drop target | A folder something is held over fills with selection blue at 18% under a 1.5 pt selection-blue edge |
| Storage | Under a hairline: the save folder from the home folder (such as "Pictures/Shot") in 11.5 pt secondary and the captures' size in tertiary, a 4 pt bar of that size against the disk in ink on `quietTrack`, and "Make room…" in `PanelLinkStyle` |
| Toolbar heading | The picked row's name in 15 pt bold and "N items" in 11 pt tertiary, in the title bar beside the sidebar. #1108 restyles the rest of the toolbar (Gallery grid, toolbar and selection bar) |

- **One row at a time.** ShotCore's `GallerySource` is the picked row, as a kind, a folder or a tag, and gives the grid its filter, folder and tags, with tests. Picking a folder shows every kind in it, and picking a tag shows it in every folder. Typing `tag:name` in the search still narrows any row, so combining is still possible.
- **Counts.** `GalleryCounts` counts each Library row, the captures directly in each folder, and each tag whatever its case, plus their size together, once when the list or the tags change, never per row. A count of 0 shows nothing.
- **Make room…** shows All Captures sorted Largest first and clears the search, so the biggest captures are at the top to trash. The bar measures the captures against the disk's whole size (`volumeTotalCapacity`), so it's usually a sliver; a sliver of 4 pt shows whenever there are captures. Make room… hides when the folder has none.
- **What's kept.** Every folder action in Organise your captures works as before: New Folder, New Folder Inside, Rename (also by double-click), Save New Captures Here with its arrow mark, Show in Finder, Move to Trash…, dragging captures and folders onto a folder, the 700 ms open while dragging over a closed folder, and dropping on the space below the rows to bring a folder to the top. The tag manager moved from the chip row's tag button to the Tags heading, and right-clicking a tag still offers Rename or Remove Tags… and Remove.
- **What went.** The segmented filter, the tag chip row, the "All" row at the top of the folder list (All Captures replaces it) and the lines that joined nested folders.
- **Focus.** A new or renamed folder's field takes focus a turn after it appears. Taking it at once lost it to the search field, so typing went into the search.
- **Departures from the board.** The sidebar starts open, which rule 2 would close: it's how the gallery filters by kind now, so hiding it would hide the filters, and it's navigation, as in Finder and Photos, not a tool panel. The board rounds rows at 7; Shot uses the control radius 6. Recordings is "Videos" in the board's segmented control of old and "Recordings" in the board's sidebar; Shot follows the sidebar. The board gives every tag a colour; Finder tags only have one when named after a Finder colour, so the rest are grey (rule 6). The board's GIF icon is a drawn box; Shot uses `play.rectangle.on.rectangle`. The board has no sidebar button, New Folder button, tag manager button, chevrons or drop highlight; Shot needs them for hiding the sidebar and for the folder and tag actions it already had. The board's storage bar is 38% full for 2.1 GB, which no disk gives; Shot's bar is the true share. The board's folder count for the save folder is blank; Shot shows it, as for every folder.
- **Keyboard.** The arrow keys still move through the grid wherever focus is. With keyboard navigation on, Tab reaches the sidebar button and each Library and tag row, and Space picks one. Folder rows aren't Tab stops, as before, since a button would swallow the drag that moves a folder; VoiceOver and the right-click menu reach them.
- **VoiceOver** reads each row's name, its count as "N captures" and whether it's selected, the headings as headings, and the storage as "Captures in Pictures/Shot" with its size. The bar is hidden from it.
- **Text size** scales every row, heading, count and the storage text. At Larger the rows grow taller and the sidebar scrolls sooner; its width doesn't change, so long names truncate in the middle.
- **Reduce Motion.** The sidebar slides in and out with the panel moment, a 240 ms spring, which Reduce Motion makes a 120 ms fade.
- **Increase Contrast** makes the sidebar solid in the Sidebar colour, and the headings, counts, storage text and chevrons ink.

### Gallery grid, toolbar and selection bar

#1108 redraws the rest of the gallery's toolbar, its grid of tiles and what happens once something is selected, from Library & Settings › Gallery, in light and dark. The tiles used to have a 2 pt ink edge, a yellow play button on recordings and a violet selection, and a footer held the count, Select All and every action. Now tiles are rounded thumbnails with a quiet edge, a selected tile has a selection-blue ring and tick, and a bar floats up from the foot of the grid while something is selected, with Copy as its one ink button. Nothing here runs during a capture, so the capture → copy path is unchanged.

| Part | Look |
| --- | --- |
| Search | 290 pt at most, 120 pt at least, with "Search names and text in screenshots" as its prompt (`BrutalSearchField`) |
| Sort | The shared pop-up, "Newest first" and so on, as before |
| Thumbnail size | `BrutalSlider` 70 pt wide between a 10 pt and a 14 pt `square` in tertiary text |
| Section heading | "Today" and so on in 13 pt bold, its count after it in 12 pt tertiary tabular figures |
| Grid | 16 pt between tiles both ways (was 20), 64 pt of room under the last row for the selection bar |
| Thumbnail | 4:3, rounded at the group radius, 10, on the well colour, with a 1 pt hairline edge and a 1.5 pt soft shadow |
| Selected thumbnail | A 2.5 pt selection-blue ring just outside the edge with a 2 pt halo at 20% outside that, and no shadow |
| Tick | A 20 pt circle in the top-left corner with a 2 pt white ring: selection blue with a white tick when selected, white at 85% with a faint edge otherwise. It shows on hover, and on every tile while anything is selected |
| Badge | A recording's length, or "GIF", in 10.5 pt bold monospaced white on `#16161A` at 78%, rounded at the tiny radius, 4, 7 pt in from the bottom-right corner |
| Name and detail | The name in 12.5 pt medium, truncated in the middle, then a 7 pt dot for the first tag and the file's type with the time, size or date in 11 pt tertiary |
| Selection bar | Centred 20 pt above the grid's foot on the floating depth in the group colour, rounded at the panel radius, 14: "N selected" in 13 pt semibold, Edit, Move to…, Tag and Show in Finder as toolbar buttons, a `trash` button in destructive red, and Copy as the main button |

- **The detail line.** ShotCore's `Gallery.tileDetail` gives the file's type and, for the date sorts, the time (the section already says the day); for Largest first, the size; for Name, the date. It has tests.
- **The selection bar** rises 8 pt and fades in with the panel moment when the first capture is selected, and goes when the last is deselected. Move to… lists the save folder and every folder, greying out the one every selected capture is already in, then New Folder…. Tag opens the Tag popover above the bar for the whole selection.
- **One ink control.** Copy in the bar is the gallery's only ink button, and it shows only while something is selected (rule 1).
- **What went.** The footer with its count, Select All and Deselect All, and Edit, Copy, Show in Finder and Move to Trash, which the bar now holds; the count is in the toolbar heading and ⌘A, ⇧⌘A and Esc select and deselect. The yellow play button on recordings, the violet ring and name fill on selected tiles, and the count badge on section headings.
- **The lazy grid rules hold.** A tile takes its first tag and its detail line as plain values and stays `Equatable`, so one selection change re-evaluates only the tiles whose `selected` or `selectionActive` changed. The selection bar reads the selection in its own view, and the root view no longer reads it at all, so selecting doesn't re-evaluate the toolbar, the sidebar or the grid around the tiles.
- **Keeping the lead in view.** Moving the selection with the arrow keys scrolls a row clear of the bar, not just of the window's edge.
- **Departures from the board.** The board rounds thumbnails at 9; Shot uses the group radius, 10. The board's badge corner is 5; Shot uses the tiny radius, 4. The board's search is 260 pt; its prompt doesn't fit in SF Pro at that width, so Shot allows 290. The board shows a tick only on selected tiles; Shot also shows an empty circle on hover and on every tile while anything is selected, as before, so a click on it adds a tile without ⌘. The board's detail is "PNG · 21:53" or a size; Shot picks between time, size and date by the sort. The board has no pencil or scissors on a hovered tile; Shot keeps them, as the guide's "Open in an editor" uses them. The board's bar shows the Trash as an icon without a label, which Shot keeps, with "Move to Trash" for VoiceOver and the tip.
- **Keyboard.** Every shortcut in Keyboard shortcuts › Gallery works as before. With keyboard navigation on, Tab reaches each button in the bar.
- **VoiceOver** reads a tile as its name and whether it's selected, with a Select or Deselect action, as before. The bar is a group named "Selection", and the Trash button reads "Move to Trash". Section headings read as headings.
- **Text size** scales the names, details, badges, section headings and the bar. The search prompt truncates at Larger.
- **Reduce Motion** makes the bar's arrival a 120 ms fade. A hovered tile's tick and edit button fade in over 120 ms either way, as before.
- **Increase Contrast** takes the tile details, section counts and slider icons to ink. The bar's group-colour fill is already solid, so it needs no change; its 0.5 pt edge stays as it is.

### Gallery preview and details panel

#1109 replaces the system Quick Look panel with the board's preview from Library & Settings › Gallery · preview and empty state (left). Space used to open Quick Look over the gallery, for the whole selection. Now it shows the lead capture large inside the gallery window, over the sidebar and grid, with a details panel beside it. Nothing here runs during a capture, so the capture → copy path is unchanged.

| Part | Look |
| --- | --- |
| Toolbar | In the title bar after the traffic lights: a `chevron.left` toolbar button, the name in 13 pt semibold truncated in the middle, "3 of 248" in 12 pt tertiary tabular figures, then Edit as a secondary button and Copy as the main button, over a 1 pt separator |
| Stage | The well colour with 24 pt of room around the capture, which fits the space and is never larger than its pixels at 2x. Rounded at the control radius, 6, with a 1 pt hairline edge and a `0 14 32` shadow at 16% |
| Matches | Each place the search appears in the image under a selection-blue wash at 22%, rounded 2 |
| Keys | "← → next · Space close" on `Keycap`s in 11.5 pt secondary text, 14 pt above the stage's foot |
| Details panel | 250 pt on the side panel colour with a hairline down its leading edge (`sidePanel(width:)`), 16 pt in, 16 pt between sections, in 12.5 pt |
| Facts | Taken, Size, Folder, Versions and, while searching, Search: the name in tertiary text and the value in medium weight, right-aligned |
| Tags | "Tags" as a panel heading, then each tag as a chip in the group colour with an 8 pt dot and a 1 pt control edge, then "+ Add tag" as an outlined chip |
| Text in this screenshot | A panel heading over the text in 12.5 pt secondary on the group colour, rounded 6 with a hairline edge, its lines joined with " · " and each match on a selection-blue wash at 22% |
| Actions | "Copy path for an AI assistant" (`sparkles`) and "Show in Finder" (`folder`) as full-width secondary buttons, pinned to the panel's foot |

- **Opening and stepping.** Space previews the lead capture, or the first selected, and selects it alone, so Return, ⌘C, ⌘R and ⌘⌫ act on what's shown. The context menu's Quick Look is now Preview. ← and → (and ↑ ↓) step through the grid's captures in its order and stop at either end, Home and End go to the first and last, and Space, Esc or Back return to the grid. The grid stays built under the preview, so it keeps its scroll position, and the lead stays selected.
- **The facts.** ShotCore works out each one, with tests: `Gallery.takenLabel` gives "Today, 21:53" or a date and time, `sizeLabel` the pixels and file size, `folderLabel` the folder from the save folder ("Shot › Bugs"), and `versions` counts the files beside it that `VersionNaming` names as versions of the same original ("Original + 1 edit"). The Versions row hides when there are none, and Search hides when the search isn't in the text.
- **Reading the text without indexing.** The text panel reads the index `TextIndexer` keeps (`TextIndexer.store`) once when the preview opens, and again when the indexer hands over more, and never adds to it. A screenshot not read yet says that Shot reads the text the first time you search. `TextSearch.ranges` finds the matches, ignoring case and accents as search does.
- **Highlights in the image.** The index keeps text but not where it is, so while a search matches the shown screenshot's text, `TextRecognizer` reads that one screenshot again on this Mac, and `CaptureText.boxes(matching:)` gives the boxes. Without a search, nothing is read.
- **Recordings and GIFs.** A recording plays in AppKit's `AVPlayerView` with the system's inline controls and stops when the preview moves on or closes. SwiftUI's `VideoPlayer` crashed in AVKit's SwiftUI overlay on macOS 27, so it isn't used. A GIF animates in an `NSImageView`. Neither has a text section.
- **Loading.** The grid's thumbnail shows at once, and the full image decodes off the main actor, up to 5,120 pixels on its longer side.
- **Departures from the board.** The board rounds the image at 8; Shot uses the control radius, 6. The board's preview has no sidebar; Shot hides it while the preview is open and brings it back with the grid. The board shows only a screenshot; Shot also previews recordings and GIFs. The board's text card has no empty or unread state; Shot adds a short line for each. Space previews one capture where Quick Look showed the whole selection.
- **Focus.** Esc in the search field, or a click on a tile while typing in it, now also clears the field's focus state, which used to take the keyboard back so Space typed into the field instead of previewing. The Tag popover's field takes focus a turn after it opens, as the sidebar's folder field does, and the preview clears the keyboard when its popover closes, since the field stays in the window and kept it.
- **Keyboard.** ← → step, Space and Esc close, and ⌘F goes back to the grid's search. ⌘A, ⇧⌘A and the thumbnail size keys do nothing in the preview. With keyboard navigation on, Tab reaches Back, Edit, Copy, + Add tag and the two actions.
- **VoiceOver** reads Back as "Back to grid", the name as a heading, the image as "Preview of" its name, each fact as one element, each tag as "Tag" and its name, and the panel as a group named "Details". The keys along the foot are hidden from it.
- **Text size** scales the toolbar, facts, chips, text and actions; the panel scrolls above its actions when they don't fit.
- **Reduce Motion.** Nothing here moves. Opening, stepping and closing are instant.
- **Increase Contrast** takes the position, fact names, notes and secondary text to ink, and the panel's edge to 60% ink.

### Gallery empty state and Move to Trash

#1110 draws the gallery before anything is saved, from Library & Settings › Gallery · preview and empty state (right), and asks before captures go to the Trash, from Capture › Permission card… › Confirming something destructive. The empty gallery used to be the shared `EmptyState`, "No captures yet" with Open Folder, and trashing moved files at once with only the toast's ⌘Z to undo it. Nothing here runs during a capture, so the capture → copy path is unchanged.

| Part | Look |
| --- | --- |
| Toolbar | Unchanged: "All Captures" in 15 pt bold and "0 items" (Gallery sidebar) |
| Background | 1 pt dots 18 pt apart in ink at 8%, edge to edge under the toolbar |
| Box | 220 × 140 pt, a 2 pt dashed line in ink at 25%, rounded at the panel radius, 14. Inside, "Your first capture goes here" in 15 pt semibold secondary text |
| Arrow | The board's 60 × 44 curved arrow in record red, a 4 pt round-capped stroke and a filled head aimed along the curve's last stretch. The stroke draws itself in 0.5 s, 0.45 s into every 3 s, and the head appears as the stroke reaches it, so it never shows alone |
| Keys | The screenshot shortcut from Settings, one big keycap per key: 22 pt heavy on the group colour, a 2 pt ink edge and a 4 pt ink drop, rounded at the group radius, 10, at least 36 pt wide, 6 pt apart. ⇧ takes the accent |
| Words | "Take a screenshot to start your library" in 17 pt heavy, then "Everything Shot saves to Pictures/Shot appears here, and you can search the text inside it." in 13 pt secondary text, 320 pt wide at most, 6 pt apart |
| Button | "Choose a different folder…" as the secondary button |
| Trash dialog | A sheet on the gallery window, 300 pt wide on the group colour, 20 pt padding, 10 pt between parts, all centred |
| Thumbnails | The first three captures as 54 × 40 pt cards overlapping by 30, rounded at the control radius, 6, with a 1 pt edge in ink at 15% and a `0 4 10` shadow at 10%. Two turn −6° and 5°, one turns −3°, three turn −8°, 0° and 7° |
| Title and detail | "Move 2 captures to the Trash?" in 15 pt bold, then "They leave Pictures/Shot too. You can put them back from the Trash in Finder." in 12.5 pt secondary text. One capture reads "It leaves … put it back" |
| Buttons | Cancel as the secondary button and Move to Trash as the main button in record red with white text, equal widths, 8 pt apart and 6 pt further below the detail |

- **When it shows.** The empty library shows once the save folder has been read and holds no captures at all, whatever row is picked. An empty folder and a search with no matches keep the shared `EmptyState` ("This folder is empty", "Nothing matches").
- **The real shortcut.** The keys are the Screenshot shortcut in Settings › Shortcuts, read as it changes, with modifiers in the order menus show them, so the default reads ⌃ ⇧ 4, or ⇧ ⌘ 4 when Shot replaces the system's. With no shortcut set, the keys and arrow hide. ShotCore's `KeyCombo.keycaps` splits it, with a test.
- **The folder's name.** "Pictures/Shot" is the save folder from the home folder, in the names Finder shows, or the whole path when it's elsewhere. ShotCore's `Gallery.folderPath` works it out, with tests. Choose a different folder… opens the folder panel as a sheet and sets the save folder as Settings › General does, and the gallery lists the new folder at once.
- **A short window** drops the box and the arrow first, then scrolls, so the words and the button always show.
- **What asks.** The selection bar's Trash button, the context menu's Move to Trash, and Delete in the grid or the preview open the dialog for what they act on. ⌘⌫ moves the selection to the Trash without asking, as in Photos and Finder. Either way the toast offers ⌘Z, which puts the files back.
- **Keyboard.** Return presses Move to Trash and Esc presses Cancel. While the dialog is open, the gallery's own keys do nothing, so Delete or ⌘⌫ can't trash twice. With keyboard navigation on, Tab moves between the two buttons, which show the accent focus halo.
- **Departures from the board.** The note is in the app's type, not Caveat, and doesn't wobble, since rule 7 keeps handwriting out of the app (#1169). The board's empty window has no sidebar; Shot keeps it, so the folders and Make room… stay where they were. The board's keycaps read ⌘ ⇧ 4; Shot shows the shortcut actually set, in menu order. The board's dialog floats on its own; Shot shows it as a sheet on the gallery window, native rule 4. The board rounds the cards at 6 and the buttons at 8; Shot uses the control radius, 6, for both.
- **VoiceOver** reads the title as a heading, the keys as "Screenshot shortcut" and the shortcut, and the box, arrow and dots not at all. The dialog is a group named by its title, which is a heading; its thumbnails are hidden.
- **Text size** scales the words, keys, box and dialog width; the box and arrow give way first when they don't fit.
- **Reduce Motion** leaves the arrow drawn and still. Nothing else here moves.
- **Increase Contrast** takes the box's line to 60% ink, the note and secondary text to ink, the cards' edge to 60% ink, and darkens Move to Trash's red, as every destructive main button does.

### Settings window and sidebar

#1111 redraws the Settings window from Library & Settings › Settings sidebar and Settings · General, in light and dark. The sidebar used to be a column of 28 pt colour tiles with 2 pt ink edges under the app icon and "Shot", with a "Show icons only" button, and the content opened under a 30 pt title over a yellow marker and a subtitle. Now the sidebar is the board's: a search field, six rows with tinted icons, Open Gallery, and Shot's icon with its update status. The content has a 15 pt title in the title bar and grouped white panels. The panes' rows are unchanged until #1112–#1117, so this section covers the window, the sidebar, the search and the shared groups and rows. Nothing here runs during a capture, so the capture → copy path is unchanged.

| Part | Look |
| --- | --- |
| Sidebar | 228 pt wide by default, 180–300 pt by dragging its edge, the full window height under the traffic lights, on `SidebarMaterial` with a 1 pt separator on its right, 10 pt in from each side |
| Search | `BrutalSearchField` with "Search" as its prompt, 4 pt further in and 12 pt above the rows |
| Rows | A 22 pt tile rounded at the control radius, 6, with the section's symbol in 12 pt semibold in its tint (Colour › Sidebar icon tints), then the name in 13 pt regular, 6 × 8 pt padding, 2 pt apart. Hover fills with `Brutal.hover` |
| Selected row | Yellow, `#FFD43B` (dark `#F2CC4A`), with a 1.5 pt ink edge and semibold text (`SidebarRowBackground`, shared with the gallery). Its tile turns white with a 1 pt edge in ink at 20% and an ink symbol |
| Open Gallery | At the foot: `square.grid.2x2` on a white tile (dark `#3A3A3F`) with a 1 pt control edge, "Open Gallery" in 13 pt and a small `arrow.up.right` in tertiary text |
| Footer | Under a hairline, 6 pt below Open Gallery: the app icon at 28 pt, "Shot" in 12 pt bold and the status in 11 pt tertiary text |
| Title | The section's name in 15 pt bold in the 52 pt title bar beside the sidebar, 28 pt in, over a 1 pt separator. While searching, "Results for “login”" |
| Content | 18 pt from the top and 28 pt from each side, groups 18 pt apart |
| Group | Its name in 12 pt semibold tertiary text, 12 pt in, 6 pt above a panel in the group colour with the group depth, rounded at the group radius, 10 |
| Group row | The name in 13 pt regular and its description in 11 pt tertiary text 2 pt under it, the control on the right, 9 × 14 pt padding, with a 1 pt separator between rows |
| Search results | Each section with a match: its tile and name in 15 pt bold with Show All as a `PanelLinkStyle` link on the right, then its groups that match, 28 pt before the next section |
| No results | The shared `EmptyState`, "No settings match" and "Try another word, or clear the search to see every section.", centred in the content |

- **Search.** Typing in the field lists every row whose name or description holds every word typed, from all six sections, under their names. A row also matches its group's and its section's names, so "audio" lists the Audio group and "about" lists About. Groups and sections with no matching row hide, and sidebar rows without one fade to 40%. Case, accents, full-width letters and curly apostrophes don't matter, and a word can match inside another, which languages written without spaces need. ShotCore's `SettingsSearch` does the matching, with tests. Previews and notes that aren't rows, such as the Quick Access screen and the shortcut hint, hide while searching.
- **How the rows filter.** Each `SettingRow` hides itself when the search doesn't match, and `SettingsCard` lays out the rows that are left (`Group(subviews:)`), drawing the separators between them, so it draws nothing when none are. Rows no longer take a `divider:` argument, and groups no longer take a symbol.
- **Leaving a search.** Clicking a sidebar row or Show All clears the search and opens that section. Esc in the field clears it and gives the keyboard back to the window.
- **Arrow keys.** ↑ and ↓ move to the section above or below, stopping at the first and last, unless a text field, a shortcut recorder, a pop-up menu or a sheet has the keyboard. The window opens with the keyboard out of the search field so they work at once, and picking a section takes it out again. ⌘F puts it back in the field. `SettingsSearch.step` has a test.
- **The status.** "Up to date" while Shot checks for updates by itself and has found nothing, "Shot 1.2 is available" in accent text once a check finds one, and "Version 1.2" when automatic checks are off or the build has no update feed, as ShotDev doesn't, since then it can't tell. Clicking the footer opens About, where updates are.
- **`shot://settings?section=`** opens that section as before, and ends a search.
- **What went.** The icons-only rail with its "Show icons only" button, and the automatic shrink below 920 pt wide, which the board doesn't have and which left no room for the search. The app icon and "Shot" at the top of the sidebar, the 30 pt title with its marker, and the subtitles under it. The upper-case group headings with symbols, and the rows' 1.5 pt dividers. `PreferenceKey.appSidebarCollapsed` is gone, and the sidebar's default width is 228 pt, up from 196.
- **Departures from the board.** The board rounds rows at 7; Shot uses the control radius, 6. The board's sidebar is fixed; Shot keeps the drag to resize it, as in the gallery. The board's footer tile is the brand mark on yellow with an ink edge and drop; Shot shows the app icon, as #1111 asks, so the selected row stays the sidebar's only ink. The board always says "Up to date"; Shot says it only when that's true. The board has no search results; Shot lists them in the content, as the issue asks, with Show All and a no-results state.
- **Keyboard.** With keyboard navigation on, Tab reaches the search field, each row, Open Gallery and the footer, and Space presses them.
- **VoiceOver** reads the sidebar as "Settings sections", each row as a button with its name and whether it's selected, a faded row's value as "No matches", and the footer as "Shot" with its status and the hint "Opens About". Group names and the title read as headings.
- **Text size** scales the search, the rows' names, Open Gallery, the footer, the title and every group and row; the tiles stay 22 pt, and Open Gallery's arrow gives way first in a narrow sidebar.
- **Reduce Motion.** Nothing here moves. Sections switch at once, where the old sidebar sprang.
- **Increase Contrast** makes the sidebar solid in the Sidebar colour, and the group names, row descriptions, Open Gallery's arrow and the footer's status ink.

### Settings · General

#1112 redraws the General pane from Library & Settings › Settings · General, in light and dark. Its settings and their keys are unchanged; the rows' descriptions are the board's shorter ones, Text size is a pop-up menu where it was a segmented control, and the save folder's Reveal button now says Show in Finder. Nothing here runs during a capture, so the capture → copy path is unchanged.

| Group | Row | Control | Description |
| --- | --- | --- | --- |
| Behaviour | Open Shot at login | Switch | "Start Shot when you log in to your Mac." |
| Behaviour | Play capture sound | Switch | None |
| Behaviour | Exclude menu bar | Switch | "Crop the menu bar and notch off full-screen captures." |
| Behaviour | Appearance | `BrutalSegmented`: System, Light, Dark | "Captures look the same either way." |
| Behaviour | Text size | `BrutalPopUp`: Default, Large, Larger | "Shot’s windows, panels and toasts." |
| Files | Save folder | Show in Finder and Choose…, secondary buttons 8 pt apart | The folder from the home folder, such as `~/Pictures/Shot` |
| Files | File name | The shared text field, 180 pt wide (was 150) | The next capture's name, such as "Shot 2026-11-03 at 14.02.11.png" |
| Files | Image format | `BrutalSegmented`: PNG, JPEG | "Clipboard copies always use PNG." |
| Files | Scale Retina captures to 1× | Switch | "Halves pixel size on 2× displays." |
| Files | Save edits over the original | Switch | "Off keeps the original and saves a copy." |

- **One ink control.** The pane adds none: the selected sidebar row stays the window's only ink. Switches that are on take the accent with an ink edge, as the Ink table allows.
- **Choose…** opens the folder picker as a sheet on the Settings window, as the gallery's does, where it used to open a separate modal window.
- **What went.** The longer descriptions: "Smaller files, less detail" under Scale Retina, the note that the editor's Save keeps the original so you can undo (Annotate a screenshot › Save still says it), and "Shot's windows and panels" before Appearance's note. The guide's Settings page lists every row.
- **Departures from the board.** The board's row buttons are 3 × 12 pt; Shot uses the shared secondary button, 5 × 14 pt, which still fits within a row's two lines of text. The board's File name field has a 0.16 edge with an inner shadow, and in dark the field fill; Shot uses the shared text field (Feedback), whose dark fill is the group colour, so #1119 decides whether fields in a group take the field fill. The board's file name example is a fixed date; Shot shows the next capture's real name in the chosen format.
- **Keyboard.** With keyboard navigation on, Tab reaches each switch, segmented control, the Text size pop-up, both buttons and the field. The pop-up opens with Space and takes ↑, ↓, Return and typing, like a system menu. The window still opens with the keyboard out of the File name field, so ↑ and ↓ move between sections at once.
- **VoiceOver** reads each switch with its row's name, the segmented controls as segmented controls, Text size as a pop-up button with its value, and the field as "File name".
- **Text size** scales every row, control and description. At Larger the descriptions wrap rather than truncate.
- **Reduce Motion.** The switches' knobs and the segmented thumbs move at once.
- **Increase Contrast** makes the descriptions ink, and gives the off switches, segmented tracks, buttons, pop-up and field their 60% ink edges.

### Settings · Capture

#1113 redraws the Capture pane from Library & Settings › Settings · Capture. Its settings and their keys are unchanged. The rows sit in three groups where there were two, in the board's two columns, with notes under After a capture and While selecting, and a preview of the selection aids. The descriptions are the board's shorter ones. Nothing here runs during a capture, so the capture → copy path is unchanged.

| Group | Row | Control | Description |
| --- | --- | --- | --- |
| After a capture | Save to folder | Switch | None |
| After a capture | Copy to clipboard | Switch | None |
| After a capture | Show Quick Access | Switch | None |
| After a capture | Open in editor | Switch | "Opens the editor instead of Quick Access." |
| Captured image | Show cursor | Switch | "Include the pointer in area and full-screen captures." |
| Captured image | Window shadow | Switch | "Keep the macOS drop shadow in window captures." |
| Captured image | Capture only the page in browser windows | Switch, which asks for Accessibility access when turned on without it | "Window captures of a browser leave out its toolbar and tabs. It needs Accessibility access, and B on the capture bar switches it for one capture." |
| While selecting | Magnifier | Switch | "An 8× loupe beside the pointer, for exact edges." |
| While selecting | Crosshair | Switch | "Guide lines through the pointer across the screen." |
| While selecting | Size label | Switch | "Width and height in pixels while you drag." |

- **Layout.** After a capture and Captured image fill the left column, While selecting and the preview the right, 16 pt apart, with 16 pt between groups. Below 600 pt of content, as in a narrow window, they stack in one column 18 pt apart. While searching, the three groups list one under another like every other section's, without the notes or the preview.
- **Group notes.** `SettingsCard(title:note:)` puts a note in 11 pt tertiary text 12 pt in and 8 pt under the panel. After a capture says "The quick path saves and copies each capture and shows it in Quick Access, without opening a window." While selecting says "Each one also has a key on the capture bar: M, C and I." Notes hide while searching. The group name is now `SettingsGroupHeading`, which the preview uses too.
- **Preview.** Under a "Preview" heading, a 150 pt panel rounded at the group radius with a 1 pt edge in ink at 8%, and under it the note "Move the pointer over the preview to drag the area." It pictures picking an area as the overlay draws it, over a desktop of warm wallpaper (`#9A8F84` to `#6F675F`) and a light sample window with a sidebar, a heading, lines of text and a yellow tag, which stays light in dark mode. The area runs from a fixed corner at 40, 30 pt to the pointer, which rests at the board's 170 × 80 pt area: outside it dimmed with `rgba(12,12,16,0.35)`, the overlay's 1 pt white and dark rings, and its round handles at 7 pt. With the mouse elsewhere the overlay's crosshair cursor is drawn at the pointer. Moving the mouse over the preview drags the area under the overlay's own cursor, and leaving springs it back. The size label is the overlay's two chips, the size in pixels in 10 pt bold monospaced type and "Free ratio", 5 pt above the area. The crosshair is the overlay's 1 pt white line over a 3 pt shadow with an 8 pt gap at the pointer. The loupe is the overlay's: the scene magnified 6×, 11 points across and ruled per point, the pointer's row and column lit yellow at 35%, its own point outlined in ink, and its position in pixels in a chip at the foot, in a 2 pt white ring and a 1 pt ink ring with a soft shadow. It sits 12 pt below and right of the pointer and flips to the other side where it wouldn't fit. Each aid shows only while its switch is on, and fades in or out over 0.15 s as it changes. ShotCore's `SelectionAidsPreviewLayout` places the area, loupe and readouts, with tests.
- **One ink control.** The pane adds none: the selected sidebar row stays the window's only ink. Switches that are on take the accent with an ink edge, as the Ink table allows. The loupe's ink ring is part of the picture, as on the overlay.
- **What went.** The Selection group, which held all six of the selection and image switches. The longer descriptions: "for pixel-precise edges", "next to the pointer" under Size label, the annotation editor by name, and "Off captures the whole window" with "Press B on the overlay" under the browser row.
- **Departures from the board.** The board has no browser row; Shot keeps Capture only the page in browser windows at the end of Captured image, since it decides what ends up in the image and Settings is the only place to change it. The board's rows are 9 × 12 pt with a 12 pt gap and its content is 24 pt in; Shot uses the shared rows, 9 × 14 pt with 16, and the shared 28 pt, so Capture lines up with the other panes. The board's preview is a flat colour with a bare rectangle, a blank loupe and the caption "Updates as you change options" inside it; Shot's draws a sample window under the overlay's handles, chips, cursor and working loupe, lets the mouse drag the area, and puts its note under the panel like the groups' notes, so the crosshair and loupe never cross it. The board's quick-path note reads "saved, copied and in the corner card"; Shot names Quick Access, as the row above it does. The board's preview is fixed; Shot's follows the switches, as #1113 asks.
- **Keyboard.** With keyboard navigation on, Tab reaches each switch in reading order, the left column before the right. The preview takes no focus, and dragging its area is for the mouse only, since it changes no setting.
- **VoiceOver** reads each switch with its row's name, and the group names as headings. It reads the notes after their groups and skips the preview, since the switches above it say the same.
- **Text size** scales every row, description, note, and the preview's heading, chips and loupe readout. The preview and its loupe keep their size. At Larger the descriptions wrap rather than truncate.
- **Reduce Motion.** The switches' knobs move at once, the preview's aids appear and disappear without fading, and the area jumps back rather than springing when the mouse leaves.
- **Increase Contrast** makes the group names, descriptions and notes ink, and gives the off switches their 60% ink edges. The preview keeps its colours, since it pictures the overlay.

### Settings · Quick Access

#1114 redraws the Quick Access pane from Library & Settings › Settings · Quick Access. Its settings and their keys are unchanged, and so are the row names and the description, which match the board already. Under the group, a preview of a desktop pictures the real card in the chosen corner and counts down the auto-close time. Nothing here runs during a capture, so the capture → copy path is unchanged.

| Group | Row | Control | Description |
| --- | --- | --- | --- |
| Placement | Screen corner | Segmented: Bottom left, Bottom right | None |
| Placement | Auto-close | Segmented: 4s, 8s, 15s, 30s, Never | "Hovering a card pauses the timer." |

- **Layout.** Placement, then the preview 18 pt under it, in one column like General. While searching, Placement lists like every other section's group, without the preview.
- **Preview.** Under a "Preview" heading, a panel half as tall as it is wide, between 200 and 340 pt, rounded at the group radius with a 1 pt edge in ink at 8%. It pictures a 1440 pt display at the pane's width, so a 720 pt preview draws it at half size, with its bottom edge at the panel's and any cut taken off the top. On the Capture preview's warm wallpaper (`#9A8F84` to `#6F675F`) sit a light menu bar 24 display points tall and the Capture preview's sample window at 2.8 times its size, centred 70 points under the menu bar, which shrinks in a short panel to keep 12 pt under it. The card is the real one, placed as `QuickAccessController` places it: 280 × 175 points, 30 points in from the side and bottom, with the 14 point panel radius, a white fill, the 0.5 pt edge at 30% black and a soft shadow. Its capture is the Capture preview's desktop. The card slides in from its corner's edge as the real one does, moving in with a spring and scaling up from 88%, waits out the chosen time, slides out past the edge, and comes back 1.6 s later. Changing the corner brings it in from the new edge, and choosing Never leaves it in place. Pointing at the card shows the real card's hover state at the same scale: the scrim, Copy in the floating accent with an ink edge, Save As… in white, and Close, Annotate and Pin in round dark buttons. The timer waits while the pointer is on the card and starts again from the full time when it leaves, as `QuickAccessController` does. ShotCore's `QuickAccessPreviewLayout` places the menu bar, window and card and counts the seconds, with tests.
- **Caption.** Under the panel, in 11 pt tertiary text 12 pt in, with digits that keep their width. While the card counts down it says "Closes in 5s. Hover over the card to keep it open." with the seconds left, and after the card closes "Closed after 8s. The next capture brings a new card." While the pointer is on the card it says "The timer waits while the pointer is on the card, and starts again when it leaves." With Never it says the board's "Cards stay until you close them."
- **One ink control.** The pane adds none: the selected sidebar row stays the window's only ink. The Copy button's ink edge inside the preview is part of the picture, as on the real card.
- **What went.** The old preview: a violet-to-sky gradient, the "PREVIEW" badge and two plain cards with 2 pt ink borders, one in the section's colour. The pane no longer uses `SettingsSection.color`.
- **Departures from the board.** The board draws a timer bar along the foot of the card; the real card has none, so the preview card has none either, and the caption counts the seconds down instead, as agreed in #1114. The board's caption sits in a dark pill inside the preview and reads "Card closes after 8s · hover to keep it"; Shot's sits under the panel like the Capture preview's note, so the card never crosses it, and counts down. The board's card is a white sheet with coloured lines; Shot's is the real card at scale, with a capture on it and the real hover state. The board's preview fills the rest of the window; Shot's is half as tall as it is wide within limits, since the pane scrolls. The board's segments are 3 × 12 and 3 × 11 pt; Shot uses the shared `BrutalSegmented`, so Quick Access lines up with General and Capture. The board's rows are 10 × 14 pt; Shot uses the shared 9 × 14.
- **Keyboard.** With keyboard navigation on, Tab reaches both segmented controls in reading order. The preview takes no focus, and pointing at its card is for the mouse only, since it changes no setting.
- **VoiceOver** reads both segmented controls as segmented controls, and the group name as a heading. It skips the preview and its caption, since the rows above say the same.
- **Text size** scales the rows, the description, the preview's heading and its caption. The preview keeps its size, since it pictures the screen at scale.
- **Reduce Motion.** The card fades in and out in place rather than sliding, and the hover state appears at once. The countdown still runs.
- **Increase Contrast** makes the group name, description and caption ink. The preview keeps its colours, since it pictures the screen.

### Settings · Recording

#1115 redraws the Recording pane from Library & Settings › Settings · Recording. Its settings and their keys are unchanged. The rows move into the board's five groups in two columns, and a dark card over the Camera group previews the camera. System audio is now called Mac sound, Bubble size is Size, and most descriptions are the board's shorter ones. Nothing here runs during a capture or a recording, so the capture → copy path is unchanged.

| Group | Row | Control | Description |
| --- | --- | --- | --- |
| Sound | Microphone | Switch | None |
| Sound | Input | `LevelMeter`, Test (Stop while it runs) and the device pop-up, 8 pt apart | None |
| Sound | Mac sound | Switch | "Sound from other apps. Shot’s own sounds are left out." |
| Pointer | Show cursor | Switch | None |
| Pointer | Show clicks | Switch | "A ring wherever you click." |
| Pointer | Region border | Switch | "Outlines what’s recorded. It never appears in the video." |
| After recording | Copy to clipboard | Switch | None |
| After recording | Adjust before recording | Switch | "Check the frame and options before every recording. Hold ⌥ as you finish the selection to check once." |
| Camera | Camera bubble | Switch | None |
| Camera | Camera | The device pop-up | None |
| Camera | Size | `BrutalSegmented`: Small, Medium, Large | None |
| Quality | Frame rate | `BrutalSegmented`: 30, 60, and 120 on a display that fast or when it's already chosen (`RecordingFrameRate`) | "MP4. 120 records HEVC on ProMotion displays." while 120 is offered, otherwise "Recordings save as MP4." |
| Quality | GIF from Quick Access | None | "Export GIF on the card uses the video editor’s last settings:" and the summary, such as "15 fps, up to 720 px wide, first 60 seconds." |

- **Layout.** Sound, Pointer and After recording fill the left column, and the camera card, Camera and Quality the right, 16 pt apart, with 16 pt between groups. Below 600 pt of content, as in a narrow window, they stack in one column 18 pt apart. While searching, the five groups list one under another like every other section's, without the camera card.
- **Camera card.** `#2A2A2E` in both appearances, rounded at 12 with a 1 pt edge in white at 6%, with 14 pt padding. On the left, an 84 pt circle inside the camera bubble's 3 pt white ring (`CameraBubbleStyle.ringWidth`). It shows a grey figure (`person.fill` on `#3A3A3F`) until Preview runs, then the camera live and mirrored, as the bubble draws it. Beside it, the chosen camera's name in 13 pt semibold white, or the system default's, and "Check your framing and lighting." in 11 pt white at 70%, which becomes "Live and mirrored, as the bubble shows it." while the preview runs. Preview is a secondary button on the right that becomes Stop. Preview asks for camera access the way it did before, and the preview stops when the pane closes.
- **Level meter.** `LevelMeter` is the board's: eight 4 × 10 pt bars rounded at 1 and 2 pt apart, lit success green and the setup bar's amber for the top two, over ink at 12% (white at 16% in dark). It no longer draws ink edges or record red, and it only redraws while Test runs. `LevelBars.loudFrom(of:)` in ShotCore picks the amber bars for both meters, with a test.
- **One ink control.** The pane adds none: the selected sidebar row stays the window's only ink. Switches that are on take the accent with an ink edge, as the Ink table allows.
- **What went.** The Starting, Video, Audio and GIF export groups, the Test microphone and Preview rows, the GIF badge, and the pane's use of `SettingsSection.color`. The longer descriptions: the permission and mute note under Microphone, "Copies the finished recording, ready to paste as a file.", the bubble's drag and double-click hint (the guide still has it), the frame rate's codec for each choice, and "Shows the input level of the microphone above." The "fps" after each frame rate, which the row's name already says.
- **Departures from the board.** The board has no switch to turn the microphone off; Shot keeps Microphone as a switch over an Input row, as agreed in #1115, so it mirrors Camera bubble over Camera. The board's Microphone row has a meter and a pop-up; Shot's Input row adds Test between them, as #1115 asks. The board's camera card is a still drawing that says the bubble shows bottom-right; Shot's shows the live camera with a Preview button, and leaves out the corner, since the bubble starts bottom-left (Camera bubble). Its figure is a system symbol rather than the board's drawn one. The board's sizes read S, M and L; Shot spells them out, since VoiceOver reads the labels. The board has no GIF row; Shot keeps it at the end of Quality, as #1115 asks. The board's Adjust before recording says only "Always show the check step."; Shot keeps the ⌥ shortcut in it. The board's rows are 9 × 12 pt and its content is 24 pt in; Shot uses the shared rows, 9 × 14 pt, the shared 28 pt and `BrutalSegmented`.
- **Keyboard.** With keyboard navigation on, Tab reaches each control in reading order, the left column before the right, including Test, both pop-ups and Preview.
- **VoiceOver** reads each switch with its row's name, the group names as headings, the meter as "Microphone level", or "Microphone level, muted" while Test is off, Test as "Test the microphone" and Preview as "Preview the camera", which become "Stop the microphone test" and "Stop the camera preview" while they run. It reads the camera card's name and line together and skips the circle.
- **Text size** scales every row, description, button and the card's text. The circle, the meter and the ring keep their size. At Larger the descriptions wrap rather than truncate.
- **Reduce Motion.** The switches' knobs and the segmented thumbs move at once. Nothing else moves.
- **Increase Contrast** makes the group names and descriptions ink, gives the off switches their 60% ink edges, and takes the meter's unlit bars to 30% ink (35% white in dark). The camera card keeps its colours, since it pictures the camera.

### Settings · Shortcuts

#1116 redraws the Shortcuts pane from Library & Settings › Settings · Shortcuts. Its settings and their keys are unchanged, and so are the actions that can have a shortcut, Screenshot and Record (`ShotAction.hasShortcut`); the board's five rows are an example. The takeover switch sits alone at the top, each shortcut shows as keycaps beside the action's icon, Restore Defaults moves to the title bar, and a reference lists the keys that work while picking what to capture. Nothing here runs during a capture, so the capture → copy path is unchanged, and the shortcuts work as before.

| Group | Row | Control | Description |
| --- | --- | --- | --- |
| None | Use Shot for ⌘⇧4 and ⌘⇧5 | Switch | "Off gives macOS its screenshot keys back, and Shot’s default shortcuts become ⌃⇧4 and ⌃⇧5." |
| None | macOS still uses these keys, only while the switch is on and the macOS shortcuts are too | Open, a secondary button | "Turn off the Screenshots shortcuts under Keyboard Shortcuts." |
| Global | Screenshot, with `viewfinder` | The recorder | None |
| Global | Record, with `record.circle` in record red | The recorder | None |

- **Layout.** One column, as on the board: the switch's panel with no group name, Global with its note, then While picking what to capture, 18 pt apart. While searching, the switch's panel and Global list like every other section's groups, without the note, the key reference or Restore Defaults.
- **Rows with icons.** `SettingRow` takes an optional `Icon`, a 16 pt wide SF Symbol in ink at 85% (or a given tint) 12 pt before the name. Each action's symbol is `ShotAction.symbol` in ShotCore, which the menu bar menu now uses too, so Record is red in both. `SettingsCard`'s title is optional, for the switch's panel.
- **Recorder.** At least 120 pt wide and 24 pt tall, rounded at 7. A set shortcut shows each key from `KeyCombo.keycaps` as a 12 pt semibold keycap on the secondary fill with a control edge and a 1 pt drop, 3 pt apart, on a field-fill pill with a hairline edge. With no shortcut it says "Record Shortcut" in 12.5 pt tertiary text in an empty box with a control edge. Clicking it listens: "Press keys…" in 12.5 pt semibold accent text on the accent at 18%, in the focus halo, with "Esc cancels · ⌫ clears" in 11.5 pt tertiary text to its left. Esc or a second click cancels, Delete clears, and the new keys are checked as before: they need ⌘, ⌥ or ⌃, and a reserved shortcut or another action's beeps and shows a toast. ↑ and ↓ reach the recorder while it listens (`SettingsNavigation.recordingShortcut`).
- **Global note.** "Click a shortcut to change it. It needs ⌘, ⌥ or ⌃, and can’t be one that macOS or another action already uses."
- **Key reference.** "While picking what to capture" over a group panel with 12 × 14 pt padding: ten keys three to a row, two below 480 pt, 18 pt apart across and 10 pt down. Each is the shared `Keycap` beside its label in 12.5 pt: Tab steps through Area, Window and Full Screen, then B Browser, D the delays, S Scrolling capture, R the ratios, M Magnifier, C Crosshair, I Size label, ⌥ Adjust before recording and Esc Cancel. `PickingKey.all` in ShotCore builds the list from the overlay's own targets, delays and ratios, with tests, so it changes when they do.
- **Restore Defaults** is a secondary button at the right of the 52 pt title bar, 20 pt in, while Shortcuts shows and nothing is being searched. It resets every shortcut and turns the switch back on, as before.
- **One ink control.** The pane adds none: the selected sidebar row stays the window's only ink. The switch takes the accent with an ink edge when on, as the Ink table allows.
- **What went.** The "macOS screenshot keys" group name and the long description that named a keyboard's screenshot key and said macOS gets the keys back while Shot isn't running (Keyboard shortcuts › Global still says so). The "Global hotkeys" name, the mono shortcut buttons that read "None" with no shortcut, and the hint under them, "Click a shortcut, then press the new keys. Esc cancels, Delete clears.", which the listening recorder now says.
- **Departures from the board.** The board lists five actions; Shot lists the two that can have a shortcut, as #1116 asks. The board's listening recorder has a 1.5 pt ink edge on `#FFF8DB`; Shot's has the focus halo on the accent at 18% without the edge, as the secondary button's on state does, so the selected sidebar row stays the only ink (Rule 1). The board shows ⌘ before ⇧; Shot shows modifiers in the order macOS menus do, ⌃⌥⇧⌘, as the board's own ⌥⌘G does. The board's Tab reads "Area · Window · Screen · Browser"; in the overlay Tab steps through three targets and B picks Browser, so Shot lists B on its own and calls the screen Full Screen, as the capture bar does. The board's "Size readout" is Size label, the Capture pane's name for it. The board's note says only that shortcuts need a modifier and can't repeat another action's; Shot's starts with "Click a shortcut to change it." for the quick sharer and adds macOS's reserved shortcuts. The board's switch name is 600 weight with "Off gives macOS its keys back, and Shot uses ⌃⇧4 and ⌃⇧5."; Shot uses the shared 13 pt regular row, says "screenshot keys" so a search for "screenshot" finds it, and says the default shortcuts move, since a recorded one stays. The board's title bar button is 3 × 11 pt; Shot uses the shared secondary button, 5 × 14 pt. The board's rows are 9 × 14 pt with the icon 12 pt from the name, which Shot matches.
- **Keyboard.** With keyboard navigation on, Tab reaches Restore Defaults, the switch, Open when it shows, and each recorder, and Space starts listening. While a recorder listens, every key goes to it.
- **VoiceOver** reads the switch with its name, each recorder as "Screenshot shortcut, button" with the shortcut as its value, such as "⇧⌘4", or "None", and the hint "Records a new shortcut.", which becomes "Press the new keys. Escape cancels and Delete clears." with the value "Press keys…" while it listens. It skips the icons, reads each reference key with its label, and reads Restore Defaults as "Restore the default shortcuts".
- **Text size** scales every row, the note, the recorders' text and keycaps, the hint, the reference's keycaps and labels, and Restore Defaults. The icons scale with the text. At Larger the reference's labels wrap rather than truncate.
- **Reduce Motion.** The switch's knob moves at once. Nothing else moves.
- **Increase Contrast** makes the group names, the description, the note and the hint ink, gives the off switch, the recorders and their keycaps 60% ink edges, and makes the recorders' text ink.

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
| Permission card… › Move to Trash | #1110 | `Gallery/GalleryEmptyLibrary.swift` (new, `TrashConfirmation`), `Gallery/GalleryModel.swift` (`trashRequest`, `askToTrash`, `confirmTrash`), `Gallery/GalleryController.swift` (Delete asks, ⌘⌫ doesn't), `Gallery/GalleryView.swift` (the sheet) | ☐ |

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
| Image editor · style | #1096 | `Editor/StylePanel.swift` (replaces the popover, which #1104 removed), `Editor/EditorRootView.swift`, `Editor/EditorModel.swift` (`showsStylePanel`, canvas setters), `Editor/DesktopPicture.swift`, `Editor/CanvasControls.swift` (Background… opens the panel), `Capture/CaptureCoordinator.swift`, `Design/BrutalStyle.swift` (`BrutalSegmented.fillingWidth()`), ShotCore `CanvasFrame.swift` (`CanvasFrame`, `CanvasAspect`, `BackgroundFill`, `BackgroundSwatches`, `CanvasStyle`, `StylePanelLayout`), ShotCore `EditorDocument.swift`, `AnnotationRenderer.swift` (`drawFill`), `ObjectStyle.swift` (`CopiedStyle.canvas`) | ☐ |
| Image editor · crop and combine | #1097 crop | `Editor/CropBar.swift` (`CropBarOverlay`, `CropBarView`), `Editor/EditorCanvasView.swift` (`drawCrop`, `cropMarks`, `viewportSize`), `Editor/EditorModel.swift` (`cropKeptSize`, `cropBarClearance`, `canvasFootLeading`), `Editor/CanvasControls.swift` (hint steps aside), `Editor/EditorRootView.swift` (overlay, Copy steps down), `Editor/StyleBar.swift` (crop removed), ShotCore `CropBar.swift` (`CropBar`), ShotCore `StyleBar.swift`, ShotCore `CanvasHint.swift` | ☐ |
| Image editor · crop and combine | #1098 layers | `Design/LayersPanel.swift` (`LayersPanel`, `FrameRowView`, `LayerRowView`, `CropBadge`), `Design/SidePanel.swift` (`sidePanel(width:)`, `Brutal.sidePanel`), `Editor/StylePanel.swift` (flush panel), `Editor/EditorRootView.swift` (canvas edge to edge, title bar hairline), `Editor/EditorModel.swift` (`frameRow`), ShotCore `Layers.swift` (`FrameRowDetail`) | ☐ |
| Image editor · crop and combine | #1099 combine | `Editor/EditorRootView.swift` (`CanvasMenu` in `EditorTitleBar`), `Editor/CanvasControls.swift` (menu leaves the foot), `Editor/EditorCanvasView.swift` (crop badge, hover), `Editor/EditorModel.swift` (`startingStyle`, `resetTargetStyle`, `isTargetStyleDefault`), ShotCore `CanvasCropBadge.swift`, ShotCore `ObjectStyle.swift` (`editorDefaultStyle`), ShotCore `EditorTool.swift` (`editorObjectStyle`) | ☐ |
| Video editor and export (dark) | #1100 window and toolbar | `VideoEditor/VideoEditorView.swift` (`VideoEditorTitleBar`, hairline), `VideoEditor/VideoEditorModel.swift` (`toggleDrawing()`, hiding the tracks stops drawing), `VideoEditor/TracksView.swift` (Annotate removed), `VideoEditor/VideoEditorWindowController.swift` (unchanged), ShotCore `VideoEditSummary.swift` | ☐ |
| Video editor and export (dark) | #1101 drawing tools | `VideoEditor/AnnotationPalette.swift` (`DrawToolColumn`, options in one row), `VideoEditor/VideoEditorView.swift` (column over the video), `VideoEditor/VideoEditorModel.swift` (`showsDrawTools`, `pickDrawTool`, `cropFromDrawTools`, Draw leaves the tracks alone), `VideoEditor/VideoEditorWindowController.swift` (C while drawing), ShotCore `VideoDrawTools.swift` | ☐ |
| Video editor and export (dark) | #1102 timeline | `VideoEditor/TracksView.swift` (lane names, clip looks, cut badges, `Playhead`, toolbar and trim strip removed), `VideoEditor/PlaybackControls.swift` (`PlaybackControls`, `VideoEditorSurface`, `AddMediaMenu`), `VideoEditor/VideoEditorView.swift` (the well, the controls area, More tools removed), `VideoEditor/VideoEditorModel.swift` (`showsTracks` and `toggleTracks()` removed), `VideoEditor/VideoEditorWindowController.swift` (T removed, window sized for the well), ShotCore `VideoTimelineControls.swift` (`VideoWell`, `LaneLayout.Name`, `Project.mainCutMarks`, the zoom slider), ShotCore `TimelineLayout.swift` (lane heights), ShotCore `TrimRange.swift` (handle width) | ☐ |
| Video editor and export (dark) | #1103 export panel | `VideoEditor/ExportPanel.swift` (`ExportPanel`, `SummaryCard`), `VideoEditor/VideoEditorView.swift` (panel beside the well and controls, `ExportOptionsBar` removed, Export opens the panel), `VideoEditor/VideoEditorModel.swift` (`showsExportPanel`, `toggleExportPanel()`, `closeExportPanel()`, `exportFraction`), `VideoEditor/VideoEditorWindowController.swift` (Esc closes the panel), `Design/SidePanel.swift` (`PanelLinkStyle` shared), `Editor/StylePanel.swift`, ShotCore `VideoExportPanel.swift` | ☐ |
| Video editor and export (dark) | #1104 inspectors | `VideoEditor/InspectorPanel.swift` (replaces `ClipInspector.swift`), `VideoEditor/VideoEditorView.swift` (side panel switch, Inspector tile, style bar, the well's content shape), `VideoEditor/AnnotationPalette.swift` (`VideoStyleBar` replaces the options row), `VideoEditor/VideoEditorModel.swift` (`sidePanel`, `toggleInspector()`, `resetToolOptions()`), `VideoEditor/PlaybackControls.swift` (Inspector tile removed), `VideoEditor/TracksView.swift` (keyframe marks), `VideoEditor/VideoEditorWindowController.swift` (⌥⌘I), `Editor/StyleSections.swift` (`StyleSection`, shared with the Style panel), `Editor/StyleEditing.swift` (replaces `StylePopover.swift`), `Editor/StyleBar.swift` (`StyleBarEditing`), `Editor/StylePanel.swift`, `Editor/EditorToolbar.swift` (unused option views removed), `Design/SidePanel.swift` (`panelHeading()`, `PanelSliderRow`), ShotCore `VideoInspectorPanel.swift` (`VideoSidePanel`, `VideoInspectorPanel`), ShotCore `StyleThumbnail.swift` removed | ☐ |
| Video editor and export (dark) | #1105 crop and transform | `VideoEditor/VideoCropOverlay.swift` (the image editor's crop look, `CropBarEditing` conformance), `VideoEditor/TransformOverlay.swift` (selection style, rotate handle), `VideoEditor/VideoEditorView.swift` (crop bar in the well, video fits above it), `VideoEditor/VideoEditorModel.swift` (`cropBarClearance`, `resetCrop()`, `chooseCropAspect(_:)`), `VideoEditor/VideoEditorWindowController.swift` (Delete resets), `Editor/CropBar.swift` (`CropBarEditing`, generic `CropBarOverlay`), `Editor/EditorCanvasView.swift` (marks from `CropMarks`), `Editor/EditorToolbar.swift` (`CropOptions` removed), `Design/SelectionStyle.swift` (`SelectionHandle`), ShotCore `CropBar.swift` (`CropMarks`, video `keptSize`), ShotCore `TransformHandles.swift`, ShotCore `VideoTimelineControls.swift` (`bottomClearance`) | ☐ |
| Video editor and export (light) | #1100 | `VideoEditor/VideoEditorView.swift`, `VideoEditor/VideoEditorModel.swift`, `VideoEditor/TracksView.swift`, ShotCore `VideoEditSummary.swift` (the title bar takes the light tokens; see Video editor toolbar) | ☐ |
| Image editor · annotate (dark) | #1119, after #1093–#1099 | `Design/BrutalStyle.swift` (dark values), `Editor/EditorToolbar.swift`, `Editor/EditorCanvasView.swift` | ☐ |

### Library & Settings

| Board | Issue | Files | QA |
| --- | --- | --- | --- |
| Gallery | #1106 own window | `Gallery/GalleryWindowController.swift` (new), `Settings/SettingsWindowController.swift` (was `MainWindowController.swift`), `Gallery/GalleryController.swift`, `Capture/ShotWindows.swift` (new), `Capture/DisplayCapturer.swift`, `Capture/ScrollingCaptureController.swift`, `Recording/Recorder.swift`, `MenuBar/StatusMenu.swift`, `AppDelegate.swift`, ShotCore `ShotURL.swift` (`shot://settings?section=gallery`) | ☐ |
| Gallery | #1107 sidebar | `Gallery/GallerySidebar.swift`, `Gallery/GalleryView.swift` (layout, toolbar heading, tag row removed), `Gallery/GalleryModel.swift` (`source`, `counts`, `makeRoom`), `Gallery/GalleryWindowController.swift`, ShotCore `GallerySource.swift` (new) and `Preferences.swift` (sidebar open, 220 pt) | ☐ |
| Gallery | #1108 grid and selection bar | `Gallery/GalleryView.swift` (toolbar, `GalleryGrid`, `GalleryTile`, `SelectionCheckbox`, `GallerySelectionBar`; footer removed), ShotCore `GalleryTileDetail.swift` (new) | ☐ |
| Gallery · preview and empty state | #1109 preview | `Gallery/GalleryPreview.swift` (`GalleryPreviewView` replaces the Quick Look panel), `Gallery/GalleryModel.swift` (`previewing`, `preview(_:)`, `stepPreview(by:)`, `textRevision`), `Gallery/GalleryController.swift` (preview keys), `Gallery/GalleryView.swift` (preview over the grid, Preview in the menu), ShotCore `GalleryPreviewDetails.swift` (new) | ☐ |
| Gallery · preview and empty state | #1110 empty state | `Gallery/GalleryEmptyLibrary.swift` (new, `GalleryEmptyLibrary`), `Gallery/GalleryView.swift` (`content`), `Gallery/GalleryModel.swift` (`folderPath`, `chooseFolder(in:)`), ShotCore `GalleryEmptyLibrary.swift` (new, `Gallery.folderPath`, `trashFan`, `KeyCombo.keycaps`) | ☐ |
| Welcome | #1118 | `WelcomeWindow.swift` | ☐ |
| Settings sidebar (shared component) | #1111 | `Settings/SettingsSidebar.swift` (new: sidebar, rows, Open Gallery, footer), `Settings/SettingsView.swift` (`SettingsNavigation` search, layout, title, search results), `Settings/SettingsWindowController.swift` (arrow keys), `Settings/ShortcutRecorderView.swift`, `Design/BrutalStyle.swift` (`SettingsCard`, `SettingRow`, `SidebarTint.gallery`), `Design/GlassWindow.swift` (`SidebarRowBackground`, from the gallery), `Updater.swift` (`isEnabled`), ShotCore `SettingsSearch.swift` (new) and `Preferences.swift` (228 pt, no collapse) | ☐ |
| Settings sidebar (shared component) | #1106 Open Gallery | `Settings/SettingsView.swift` (`OpenGalleryItem`, redrawn by #1111 as `OpenGalleryRow` in `Settings/SettingsSidebar.swift`) | ☐ |
| Settings · General | #1111 title, groups and rows | `Settings/SettingsView.swift`, `Design/BrutalStyle.swift` (`SettingsCard`, `SettingRow`) | ☐ |
| Settings · General | #1112 | `Settings/SettingsView.swift` (`GeneralSettings`: descriptions, Text size pop-up, Show in Finder, 180 pt File name field, Choose… as a sheet) | ☐ |
| Settings · General | #1073 sidebar material | `Design/GlassWindow.swift` (`SidebarMaterial`), `Settings/SettingsView.swift` | ☐ |
| Settings · Capture | #1113 | `Settings/SettingsView.swift` (`CaptureSettings`: three groups in two columns, shorter descriptions, `SelectionAidsPreview`, `PreviewScene`), `Design/BrutalStyle.swift` (`SettingsCard` note, `SettingsGroupHeading`), `ShotCore/SelectionAidsPreview.swift` (`SelectionAidsPreviewLayout`) | ☐ |
| Settings · Quick Access | #1114 | `Settings/SettingsView.swift` (`QuickAccessSettings`, `QuickAccessPreview`, `QuickAccessPreviewHover`, `QuickAccessDesktop`, `PreviewSampleWindow` split out of `PreviewScene`), `ShotCore/QuickAccessPreview.swift` (`QuickAccessPreviewLayout`), `ShotCore/QuickAccessLayout.swift` (`screenInset`) | ☐ |
| Settings · Recording | #1115 | `Settings/SettingsView.swift` (`RecordingSettings`: five groups in two columns, shorter descriptions, `SoundSettings`, `CameraPreviewCard`, `CameraSettings`, `DevicePicker` width), `Recording/AudioMeter.swift` (`LevelMeter` redrawn), `ShotCore/RecordSetupFrame.swift` (`LevelBars.loudFrom(of:)`) | ☐ |
| Settings · Shortcuts | #1116 | `Settings/ShortcutRecorderView.swift` (keycaps, Record Shortcut, the listening halo and hint, `RecorderButtonStyle`, `RecorderKeycap`), `Settings/SettingsView.swift` (`ShortcutSettings`: the untitled switch panel, Global with icons and its note, `PickingKeysCard`; `RestoreShortcutsButton` in the title bar), `Design/BrutalStyle.swift` (`SettingsCard` optional title, `SettingRow.Icon`), `MenuBar/StatusMenu.swift` (`ShotAction.symbol`), `ShotCore/PickingKeys.swift` (`PickingKey.all`, `ShotAction.symbol`) | ☐ |
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
| 09 Keyboard shortcuts | M, C and I on the capture bar; Settings › Shortcuts; Delete asks before the Trash and ⌘Delete doesn't | #1128 | #1075, #1110, #1116 | ☐ |
| 10 Automation reference | `shot://gallery` and `shot://settings?section=gallery` open the gallery window; `shot://welcome` | #1128 | #1106, #1118 | ☐ |
| 11 Settings | Section and row names, the sidebar search, Open Gallery, General's Text size menu and Show in Finder, Capture's groups and its preview of the selection aids, Quick Access's preview of the card in its corner with the countdown, Recording's groups with Mac sound and its camera card, Shortcuts' keycaps with Restore Defaults in the title bar and the list of keys for picking what to capture | #1128 | #1111, #1112, #1113, #1114, #1115, #1116, #1117 | ☐ |
| 12 Languages | Check only: no redesigned screen is described | #1128 | #1121 | ☐ |
| 13 Updates | The restyled update prompt; Settings › About › Updates | #1128 | #1117, #1084 | ☐ |
| 14 Privacy | Permissions in Settings › About show Allowed or Allow… | #1128 | #1117 | ☐ |
| 15 Troubleshooting | The browser permission card; permissions in Settings › About; the recovery dialog | #1128 | #1087, #1117, #1092 | ☐ |
| 16 Removing Shot | Settings row names (Open Shot at login, Reset all settings) | #1128 | #1112, #1117 | ☐ |
