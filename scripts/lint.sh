#!/bin/sh
# Fails on hosting views that let SwiftUI manage window size limits; see NSHostingView(fixedFrame:).
set -eu
cd "$(dirname "$0")/.."

hits=$(grep -rnE 'NSHostingView\(rootView:|NSHostingController\(' Sources | grep -v 'Sources/Shot/Design/GlassWindow.swift' || true)
if [ -n "$hits" ]; then
    echo "Use NSHostingView(fixedFrame:) instead; a plain hosting view crashes when content changes under a visible window:"
    echo "$hits"
    exit 1
fi
