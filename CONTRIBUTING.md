# Contributing to Shot

Thanks for helping. Bug reports, ideas, and pull requests are all welcome. For a large change, open an issue first so we can agree on the approach.

## Set up

You need macOS 15 or later and either Xcode or the Xcode Command Line Tools. Shot is a SwiftPM package whose only dependency is [Sparkle](https://sparkle-project.org), for updates.

```bash
scripts/make-dev-cert.sh   # once
make run
```

macOS ties the Screen Recording permission to the app's code signature. An ad-hoc signature changes on every build, so the permission would reset each time. `make-dev-cert.sh` creates a self-signed certificate named `Shot Dev` in your login keychain, and the build signs with it. Keychain Access shows it as "not trusted"; that's expected and signing still works. To sign with another identity, set `SHOT_SIGN_IDENTITY`.

On the first run, turn on Shot in System Settings › Privacy & Security › Screen & System Audio Recording, then relaunch it.

Only `make dist` keeps the update feed in `Info.plist`. Every other build leaves it out, so the updater stays off and Sparkle never replaces your build with a release.

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
                     annotations and rendering, GIF export, segment joining, video trim and cuts,
                     hotkeys, preferences
Sources/Shot/        The app: capture, selection overlay, Quick Access, editor,
                     video editor, recording, settings, and the design system
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
- Run `make test`, then run the app and try your change. CI runs the tests and a universal release build on every pull request, and repeats the tests on an Intel Mac after merge.
- Use a [Conventional Commits](https://www.conventionalcommits.org) title for the pull request, such as `fix(recording): …` or `feat(editor): …`. Pull requests are squash-merged, so the title becomes the commit on `main`, and release notes are generated from it.

By contributing, you agree that your contributions are licensed under the project's [GPL-3.0 license](LICENSE).

## Releases

Releases are automated with [release-please](https://github.com/googleapis/release-please). Don't create tags or edit the version by hand.

1. When `main` gets a `feat:` or `fix:` commit, release-please opens or updates a release pull request. It bumps the version in `Resources/Info.plist` and `.release-please-manifest.json`, and adds the changes to `CHANGELOG.md`. Before 1.0, `feat` bumps the minor version and `fix` bumps the patch. Other types such as `docs`, `chore`, `ci`, `refactor`, and `build` appear in the history but don't trigger a release.
2. Merging the release pull request tags `vX.Y.Z` and publishes a GitHub release. The release workflow then builds the universal `Shot-vX.Y.Z.zip`, signs it for Sparkle, and attaches it with `appcast.xml`, the update feed. Installed copies read the feed from the latest release.

To force a particular version, add a `Release-As: X.Y.Z` line to the body of a commit on `main`.

### Release secrets

The release workflow needs three repository secrets. Create them once, and keep a backup of each somewhere safe: if you lose the Sparkle key, installed copies can't verify updates and you have to ship a new key by hand.

| Secret | What it is |
|---|---|
| `SPARKLE_PRIVATE_KEY` | The EdDSA key that signs updates. Its public half is `SUPublicEDKey` in `Resources/Info.plist`. |
| `SHOT_SIGNING_CERT_P12` | A base64 `.p12` of the self-signed `Shot Release` code-signing certificate. Every release signs with it, so macOS keeps the Screen Recording permission across updates. |
| `SHOT_SIGNING_CERT_PASSWORD` | The password for that `.p12`. |

```bash
make build                                                     # fetches Sparkle's tools
.build/artifacts/sparkle/Sparkle/bin/generate_keys             # prints the public key for SUPublicEDKey
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle.key
gh secret set SPARKLE_PRIVATE_KEY < sparkle.key

scripts/make-dev-cert.sh "Shot Release" release.p12            # prints the .p12 password
base64 -i release.p12 | gh secret set SHOT_SIGNING_CERT_P12
gh secret set SHOT_SIGNING_CERT_PASSWORD                       # paste the password

rm sparkle.key release.p12                                     # both stay in your login keychain
```
