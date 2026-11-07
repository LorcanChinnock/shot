# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Shot is a macOS 15+ menu bar app for screenshots, annotation, screen recording and GIF export. It's an Xcode project, `Shot.xcodeproj` (Swift 6 language mode, strict concurrency), whose only dependency is the Sparkle package.

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
make perf-app                     # make bundle, then scripts/perf.sh: launch, capture, memory, idle CPU of build/ShotDev.app
make lint                         # scripts/lint.sh: bans patterns that caused bugs (see below); on macOS also scripts/strings.sh --check
make strings                      # sync Resources/Localizable.xcstrings with the strings the build extracted
make build                        # Debug build of the app, as Xcode's Build does
make bundle                       # archive a universal Release build/ShotDev.app only
make run                          # without Xcode: Debug build, quit other copies, launch (APP_ARGS=… for the app)
make stop                         # quit ShotDev and reopen the installed Shot if a run quit it
scripts/shotdev-open.sh 'shot-dev://gallery'   # send a link to the one running ShotDev
make demo                         # build and open the MugCo sample app (Samples/MugCo): fake data, fixed size, for QA runs and screenshots
cd site && npm run dev            # the marketing site (see site/README.md)
make test ONLY='ShotCoreTests/hitTestFilledKinds()'   # one test or suite
```

- In Xcode, open `Shot.xcodeproj`: the **Shot** scheme runs and debugs ShotDev (⌘R, which first quits every other ShotDev and the installed Shot) and runs the test plan `Tests/Shot.xctestplan` (⌘U). `make` builds the same project through `scripts/xcodebuild.sh` into `build/DerivedData`, never Xcode's own folder, since Xcode 27 can leave a test bundle unsigned when both build into one.
- Build settings live in `Config/*.xcconfig`, never in the project file: `Shared.xcconfig` (version, signing, Swift), `Debug`/`Release`, and one per target. `Config/Local.xcconfig`, which git ignores, takes personal overrides. Folders are synchronised, so a new Swift file in `Sources/` or `Tests/` needs no project edit.
- Signing uses the `Shot Dev` certificate from `scripts/make-dev-cert.sh` so the Screen Recording permission survives rebuilds. `make reset-tcc` clears it.
- Logs: `log stream --predicate 'subsystem == "dev.lorcan.Shot.dev"'` for ShotDev, `dev.lorcan.Shot` for a release. Use `Logger.shot("category")` from `Sources/ShotCore/ShotLog.swift`.
- The `shot://` URL scheme drives every action without a keyboard (`shot://annotate?path=`, `shot://edit-video?path=`, `shot://gallery`, `shot://settings?section=`; full list on the URL scheme page, `site/src/guide/10-automation-reference.md`). ShotDev registers `shot-dev://` instead, so it never collides with an installed release.

## Running and testing locally

Run ShotDev through Xcode, with the `run-shotdev` skill (`.claude/skills/run-shotdev/SKILL.md`): it uses the Xcode tools to build, run, read the console, debug and stop. The real installed version is `/Applications/Shot.app`, usually from the curl installer on the website. Never install over, rename or delete `Shot.app`; it is the copy the user relies on.

- **Only one ShotDev runs at a time.** The Shot scheme's Run pre-action, `make run` and `scripts/perf.sh` all call `scripts/dev.sh prepare`, which quits every other ShotDev (another worktree's, an earlier run, one Xcode is debugging) and the installed Shot, whose global shortcuts would otherwise catch hotkeys, and notes that the release was running. Never start ShotDev any other way, such as `open` on a built app.
- **Send links with `scripts/shotdev-open.sh 'shot-dev://pick-color'`,** never a plain `open 'shot-dev://…'`. LaunchServices answers a plain `open` with any ShotDev it has seen, such as a stale build in another checkout's DerivedData, and starts it if it isn't running. The script sends the link to the running copy and stops when none or several are running.
- **Always stop it when finished:** `StopProject`, then `scripts/dev.sh stop` (or `make stop`), which quits anything left and reopens the installed Shot if a run quit it. `scripts/dev.sh status` shows what's running.
- Languages are launch arguments in the scheme, off by default; the Xcode tools can't pass arguments, so use `make run APP_ARGS="-AppleLanguages '(de)'"` for them, then `make stop`.
- Leave ShotDev's settings (`dev.lorcan.Shot.dev`) and its Screen Recording permission in place, so the next run doesn't ask for the permission again.

## Capturing something in QA and screenshots

Use the MugCo sample app (`make demo`), not whatever window is open: your screen can show private tabs and mail, and changes every run. It is a fake support inbox in its own package, `Samples/MugCo`, so the main build and CI never compile it. It has an email address and card number to blur, and a wrong balance to point an arrow at. All its data is made up, so captures of it are safe to publish. Its window is titled "Mug Co. Support" and the process is `MugCo`.

The screenshots and recordings in `docs/media` come from a second sample, `docs/demo` (ShotDemo, "Acme Support"), whose ticket, dashboard and chat scenes are scripted so a reshoot lines up with the last one. Use it to reshoot the guide media (see `docs/demo/README.md`), and MugCo for everything else.

## Architecture

Four targets in `Shot.xcodeproj`, all macOS-only:
- `ShotCore` (`Sources/ShotCore`, a static framework): everything that needs no window, display or permission. It imports no AppKit, SwiftUI or Cocoa (`make lint` checks).
- `Shot` (`Sources/Shot` and `Resources`, the app): AppKit and SwiftUI that need a real session, grouped by feature (`Capture`, `Overlay`, `QuickAccess`, `Editor`, `Recording`, `VideoEditor`, `Gallery`, `Settings`, `Design`).
- `ShotCoreTests` (`Tests/ShotCoreTests`) and `ScrollLab` (`Sources/ScrollLab`, the tool behind `scripts/scroll-lab`).

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
- Every PR runs two required checks (`ci.yml`). `linux` runs `scripts/lint.sh`. `macos` waits on two jobs that run side by side on `macos-26` runners, and fails if either fails. When the PR changes only `site/`, `docs/` or top-level Markdown files, both are skipped, which counts as a pass.
  - `test` checks the code. It does a debug build, checks the strings catalog, runs the ShotCore tests, and runs `make test-install test-uninstall`. It never launches the app.
  - `smoke` checks that the app starts. It builds the universal release app as `make dist` does, so the Intel slice must compile. Then `scripts/smoke.sh` launches it and fails if it exits within 8 seconds or leaves a crash report, which catches a bad entitlement, a missing resource or a Sparkle misconfiguration that no unit test sees.
  - The tests run through `scripts/ci-test.sh`, which samples the test process when no test has started or ended for five minutes, prints crash reports when the run fails, and keeps the `.xcresult` as an artifact to open in Xcode. `release.yml` builds on the same image.
- The repository has auto-merge turned on only for `dependabot-automerge.yml`, which enables it on Dependabot's patch and minor PRs (not major bumps or Sparkle) so they merge once `linux` and `macos` pass. An admin merges the release PR by hand once the gate has passed. If the gate fails, fix it in a normal PR. release-please updates the release PR only for commits that change the changelog, so after a `test:`, `ci:` or `docs:` fix, run `gh pr update-branch <release PR>` to gate it again.
- `release.yml` runs `make test` on the tagged commit before it signs anything, because a `docs:`, `test:` or `ci:` commit merged after the gate passed can change what's released.
- Run `make lint` and `make test` before every push, and push once per PR where you can, so CI is a check rather than a debugger. Every push re-runs CI, and a newer push cancels the run before it.
- The redesign is built on a long-lived `redesign` branch with the same required checks. `redesign-sync.yml` opens a `chore: merge main into redesign` PR every Monday and after each release; merge it with a merge commit, never squash. When main conflicts it fails instead, and the merge is resolved by hand on the redesign side (CONTRIBUTING.md › The redesign branch). PRs into `redesign` still use `Closes #N`; `redesign-close-issues.yml` closes those issues on merge, since GitHub only does it for `main`. Only the epic, #1050, stays open until `redesign` merges into `main`.
- Every release builds and tests again, so let the release-please PR collect several merges rather than releasing after each one.

## Conventions

- UI strings go through `Resources/Localizable.xcstrings` (CONTRIBUTING.md › Strings and translations). Pass literals to localizing APIs: SwiftUI views, the Design components and `Toast`, which take `LocalizedStringResource` with a `@_disfavoredOverload` generic `StringProtocol` overload for text that's already localized. Keep that overload generic: a concrete `String` one, even disfavoured, wins over `LocalizedStringResource` when the call has other arguments, and the literal goes unlocalized. Two traps remain: a literal title next to a `String` subtitle or detail picks the verbatim overload (wrap the title in `String(localized:)`), and a ternary passed to an optional `LocalizedStringResource?` parameter extracts only its first branch (use a computed property). Anything else, such as AppKit titles, ShotCore's labels or a `String` property, uses `String(localized:)`. `shot://` output, logs and file names stay English. After adding strings, run `make strings` and commit the catalog; `make lint` and CI fail while it's stale.
- PR titles use Conventional Commits (`feat(editor): …`, `fix(recording): …`). PRs are squash-merged and release-please generates versions and `CHANGELOG.md`, so never edit the version or tags by hand.
- Website changes use the `site:` type, with no scope (`site: remake the guide home`). release-please ignores it, so it makes no changelog entry or app version. `exclude-paths` already skips commits that touch only `site/`, but a PR that also touches app files counts unless it's `site:`. If a change also alters the app's behaviour, split it so the app part has its own `fix:` or `feat:` PR.
- Every PR links an issue or sub-issue: put `Closes #N` (or `Part of #N` when it doesn't finish the issue) in the PR body. Create the issue before starting any work, as a sub-issue when the work belongs to an umbrella issue.
- Any substantial change or new feature must keep docs and marketing in line in the same PR: the user guide in `site/src/guide/`, `README.md`, the landing page `site/src/pages/index.astro`, and the media in `docs/media/` if they now show stale UI. If an update needs new screenshots or recordings you can't make, say so rather than skipping it silently. `CHANGELOG.md` is generated, so don't edit it.
- Only `make dist` builds `Shot.app` with the Sparkle feed. Every other build, Xcode's included, is `ShotDev.app` (bundle ID `dev.lorcan.Shot.dev`, executable `ShotDev`, scheme `shot-dev://`, no feed), so dev builds never self-update or replace the installed release. `Config/Shot.xcconfig` switches them on `SHOT_DISTRIBUTION`, which only `make dist` sets.
