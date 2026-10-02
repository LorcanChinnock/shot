<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Shot app icon">
</p>

# Shot

A macOS screenshot and screen-recording app. It runs from the menu bar.

## Features

- **Screenshots:** area (frozen screen with magnifier), fullscreen, window (with shadow), and text (OCR to clipboard).
- **Quick Access:** a floating card after each capture. Copy, Save As, Annotate, Show in Finder, or drag it into another app.
- **Annotation editor:** arrow, line, rectangle, ellipse, text, highlight, pixelate, numbered counter, and crop, with undo.
- **Screen recording:** area, screen, or window to MP4. Shot shows a setup step with an adjustable frame, then a 3-second countdown. While recording, controls let you pause, stop, discard, and toggle the camera.
- **Camera bubble:** a round webcam overlay recorded with the screen.
- **GIF export** from a recording's Quick Access card.
- **Settings** for files, formats, capture behavior, Quick Access, recording, audio, camera, and shortcuts.

## Requirements

- macOS 15 or later on Apple Silicon.
- Xcode Command Line Tools. Xcode itself is not required.

The Makefile builds against the Command Line Tools' macOS 26.5 SDK. In the default SDK (27), SwiftUI's `@State` is a macro whose plugin ships only with Xcode. If a Command Line Tools update removes the 26.5 SDK, install Xcode and remove the `SDKROOT` line from the Makefile.

## Build and install

```bash
make run        # build, sign, install to /Applications/Shot.app, and launch
make test       # unit tests (ShotCore)
make app        # build, sign, and install without launching
make icon       # regenerate Resources/AppIcon.icns
make reset-tcc  # clear Shot's Screen Recording permission
```

To install somewhere else, run `INSTALL_DIR=~/Applications make app`.

### Signing certificate

macOS ties Screen Recording permission to the app's signature. Ad-hoc signatures change on every build, so the permission resets each time. Sign with a stable self-signed certificate named `Shot Dev` instead:

```bash
cat > /tmp/shot-cert.cnf <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Shot Dev
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
cd /tmp
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config shot-cert.cnf
PASS=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -name "Shot Dev" -out shot.p12 -passout pass:$PASS
security import shot.p12 -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign
rm key.pem cert.pem shot.p12 shot-cert.cnf
```

The certificate shows as "not trusted". Code signing and the permission work anyway. To use a different identity, set `SHOT_SIGN_IDENTITY`. Without any identity, the build signs ad-hoc and prints a warning.

### First run

1. Run `make run`.
2. Turn on **Shot** in System Settings › Privacy & Security › Screen & System Audio Recording.
3. Relaunch Shot. macOS applies a new grant only after a relaunch.

macOS asks for Microphone and Camera access the first time you record with them.

## Shortcuts

Recording uses the same keys as screenshots, plus Option.

| | Screenshot | Record |
|---|---|---|
| Area | ⌃⇧4 | ⌃⌥⇧4 |
| Fullscreen | ⌃⇧3 | ⌃⌥⇧3 |
| Window | ⌃⇧W | ⌃⌥⇧W |
| Text (OCR) | ⌃⇧2 | – |

Any record shortcut also confirms the recording setup, and stops a recording that is running. To change shortcuts, open Settings › Shortcuts. macOS keeps ⌘⇧3, ⌘⇧4, and ⌘⇧5 for its own screenshot tool.

## URL scheme

Launchers, the Shortcuts app, or scripts can drive Shot with `open "shot://…"`:

| URL | Action |
|---|---|
| `shot://capture-area`, `capture-fullscreen`, `capture-window`, `capture-text` | Take a screenshot |
| `shot://record`, `record-fullscreen`, `record-window` | Set up, confirm, or stop a recording |
| `shot://pause` | Pause or resume the recording |
| `shot://annotate?path=<file>` | Open an image in the editor |
| `shot://settings?section=<name>` | Open Settings: `general`, `capture`, `quickAccess`, `recording`, `shortcuts`, or `about` |

## Project layout

```
Sources/ShotCore/   Pure logic, unit-tested: geometry, file naming, encoding, annotations,
                    rendering, OCR, GIF export, segment joining, hotkeys, preferences
Sources/Shot/       The app: capture, overlay, Quick Access, editor, recording, settings, design system
Tests/ShotCoreTests Swift Testing suite
scripts/            bundle.sh (assemble, sign, install), make-icon.swift
docs/HANDOVER.md    The original v1 build plan, kept as history
```

The app uses SwiftPM, has no dependencies, and is not sandboxed. Logs use the `dev.lorcan.Shot` subsystem:

```bash
log show --last 5m --predicate 'subsystem == "dev.lorcan.Shot"'
```
