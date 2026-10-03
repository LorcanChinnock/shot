#!/bin/bash
# Builds a release binary and assembles a signed build/Shot.app.
set -euo pipefail
cd "$(dirname "$0")/.."

# SHOT_ARCHS="arm64 x86_64" builds a universal binary, as releases do; the default is this Mac's.
arch_flags=()
for arch in ${SHOT_ARCHS:-$(uname -m)}; do
    arch_flags+=(--arch "$arch")
done
swift build -c release "${arch_flags[@]}"
binary="$(swift build -c release "${arch_flags[@]}" --show-bin-path)/Shot"

app=build/Shot.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Shot"
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

identity="${SHOT_SIGN_IDENTITY:-Shot Dev}"
if [ "$identity" != "-" ] && ! security find-identity -p codesigning | grep -q "\"$identity\""; then
    echo "warning: signing identity '$identity' not found; signing ad-hoc. Screen Recording permission resets on every build." >&2
    identity="-"
fi
codesign --force --sign "$identity" "$app"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
echo "Built $app $version ($build_number) for $(lipo -archs "$app/Contents/MacOS/Shot")"
