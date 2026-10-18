# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Shot is a macOS 15+ menu bar app for screenshots, annotation, screen recording and GIF export. It's a SwiftPM package (Swift 6 language mode, strict concurrency) whose only dependency is Sparkle.

## Mantra

By default, Shot is fast, convenient and bloat-free for its main use: taking quick, easy screenshots and recordings. If you want more tools, they're built in too, but they stay out of the way until you ask for them.

- Nothing may slow down or clutter the capture → copy/save path.
- The default is the simplest state. Extra tools, panels and controls start off.

## Who uses Shot

Shot is for anyone on a Mac, not just developers. Design and write for the first person on this list; the later ones opt in to more.

- **The quick sharer.** Takes a screenshot, maybe adds an arrow, and pastes it into a chat or email. Rarely opens Settings. Every default is set for them, and the capture → copy/save path is theirs.
- **The explainer.** Support staff, teachers, managers and testers showing someone what's wrong or how to do something. Annotates, blurs private details, records short walkthroughs with their voice, and exports GIFs.
- **The polisher.** Designers, marketers and writers making images for docs, slides and social posts. Uses the editor: combining screenshots, padding, backgrounds, styled markup, trimmed and sped-up recordings.
- **The AI assistant user.** Asks Claude, ChatGPT or another assistant about what's on their screen. Isn't a developer and won't edit a config file or use a terminal, so agent features need one-click setup and plain words.
- **The developer.** Uses coding agents (Claude Code, Codex, Cursor), the `shot` command and the MCP server, and lets agents capture windows such as the iOS Simulator to check their own work.

What this means in practice:
- UI strings, Settings and the user guide speak to everyone. Avoid jargon (MCP, CLI, JSON, stdio) outside the developer-facing parts, and explain it where it can't be avoided.
- When a feature mentions AI, lead with general assistants as examples, then coding agents.
- Developer features stay in their own Settings cards and guide pages, off by default, so they never clutter the path the quick sharer uses.

## Commands

```bash
make test                         # ShotModel, ShotCore and ShotCoreApple unit tests (Swift Testing)
make test-linux                   # ShotModel and ShotCore tests in Docker on Linux, as CI runs them
make perf                         # ShotCore performance budgets (PerfTests; make test skips them)
make perf-app                     # scripts/perf.sh: launch, capture, memory, idle CPU of the installed app
make lint                         # scripts/lint.sh: bans patterns that caused bugs (see below); on macOS also scripts/strings.sh --check
make strings                      # sync Resources/Localizable.xcstrings with the strings the build extracted
make build                        # swift build
make bundle                       # build and sign build/ShotDev.app only
make run                          # build, install to /Applications/ShotDev.app, relaunch
cd site && npm run dev            # the marketing site (see site/README.md)
swift test --filter <testName>    # one test, e.g. --filter hitTestFilledKinds
```

- With only the Command Line Tools selected, the Makefile pins the newest 26.x SDK and adds the testing plugin path, so a bare `swift build`/`swift test` can fail on SwiftUI macros. Prefer `make`, or prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Signing uses the `Shot Dev` certificate from `scripts/make-dev-cert.sh` so the Screen Recording permission survives rebuilds. `make reset-tcc` clears it.
- Logs: `log stream --predicate 'subsystem == "dev.lorcan.Shot.dev"'` for ShotDev, `dev.lorcan.Shot` for a release. Use `Logger.shot("category")` from `Sources/Shot/Log.swift`.
- The `shot://` URL scheme drives every action without a keyboard (`shot://annotate?path=`, `shot://edit-video?path=`, `shot://gallery`, `shot://settings?section=`; full list on the URL scheme page, `site/src/guide/10-url-scheme.md`). ShotDev registers `shot-dev://` instead, so it never collides with an installed release.

## Running and testing locally

Local builds are `ShotDev.app`. The real installed version is `/Applications/Shot.app`, usually from Homebrew. Never install over, rename or delete `Shot.app`, or Homebrew loses track of it.

1. **Quit the installed release first:** `pkill -x Shot`. Both apps register the same global shortcuts, so with both running a hotkey can reach the wrong one. `-x` matches the executable name exactly, so `pkill -x Shot` never kills ShotDev, and `pkill -x ShotDev` never kills the release.
2. **Run the dev build:** `make run` builds, installs `/Applications/ShotDev.app` and launches it. Drive it with `shot-dev://` URLs, and confirm the running binary with `pgrep -lf ShotDev`. The ux-qa skill runs `build/ShotDev.app` from `make bundle` without installing it.
3. **When finished, quit and uninstall the dev build,** then reopen the release if it was running:
   ```bash
   pkill -x ShotDev
   rm -rf /Applications/ShotDev.app build/ShotDev.app   # or $INSTALL_DIR/ShotDev.app if you set it
   open /Applications/Shot.app
   ```
   Leave ShotDev's settings (`dev.lorcan.Shot.dev`) and its Screen Recording permission in place, so the next run doesn't ask for the permission again.

## Architecture

Four targets:
- `Sources/ShotModel`: logic that needs only Foundation, so CI builds and tests it on Linux. Undo stack, keyframes, cut list and trim range, hotkeys (`ShotAction`, `KeyCombo`), layout math, text wrapping (`TextLayout`, `NoteLayout`) over the `TextShaper` protocol, and small helpers. It may import CoreGraphics only inside `#if canImport(CoreGraphics)`, for the few members that need it. Linux Foundation has `CGFloat`, `CGPoint`, `CGSize` and `CGRect`, but not `CGVector`, `CGAffineTransform`, `CGPath`, `CGColor` or `CGImage`.
- `Sources/ShotCore`: pure logic that needs Apple frameworks (CoreGraphics paths and images, CoreText, CoreImage, AVFoundation, ImageIO, UniformTypeIdentifiers), but no window, display or permission. Annotation model and renderer, timeline/clip model, composition, GIF export, preferences, file naming, gallery. It re-exports ShotModel. CI builds and tests it on Linux too, so every file that imports an Apple framework (or uses Darwin-only Foundation such as `String(localized:)`) sits inside `#if canImport(...)` and Linux compiles it out. #646 moves these framework calls behind protocols, one sub-issue at a time.
- `Sources/ShotCoreApple`: macOS only. The Apple implementations of ShotCore's protocols move here as each one lands; so far `ImageIOCodec`, ShotCore's `ImageCoding` on ImageIO (#649), `CGCanvas`, its `Canvas` on a `CGContext` (#648), `CoreImageEffects`, its `ImageEffects` on Core Image (#651), and `CoreTextShaper`, ShotModel's `TextShaper` on Core Text (#650). ShotCore code that needs one takes it as a parameter (`codec: any ImageCoding`, `shaper: any TextShaper` where it measures text, or `canvasType: any Canvas.Type` where it makes its own canvas; a canvas type names its effects and shaper as `Canvas.effects` and `Canvas.shaper`), and ShotCoreApple declares the same call again without that parameter, passing the Apple implementation (`ImageIOCodec+Defaults.swift`, `CGCanvas+Defaults.swift`, `CoreTextShaper+Defaults.swift`), so the app, ShotCLI and the tests call it as before. It re-exports ShotCore, so the app and ShotCLI need only `import ShotCoreApple`, and tests of the calls it completes add `import ShotCoreApple`.
- `Sources/Shot`: AppKit and SwiftUI that need a real session, grouped by feature (`Capture`, `Overlay`, `QuickAccess`, `Editor`, `Recording`, `VideoEditor`, `Gallery`, `Settings`, `Design`).

**If logic can be tested without a window, it goes in ShotModel with a test, or in ShotCore if it needs an Apple framework.** Tests are mostly top-level `@Test func` with sentence-style names: `Tests/ShotModelTests` and `Tests/ShotCoreTests` (run on Linux), and `Tests/ShotCoreAppleTests` (macOS), which holds the tests of everything still under `#if canImport`. The app target has no tests.

Flow:
- `ShotApp` is a `MenuBarExtra` with an `AppDelegate` adaptor. `AppDelegate` owns `AppState` and the `CaptureCoordinator`, wires hotkeys and controller callbacks to it, and routes `shot://` URLs. Other long-lived controllers are `.shared` singletons.
- `CaptureCoordinator.perform(_: ShotAction)` is the central dispatcher. `ShotAction` lives in ShotModel and `EditorRoute` in ShotCore.
- Capture: for an area or window pick, `DisplayCapturer` freezes every display, then `SelectionOverlayController.select` returns an area, window or display. Fullscreen freezes only its screen and shows no overlay, a picked window is captured afresh, live, and recording runs live. `finish` encodes off the main actor, saves and copies, then opens Quick Access or the editor.
- Image editor: `EditorDocument` / `Annotation` (ShotCore) is the model. `AnnotationRenderer` is shared by the on-screen canvas, flattened export, and the video compositor (`ProjectCompositor` via `AnnotationFrame`/`RenderCache`), so a rendering change affects all three. Undo is snapshot-based through ShotModel's generic `UndoStack`, not `NSUndoManager`. Group continuous edits (slider drags, held keys) into one step; view state like zoom is not undoable.
- Recording: `Recorder` uses `SCStream` + `SCRecordingOutput`. Each pause starts a new segment, and `VideoConcatenator` joins them on stop. With both the microphone and system audio on, each is also written to its own file, so mute silences only the microphone.
- Video editor: `VideoEditorModel` keeps its own `UndoStack`. The timeline and composition logic is in ShotCore (`Timeline*`, `ProjectComposition`); keyframes, trim and cuts are in ShotModel (`Keyframes`, `TrimRange`, `VideoCuts`). GIF export is entirely ShotCore (`GIFExporter`, `GIFStreamWriter`).
- Settings: keys and defaults live in ShotCore `Preferences`. `SettingsStore` is an `@Observable` cache, and views use its `@Setting(key)` wrapper.
- Design system: `Sources/Shot/Design`. `Brutal` holds the tokens in `BrutalStyle.swift`, and `GlassWindow.swift` the window chrome.

Website: `site/` is the Astro marketing site, built and deployed by Cloudflare Workers Builds (see `site/README.md`). The user guide lives in `site/src/guide/`, one Markdown file per page at `/docs/<slug>/`, in file name order. Each file's front matter gives its `title`, a one-line `summary` and its `group` (the groups are in `site/src/lib/guide-files.ts`); `aliases` lists a renamed page's old slugs, which get redirects, and `anchors` lists old section ids whose content moved to the page. Write pages as tasks, in second person: numbered steps, `<kbd>⌘⇧4</kbd>` for keys, and `> [!TIP]` or `> [!NOTE]` callouts. `/docs/` maps old `#anchors` to the pages. A new file becomes a new page. The site also renders `CHANGELOG.md` directly. release-please ignores `site/`.

Views in lazy collections (`LazyVGrid`, `List`, `LazyVStack`): a row or tile reads only its own state. It takes plain values, not the shared `@Observable` model, for anything that changes often (selection, hover, the playing item), and is `Equatable` with `.equatable()`, so one change re-evaluates the few views whose values changed, not all of them. Put footers and status text that read such state in their own `View` structs, not computed properties of a big body. One interaction must cost the same however big the library is. Use a single `onTapGesture` and read `NSApp.currentEvent?.clickCount`; `onTapGesture(count: 2)` delays every single click (lint rejects it).

Concurrency: UI and model types are `@MainActor`. Heavy work runs in `Task.detached`, and CG types cross actors through `@unchecked Sendable` wrappers (`SendableImage`, `EditorDocument`).

## Rules enforced by `make lint`

- Use `NSView(hosting:)`, never `NSHostingView(rootView:)`/`NSHostingController`; a plain hosting view crashes when content changes under a visible window. `GlassWindow.swift`, which defines the helper, is exempt.
- Use `@Setting`, never `@AppStorage`; `@AppStorage` updates late, so views show inconsistent state.
- Use `inkBorder(_:width:color:)` rather than `strokeBorder` with any `Brutal` colour (a ternary included), and only whole-point ink widths and line widths. `BrutalStyle.swift`, which defines `inkBorder`, is exempt.
- Use `style: .circular`, never `.continuous`, for rounded corners; continuous corners leave steps under ink borders.
- ShotModel and its tests import only Foundation, Synchronization and Testing, plus CoreGraphics inside `#if canImport(CoreGraphics)`.
- ShotCore and its portable tests import Apple frameworks only inside `#if canImport(...)`.
- Every `runs-on: macos-*` needs a `# macOS: <reason>` comment on the line above.

## CI

The repository is public, so GitHub's runners are free, but the free plan runs only 5 macOS jobs at once, so macOS runs can queue (`.github/workflows/ci.yml`):
- Every PR runs two required checks. `test` is Linux: `scripts/lint.sh` and the ShotModel and ShotCore tests, which keeps both portable (it installs zsh, which `AgentCommand`'s tests run). `macos` builds the app, checks the strings catalog, compiles for Intel, and runs every test target. On push to `main`, `warm-cache.yml` only builds, to save the Linux build cache PRs restore.
- On release-please's PR, `macos` also runs `PerfTests`: that's the release gate. Every push to that PR runs it again. release-please opens the PR as the repository's GitHub App (`release.yml`), so its runs start without the approval GitHub asks for on `github-actions[bot]` PRs.
- The repository has auto-merge turned off: an admin merges the release PR by hand once the gate has passed. If the gate fails, fix it in a normal PR. release-please updates the release PR only for commits that change the changelog, so after a `test:`, `ci:` or `docs:` fix, run `gh pr update-branch <release PR>` to gate it again.
- `release.yml` runs `make test` on the tagged commit before it signs anything, because a `docs:`, `test:` or `ci:` commit merged after the gate passed can change what's released.
- New logic and tests go in ShotModel unless they need an Apple framework. When they do, keep the Apple part in ShotCore as thin as you can and leave the rest portable.
- Run `make lint` and `make test` before every push, plus `make test-linux` when you change ShotModel or ShotCore, and push once per PR where you can, so CI is a check rather than a debugger. Every push re-runs CI, and a newer push cancels the run before it.
- Every release PR update runs the perf budgets, and every release builds and tests again, so let the release-please PR collect several merges rather than releasing after each one.

## Conventions

- UI strings go through `Resources/Localizable.xcstrings` (CONTRIBUTING.md › Strings and translations). Pass literals to localizing APIs: SwiftUI views, the Design components and `Toast`, which take `LocalizedStringResource` with a `@_disfavoredOverload` generic `StringProtocol` overload for text that's already localized. Keep that overload generic: a concrete `String` one, even disfavoured, wins over `LocalizedStringResource` when the call has other arguments, and the literal goes unlocalized. Two traps remain: a literal title next to a `String` subtitle or detail picks the verbatim overload (wrap the title in `String(localized:)`), and a ternary passed to an optional `LocalizedStringResource?` parameter extracts only its first branch (use a computed property). Anything else, such as AppKit titles or a `String` property, uses `String(localized:)`. ShotModel can't (no `String(localized:)` on Linux), so its labels live in ShotCore (`ShotModelTitles.swift`). Agent, MCP, CLI and `shot://` output, logs and file names stay English. After adding strings, run `make strings` and commit the catalog; `make lint` and CI fail while it's stale.
- PR titles use Conventional Commits (`feat(editor): …`, `fix(recording): …`). PRs are squash-merged and release-please generates versions and `CHANGELOG.md`, so never edit the version or tags by hand.
- Every PR links an issue or sub-issue: put `Closes #N` (or `Part of #N` when it doesn't finish the issue) in the PR body. Create the issue before starting any work, as a sub-issue when the work belongs to an umbrella issue.
- Any substantial change or new feature must keep docs and marketing in line in the same PR: the user guide in `site/src/guide/`, `README.md`, the landing page `site/src/pages/index.astro`, and the media in `docs/media/` if they now show stale UI. If an update needs new screenshots or recordings you can't make, say so rather than skipping it silently. `CHANGELOG.md` is generated, so don't edit it.
- Only `make dist` builds `Shot.app` with the Sparkle feed. Every other build is `ShotDev.app` (bundle ID `dev.lorcan.Shot.dev`, executable `ShotDev`, scheme `shot-dev://`, no feed), so dev builds never self-update or replace the installed release. `scripts/bundle.sh` does the renaming.
- To QA UI changes by driving the real app, use the `.agents/skills/ux-qa` skill.
