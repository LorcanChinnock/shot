#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
swift build -c release

app=build/Shot.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Shot "$app/Contents/MacOS/Shot"
cp Resources/Info.plist "$app/Contents/Info.plist"

identity="${SHOT_SIGN_IDENTITY:-Shot Dev}"
if ! security find-identity -p codesigning | grep -q "\"$identity\""; then
    echo "warning: signing identity '$identity' not found; signing ad-hoc. Screen Recording permission resets on every build." >&2
    identity="-"
fi
codesign --force --deep --sign "$identity" "$app"

mkdir -p ~/Applications
rm -rf ~/Applications/Shot.app
cp -R "$app" ~/Applications/Shot.app
echo "Installed ~/Applications/Shot.app"
