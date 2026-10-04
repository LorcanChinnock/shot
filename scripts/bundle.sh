#!/bin/bash
# Builds a release binary and assembles a signed app in build/.
# SHOT_VARIANT=release builds Shot.app, as releases ship it. The default, dev, builds "Shot Dev.app"
# with its own bundle identifier and no updater, so it keeps its own permissions and settings,
# and Sparkle never replaces it with a release.
set -euo pipefail
cd "$(dirname "$0")/.."

# SHOT_ARCHS="arm64 x86_64" builds a universal binary, as releases do; the default is this Mac's.
arch_flags=()
for arch in ${SHOT_ARCHS:-$(uname -m)}; do
    arch_flags+=(--arch "$arch")
done
swift build -c release "${arch_flags[@]}"
bin_path="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"
binary="$bin_path/Shot"

variant="${SHOT_VARIANT:-dev}"
case "$variant" in
    release) app=build/Shot.app ;;
    dev) app="build/Shot Dev.app" ;;
    *) echo "error: SHOT_VARIANT must be dev or release, not '$variant'." >&2; exit 1 ;;
esac
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary" "$app/Contents/MacOS/Shot"
ditto "$bin_path/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
for arch in ${SHOT_ARCHS:-$(uname -m)}; do
    if ! lipo "$app/Contents/MacOS/Shot" -verify_arch "$arch"; then
        echo "error: the built binary has no $arch slice; run 'make clean' and try again." >&2
        exit 1
    fi
done
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
if [ "$variant" = dev ]; then
    bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist")"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id.dev" \
        -c "Set :CFBundleName Shot Dev" -c "Set :CFBundleDisplayName Shot Dev" \
        -c "Delete :SUFeedURL" "$app/Contents/Info.plist"
fi

identity="${SHOT_SIGN_IDENTITY:-Shot Dev}"
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
codesign --force --sign "$identity" "$app"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
echo "Built $app $version ($build_number) for $(lipo -archs "$app/Contents/MacOS/Shot")"
