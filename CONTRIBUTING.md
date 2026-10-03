# Contributing to Shot

Thanks for helping. Bug reports, ideas, and pull requests are all welcome. For a large change, open an issue first so we can agree on the approach.

## Set up

You need macOS 15 or later and either Xcode or the Xcode Command Line Tools. Shot is a SwiftPM package with no dependencies.

```bash
scripts/make-dev-cert.sh   # once
make run
```

macOS ties the Screen Recording permission to the app's code signature. An ad-hoc signature changes on every build, so the permission would reset each time. `make-dev-cert.sh` creates a self-signed certificate named `Shot Dev` in your login keychain, and the build signs with it. Keychain Access shows it as "not trusted"; that's expected and signing still works. To sign with another identity, set `SHOT_SIGN_IDENTITY`.

On the first run, turn on Shot in System Settings › Privacy & Security › Screen & System Audio Recording, then relaunch it.

### Make targets

| Target | What it does |
|---|---|
| `make run` | Build, install to `/Applications/Shot.app`, and launch |
| `make test` | Run the `ShotCore` unit tests |
| `make app` | Build and install without launching (`INSTALL_DIR=~/Applications make app` to install elsewhere) |
| `make bundle` | Build and sign `build/Shot.app` only |
| `make dist` | Build a universal (Apple Silicon and Intel) `build/Shot.zip`, as the release workflow does |
| `make icon` | Regenerate `Resources/AppIcon.icns` from `scripts/make-icon.swift` |
| `make reset-tcc` | Clear Shot's Screen Recording permission |
| `make clean` | Remove build output |

**Command Line Tools only:** the CLT's default SDK (27) makes SwiftUI's `@State` a macro whose compiler plugin ships only with Xcode. The Makefile pins the CLT's 26.5 SDK when Xcode isn't selected. With Xcode, nothing is pinned.

## Project layout

```
Sources/ShotCore/    Pure logic with unit tests: geometry, file naming, image encoding,
                     annotations and rendering, OCR, GIF export, segment joining,
                     hotkeys, preferences
Sources/Shot/        The app: capture, selection overlay, Quick Access, editor,
                     recording, settings, and the design system
Tests/ShotCoreTests/ Swift Testing suite
scripts/             Bundling, install, signing certificate, icon generation
```

If logic can be tested without a window, a display, or a permission, put it in `ShotCore` and add a test. `Shot` holds the AppKit and SwiftUI code that needs a real session.

## Debugging

Shot logs to the unified log under its bundle identifier. File paths are redacted unless you've enabled private data logging.

```bash
log stream --predicate 'subsystem == "dev.lorcan.Shot"'
```

The `shot://` URL scheme (see the README) drives every action without a keyboard, which helps when you reproduce a bug.

## Sending a change

- Keep each pull request focused on one change, and match the style of the surrounding code.
- Run `make test`, then run the app and try your change. CI runs the tests and a release build on every pull request.
- Write commit messages in the [Conventional Commits](https://www.conventionalcommits.org) style the history uses, such as `fix(recording): …` or `feat(editor): …`.

By contributing, you agree that your contributions are licensed under the project's [GPL-3.0 license](LICENSE).

## Releases

Push a `vX.Y.Z` tag. The release workflow tests the code, builds `Shot-vX.Y.Z.zip` with that version, and publishes a GitHub release with generated notes.
