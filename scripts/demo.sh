#!/bin/bash
# Builds the MugCo sample app (Samples/MugCo) into build/MugCo.app and opens it. A steady window for QA runs, guide
# screenshots and agent checks to capture, with only made-up data in it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --package-path Samples/MugCo
bin_path="$(swift build -c release --package-path Samples/MugCo --show-bin-path)"

app="build/MugCo.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_path/MugCo" "$app/Contents/MacOS/MugCo"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.lorcan.Shot.sample</string>
    <key>CFBundleName</key><string>Mug Co. Support</string>
    <key>CFBundleExecutable</key><string>MugCo</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"

pkill -x MugCo || true
open "$app"
echo "Opened $app"
