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
  homepage "https://shot.lorcanchinnock.com"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sequoia

  app "Shot.app"
  binary "#{appdir}/Shot.app/Contents/MacOS/shot-cli", target: "shot"

  uninstall quit: "dev.lorcan.Shot"

  zap trash: [
    "~/Library/Application Support/dev.lorcan.Shot",
    "~/Library/Caches/dev.lorcan.Shot",
    "~/Library/HTTPStorages/dev.lorcan.Shot",
    "~/Library/HTTPStorages/dev.lorcan.Shot.binarycookies",
    "~/Library/Preferences/dev.lorcan.Shot.plist",
  ]

  caveats <<~EOS
    Shot isn't notarized by Apple yet, so macOS blocks it the first time you open it.
    Open Shot and click Done, then click Open Anyway in
    System Settings > Privacy & Security and confirm. You only do this once.
    Steps with pictures: https://shot.lorcanchinnock.com/#install
  EOS
end
EOF
