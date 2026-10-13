# Contributing to Shot

Thanks for helping. Bug reports, ideas, and pull requests are all welcome. For a large change, open an issue first so we can agree on the approach.

## Design principle

The default is the simplest state. Extra tools, panels and controls start off, and the user turns them on if they want them.

## Set up

You need an Apple Silicon Mac with macOS 15 or later, and either Xcode or the Xcode Command Line Tools. Shot is a SwiftPM package whose only dependency is [Sparkle](https://sparkle-project.org), for updates.

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
| `make test` | Run the `ShotModel` and `ShotCore` unit tests |
| `make test-linux` | Run the `ShotModel` tests on Linux in Docker, as CI does |
| `make lint` | Check for code patterns that have caused bugs (`scripts/lint.sh`) and, on a Mac, that the string catalog is up to date |
| `make strings` | Add new strings to `Resources/Localizable.xcstrings` and drop unused ones |
| `make perf` | Time the `ShotCore` paths that have [performance budgets](docs/performance.md) |
| `make perf-app` | Measure launch, capture, memory and idle CPU of the installed app against its budgets |
| `make app` | Build and install without launching (`INSTALL_DIR=~/Applications make app` to install elsewhere) |
| `make bundle` | Build and sign `build/ShotDev.app` only |
| `make dist` | Build `build/Shot.zip`, as the release workflow does |
| `make icon` | Regenerate `Resources/AppIcon.icns` from `scripts/make-icon.swift` |
| `make reset-tcc` | Clear ShotDev's Screen Recording permission |
| `make clean` | Remove build output |

**Command Line Tools only:** the CLT's default SDK (27) makes SwiftUI's `@State` a macro whose compiler plugin ships only with Xcode. When Xcode isn't selected, the Makefile pins the newest 26.x SDK the CLT has and points the tests at the CLT's testing plugin, so use `make` rather than a bare `swift build`. With Xcode, nothing is pinned.

## Project layout

```
Sources/ShotModel/    Pure logic that needs only Foundation, tested on Linux: undo, keyframes,
                      video trim and cuts, hotkeys, layout math
Sources/ShotCore/     Pure logic that needs Apple frameworks: geometry, file naming, image
                      encoding, annotations and rendering, redaction, GIF export, segment
                      joining, preferences
Sources/Shot/         The app: capture, selection overlay, Quick Access, editor,
                      video editor, recording, gallery, settings, the welcome window,
                      the agent server (Agents/), and the design system
Sources/ShotCLI/      The `shot` command and MCP server, bundled as shot-cli
Tests/ShotModelTests/ ShotModel's Swift Testing suite
Tests/ShotCoreTests/  ShotCore's Swift Testing suite
Resources/            Info.plist, the app icon and the string catalogs
scripts/              Bundling, install, signing certificate, icon, lint, performance
                      checks, and the Homebrew cask
docs/                 The user guide, its screenshots, and the demo app they show
site/                 The website (see site/README.md)
```

If logic can be tested without a window, a display, or a permission, put it in `ShotModel` and add a test. If it needs an Apple framework, such as CoreText, AVFoundation or `CGPath`, put it in `ShotCore` instead, keeping the Apple part as thin as you can. CI runs `ShotModel`'s tests on Linux, where minutes cost a fraction of macOS ones. `Shot` holds the AppKit and SwiftUI code that needs a real session.

## Strings and translations

Shot's interface is in English, and every string it shows goes through `Resources/Localizable.xcstrings`, so it can be translated. Each build extracts the strings from `Sources/Shot` and `Sources/ShotCore` (see `Package.swift`), and `make strings` adds the new ones to the catalog. `make lint` and CI fail while the catalog is out of date.

A string reaches the catalog when it's a literal passed to an API that localizes:

- SwiftUI's `Text`, `Button`, `Toggle` and the like, and Shot's own `brutalTip`, `Tile`, `SettingRow`, `BrutalChip`, `Toast` and other design components. A `String` variable passed to one of these is shown as it is, so a string that needs translating has to be localized where it's defined.
- `String(localized: "…")`, for AppKit titles, alerts, panel messages and any `String` property that holds text the user reads.

Interpolate values into one string, such as `"Saved \(name)"`, rather than joining fragments, so a translator can reorder the words. Leave text that agents, the `shot` command or scripts read in English, and the same goes for log messages and file names.

To add a language, open the catalogs in Xcode, add the language, translate each string and add its code to `CFBundleLocalizations` in `Resources/Info.plist`. `Resources/InfoPlist.xcstrings` holds the camera and microphone permission prompts. To try a language without changing your Mac's, run `open -a ShotDev --args -AppleLanguages '(de)'`.

## Debugging

Shot logs to the unified log under its bundle identifier. File paths are redacted unless you've enabled private data logging.

```bash
log stream --predicate 'subsystem == "dev.lorcan.Shot.dev"'   # ShotDev; a release logs under dev.lorcan.Shot
```

The `shot://` [URL scheme](https://shot.lorcanchinnock.com/docs/url-scheme/) drives every action without a keyboard, which helps when you reproduce a bug.

## Sending a change

- Keep each pull request focused on one change, and match the style of the surrounding code.
- Run `make lint` and `make test`, then run the app and try your change. CI only lints and runs the `ShotModel` tests on Linux. It doesn't build the app or run the `ShotCore` tests until the release gate, so run them yourself.
- Use a [Conventional Commits](https://www.conventionalcommits.org) title for the pull request, such as `fix(recording): …` or `feat(editor): …`. Pull requests are squash-merged, so the title becomes the commit on `main`, and release notes are generated from it.

By contributing, you agree that your contributions are licensed under the project's [GPL-3.0 license](LICENSE).

## Releases

Releases are automated with [release-please](https://github.com/googleapis/release-please). Don't create tags or edit the version by hand.

Before a release, run `make app` and then `make perf-app`, which CI can't run because it needs the Screen Recording permission. It exits non-zero if anything is over budget. See [docs/performance.md](docs/performance.md).

1. When `main` gets a `feat:` or `fix:` commit, release-please opens or updates a release pull request. It bumps the version in `Resources/Info.plist` and `.release-please-manifest.json`, and adds the changes to `CHANGELOG.md`. While Shot is in beta, each release only bumps the beta number, for example `0.7.0-beta.35` to `0.7.0-beta.36`, whether it has features or only fixes. Changes under `site/` never trigger one. Other types such as `docs`, `chore`, `ci`, `refactor`, and `build` appear in the history but don't trigger a release.
2. Run `make release-gate`. It runs CI on the release pull request on macOS: it builds the app, checks the strings catalog, and runs every test, the performance budgets included. The pull request can't merge until the gate passes, and if anything merges to `main` afterwards, release-please updates the pull request and the gate has to run again. If the gate fails, fix it in a normal pull request first.
3. Merging the release pull request tags it (`v0.7.0-beta.36`, say) and creates a draft GitHub release. The release workflow then builds `Shot-<tag>.zip`, signs it for Sparkle, attaches it with `appcast.xml`, the update feed, and only then publishes the release, so the latest release always has a feed. Installed copies read the feed from the latest release. Last, the workflow rebuilds the website and updates the Homebrew cask.

To force a particular version, add a `Release-As: X.Y.Z` line to the body of a commit on `main`.

### Release secrets

The release workflow needs five repository secrets. Create them once, and keep a backup of each somewhere safe: if you lose the Sparkle key, installed copies can't verify updates and you have to ship a new key by hand.

| Secret | What it is |
|---|---|
| `SPARKLE_PRIVATE_KEY` | The EdDSA key that signs updates. Its public half is `SUPublicEDKey` in `Resources/Info.plist`. |
| `SHOT_SIGNING_CERT_P12` | A base64 `.p12` of the self-signed `Shot Release` code-signing certificate. Every release signs with it, so macOS keeps the Screen Recording permission across updates. |
| `SHOT_SIGNING_CERT_PASSWORD` | The password for that `.p12`. |
| `HOMEBREW_TAP_DEPLOY_KEY` | The private half of an SSH deploy key with write access to `LorcanChinnock/homebrew-tap` only. The workflow uses it to update `Casks/shot.rb` there; the tap's `main` ruleset lets deploy keys push. |
| `SITE_DEPLOY_HOOK` | The URL of the website's Cloudflare deploy hook, which rebuilds the site so its download button moves to the new release. See [site/README.md](site/README.md). |

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

gh secret set SITE_DEPLOY_HOOK                                 # paste the hook URL from Cloudflare
```
