#!/bin/sh
# Fails unless the Shot binary at $1 weak-links FoundationModels. Copy Alt Text compiles only against the macOS 27 SDK
# (see Sources/ShotCore/AltText.swift), so an older SDK leaves it out without an error; the link shows it's in. It must
# be weak, because macOS 15 has no FoundationModels and the app wouldn't launch there.
set -eu

binary="${1:?usage: scripts/check-sdk.sh <path to the Shot binary>}"
archs="$(lipo -archs "$binary")"
# Every slice of a universal binary, Intel's too, needs the weak link.
for arch in $archs; do
    if ! otool -arch "$arch" -l "$binary" | grep -A2 LC_LOAD_WEAK_DYLIB | grep -q FoundationModels.framework; then
        if otool -arch "$arch" -L "$binary" | grep -q FoundationModels.framework; then
            echo "$binary ($arch) links FoundationModels strongly, so it won't launch on macOS 15." >&2
        else
            echo "$binary ($arch) doesn't link FoundationModels: built without the macOS 27 SDK, it has no Copy Alt Text." >&2
        fi
        exit 1
    fi
done
echo "$binary weak-links FoundationModels ($archs): Copy Alt Text is in."
