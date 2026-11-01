#!/bin/bash
# Removes Shot from this Mac.
#
#   curl -fsSL https://shot.lorcanchinnock.com/uninstall.sh | bash
#   curl -fsSL https://shot.lorcanchinnock.com/uninstall.sh | bash -s -- --everything
#
# By default this quits Shot and moves the app to the Trash, and keeps your settings, permissions and saved versions,
# so installing Shot again picks up where you left off. With --everything it also removes those. Your captures stay in
# your save folder either way.
#
# Environment: SHOT_UNINSTALL_APPS (the folder holding Shot.app) and SHOT_UNINSTALL_HOME (the home folder) exist so
# scripts/test-uninstall.sh can run this against a local folder. With SHOT_UNINSTALL_HOME set, the script touches only
# files under it and leaves the real preferences and permissions alone.
set -euo pipefail

EVERYTHING=0
HOME_DIR="${SHOT_UNINSTALL_HOME:-$HOME}"
TESTING=0
[ -n "${SHOT_UNINSTALL_HOME:-}" ] && TESTING=1
ID="dev.lorcan.Shot"

say() { printf '%s\n' "$*"; }
fail() { printf 'Shot was not removed: %s\n' "$*" >&2; exit 1; }

# Finds Shot.app in the folder from SHOT_UNINSTALL_APPS, or else /Applications and then ~/Applications (where the
# installer puts it when /Applications isn't writable).
find_app() {
    local dir
    for dir in "${SHOT_UNINSTALL_APPS:-/Applications}" "$HOME_DIR/Applications"; do
        if [ -d "$dir/Shot.app" ]; then
            printf '%s\n' "$dir/Shot.app"
            return 0
        fi
    done
    return 1
}

main() {
    for arg in "$@"; do
        case "$arg" in
            --everything) EVERYTHING=1 ;;
            *) fail "unknown option $arg" ;;
        esac
    done
    [ "$(uname -s)" = "Darwin" ] || fail "Shot only runs on a Mac."

    app=""
    app="$(find_app)" || true

    if [ -n "$app" ] && [ "$TESTING" = 0 ] && pgrep -x Shot > /dev/null 2>&1; then
        say "Quitting Shot..."
        osascript -e "tell application id \"$ID\" to quit" > /dev/null 2>&1 || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -x Shot > /dev/null 2>&1 || break
            sleep 0.5
        done
    fi

    if [ "$EVERYTHING" = 1 ]; then
        # macOS can only look up Shot's permissions while the app is still installed, so this comes before the Trash.
        if [ "$TESTING" = 0 ]; then
            tccutil reset All "$ID" > /dev/null 2>&1 || say "Couldn't clear Shot's permissions. Remove Shot in System Settings › Privacy & Security."
            defaults delete "$ID" > /dev/null 2>&1 || true
        fi
        rm -f "$HOME_DIR/Library/Preferences/$ID.plist" "$HOME_DIR/Library/HTTPStorages/$ID.binarycookies"
        rm -rf \
            "$HOME_DIR/Library/Application Support/$ID" \
            "$HOME_DIR/Library/Caches/$ID" \
            "$HOME_DIR/Library/HTTPStorages/$ID"
        # TMPDIR is per user and folder-per-app; skip it in a test, which has no real one.
        [ "$TESTING" = 0 ] && rm -rf "${TMPDIR:-/tmp}/Shot"
        say "Removed Shot's settings, permissions, saved versions and temporary files."
    fi

    if [ -n "$app" ]; then
        trash="$HOME_DIR/.Trash"
        mkdir -p "$trash"
        name="Shot.app"
        [ -e "$trash/$name" ] && name="Shot $(date +%H.%M.%S).app"
        mv "$app" "$trash/$name" || fail "couldn't move $app to the Trash."
        say "Moved Shot to the Trash."
    else
        say "Shot.app isn't in Applications, so there was no app to remove."
    fi

    if [ "$EVERYTHING" = 0 ]; then
        say "Kept your settings, permissions and saved versions. Run again with --everything to remove them too."
    fi
    if [ -e /usr/local/bin/shot ]; then
        say "An older version of Shot left a command at /usr/local/bin/shot. Remove it with: sudo rm /usr/local/bin/shot"
    fi
    say "If Shot was set to open at login, remove it in System Settings › General › Login Items & Extensions."
}

# Everything runs from this one call, so a download cut off halfway can't run a partial script.
main "$@"
