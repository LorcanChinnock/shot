# Contributing to Shot

Thanks for helping. Bug reports, ideas, and pull requests are all welcome. For a large change, open an issue first so we can agree on the approach.

## Design principle

The default is the simplest state. Extra tools, panels and controls start off, and the user turns them on if they want them.

## Set up

You need a Mac with macOS 15 or later, and either Xcode or the Xcode Command Line Tools. Shot is a SwiftPM package whose only dependency is [Sparkle](https://sparkle-project.org), for updates.

```bash
git clone https://github.com/LorcanChinnock/shot.git
cd shot
scripts/make-dev-cert.sh   # once: a stable signing identity, so the Screen Recording permission survives rebuilds
make run                   # build, install to /Applications/ShotDev.app, and launch
```

macOS ties the Screen Recording permission to the app's code signature. An ad-hoc signature changes on every build, so the permission would reset each time. `make-dev-cert.sh` creates a self-signed certificate named `Shot Dev` in your login keychain, and the build signs with it. Keychain Access shows it as "not trusted"; that's expected and signing still works. To sign with another identity, set `SHOT_SIGN_IDENTITY`.

On the first run, the welcome window asks for the Screen Recording permission. Once you've turned on ShotDev in System Settings › Privacy & Security › Screen & System Audio Recording, click **Relaunch** in the window so the permission takes effect.

Only `make dist` builds `Shot.app` with the update feed. Every other build is `ShotDev.app`: a separate app with its own bundle ID (`dev.lorcan.Shot.dev`), settings, Screen Recording permission and `shot-dev://` URL scheme, and no update feed. It installs beside a released Shot rather than over it, and Sparkle never replaces it.

### Make targets

| Target | What it does |
|---|---|
| `make run` | Build, install to `/Applications/ShotDev.app`, and launch |
| `make build` | `swift build`, without making an app |
| `make test` | Run the unit tests in `Tests/ShotCoreTests` |
| `make lint` | Check for code patterns that have caused bugs (`scripts/lint.sh`) and that the string catalog is up to date |
| `make strings` | Add new strings to `Resources/Localizable.xcstrings` and drop unused ones |
| `make perf-app` | Measure launch, capture, memory and idle CPU of the installed app against its budgets |
| `make app` | Build and install without launching (`INSTALL_DIR=~/Applications make app` to install elsewhere) |
| `make bundle` | Build and sign `build/ShotDev.app` only |
| `make dist` | Build a universal (Apple Silicon and Intel) `build/Shot.zip`, as the release workflow does |
| `make icon` | Regenerate `Resources/AppIcon.icns` from `scripts/make-icon.swift` |
| `make reset-tcc` | Clear ShotDev's Screen Recording permission |
| `make clean` | Remove build output |

**Command Line Tools only:** the CLT's default SDK (27) makes SwiftUI's `@State` a macro whose compiler plugin ships only with Xcode. When Xcode isn't selected, the Makefile pins the newest 26.x SDK the CLT has and points the tests at the CLT's testing plugin, so use `make` rather than a bare `swift build`. With Xcode, nothing is pinned.

## Project layout

```
Sources/ShotCore/     Everything with no window: undo, keyframes, video trim and cuts,
                      hotkeys, layout math, file naming, image encoding, annotations and
                      rendering, redaction, GIF export, segment joining, preferences,
                      the gallery
Sources/Shot/         The app: capture, selection overlay, Quick Access, editor,
                      video editor, recording, gallery, settings, the welcome window,
                      and the design system
Tests/ShotCoreTests/  ShotCore's Swift Testing suite, and its performance budgets
Resources/            Info.plist, the app icon and the string catalogs
scripts/              Bundling, install, signing certificate, icon, lint, performance
                      checks, and the Homebrew cask
docs/                 Screenshots for the README and the user guide, and the demo app they show
site/                 The website (see site/README.md)
```

If logic can be tested without a window, a display, or a permission, put it in `ShotCore` and add a test in `Tests/ShotCoreTests`. ShotCore uses Apple's frameworks that need no window (Core Graphics, Core Image, Core Text, ImageIO, AVFoundation and Vision) directly, but imports no AppKit or SwiftUI, and `make lint` checks that. `Shot` holds the AppKit and SwiftUI code that needs a real session.

## Strings and translations

Shot's interface is in English, and every string it shows goes through `Resources/Localizable.xcstrings`, so it can be translated. Each build extracts the strings from `Sources/Shot` and `Sources/ShotCore` (see `Package.swift`), and `make strings` adds the new ones to the catalog. `make lint` and CI fail while the catalog is out of date.

A string reaches the catalog when it's a literal passed to an API that localizes:

- SwiftUI's `Text`, `Button`, `Toggle` and the like, and Shot's own `brutalTip`, `Tile`, `SettingRow`, `BrutalChip`, `Toast` and other design components. A `String` variable passed to one of these is shown as it is, so a string that needs translating has to be localized where it's defined.
- `String(localized: "…")`, for AppKit titles, alerts, panel messages, ShotCore's labels and errors, and any `String` property that holds text the user reads.

Interpolate values into one string, such as `"Saved \(name)"`, rather than joining fragments, so a translator can reorder the words. Leave `shot://` output, log messages and file names in English.

To add a language, open the catalogs in Xcode, add the language, translate each string and add its code to `CFBundleLocalizations` in `Resources/Info.plist`. `Resources/InfoPlist.xcstrings` holds the camera and microphone permission prompts. To try a language without changing your Mac's, run `open -a ShotDev --args -AppleLanguages '(de)'`.

## Debugging

Shot logs to the unified log under its bundle identifier. File paths are redacted unless you've enabled private data logging.

```bash
log stream --predicate 'subsystem == "dev.lorcan.Shot.dev"'   # ShotDev; a release logs under dev.lorcan.Shot
```

The `shot://` [URL scheme](https://shot.lorcanchinnock.com/docs/automation-reference/#url-scheme) drives every action without a keyboard, which helps when you reproduce a bug.

## Sending a change

- Keep each pull request focused on one change, and match the style of the surrounding code.
- Run `make lint` and `make test`, then run the app and try your change. CI runs the same checks on macOS, but running them first saves a round trip.
- Use a [Conventional Commits](https://www.conventionalcommits.org) title for the pull request, such as `fix(recording): …` or `feat(editor): …`. Pull requests are squash-merged, so the title becomes the commit on `main`, and release notes are generated from it.
- Use `site: …` for website changes (the Astro site and the user guide in `site/`). release-please ignores that type, so it makes no changelog entry and no new app version. If the same change also alters what the app does, split it, and give the app change its own `fix:` or `feat:` title.

Everyone taking part in the project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

By contributing, you agree that your contributions are licensed under the project's [GPL-3.0 license](LICENSE).

## Releases

Releases are automated with [release-please](https://github.com/googleapis/release-please). Don't create tags or edit the version by hand.

Before a release, run `make app` and then `make perf-app`, which CI can't run because it needs the Screen Recording permission. It exits non-zero if anything is over budget. See [docs/performance.md](docs/performance.md).

1. When `main` gets a `feat:` or `fix:` commit, release-please opens or updates a release pull request. It bumps the version in `Resources/Info.plist` and `.release-please-manifest.json`, and adds the changes to `CHANGELOG.md`. While Shot is in beta, each release only bumps the beta number, for example `0.7.0-beta.35` to `0.7.0-beta.36`, whether it has features or only fixes. Changes under `site/` never trigger one. Other types such as `docs`, `chore`, `ci`, `refactor`, and `build` appear in the history but don't trigger a release.
2. The release pull request's CI is the release gate: it runs the checks every pull request gets. It runs again on every push to the pull request, and the pull request can't merge until it passes.
   - A repository admin merges the release pull request by hand. The repository has auto-merge turned off.
   - If the gate fails, fix it in a normal pull request first. release-please only updates the release pull request for changes that appear in the changelog, so after a `test:`, `ci:` or `docs:` fix, run `gh pr update-branch <number>` on the release pull request to run the gate again.
3. The merge tags the release (`v0.7.0-beta.36`, say) and creates a draft GitHub release. The release workflow runs the tests again on the tagged commit, since a commit merged after the gate passed may have changed it. At the same time it builds `Shot-<tag>.zip` and signs it for Sparkle. Once both finish, it attaches the zip with `appcast.xml`, the update feed, and only then publishes the release, so the latest release always has a feed. Installed copies read the feed from the latest release. Last, the workflow rebuilds the website and updates the Homebrew cask.

To force a particular version, add a `Release-As: X.Y.Z` line to the body of a commit on `main`.

### Release secrets

The release workflow needs four secrets, which belong in a GitHub Environment named `release` so no other workflow or branch can read them. Create them once, and keep a backup of each somewhere safe: if you lose the Sparkle key, installed copies can't verify updates and you have to ship a new key by hand.

| Secret | What it is |
|---|---|
| `SPARKLE_PRIVATE_KEY` | The EdDSA key that signs updates. Its public half is `SUPublicEDKey` in `Resources/Info.plist`. |
| `SHOT_SIGNING_CERT_P12` | A base64 `.p12` of the self-signed `Shot Release` code-signing certificate. Every release signs with it, so macOS keeps the Screen Recording permission across updates. |
| `SHOT_SIGNING_CERT_PASSWORD` | The password for that `.p12`. |
| `HOMEBREW_TAP_DEPLOY_KEY` | The private half of an SSH deploy key with write access to `LorcanChinnock/homebrew-tap` only. The workflow uses it to update `Casks/shot.rb` there; the tap's `main` ruleset lets deploy keys push. |

Set the environment up once under Settings › Environments › `release`: limit deployment branches and tags to `main` and `v*`, and store the four secrets there instead of at repository level (`gh secret set --env release NAME`). Add a ruleset for `v*` tags that blocks deletion, updates and non-fast-forward pushes. The release build fails if the `Shot Release` signing identity is missing, rather than signing ad hoc.

release-please opens the release pull request as a GitHub App rather than with the workflow's own token, because GitHub holds the workflows on a pull request from `github-actions[bot]` until someone approves them. Create a private GitHub App once (Settings › Developer settings › GitHub Apps) with no webhook and these repository permissions: Contents, Pull requests and Issues set to read and write. Install it on this repository only. Then store its client ID as a repository variable and a private key as a repository secret. The release-please job runs on every push to `main`, outside the `release` environment, so these two can't live there:

```bash
gh variable set RELEASE_APP_CLIENT_ID                          # paste the app's client ID
gh secret set RELEASE_APP_PRIVATE_KEY < shot-release.private-key.pem
```

Each release also attaches `SHA256SUMS` and a build provenance attestation. To check a direct download, run `shasum -a 256 -c SHA256SUMS` and `gh attestation verify Shot-vX.Y.Z.zip -R LorcanChinnock/shot`.

```bash
make build                                                     # fetches Sparkle's tools
.build/artifacts/sparkle/Sparkle/bin/generate_keys             # prints the public key for SUPublicEDKey
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle.key
gh secret set SPARKLE_PRIVATE_KEY < sparkle.key

scripts/make-dev-cert.sh "Shot Release" release.p12            # prints the .p12 password
base64 -i release.p12 | gh secret set SHOT_SIGNING_CERT_P12
gh secret set SHOT_SIGNING_CERT_PASSWORD                       # paste the password

rm sparkle.key release.p12                                     # both stay in your login keychain

ssh-keygen -t ed25519 -N "" -C "shot release workflow" -f tap_key
gh repo deploy-key add tap_key.pub -R LorcanChinnock/homebrew-tap --allow-write --title "shot release workflow"
gh secret set HOMEBREW_TAP_DEPLOY_KEY < tap_key
rm tap_key tap_key.pub                                         # make a new key if you lose it

```
