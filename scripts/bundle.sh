#!/bin/bash
# Builds a release binary and assembles a signed build/Shot.app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

app=build/Shot.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Shot "$app/Contents/MacOS/Shot"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
if [ -n "${SHOT_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${SHOT_VERSION#v}" "$app/Contents/Info.plist"
fi

identity="${SHOT_SIGN_IDENTITY:-Shot Dev}"
if [ "$identity" != "-" ] && ! security find-identity -p codesigning | grep -q "\"$identity\""; then
    echo "warning: signing identity '$identity' not found; signing ad-hoc. Screen Recording permission resets on every build." >&2
    identity="-"
fi
codesign --force --sign "$identity" "$app"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
echo "Built $app $version ($build_number)"
