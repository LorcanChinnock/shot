#!/bin/bash
# Archives a universal (Apple Silicon and Intel) Release app, as Product › Archive does, and copies it to build/. The
# archive, with the dSYMs that symbolicate a crash report, stays in build/<name>.xcarchive.
# Only SHOT_RELEASE=1 (make dist) builds Shot.app, with the update feed. Every other build is ShotDev.app, with its own
# name, bundle ID, executable and shot-dev:// scheme and no feed, so it never replaces or answers for an installed
# release (Config/Shot.xcconfig).
set -euo pipefail
cd "$(dirname "$0")/.."

args=(-scheme Shot -configuration Release -destination generic/platform=macOS ARCHS="arm64 x86_64")
name=ShotDev
if [ "${SHOT_RELEASE:-}" = 1 ]; then
    name=Shot
    # A release builds exactly the versions in Package.resolved, so a dependency only changes through a reviewed bump.
    args+=(-onlyUsePackageVersionsFromResolvedFile SHOT_DISTRIBUTION=YES)
    # A release signed ad hoc would reset every user's Screen Recording permission on update, so it fails instead.
    identity="${SHOT_SIGN_IDENTITY:-}"
    if [ -z "$identity" ] || [ "$identity" = "-" ] || ! security find-identity -p codesigning | grep -q "\"$identity\""; then
        echo "error: set SHOT_SIGN_IDENTITY to the release signing identity; a release must not be signed ad hoc." >&2
        exit 1
    fi
fi
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
archive="build/$name.xcarchive"
app="build/$name.app"

rm -rf "$archive" "$app"
scripts/xcodebuild.sh "${args[@]}" CURRENT_PROJECT_VERSION="$build_number" -archivePath "$archive" -quiet archive
ditto "$archive/Products/Applications/$name.app" "$app"
codesign --verify --deep --strict "$app"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
echo "Built $app $version ($build_number) for $(lipo -archs "$app/Contents/MacOS/$name")"
