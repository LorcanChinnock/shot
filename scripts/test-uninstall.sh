#!/bin/bash
# Runs site/public/uninstall.sh against a fake home folder, and checks that the default keeps Shot's data, that
# --everything removes it, and that neither touches the user's captures or another app's files.
set -euo pipefail
cd "$(dirname "$0")/.."

script="$PWD/site/public/uninstall.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if command -v shellcheck > /dev/null; then
    shellcheck "$script"
else
    echo "shellcheck isn't installed; skipping it."
fi

home="$work/home"
apps="$work/Applications"
id="dev.lorcan.Shot"

# Builds a fake install: the app, Shot's data, a capture, and files that belong to other apps.
setup() {
    rm -rf "$home" "$apps"
    mkdir -p "$apps/Shot.app/Contents" \
        "$home/Library/Preferences" "$home/Library/Caches/$id" "$home/Library/Application Support/$id" \
        "$home/Library/HTTPStorages/$id" "$home/Library/Application Support/dev.lorcan.Shot.dev" "$home/Pictures"
    touch "$home/Library/Preferences/$id.plist" "$home/Library/Preferences/dev.lorcan.Shot.dev.plist" "$home/Pictures/capture.png"
}
run() { SHOT_UNINSTALL_APPS="$apps" SHOT_UNINSTALL_HOME="$home" "$script" "$@"; }

# 1. The default moves the app to the Trash and keeps everything else.
setup
run > /dev/null
[ ! -e "$apps/Shot.app" ] || { echo "FAIL: Shot.app is still in Applications"; exit 1; }
[ -d "$home/.Trash/Shot.app" ] || { echo "FAIL: Shot.app isn't in the Trash"; exit 1; }
[ -f "$home/Library/Preferences/$id.plist" ] || { echo "FAIL: the default removed the preferences"; exit 1; }
[ -d "$home/Library/Application Support/$id" ] || { echo "FAIL: the default removed Application Support"; exit 1; }

# 2. --everything also removes Shot's data, and leaves captures and the dev build's files alone.
setup
run --everything > /dev/null
[ ! -e "$home/Library/Preferences/$id.plist" ] || { echo "FAIL: preferences survived"; exit 1; }
[ ! -e "$home/Library/Application Support/$id" ] || { echo "FAIL: Application Support survived"; exit 1; }
[ ! -e "$home/Library/Caches/$id" ] || { echo "FAIL: caches survived"; exit 1; }
[ ! -e "$home/Library/HTTPStorages/$id" ] || { echo "FAIL: HTTP storage survived"; exit 1; }
[ -f "$home/Pictures/capture.png" ] || { echo "FAIL: a capture was deleted"; exit 1; }
[ -f "$home/Library/Preferences/dev.lorcan.Shot.dev.plist" ] || { echo "FAIL: the dev build's preferences were deleted"; exit 1; }
[ -d "$home/Library/Application Support/dev.lorcan.Shot.dev" ] || { echo "FAIL: the dev build's data was deleted"; exit 1; }

# 3. A second run when Shot is already gone succeeds and says so.
run > "$work/out.txt"
grep -q "no app to remove" "$work/out.txt" || { echo "FAIL: no message when Shot is already gone"; cat "$work/out.txt"; exit 1; }

# 4. An unknown option is refused.
if run --nonsense > /dev/null 2>&1; then echo "FAIL: an unknown option was accepted"; exit 1; fi

echo "uninstall.sh: all checks passed"
