#!/bin/bash
# Copies the dev build, build/Shot Dev.app, into the given folder (default /Applications) and registers it.
set -euo pipefail
cd "$(dirname "$0")/.."

install_dir="${1:-/Applications}"
mkdir -p "$install_dir"
rm -rf "$install_dir/Shot Dev.app"
cp -R "build/Shot Dev.app" "$install_dir/Shot Dev.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$install_dir/Shot Dev.app"
echo "Installed $install_dir/Shot Dev.app"
