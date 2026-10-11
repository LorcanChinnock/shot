#!/bin/sh
# Fails on patterns that have caused bugs: hosting views that let SwiftUI manage window size limits, and ink lines
# drawn in ways that leave fringes and seams.
set -eu
cd "$(dirname "$0")/.."

hits=$(grep -rnE 'NSHostingView\(rootView:|NSHostingController\(' Sources | grep -v 'Sources/Shot/Design/GlassWindow.swift' || true)
if [ -n "$hits" ]; then
    echo "Use NSView(hosting:) instead; a plain hosting view crashes when content changes under a visible window:"
    echo "$hits"
    exit 1
fi

# Any Brutal colour, so a ternary such as `strokeBorder(selected ? Brutal.yellow : Brutal.ink, …)` is caught too.
hits=$(grep -rnE 'strokeBorder\(.*Brutal\.' Sources | grep -v 'Sources/Shot/Design/BrutalStyle.swift' || true)
if [ -n "$hits" ]; then
    echo "Use inkBorder(_:width:) instead; content under a plain ink stroke bleeds through its anti-aliased outer edge:"
    echo "$hits"
    exit 1
fi

hits=$(grep -rnE '(inkBorder\(.*width|border|lineWidth): [0-9]*\.[0-9]' Sources || true)
if [ -n "$hits" ]; then
    echo "Use whole-point ink widths; a fractional width leaves a grey half-pixel seam on 1x displays:"
    echo "$hits"
    exit 1
fi

hits=$(grep -rnE 'style: \.continuous' Sources || true)
if [ -n "$hits" ]; then
    echo "Use style: .circular instead; continuous corners leave steps under ink borders (#92):"
    echo "$hits"
    exit 1
fi

hits=$(grep -rnE '@AppStorage[( ]|AppStorage\(' Sources || true)
if [ -n "$hits" ]; then
    echo "Use @Setting instead; @AppStorage catches up an update late, so views mixing it with other state show combinations that never existed:"
    echo "$hits"
    exit 1
fi

# ShotModel builds and tests on Linux, where only Foundation and the standard library exist. The Linux build is the
# backstop; this names the cause first.
hits=$(find Sources/ShotModel Tests/ShotModelTests -name '*.swift' -exec awk '
    /^(@testable )?import / && !/^(@testable )?import (Foundation|Synchronization|Testing|ShotModel)$/ &&
        !(/^import CoreGraphics$/ && prev == "#if canImport(CoreGraphics)") { print FILENAME ":" FNR ": " $0 }
    { prev = $0 }' {} +)
if [ -n "$hits" ]; then
    echo "ShotModel runs on Linux: import only Foundation, or CoreGraphics inside #if canImport(CoreGraphics). Apple-only code goes in ShotCore:"
    echo "$hits"
    exit 1
fi

# macOS runner minutes cost about 15× Linux ones.
hits=$(awk '/runs-on:.*macos/ && prev !~ /# macOS: / { print FILENAME ":" FNR ": " $0 } { prev = $0 }' .github/workflows/*.yml)
if [ -n "$hits" ]; then
    echo "Put a '# macOS: <reason>' comment above each macOS runs-on, saying why the job can't run on Linux:"
    echo "$hits"
    exit 1
fi
