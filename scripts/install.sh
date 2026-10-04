#!/bin/bash
# Moves build/Shot.app into the given folder (default /Applications) and registers it.
# Moving, not copying, leaves no second Shot.app in build/ for Spotlight and Launchpad to find.
set -euo pipefail
cd "$(dirname "$0")/.."

install_dir="${1:-/Applications}"
mkdir -p "$install_dir"
rm -rf "$install_dir/Shot.app"
mv build/Shot.app "$install_dir/Shot.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$install_dir/Shot.app"
echo "Installed $install_dir/Shot.app"
