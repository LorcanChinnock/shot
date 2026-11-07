#!/bin/sh
# Runs xcodebuild on Shot.xcodeproj with the repository's defaults, so make, CI and the release build the same way,
# with Xcode even when only the Command Line Tools are selected. It builds into build/DerivedData ($DERIVED_DATA), apart
# from Xcode's own folder: Xcode 27 can leave a test bundle unsigned when both build into one. It signs with SHOT_SIGN_IDENTITY when that's set. Otherwise the project signs with "Shot Dev"
# (scripts/make-dev-cert.sh), and when that identity is missing, as on CI, this signs ad hoc instead, so the build
# still works but the Screen Recording permission resets on every build.
# Usage: scripts/xcodebuild.sh <xcodebuild arguments>
set -eu
cd "$(dirname "$0")/.."

if xcode-select -p | grep -q CommandLineTools; then
    if [ -d /Applications/Xcode.app ]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        echo "error: building Shot needs Xcode, and only the Command Line Tools are installed. Install Xcode from the App Store." >&2
        exit 1
    fi
fi

has_identity() {
    security find-identity -p codesigning | grep -q "\"$1\""
}

if [ -n "${SHOT_SIGN_IDENTITY:-}" ]; then
    set -- "$@" CODE_SIGN_IDENTITY="$SHOT_SIGN_IDENTITY"
elif [ ! -f Config/Local.xcconfig ] && ! has_identity "Shot Dev"; then
    echo "warning: signing identity 'Shot Dev' not found; signing ad hoc. Run scripts/make-dev-cert.sh so the Screen Recording permission survives rebuilds." >&2
    set -- "$@" CODE_SIGN_IDENTITY=-
fi

derived="${DERIVED_DATA:-build/DerivedData}"
status=0
xcodebuild -project Shot.xcodeproj -derivedDataPath "$derived" "$@" || status=$?

# Xcode registers every app it builds with Launch Services, which then picks one of the copies for shot-dev:// links,
# often this one rather than the ShotDev you're running from Xcode. Unregister them, so links reach that one.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
find "$derived/Build" -maxdepth 6 -name "*.app" -path "*Products*" -prune 2>/dev/null | while read -r app; do
    "$lsregister" -u "$app" 2>/dev/null || true
done
exit "$status"
