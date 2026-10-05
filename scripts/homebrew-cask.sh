#!/bin/bash
# Prints the Homebrew cask for a release, for Casks/shot.rb in LorcanChinnock/homebrew-tap.
# The release workflow runs it on every release; run it by hand to seed or repair the tap.
# Usage: homebrew-cask.sh <version, without the v> <path to Shot-v<version>.zip>
set -euo pipefail

version="$1"
sha256="$(shasum -a 256 "$2" | cut -d ' ' -f 1)"

cat <<EOF
cask "shot" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/LorcanChinnock/shot/releases/download/v#{version}/Shot-v#{version}.zip"
  name "Shot"
  desc "Screenshots, annotations and screen recordings from the menu bar"
  homepage "https://github.com/LorcanChinnock/shot"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sequoia

  app "Shot.app"

  zap trash: [
    "~/Library/Caches/dev.lorcan.Shot",
    "~/Library/HTTPStorages/dev.lorcan.Shot",
    "~/Library/Preferences/dev.lorcan.Shot.plist",
  ]
end
EOF
