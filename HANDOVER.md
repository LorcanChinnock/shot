# Shot: handover plan

Build a personal macOS screenshot and screen-recording app that covers the CleanShot X features in daily use. One agent executes this plan end to end. A human does the steps marked **HUMAN**.

## 1. Goal and scope

### In scope (v1)
1. Area capture with a frozen-screen overlay.
2. Fullscreen capture and window capture.
3. Quick Access thumbnail after each capture.
4. Annotation editor.
5. Text capture (OCR).
6. Screen recording to MP4, with GIF export.
7. Settings: save folder, hotkeys, after-capture actions, launch at login.
8. URL scheme `shot://` for automation (Raycast, Shortcuts, smoke tests).

### Out of scope
Do not build these items: scrolling capture, cloud upload, pinned screenshots, self-timer, desktop-icon hiding, click visualization, webcam overlay, App Store distribution, sandboxing, localization, auto-update.

## 2. Verified environment (2026-10-02)

| Item | Value |
|---|---|
| macOS | 26.6.2 (Apple Silicon assumed) |
| Xcode | **Not installed.** Only Command Line Tools. |
| Swift | 6.4 (CLT toolchain) |
| Code-signing identities | **None** (`security find-identity -v -p codesigning` returns 0) |
| ffmpeg | `/opt/homebrew/bin/ffmpeg` (not needed by the app) |
| xcodegen, swiftlint | Not installed. Do not install them. |

## 3. Key decisions

| Decision | Choice | Reason |
|---|---|---|
| Build system | SwiftPM + a shell script that assembles `Shot.app` | No Xcode on this machine. No `.pbxproj` for the agent to edit. |
| Dependencies | **Zero** | The SwiftPM resource bundles of packages such as `KeyboardShortcuts` break `codesign` in a hand-assembled `.app`. Carbon `RegisterEventHotKey` needs about 100 lines. |
| Minimum OS | macOS 15.0 | Gives `SCRecordingOutput` (no `AVAssetWriter` code) and `captureMicrophone`. |
| Capture model | Freeze first: capture every display at hotkey press, then show the frozen image in the overlay and crop it | The overlay never appears in the capture. No timing races. Selection crops a `CGImage` in memory. |
| Window z-order | `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` | This list is ordered front to back. `SCShareableContent.windows` has no documented order. |
| After capture | Always save the PNG, copy it to the clipboard, and show Quick Access | Saving first makes drag-out trivial and prevents data loss. Each action has a settings toggle. |
| Rendering | One `AnnotationRenderer` draws into a `CGContext` for both screen and export | What you see is what you export. |
| Signing | Self-signed "Shot Dev" certificate | Screen Recording permission (TCC) is tied to the signature. Ad-hoc signatures change on every build and reset the permission. |

## 4. Prerequisites (HUMAN, about 5 minutes)

1. Create the signing certificate:
   1. Open **Keychain Access**.
   2. Select **Keychain Access › Certificate Assistant › Create a Certificate…**.
   3. Set Name to `Shot Dev`, Identity Type to `Self Signed Root`, and Certificate Type to `Code Signing`.
   4. Select **Create**.
   5. Run `security find-identity -p codesigning` and confirm that `Shot Dev` appears. It can show as not trusted. That is acceptable.
2. After the first `make run`, grant permissions:
   1. Open **System Settings › Privacy & Security › Screen & System Audio Recording**.
   2. Turn on **Shot**.
   3. Relaunch with `make run`.
3. Grant Microphone permission when the first recording with the mic prompts for it.

## 5. Repository layout

Path: `~/dev/shot`. Run `git init`, create branch `build/v1`, and commit after each phase. Do not add a remote.

```
shot/
  HANDOVER.md
  Package.swift
  Makefile
  Resources/
    Info.plist
  scripts/
    bundle.sh
  Sources/
    ShotCore/                 # pure logic, no AppKit windows; unit-tested
      Geometry.swift          # coordinate conversion, rect normalization, even-size rounding
      FileNaming.swift        # "Shot 2026-10-02 at 14.03.11.png"
      ImageIO+PNG.swift       # PNG encode with DPI metadata, crop
      Annotation.swift        # model + hit-testing
      AnnotationRenderer.swift
      OCR.swift               # Vision wrapper
      GIFExporter.swift
      Hotkey.swift            # key combo model + Carbon codes
    Shot/                     # the app
      ShotApp.swift           # @main, MenuBarExtra, Settings scene
      AppDelegate.swift       # URL scheme, launch tasks
      AppState.swift          # @Observable app state, recording state
      Permissions.swift
      HotkeyCenter.swift      # RegisterEventHotKey wrapper
      Capture/
        DisplayCapturer.swift # SCK freeze-capture of all displays
        WindowCapturer.swift
        CaptureCoordinator.swift  # orchestrates modes and post-capture actions
      Overlay/
        SelectionOverlayController.swift
        SelectionOverlayView.swift
      QuickAccess/
        QuickAccessController.swift
        QuickAccessView.swift
        Toast.swift
      Editor/
        EditorWindowController.swift
        EditorCanvasView.swift
        EditorToolbar.swift
      Recording/
        Recorder.swift
        RecordingBorderPanel.swift
      Settings/
        SettingsView.swift
        ShortcutRecorderView.swift
        Preferences.swift
  Tests/
    ShotCoreTests/
```

## 6. Build and run

### Package.swift
- `swift-tools-version: 6.0`, `platforms: [.macOS(.v15)]`.
- Targets: library `ShotCore`, executable `Shot` (depends on `ShotCore`), test target `ShotCoreTests`.
- Use Swift Testing (`import Testing`).

### Resources/Info.plist
| Key | Value |
|---|---|
| `CFBundleIdentifier` | `dev.lorcan.Shot` |
| `CFBundleName` / `CFBundleExecutable` | `Shot` |
| `CFBundlePackageType` | `APPL` |
| `CFBundleShortVersionString` / `CFBundleVersion` | `0.1.0` / `1` |
| `LSMinimumSystemVersion` | `15.0` |
| `LSUIElement` | `true` |
| `NSHighResolutionCapable` | `true` |
| `NSMicrophoneUsageDescription` | `Shot records your microphone during screen recordings when you turn it on.` |
| `CFBundleURLTypes` | one entry, scheme `shot` |

### scripts/bundle.sh
1. Run `swift build -c release`.
2. Create `build/Shot.app/Contents/{MacOS,Resources}`.
3. Copy `.build/release/Shot` to `Contents/MacOS/Shot`.
4. Copy `Resources/Info.plist` to `Contents/Info.plist`.
5. Sign: `codesign --force --deep --sign "${SHOT_SIGN_IDENTITY:-Shot Dev}" build/Shot.app`. If the identity is missing, print a warning and sign ad-hoc (`-`).
6. Replace `~/Applications/Shot.app` with the new bundle. A stable install path keeps the TCC grant stable.

### Makefile
- `make build`: `swift build`
- `make test`: `swift test`
- `make app`: `scripts/bundle.sh`
- `make run`: `make app`, then `pkill -x Shot || true`, then `open ~/Applications/Shot.app`
- `make reset-tcc`: `tccutil reset ScreenCapture dev.lorcan.Shot`

## 7. Cross-cutting rules

### Coordinates
- AppKit global space: origin at the bottom-left of the primary screen, in points.
- CoreGraphics and ScreenCaptureKit space: origin at the top-left of the primary screen, in points.
- Convert with `cgY = primaryScreenHeight - (y + height)`. Put this conversion in `ShotCore/Geometry.swift` only. Test it with two displays, one of them at a negative offset.
- Match `NSScreen` to `SCDisplay` with `screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as CGDirectDisplayID` and `SCDisplay.displayID`.
- Pixel scale for a display = frozen image pixel width / `screen.frame.width`. Do not assume 2.0.

### Image output
- Encode PNG with `CGImageDestination`. Set `kCGImagePropertyDPIWidth` and `kCGImagePropertyDPIHeight` to `72 × scale`. Retina captures then open at point size.
- Clipboard: call `clearContents()`, then write PNG data for `.png` and the `NSImage` (TIFF) for apps that do not read PNG.
- Default save folder: `~/Pictures/Shot/`. Create it if it is missing.
- Filename: `Shot yyyy-MM-dd at HH.mm.ss.png`. Add ` (2)`, ` (3)` on collision.

### Threading
- Use Swift 6 strict concurrency. Mark UI types `@MainActor`.
- Run SCK, Vision, PNG encoding, and GIF export off the main actor.

### Errors
- Show a `Toast` with a one-line message for every failed user action. Never fail silently.
- Log with `os.Logger(subsystem: "dev.lorcan.Shot", category: …)`.

### Code style
- Brace every `if`, `else`, `for`, and `while` body.
- Write comments only for non-obvious constraints. Keep each comment to one line.

## 8. Phases

Complete each phase in order. At the end of each phase, run `make test` and `make app`, run the agent checks, and commit (`feat(scope): summary`). List the HUMAN checks in the final report. Do not block on them.

### Phase 0: Toolchain gate
1. Create the package with a minimal `MenuBarExtra("Shot", systemImage: "camera.viewfinder")` and one `@Observable` class.
2. Add one Swift Testing test in `ShotCoreTests`.
3. Run `make test` and `make run`.

**Pass:** the build succeeds, the test runs, and the menu bar icon appears.
**If `swift test` fails** because the Testing or XCTest module is missing in the CLT, add an executable target `ShotCoreSelfTest` that runs `precondition`-based checks, and make `make test` run it. Record this in the final report.
**If SwiftUI macros or `MenuBarExtra` fail to build:** stop. Report that Xcode is required. Do not work around it.

### Phase 1: Permissions, hotkeys, menu
1. `Permissions.swift`: on launch, call `CGPreflightScreenCaptureAccess()`. If it returns false, show an onboarding window. The window has a **Grant** button (`CGRequestScreenCaptureAccess()`), an **Open Settings** button (`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`), and a **Relaunch** button.
2. `HotkeyCenter.swift`: register combos with `RegisterEventHotKey` and an `InstallEventHandler` for `kEventHotKeyPressed`. Support re-registration when settings change.
3. Default hotkeys:

| Action | Default |
|---|---|
| Capture Area | ⌃⇧4 |
| Capture Fullscreen | ⌃⇧3 |
| Capture Window | ⌃⇧W |
| Capture Text (OCR) | ⌃⇧2 |
| Record Screen / Stop | ⌃⇧5 |

4. Menu items: each action with its shortcut, a divider, **Open Capture Folder**, **Settings…** (`SettingsLink`; also call `NSApp.activate()`), and **Quit**.
5. `AppDelegate.application(_:open:)` handles URLs: `shot://capture-area`, `shot://capture-fullscreen`, `shot://capture-window`, `shot://capture-text`, `shot://record`, `shot://annotate?path=<file>`.

**Agent check:** run `open "shot://capture-fullscreen"` and confirm in `log show --last 1m --predicate 'subsystem == "dev.lorcan.Shot"'` that the action is received.
**HUMAN:** each hotkey triggers its action. The onboarding window appears when permission is missing.

### Phase 2: Fullscreen capture and post-capture pipeline
1. `DisplayCapturer.captureAll() async throws -> [FrozenDisplay]`. `FrozenDisplay` holds the `CGDirectDisplayID`, the `NSScreen` frame, the scale, and the `CGImage`.
   - Get `SCShareableContent.current`.
   - For each display, call `SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display:excludingWindows: []), configuration:)`.
   - Set `width` and `height` in pixels (points × `backingScaleFactor`). Set `showsCursor = false`.
   - Capture all displays concurrently with a task group.
2. Fullscreen captures the display under the mouse pointer.
3. `CaptureCoordinator.finish(image:)` runs the enabled actions: save, copy, show Quick Access (Phase 4; use a Toast until then).

**Agent check:** run `open "shot://capture-fullscreen"`. Confirm that a new PNG exists in `~/Pictures/Shot/`. Confirm that `sips -g pixelWidth -g pixelHeight` matches the main display's pixel size from `system_profiler SPDisplaysDataType`.
**Unit tests:** filename generation and collision suffixes, PNG DPI metadata, coordinate conversion.

### Phase 3: Area overlay and window capture
1. `SelectionOverlayController` creates one `NSPanel` for each display.
   - Style mask `[.borderless, .nonactivatingPanel]`. Subclass so that `canBecomeKey` returns `true`.
   - Level `.screenSaver`. Collection behavior `[.canJoinAllSpaces, .fullScreenAuxiliary]`.
   - Frame = `screen.frame`. Content = the frozen image for that display.
   - Call `NSApp.activate()` and make the panel under the pointer key.
2. `SelectionOverlayView` (an `NSView`, not SwiftUI, for precise mouse handling):
   - Draw the frozen image, a 45% black dim layer, and the clear selection rectangle with a 1 pt white border.
   - Draw full-screen crosshair lines through the pointer before the drag starts.
   - Show a size label (`W × H` in pixels) near the pointer.
   - Show a magnifier loupe (8× zoom, 120 pt) near the pointer before the drag starts.
   - Hold Shift while dragging to constrain the selection to a square.
   - Hold Space while dragging to move the selection.
   - Press Esc to cancel. Release the mouse to finish.
   - Keep the selection on the display where the drag started.
   - Ignore selections smaller than 4 × 4 pt as accidental clicks.
3. Window mode: press Space before the drag starts to toggle it. **Capture Window** starts directly in this mode.
   - Get on-screen windows from `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)` (front to back).
   - Keep windows with `kCGWindowLayer == 0`, not owned by Shot, and at least 40 × 40 pt.
   - Highlight the topmost window under the pointer with a tinted fill.
   - On click, map `kCGWindowNumber` to `SCWindow.windowID` and capture with `SCContentFilter(desktopIndependentWindow:)`. This capture is live, not frozen, so it excludes occluding windows.
   - Include the window shadow by default (setting: **Window shadow**). **Unverified:** shadow sizing with `ignoreShadowsSingleWindow = false`. If the shadow is clipped, set it to `true` for v1 and record this in the final report.
4. Crop the frozen image with `CGImage.cropping(to:)` in pixel coordinates.

**Unit tests:** rect normalization from any drag direction, square constraint, crop rect conversion for scale 1 and 2, window hit-test order.
**HUMAN:** area capture on each display, window capture, Esc, Shift, Space.

### Phase 4: Quick Access
1. `QuickAccessController` creates a non-activating floating `NSPanel` (level `.floating`). It sits at the bottom-left corner of the screen under the pointer, with 20 pt insets. It hosts a SwiftUI `QuickAccessView`.
2. Each capture adds a card: a 240 pt wide thumbnail. On hover, the card shows **Copy**, **Save As…**, **Annotate**, **Show in Finder**, and **×**.
3. Stack up to 5 cards vertically, newest at the bottom. Close the oldest card when a sixth arrives.
4. Drag a card to another app to drop the saved file URL (`.onDrag { NSItemProvider(contentsOf: url) }`).
5. Auto-close each card after 8 s. Hover pauses the timer. The duration is a setting; 0 means never.
6. `Toast`: a small HUD panel with a message. It auto-hides after 1.5 s.

**HUMAN:** drag into Slack or Finder, every button, auto-close, stacking.

### Phase 5: Annotation editor
1. `EditorWindowController` opens a titled, resizable `NSWindow` for a file URL. It opens from Quick Access **Annotate** or from `shot://annotate?path=`.
2. Model (`ShotCore/Annotation.swift`), all in image pixel coordinates:
   ```swift
   struct Annotation: Identifiable, Equatable {
       let id: UUID
       var kind: Kind
       var color: RGBA
       var lineWidth: CGFloat
       enum Kind: Equatable {
           case arrow(from: CGPoint, to: CGPoint)
           case line(from: CGPoint, to: CGPoint)
           case rect(CGRect)
           case ellipse(CGRect)
           case highlight(CGRect)          // translucent yellow fill, multiply blend
           case pixelate(CGRect)
           case text(String, origin: CGPoint, fontSize: CGFloat)
           case counter(Int, center: CGPoint)
       }
   }
   struct EditorDocument { var base: CGImage; var annotations: [Annotation]; var crop: CGRect? }
   ```
3. `AnnotationRenderer.render(_ doc: EditorDocument, into ctx: CGContext)` draws the base image, then each annotation in order.
   - Arrow: a line with a filled triangular head. Head length = `max(12, lineWidth × 4)`.
   - Pixelate: apply `CIPixellate` to the base region. Scale = `max(8, rect.width / 20)`.
   - Counter: a filled circle with a white number. Numbers increase from 1.
4. `EditorCanvasView` (`NSView`) scales the document to fit and calls the same renderer.
5. Tools and keys:

| Tool | Key |
|---|---|
| Select / move | V |
| Arrow | A |
| Line | L |
| Rectangle | R |
| Ellipse | O |
| Text | T |
| Highlight | H |
| Pixelate | P |
| Counter | N |
| Crop | C |

6. Toolbar: the tools, 6 preset colors (red default), and 3 line widths (2, 4, 8 px × scale).
7. Select tool: click to hit-test from top to bottom, drag to move, Delete to remove.
8. Text tool: click to place an `NSTextField` over the canvas. Enter or a click outside commits the text. Esc cancels it.
9. Undo and redo: ⌘Z and ⇧⌘Z over a stack of `[Annotation]` + crop snapshots. Value types make each snapshot a copy.
10. ⌘C copies the flattened image. ⌘S overwrites the capture file and copies the image. Closing a window with unsaved changes shows an `NSAlert` with **Save**, **Discard**, and **Cancel**.

**Unit tests:** hit-testing for each kind, export size with and without crop, renderer output size, undo/redo stack.
**Agent check:** run `open "shot://annotate?path=<a phase-2 PNG>"` and confirm in the log that the window opens.
**HUMAN:** every tool, text editing, undo, save.

### Phase 6: Text capture (OCR)
1. **Capture Text** opens the area overlay in text mode (same overlay, different finish handler).
2. `ShotCore/OCR.swift`: `VNRecognizeTextRequest` with `recognitionLevel = .accurate`, `usesLanguageCorrection = true`, and `automaticallyDetectsLanguage = true`. Join the top candidates in reading order with `\n`.
3. Copy the string to the clipboard. Show the toast "Copied N characters", or "No text found".
4. Do not save a file. Do not show Quick Access.

**Unit test:** render "Hello Shot 123" into a `CGContext` at 32 pt and assert that OCR returns it.

### Phase 7: Screen recording
1. **Record Screen** opens the overlay in live mode: transparent with a dim layer, no frozen image. Selecting an area or clicking a window sets the region. Press Enter to record the full display.
2. `Recorder`:
   - Filter: `SCContentFilter(display:excludingApplications: [Shot's SCRunningApplication], exceptingWindows: [])`.
   - Configuration: `sourceRect` = selection in display-local top-left points. Set `width` and `height` in pixels, rounded down to even numbers (H.264 requires this). Set `minimumFrameInterval = CMTime(value: 1, timescale: fps)` (setting: 30 or 60, default 60) and `showsCursor = true`.
   - Microphone: when the setting is on, set `captureMicrophone = true`. Default: off.
   - Output: `SCRecordingOutputConfiguration` with `outputURL` in the save folder (`Shot … .mp4`), `outputFileType = .mp4`, and `videoCodecType = .h264`. Call `stream.addRecordingOutput(_:)` before `startCapture()`.
   - **Unverified:** whether `SCRecordingOutput` needs a `.screen` stream output as well. If recording produces an empty file, add a no-op `SCStreamOutput` for `.screen`.
3. While recording:
   - Show a `RecordingBorderPanel` around the region: a red 2 pt border with `ignoresMouseEvents = true`. The filter excludes Shot, so the border does not appear in the video.
   - Change the menu bar icon to `stop.circle.fill`. Put **Stop Recording (⌃⇧5)** at the top of the menu.
   - The same hotkey and `shot://record` stop the recording.
4. On finish (`SCRecordingOutputDelegate.recordingOutputDidFinishRecording`), show a Quick Access card with a video thumbnail (`AVAssetImageGenerator` at t = 0) and an extra **GIF** button.
5. `GIFExporter`: sample frames with `AVAssetImageGenerator` at 12 fps and a maximum width of 720 px. Write them with `CGImageDestination` (`UTType.gif`, loop count 0, frame delay 1/12). Show a progress toast. Cap the input at 60 s and say so in the toast. Longer input needs a streaming exporter.

**Unit test:** GIFExporter on a 2 s synthetic MP4 (write it in the test with `AVAssetWriter`). Assert the frame count (24 ± 1) and the maximum width.
**HUMAN:** region and full-display recording, mic recording, stop by hotkey, GIF export.

### Phase 8: Settings and polish
1. `Settings` scene with three tabs:
   - **General:** save folder (`NSOpenPanel`), after-capture toggles (save, copy, Quick Access), Quick Access duration, window shadow, launch at login (`SMAppService.mainApp.register()` / `unregister()`).
   - **Shortcuts:** one `ShortcutRecorderView` for each action. Click to record. A local `NSEvent` monitor captures the next keyDown with at least one modifier. Esc cancels. Backspace clears. Save changes immediately and re-register them.
   - **Recording:** FPS (30/60), microphone on/off, show cursor.
2. `Preferences.swift`: `@AppStorage` keys with the defaults from this plan.
3. Make sure every menu item shows its current shortcut.

**Unit tests:** hotkey encode and decode round trip, preference defaults.

## 9. Known risks

| Risk | Mitigation |
|---|---|
| The CLT toolchain cannot build or test | Phase 0 gate. Stop and report. |
| Screen Recording permission resets after rebuilds | Self-signed certificate plus a stable install path. Fallback: `make reset-tcc`, then grant again. |
| macOS shows periodic "still allow screen recording?" prompts for apps that use SCK outside the system picker | Expected OS behavior (unverified on macOS 26). Do not work around it. |
| A system shortcut keeps a hotkey | Defaults use ⌃⇧, which the macOS screenshot shortcuts (⌘⇧3/4/5, ⌃⌘⇧3/4) do not use. Shortcuts are configurable in Settings. |
| Settings window does not come to front from a `LSUIElement` app | Call `NSApp.activate()` before `SettingsLink` opens the window. Fallback: temporarily set the activation policy to `.regular` while the window is open. |
| Freeze capture is slow on many displays | Capture all displays concurrently. Measure. If it takes more than 300 ms, cache `SCShareableContent` for 2 s. |

## 10. Definition of done
1. All phases are committed on `build/v1`.
2. `make test` passes.
3. `make app` produces a signed `~/Applications/Shot.app`.
4. Every agent check passes.
5. The final report lists:
   - Every HUMAN check, as a checklist.
   - Every "unverified" item from this plan and its outcome.
   - Every deviation from this plan, with the reason.

## 11. Kickoff prompt

> Read `~/dev/shot/HANDOVER.md`. Execute phases 0 to 8 in order. Follow its decisions. Do not add dependencies or out-of-scope features. Stop only at the Phase 0 gate failure. At the end, give the report from section 10.
