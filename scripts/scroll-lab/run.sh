#!/bin/bash
# The scroll lab: renders scroll scenarios in Chrome (once, cached), replays them through ScrollStitcher, and scores the
# stitched images against a full-page truth. Look at the *.diff.png and *.result.png files it writes.
#   scripts/scroll-lab/run.sh [scenario-filter]     env: LAB_DIR (default /tmp/shot-scroll-lab)
# Needs Node with puppeteer-core on NODE_PATH (npm i puppeteer-core in $LAB_DIR) and Google Chrome.
set -euo pipefail
cd "$(dirname "$0")/../.."
LAB_DIR="${LAB_DIR:-/tmp/shot-scroll-lab}"
mkdir -p "$LAB_DIR/frames"
if [ ! -d "$LAB_DIR/node_modules/puppeteer-core" ]; then (cd "$LAB_DIR" && npm init -y >/dev/null && npm i puppeteer-core >/dev/null); fi
NODE_PATH="$LAB_DIR/node_modules" node scripts/scroll-lab/frames.cjs "$LAB_DIR/frames" "${1:-}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# bundle.sh leaves .build/release pointing at its last (Intel) build, so ask for this machine's own.
swift build -c release --arch arm64 --product ScrollLab 2>&1 | grep -E "error|Build" | tail -3
"$(swift build -c release --arch arm64 --product ScrollLab --show-bin-path)/ScrollLab" "$LAB_DIR/frames" "$LAB_DIR/out" "${1:-}"
