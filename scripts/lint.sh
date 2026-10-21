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

# ShotCore is everything with no window, so its logic is tested without one.
hits=$(grep -rnE '^(@_exported |@testable )?import (AppKit|SwiftUI|Cocoa)$' Sources/ShotCore || true)
if [ -n "$hits" ]; then
    echo "ShotCore has no UI, so its logic can be tested without a window: AppKit and SwiftUI code goes in Sources/Shot:"
    echo "$hits"
    exit 1
fi

# SwiftUI holds a single tap until the double-click interval passes, so every click lags by up to half a second.
hits=$(grep -rnE 'onTapGesture\(count: *[2-9]' Sources || true)
if [ -n "$hits" ]; then
    echo "Don't pair onTapGesture(count: 2) with a single-tap gesture; every single click waits out the double-click interval (#452). Use one onTapGesture and read NSApp.currentEvent?.clickCount:"
    echo "$hits"
    exit 1
fi
