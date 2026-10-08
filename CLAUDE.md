# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Shot is a macOS 15+ menu bar app for screenshots, annotation, screen recording and GIF export. It's a SwiftPM package (Swift 6 language mode, strict concurrency) whose only dependency is Sparkle.

## Mantra

By default, Shot is fast, convenient and bloat-free for its main use: taking quick, easy screenshots and recordings. If you want more tools, they're built in too, but they stay out of the way until you ask for them.

- Nothing may slow down or clutter the capture → copy/save path.
- The default is the simplest state. Extra tools, panels and controls start off.

## Commands

```bash
make test                         # ShotCore unit tests (Swift Testing)
make perf                         # ShotCore performance budgets (PerfTests; make test skips them)
make perf-app                     # scripts/perf.sh: launch, capture, memory, idle CPU of the installed app
make lint                         # scripts/lint.sh: bans patterns that caused bugs (see below)
make build                        # swift build
make bundle                       # build and sign build/Shot.app only
make run                          # build, install to /Applications/Shot.app, relaunch
swift test --filter <testName>    # one test, e.g. --filter hitTestFilledKinds
```

- With only the Command Line Tools selected, the Makefile pins the 26.5 SDK and adds the testing plugin path, so a bare `swift build`/`swift test` can fail on SwiftUI macros. Prefer `make`, or prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Signing uses the `Shot Dev` certificate from `scripts/make-dev-cert.sh` so the Screen Recording permission survives rebuilds. `make reset-tcc` clears it.
- Logs: `log stream --predicate 'subsystem == "dev.lorcan.Shot"'`. Use `Logger.shot("category")` from `Sources/Shot/Log.swift`.
- The `shot://` URL scheme drives every action without a keyboard (`shot://annotate?path=`, `shot://edit-video?path=`, `shot://gallery`, `shot://settings?section=`; full list in `docs/usage.md`). An installed release also registers it, so quit other copies before testing a build.

## Architecture

Two targets:
- `Sources/ShotCore`: pure logic with no window, display or permission needs. Annotation model and renderer, timeline/clip model, trim and cuts, composition, GIF export, preferences, hotkeys, file naming. **If logic can be tested without a window, it goes here with a test.** Only ShotCore is tested (`Tests/ShotCoreTests`, mostly top-level `@Test func` with sentence-style names).
- `Sources/Shot`: AppKit and SwiftUI that need a real session, grouped by feature (`Capture`, `Overlay`, `QuickAccess`, `Editor`, `Recording`, `VideoEditor`, `Gallery`, `Settings`, `Design`).

Flow:
- `ShotApp` is a `MenuBarExtra` with an `AppDelegate` adaptor. `AppDelegate` owns `AppState` and the `CaptureCoordinator`, wires hotkeys and controller callbacks to it, and routes `shot://` URLs. Other long-lived controllers are `.shared` singletons.
- `CaptureCoordinator.perform(_: ShotAction)` is the central dispatcher. `ShotAction` and `EditorRoute` live in ShotCore.
- Capture: `DisplayCapturer` freezes every display, then `SelectionOverlayController.select` returns an area, window or display. `finish` encodes off the main actor, saves and copies, then opens Quick Access or the editor.
- Image editor: `EditorDocument` / `Annotation` (ShotCore) is the model. `AnnotationRenderer` is shared by the on-screen canvas, flattened export, and the video compositor (`ProjectCompositor` via `AnnotationFrame`/`RenderCache`), so a rendering change affects all three. Undo is snapshot-based through ShotCore's generic `UndoStack`, not `NSUndoManager`. Group continuous edits (slider drags, held keys) into one step; view state like zoom is not undoable.
- Recording: `Recorder` uses `SCStream` + `SCRecordingOutput`. Each pause starts a new segment, and `VideoConcatenator` joins them on stop. Mic and system audio are written to separate files.
- Video editor: `VideoEditorModel` keeps its own `UndoStack`. The timeline, keyframe, trim, cut and composition logic is in ShotCore (`Timeline*`, `VideoCuts`, `ProjectComposition`). GIF export is entirely ShotCore (`GIFExporter`, `GIFStreamWriter`).
- Settings: keys and defaults live in ShotCore `Preferences`. `SettingsStore` is an `@Observable` cache, and views use its `@Setting(key)` wrapper.
- Design system: `Sources/Shot/Design`. `Brutal` holds the tokens in `BrutalStyle.swift`, and `GlassWindow.swift` the window chrome.

Concurrency: UI and model types are `@MainActor`. Heavy work runs in `Task.detached`, and CG types cross actors through `@unchecked Sendable` wrappers (`SendableImage`, `EditorDocument`).

## Rules enforced by `make lint`

- Use `NSHostingView(fixedFrame:)`, never `NSHostingView(rootView:)`/`NSHostingController`; a plain hosting view crashes when content changes under a visible window.
- Use `@Setting`, never `@AppStorage`; `@AppStorage` updates late, so views show inconsistent state.
- Use `inkBorder(_:width:)` rather than `strokeBorder(Brutal.ink…)`, and only whole-point ink widths.

## Conventions

- Strings are hard-coded English; there's no localization.
- PR titles use Conventional Commits (`feat(editor): …`, `fix(recording): …`). PRs are squash-merged and release-please generates versions and `CHANGELOG.md`, so never edit the version or tags by hand.
- Only `make dist` keeps the Sparkle feed in `Info.plist`, so dev builds never self-update.
- To QA UI changes by driving the real app, use the `.agents/skills/ux-qa` skill.
