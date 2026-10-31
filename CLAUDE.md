# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Shot is a macOS 15+ menu bar app for screenshots, annotation, screen recording and GIF export. It's a SwiftPM package (Swift 6 language mode, strict concurrency) whose only dependency is Sparkle.

## Mantra

By default, Shot is fast, convenient and bloat-free for its main use: taking quick, easy screenshots and recordings. If you want more tools, they're built in too, but they stay out of the way until you ask for them.

- Nothing may slow down or clutter the capture → copy/save path.
- The default is the simplest state. Extra tools, panels and controls start off.

## Who uses Shot

Shot is for anyone on a Mac. Design and write for the first person on this list; the later ones opt in to more.

- **The quick sharer.** Takes a screenshot, maybe adds an arrow, and pastes it into a chat or email. Rarely opens Settings. Every default is set for them, and the capture → copy/save path is theirs.
- **The explainer.** Support staff, teachers, managers and testers showing someone what's wrong or how to do something. Annotates, blurs private details, records short walkthroughs with their voice, and exports GIFs.
- **The polisher.** Designers, marketers and writers making images for docs, slides and social posts. Uses the editor: combining screenshots, padding, backgrounds, styled markup, trimmed and sped-up recordings.
- **The AI assistant user.** Asks Claude, ChatGPT or another assistant about what's on their screen. Pastes a marked-up screenshot, or copies its path. Isn't a developer and won't edit a config file or use a terminal.

What this means in practice:
- UI strings, Settings and the user guide speak to everyone. Avoid jargon (JSON, URL scheme) outside the reference pages, and explain it where it can't be avoided.
- When a feature mentions AI, lead with general assistants as examples.
- Technical features, such as the `shot://` links, stay in their own guide pages, so they never clutter the path the quick sharer uses.

## Commands

```bash
make test                         # ShotCoreTests, the unit tests (Swift Testing)
make perf-app                     # scripts/perf.sh: launch, capture, memory, idle CPU of the installed app
make lint                         # scripts/lint.sh: bans patterns that caused bugs (see below); on macOS also scripts/strings.sh --check
make strings                      # sync Resources/Localizable.xcstrings with the strings the build extracted
make build                        # swift build
make bundle                       # build and sign build/ShotDev.app only
make run                          # build, install to /Applications/ShotDev.app, relaunch
make demo                         # build and open the MugCo sample app (Samples/MugCo): fake data, fixed size, for QA runs and screenshots
cd site && npm run dev            # the marketing site (see site/README.md)
swift test --filter <testName>    # one test, e.g. --filter hitTestFilledKinds
```

- With only the Command Line Tools selected, the Makefile pins the newest 26.x SDK and adds the testing plugin path, so a bare `swift build`/`swift test` can fail on SwiftUI macros. Prefer `make`, or prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Signing uses the `Shot Dev` certificate from `scripts/make-dev-cert.sh` so the Screen Recording permission survives rebuilds. `make reset-tcc` clears it.
- Logs: `log stream --predicate 'subsystem == "dev.lorcan.Shot.dev"'` for ShotDev, `dev.lorcan.Shot` for a release. Use `Logger.shot("category")` from `Sources/ShotCore/ShotLog.swift`.
- The `shot://` URL scheme drives every action without a keyboard (`shot://annotate?path=`, `shot://edit-video?path=`, `shot://gallery`, `shot://settings?section=`; full list on the URL scheme page, `site/src/guide/10-automation-reference.md`). ShotDev registers `shot-dev://` instead, so it never collides with an installed release.

## Running and testing locally

Local builds are `ShotDev.app`. The real installed version is `/Applications/Shot.app`, usually from the curl installer on the website. Never install over, rename or delete `Shot.app`; it is the copy the user relies on.

1. **Quit the installed release first:** `pkill -x Shot`. Both apps register the same global shortcuts, so with both running a hotkey can reach the wrong one. `-x` matches the executable name exactly, so `pkill -x Shot` never kills ShotDev, and `pkill -x ShotDev` never kills the release.
2. **Run the dev build:** `make run` builds, installs `/Applications/ShotDev.app` and launches it. Drive it with `shot-dev://` URLs, and confirm the running binary with `pgrep -lf ShotDev`.
3. **When finished, quit and uninstall the dev build,** then reopen the release if it was running:
   ```bash
   pkill -x ShotDev
   rm -rf /Applications/ShotDev.app build/ShotDev.app   # or $INSTALL_DIR/ShotDev.app if you set it
   open /Applications/Shot.app
   ```
   Leave ShotDev's settings (`dev.lorcan.Shot.dev`) and its Screen Recording permission in place, so the next run doesn't ask for the permission again.

## Capturing something in QA and screenshots

Use the MugCo sample app (`make demo`), not whatever window is open: your screen can show private tabs and mail, and changes every run. It is a fake support inbox in its own package, `Samples/MugCo`, so the main build and CI never compile it. It has an email address and card number to blur, and a wrong balance to point an arrow at. All its data is made up, so captures of it are safe to publish. Its window is titled "Mug Co. Support" and the process is `MugCo`.

The screenshots and recordings in `docs/media` come from a second sample, `docs/demo` (ShotDemo, "Acme Support"), whose ticket, dashboard and chat scenes are scripted so a reshoot lines up with the last one. Use it to reshoot the guide media (see `docs/demo/README.md`), and MugCo for everything else.

## Architecture

Two targets, all macOS-only:
- `Sources/ShotCore` (library): everything that needs no window, display or permission. It imports no AppKit, SwiftUI or Cocoa (`make lint` checks).
- `Sources/Shot` (the app): AppKit and SwiftUI that need a real session, grouped by feature (`Capture`, `Overlay`, `QuickAccess`, `Editor`, `Recording`, `VideoEditor`, `Gallery`, `Settings`, `Design`).

**If logic can be tested without a window, it goes in ShotCore with a test.** The one test target is `Tests/ShotCoreTests`. The app has no tests.

Read the note in `docs/architecture/` before changing the area it covers:

| Before changing | Read |
| --- | --- |
| What belongs in ShotCore, or how it handles images and drawing | [core.md](docs/architecture/core.md) |
| Taking a capture: `CaptureCoordinator`, picking what to capture, saving | [capture.md](docs/architecture/capture.md) |
| Annotations, `AnnotationRenderer` or editor undo | [image-editor.md](docs/architecture/image-editor.md) |
| `Recorder`, pausing or audio | [recording.md](docs/architecture/recording.md) |
| The video timeline, or GIF export | [video-editor.md](docs/architecture/video-editor.md) |
| Preferences and `@Setting` | [settings.md](docs/architecture/settings.md) |
| Shared UI components, lazy lists and grids, or concurrency | [design-system.md](docs/architecture/design-system.md) |
| `site/` and the user guide | [website.md](docs/architecture/website.md) |

## Rules enforced by `make lint`

- Use `NSView(hosting:)`, never `NSHostingView(rootView:)`/`NSHostingController`; a plain hosting view crashes when content changes under a visible window. `GlassWindow.swift`, which defines the helper, is exempt.
- Use `@Setting`, never `@AppStorage`; `@AppStorage` updates late, so views show inconsistent state.
- Use `inkBorder(_:width:color:)` rather than `strokeBorder` with any `Brutal` colour (a ternary included), and only whole-point ink widths and line widths. `BrutalStyle.swift`, which defines `inkBorder`, is exempt.
- Use `style: .circular`, never `.continuous`, for rounded corners; continuous corners leave steps under ink borders.
- ShotCore imports no AppKit, SwiftUI or Cocoa, so its logic is tested without a window.

## CI

The repository is public, so GitHub's runners are free, but the free plan runs only 5 macOS jobs at once, so macOS runs can queue (`.github/workflows/ci.yml`):
- Every PR runs two required checks (`ci.yml`). `linux` runs `scripts/lint.sh`. `macos`, on the `macos-26` image, is skipped, which counts as a pass, when the PR changes only `site/`, `docs/` or top-level Markdown files. It builds the app, checks the strings catalog, compiles for Intel, and runs the tests. The tests run through `scripts/ci-test.sh`, which samples the test process when no test has started or ended for five minutes, and prints crash reports when the run fails, since `swift test` buffers its output and a hang or crash otherwise leaves nothing to go on. `release.yml` builds on the same image.
- The repository has auto-merge turned off: an admin merges the release PR by hand once the gate has passed. If the gate fails, fix it in a normal PR. release-please updates the release PR only for commits that change the changelog, so after a `test:`, `ci:` or `docs:` fix, run `gh pr update-branch <release PR>` to gate it again.
- `release.yml` runs `make test` on the tagged commit before it signs anything, because a `docs:`, `test:` or `ci:` commit merged after the gate passed can change what's released.
- Run `make lint` and `make test` before every push, and push once per PR where you can, so CI is a check rather than a debugger. Every push re-runs CI, and a newer push cancels the run before it.
- Every release builds and tests again, so let the release-please PR collect several merges rather than releasing after each one.

## Conventions

- UI strings go through `Resources/Localizable.xcstrings` (CONTRIBUTING.md › Strings and translations). Pass literals to localizing APIs: SwiftUI views, the Design components and `Toast`, which take `LocalizedStringResource` with a `@_disfavoredOverload` generic `StringProtocol` overload for text that's already localized. Keep that overload generic: a concrete `String` one, even disfavoured, wins over `LocalizedStringResource` when the call has other arguments, and the literal goes unlocalized. Two traps remain: a literal title next to a `String` subtitle or detail picks the verbatim overload (wrap the title in `String(localized:)`), and a ternary passed to an optional `LocalizedStringResource?` parameter extracts only its first branch (use a computed property). Anything else, such as AppKit titles, ShotCore's labels or a `String` property, uses `String(localized:)`. `shot://` output, logs and file names stay English. After adding strings, run `make strings` and commit the catalog; `make lint` and CI fail while it's stale.
- PR titles use Conventional Commits (`feat(editor): …`, `fix(recording): …`). PRs are squash-merged and release-please generates versions and `CHANGELOG.md`, so never edit the version or tags by hand.
- Website changes use the `site:` type, with no scope (`site: remake the guide home`). release-please ignores it, so it makes no changelog entry or app version. `exclude-paths` already skips commits that touch only `site/`, but a PR that also touches app files counts unless it's `site:`. If a change also alters the app's behaviour, split it so the app part has its own `fix:` or `feat:` PR.
- Every PR links an issue or sub-issue: put `Closes #N` (or `Part of #N` when it doesn't finish the issue) in the PR body. Create the issue before starting any work, as a sub-issue when the work belongs to an umbrella issue.
- Any substantial change or new feature must keep docs and marketing in line in the same PR: the user guide in `site/src/guide/`, `README.md`, the landing page `site/src/pages/index.astro`, and the media in `docs/media/` if they now show stale UI. If an update needs new screenshots or recordings you can't make, say so rather than skipping it silently. `CHANGELOG.md` is generated, so don't edit it.
- Only `make dist` builds `Shot.app` with the Sparkle feed. Every other build is `ShotDev.app` (bundle ID `dev.lorcan.Shot.dev`, executable `ShotDev`, scheme `shot-dev://`, no feed), so dev builds never self-update or replace the installed release. `scripts/bundle.sh` does the renaming.
