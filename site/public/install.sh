#!/bin/bash
# Installs the latest Shot into /Applications.
#
#   curl -fsSL https://shot.lorcanchinnock.com/install.sh | bash
#
# Shot isn't notarized by Apple. A zip saved by a browser is quarantined, so macOS asks you to approve it in System
# Settings. curl doesn't quarantine what it downloads, so installing this way opens without that step. The zip is
# checked against the SHA256SUMS published with the release before anything is copied.
#
# Options: --no-open (don't launch Shot afterwards).
# Environment: SHOT_INSTALL_BASE (where SHA256SUMS and the zip are fetched from) and SHOT_INSTALL_DEST (the folder to
# install into) exist so scripts/test-install.sh can run this against a local folder.
set -euo pipefail

BASE="${SHOT_INSTALL_BASE:-https://github.com/LorcanChinnock/shot/releases/latest/download}"
DEST="${SHOT_INSTALL_DEST:-/Applications}"
OPEN=1

say() { printf '%s\n' "$*"; }
fail() { printf 'Shot was not installed: %s\n' "$*" >&2; exit 1; }

main() {
    for arg in "$@"; do
        case "$arg" in
            --no-open) OPEN=0 ;;
            *) fail "unknown option $arg" ;;
        esac
    done

    [ "$(uname -s)" = "Darwin" ] || fail "Shot only runs on a Mac."
    [ "$(sw_vers -productVersion | cut -d . -f 1)" -ge 15 ] || fail "Shot needs macOS 15 (Sequoia) or later."

    # Without write access to the folder, use the user's own Applications folder rather than asking for sudo.
    if [ ! -w "$DEST" ]; then
        DEST="$HOME/Applications"
        mkdir -p "$DEST"
        say "/Applications isn't writable by your account, so Shot is going into $DEST."
    fi

    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT

    say "Finding the latest Shot..."
    curl -fsSL "$BASE/SHA256SUMS" -o "$work/SHA256SUMS" || fail "couldn't reach GitHub. Check your connection and try again."
    zip="$(awk '$2 ~ /^Shot-v.*\.zip$/ { print $2; exit }' "$work/SHA256SUMS")"
    [ -n "$zip" ] || fail "the release's checksum list doesn't name a Shot download."

    say "Downloading $zip..."
    curl -fL --progress-bar "$BASE/$zip" -o "$work/$zip" || fail "the download failed. Try again in a minute."

    say "Checking the download..."
    (cd "$work" && grep -F " $zip" SHA256SUMS | shasum -a 256 -c - > /dev/null 2>&1) \
        || fail "the download doesn't match its checksum, so it was thrown away. Try again, and report it at https://github.com/LorcanChinnock/shot/issues if it keeps happening."

    ditto -x -k "$work/$zip" "$work/unpacked"
    [ -d "$work/unpacked/Shot.app" ] || fail "the download didn't contain Shot.app."

    target="$DEST/Shot.app"
    # -f matches the full path, so a ShotDev build or a copy elsewhere is left running.
    if pgrep -f "$target/Contents/MacOS/" > /dev/null 2>&1; then
        say "Quitting the running Shot..."
        osascript -e 'tell application id "dev.lorcan.Shot" to quit' > /dev/null 2>&1 || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -f "$target/Contents/MacOS/" > /dev/null 2>&1 || break
            sleep 0.5
        done
    fi

    # Swap rather than merge, so no file from the old version stays inside the new app and breaks its signature.
    # macOS keeps Shot's permissions because they follow the signing certificate, not the folder.
    if [ -e "$target" ]; then
        mv "$target" "$work/previous.app"
    fi
    if ! ditto "$work/unpacked/Shot.app" "$target"; then
        rm -rf "$target"
        [ -e "$work/previous.app" ] && mv "$work/previous.app" "$target"
        fail "couldn't copy Shot into $DEST. Your previous copy, if you had one, is still there."
    fi
    # Normally nothing to remove, since curl doesn't set it; this covers a zip that was saved by a browser.
    xattr -dr com.apple.quarantine "$target" 2> /dev/null || true

    say "Installed Shot in $DEST."
    if [ "$OPEN" = 1 ]; then
        open "$target"
        say "Shot is open in your menu bar."
    fi
}

# Everything runs from this one call, so a download cut off halfway can't run a partial script.
main "$@"
