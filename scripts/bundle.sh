#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
install_dir="${SHOT_INSTALL_DIR:-/Applications}"
swift build -c release

app=build/Shot.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Shot "$app/Contents/MacOS/Shot"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"

identity="${SHOT_SIGN_IDENTITY:-Shot Dev}"
if ! security find-identity -p codesigning | grep -q "\"$identity\""; then
    echo "warning: signing identity '$identity' not found; signing ad-hoc. Screen Recording permission resets on every build." >&2
    identity="-"
fi
codesign --force --deep --sign "$identity" "$app"

# Earlier builds installed to ~/Applications; keep a single copy so Spotlight and TCC see one app.
if [ "$install_dir" != "$HOME/Applications" ] && [ -d "$HOME/Applications/Shot.app" ]; then
    rm -rf "$HOME/Applications/Shot.app"
fi
mkdir -p "$install_dir"
rm -rf "$install_dir/Shot.app"
cp -R "$app" "$install_dir/Shot.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$install_dir/Shot.app"
echo "Installed $install_dir/Shot.app (build $build_number)"
