#!/bin/bash
# Moves build/ShotDev.app into the given folder (default /Applications) and registers it. It never touches Shot.app,
# which belongs to the installed release. Moving, not copying, leaves no second copy in build/ for Spotlight and Launchpad to find.
set -euo pipefail
cd "$(dirname "$0")/.."

install_dir="${1:-/Applications}"
mkdir -p "$install_dir"
rm -rf "$install_dir/ShotDev.app"
mv build/ShotDev.app "$install_dir/ShotDev.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$install_dir/ShotDev.app"
echo "Installed $install_dir/ShotDev.app"
