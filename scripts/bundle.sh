#!/bin/bash
# Builds a release binary and assembles a signed app in build/.
# Only SHOT_RELEASE=1 (make dist) builds Shot.app, with the update feed. Every other build is ShotDev.app, with its own
# name, bundle ID, executable and shot-dev:// scheme and no feed, so it never replaces or answers for an installed release.
set -euo pipefail
cd "$(dirname "$0")/.."

# A release builds exactly the versions in Package.resolved, so a dependency only changes through a reviewed bump.
resolved=()
if [ "${SHOT_RELEASE:-}" = 1 ]; then
    resolved=(--force-resolved-versions)
fi

# Shot runs on Apple Silicon only.
swift build -c release --arch arm64 ${resolved[@]+"${resolved[@]}"}
bin_path="$(swift build -c release --arch arm64 --show-bin-path)"
binary="$bin_path/Shot"

if [ "${SHOT_RELEASE:-}" = 1 ]; then
    name=Shot
else
    name=ShotDev
fi
app="build/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary" "$app/Contents/MacOS/$name"
# The MCP server. Never "shot": on a case-insensitive volume that is the app's own Shot executable.
cp "$bin_path/ShotCLI" "$app/Contents/MacOS/shot-cli"
ditto "$bin_path/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# Sparkle's MIT licence requires its notice in copies of the app. Settings › About opens this file.
cp Resources/Acknowledgements.txt "$app/Contents/Resources/Acknowledgements.txt"
# One .lproj folder per language, where Bundle.main finds the app's strings and the permission prompts' text.
for catalog in Resources/*.xcstrings; do
    xcrun xcstringstool compile "$catalog" --output-directory "$app/Contents/Resources"
done
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
if [ "$name" = ShotDev ]; then
    dev_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist).dev"
    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleIdentifier $dev_id" \
        -c "Set :CFBundleName ShotDev" \
        -c "Set :CFBundleDisplayName ShotDev" \
        -c "Set :CFBundleExecutable ShotDev" \
        -c "Set :CFBundleURLTypes:0:CFBundleURLName $dev_id" \
        -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 shot-dev" \
        -c "Delete :SUFeedURL" \
        "$app/Contents/Info.plist"
fi

identity="${SHOT_SIGN_IDENTITY:-Shot Dev}"
# A release signed ad hoc would reset every user's Screen Recording permission on update, so it fails instead.
if [ "${SHOT_RELEASE:-}" = 1 ] && { [ "$identity" = "-" ] || ! security find-identity -p codesigning | grep -q "\"$identity\""; }; then
    echo "error: signing identity '$identity' not found; a release must not be signed ad hoc." >&2
    exit 1
fi
if [ "$identity" != "-" ] && ! security find-identity -p codesigning | grep -q "\"$identity\""; then
    echo "warning: signing identity '$identity' not found; signing ad-hoc. Screen Recording permission resets on every build." >&2
    identity="-"
fi
# Sign Sparkle's nested helpers inside-out, then the app. Sparkle's docs advise against --deep.
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    codesign --force --sign "$identity" --preserve-metadata=entitlements "$sparkle/$part"
done
codesign --force --sign "$identity" "$app/Contents/Frameworks/Sparkle.framework"
# The outer signature doesn't cover a nested executable, and Sparkle checks nested code on update.
codesign --force --sign "$identity" "$app/Contents/MacOS/shot-cli"
codesign --force --sign "$identity" "$app"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
echo "Built $app $version ($build_number) for $(lipo -archs "$app/Contents/MacOS/$name")"
