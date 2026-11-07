#!/bin/bash
# Live scroll lab: scrolls a real window and captures it with the running ShotDev (make run), then scores the saved
# image against the page's truth. Drives the system with synthetic mouse, key and scroll events, so the terminal needs
# Accessibility access, and nothing else should be touched while it runs.
#   scripts/scroll-lab/live.sh <page> <pattern>     page: truth-<page>.png in $LAB_DIR/frames; pattern: flicks|notches|slow|fast|reversal
set -euo pipefail
cd "$(dirname "$0")/../.."
LAB_DIR="${LAB_DIR:-/tmp/shot-scroll-lab}"
PAGE="$1"; PATTERN="${2:-flicks}"
BIN="$LAB_DIR/bin"; mkdir -p "$BIN" "$LAB_DIR/live"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Its own DerivedData, so the native Release build doesn't replace the universal one make bundle leaves.
DERIVED_DATA=build/ScrollLab scripts/xcodebuild.sh -scheme ScrollLab -configuration Release -destination "platform=macOS,arch=$(uname -m)" -quiet build
LAB=build/ScrollLab/Build/Products/Release/ScrollLab
[ "$BIN/drive" -nt scripts/scroll-lab/drive.swift ] || swiftc -O scripts/scroll-lab/drive.swift -o "$BIN/drive"
[ "$BIN/ScrollTarget" -nt scripts/scroll-lab/target.swift ] || swiftc -O scripts/scroll-lab/target.swift -o "$BIN/ScrollTarget"
pkill -x ScrollTarget || true; sleep 0.3
"$BIN/ScrollTarget" "$LAB_DIR/frames/truth-$PAGE.png" 640 440 300 200 >/dev/null 2>&1 &
sleep 1.5
D="$BIN/drive"; X=620; Y=420
before=$(ls -t "$HOME/Pictures/Shot"/*.png 2>/dev/null | head -1 || true)
open "shot-dev://capture-area"; sleep 1.5
$D key 1; sleep 0.4            # S: scroll on
$D drag 300 200 940 640; sleep 1
case "$PATTERN" in
  flicks) $D flick $X $Y 40 0.94 50 16; sleep 1; $D scroll $X $Y 12 30 16; sleep 0.8; $D flick $X $Y -35 0.94 40 16; sleep 0.8; $D flick $X $Y 50 0.95 60 16 ;;
  notches) for i in 1 2 3 4 5 6 7 8; do $D scroll $X $Y 20 5 16; sleep 0.35; done ;;
  slow) $D scroll $X $Y 3 160 16 ;;
  fast) $D flick $X $Y 110 0.93 45 16; sleep 1; $D flick $X $Y 90 0.93 45 16 ;;
  toend) for i in 1 2 3 4 5 6 7 8 9 10 11 12; do $D flick $X $Y 110 0.93 40 16; sleep 0.25; done; $D flick $X $Y 120 0.95 40 16 ;;
  reversal) $D scroll $X $Y 14 40 16; $D scroll $X $Y -14 25 16; $D scroll $X $Y 18 50 16; $D scroll $X $Y -18 35 16; $D scroll $X $Y 16 60 16 ;;
esac
sleep 1
$D key 36; sleep 3.5           # Return: finish
after=$(ls -t "$HOME/Pictures/Shot"/*.png 2>/dev/null | head -1 || true)
pkill -x ScrollTarget || true
if [ -z "$after" ] || [ "$after" = "$before" ]; then echo "$PAGE/$PATTERN: no new image"; exit 1; fi
cp "$after" "$LAB_DIR/live/$PAGE-$PATTERN.png"
printf "%-8s %-9s " "$PAGE" "$PATTERN"
"$LAB" compare "$after" "$LAB_DIR/frames/truth-$PAGE.png" "$LAB_DIR/live/$PAGE-$PATTERN.diff.png"
