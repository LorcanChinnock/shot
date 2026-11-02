# Capture

Read this before changing how Shot takes a screenshot or picks an area, window or display.

- `AppDelegate` owns `AppState` and the `CaptureCoordinator`, wires hotkeys and controller callbacks to it, and routes `shot://` URLs. `ShotApp` is a `MenuBarExtra` with an `AppDelegate` adaptor. Other long-lived controllers are `.shared` singletons.
- `CaptureCoordinator.perform(_: ShotAction)` is the central dispatcher. `ShotAction` and `EditorRoute` live in ShotCore.
- For an area or window pick, `DisplayCapturer` freezes every display, then `SelectionOverlayController.select` returns an area, window or display.
- Fullscreen freezes only its screen and shows no overlay. A picked window is captured afresh, live, and recording runs live.
- `finish` encodes off the main actor, saves and copies, then opens Quick Access or the editor.
- Scroll is a toggle on the screenshot overlay (`S`, or its chip), off each time. When it is on, the pick (an area, window, browser page or screen) goes to `ScrollingCaptureController` instead of being captured, which streams it with `SCStream` while the person scrolls, and `ScrollStitcher` in ShotCore lines each frame up with the last and paints it into a growing canvas. Return hands the image to `finish` like any other capture. The stitcher is pure pixel work, tested with synthetic pages in `ScrollStitcherTests`.

## Scroll lab

`scripts/scroll-lab/` checks scrolling capture against real rendering rather than the synthetic pages in `ScrollStitcherTests`. Run it after any change to `ScrollStitcher` or `ScrollCanvas`.

- `run.sh [filter]` renders 33 scenarios in headless Chrome (pages in `pages.cjs`, scroll paths in `frames.cjs`: wheel notches, flicks, reversals, drops, jumps, sideways and diagonal), replays the frames through `ScrollStitcher` with the `ScrollLab` target, and scores each image against a full-page screenshot. It needs Google Chrome and `puppeteer-core` (installed into `$LAB_DIR`, default `/tmp/shot-scroll-lab`). Frames are cached, so a rerun only costs the stitching. `DPR=1` with another `LAB_DIR` runs the same scenarios as an external, non-Retina display sees them; both scales should pass the same scenarios. `*.diff.png` shows where an image differs (red) and what was never painted (magenta); `CROP=y,height` writes a close-up and `DIAG=<name>` prints each frame's candidates.
- `live.sh <page> <pattern>` scrolls a real `NSScrollView` (`target.swift`, with overlay scroll bars) using synthetic events (`drive.swift`) while the running `ShotDev` captures it, then scores the saved image. It moves the pointer and sends keys, so leave the machine alone while it runs. The terminal needs Accessibility access.
- A scenario passes when under 0.6% of its pixels differ, no 24-pixel band is more than 6% wrong, under 0.3% of what a frame could show is missing and under 0.5% is extra. Known failures: steps of more than a third of the area in one frame (150 points on the lab's page, which is a hard flick at 30 frames a second) give up after a few; diagonal scrolling over a pinned column leaves the first digits of the cells beside it clipped; and a bounce on a page whose pinned bars move with it, which a real window may not do, draws those bars again as content near the end.
- `ScrollOvershoot` cuts a rubber-band bounce from the end of the image: a short push past an edge, a return that settles, and flat rows between, still the outermost when the image is read. Nothing is removed while capturing.
