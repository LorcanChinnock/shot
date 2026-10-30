# Capture

Read this before changing how Shot takes a screenshot or picks an area, window or display.

- `AppDelegate` owns `AppState` and the `CaptureCoordinator`, wires hotkeys and controller callbacks to it, and routes `shot://` URLs. `ShotApp` is a `MenuBarExtra` with an `AppDelegate` adaptor. Other long-lived controllers are `.shared` singletons.
- `CaptureCoordinator.perform(_: ShotAction)` is the central dispatcher. `ShotAction` and `EditorRoute` live in ShotCore.
- For an area or window pick, `DisplayCapturer` freezes every display, then `SelectionOverlayController.select` returns an area, window or display.
- Fullscreen freezes only its screen and shows no overlay. A picked window is captured afresh, live, and recording runs live.
- `finish` encodes off the main actor, saves and copies, then opens Quick Access or the editor.
- Scroll is a toggle on the screenshot overlay (`S`, or its chip), off each time. When it is on, the pick (an area, window, browser page or screen) goes to `ScrollingCaptureController` instead of being captured, which streams it with `SCStream` while the person scrolls, and `ScrollStitcher` in ShotCore lines each frame up with the last and paints it into a growing canvas. Return hands the image to `finish` like any other capture. The stitcher is pure pixel work, tested with synthetic pages in `ScrollStitcherTests`.
