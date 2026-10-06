#!/bin/zsh
# Writes test videos with sound into a folder: a 10 s 720p clip, a 6 s 1080p clip, and a 3 s portrait clip.
# Synthetic patterns are high-motion noise, so don't judge file-size estimates against them.
set -e
out="${1:?usage: make-clips.sh FOLDER}"
mkdir -p "$out"
clip() { # name pattern size seconds tone
  ffmpeg -loglevel error -y -f lavfi -i "${2}=size=${3}:rate=30:duration=${4}" -f lavfi -i "sine=frequency=${5}:duration=${4}" \
    -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$out/$1.mp4"
}
clip a testsrc2 1280x720 10 440
clip b smptebars 1920x1080 6 880
clip portrait testsrc2 720x1280 3 660
ls -la "$out"
