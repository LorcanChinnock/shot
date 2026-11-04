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

**Sidebar icon tints** (light): `#E8E4FF`, `#FFE0EE`, `#DCEFFF`, and the rest of today's eight bright colours, only as the tile behind a sidebar icon. Dark tints come with the dark boards (#1067).

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

Ink is drawn with `inkBorder`, crisp on 1× displays (#1069 removes the whole-point rule and keeps `inkBorder` as the one way to draw it).

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
| Design language | #1074 motion | `Design/` (new motion helpers) | ☐ |
| Components › Buttons | #1070 | `Design/BrutalStyle.swift` (`BrutalButtonStyle`) and its call sites | ☐ |
| Components › Choice | #1071 | `Design/BrutalControls.swift`, `Design/BrutalDropdown.swift` | ☐ |
| Components › Choice, Feedback | #1072 | `Design/BrutalControls.swift`, `Design/BrutalTip.swift`, `Toast.swift` | ☐ |
| Sample desktop (shared scene) | #1131 | None: the backdrop behind the Capture and Record boards. QA uses MugCo | ☐ |
| Capture bar (shared component) | #1075 | `Overlay/SelectionOverlayView.swift`, `Overlay/SelectionOverlayController.swift`, ShotCore `OverlayBarPlacement` | ☐ |
| Moments of delight | #1074 | `Design/` motion helpers, `Design/BrandMark.swift`, `Toast.swift` | ☐ |

### Capture

| Board | Issue | Files | QA |
| --- | --- | --- | --- |
| Area capture | #1076 | `Overlay/SelectionOverlayView.swift` | ☐ |
| Window pick and delay | #1077 highlights | `Overlay/SelectionOverlayView.swift`, `Overlay/SelectionOverlayController.swift` | ☐ |
| Window pick and delay | #1075 capture bar with delay | `Overlay/SelectionOverlayView.swift` | ☐ |
| Scrolling capture | #1086 | `Capture/ScrollingCaptureController.swift` | ☐ |
| Quick Access, pin, menu and toasts › card | #1081 | `QuickAccess/QuickAccessView.swift` | ☐ |
| Quick Access, pin, menu and toasts › stack | #1082 | `QuickAccess/QuickAccessController.swift`, `QuickAccess/QuickAccessView.swift` | ☐ |
| Quick Access, pin, menu and toasts › pin | #1083 | `QuickAccess/PinController.swift` | ☐ |
| Quick Access, pin, menu and toasts › menu | #1084 | `ShotApp.swift`, `Design/BrandMark.swift` | ☐ |
| Quick Access, pin, menu and toasts › toast | #1085 | `Toast.swift` | ☐ |
| Quick Access, pin, menu and toasts › countdown | #1078 | `Capture/CaptureCoordinator.swift`, `Design/BrandMark.swift` | ☐ |
| Quick Access, pin, menu and toasts › floating panels | #1073 | `Design/GlassWindow.swift` | ☐ |
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
| Image editor · annotate | #1073 title bar | `Design/GlassWindow.swift`, `Editor/EditorWindowController.swift` | ☐ |
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
| Settings · General | #1073 sidebar material | `Design/GlassWindow.swift` | ☐ |
| Settings · Capture | #1113 | `Settings/SettingsView.swift` | ☐ |
| Settings · Quick Access | #1114 | `Settings/SettingsView.swift` | ☐ |
| Settings · Recording | #1115 | `Settings/SettingsView.swift`, `Settings/DevicePreview.swift` | ☐ |
| Settings · Shortcuts | #1116 | `Settings/ShortcutRecorderView.swift`, `Settings/SettingsView.swift` | ☐ |
| Settings · About | #1117 | `Settings/SettingsView.swift`, `Updater.swift`, `Permissions.swift` | ☐ |

### Website

| Board | Issue | Files | QA |
| --- | --- | --- | --- |
| Site · components and motion | #1123 | `site/src/styles/global.css`, `site/src/layouts/Base.astro`, `site/src/components/` | ☐ |
| Site · components and motion › 404 | #1127 | `site/src/pages/404.astro` | ☐ |
| Site · landing page | #1124 | `site/src/pages/index.astro`, `site/src/components/HeroStage.astro`, `Loop.astro`, `Copy.astro`, `Window.astro`, `ForMacs.astro` | ☐ |
| Site · guide page | #1125 | `site/src/layouts/Prose.astro`, `site/src/pages/docs/[page].astro`, `site/src/components/GuideSearch.astro` | ☐ |
| Site · guide page › long-form text | #1127 | `site/src/pages/privacy/`, `site/src/pages/screenshot-apps/` | ☐ |
| Site · changelog | #1126 | `site/src/pages/changelog/index.astro` | ☐ |

### Boards still to draw

#1067 adds these to the canvas. Each gets a row above once it's drawn.

| Board | Draw | Build |
| --- | --- | --- |
| Video editor and export (light) | #1067 | #1100 |
| Image editor (dark) | #1067 | #1093–#1099, then #1119 |
| Gallery (dark) | #1067 | #1106–#1110, then #1119 |
| Settings (dark) | #1067 | #1111–#1117, then #1119 |

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
