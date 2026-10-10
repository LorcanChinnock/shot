#!/bin/sh
# Converts the README's GIFs into looping videos and poster frames for the site.
# Run after docs/media changes: npm run media
set -eu
src=../docs/media
out=public/media
mkdir -p "$out"
for name in hero recording; do
  gif="$src/$name-light.gif"
  # Even dimensions for yuv420p, which every browser decodes.
  scale="scale=trunc(iw/2)*2:trunc(ih/2)*2"
  ffmpeg -y -loglevel error -i "$gif" -vf "$scale" -c:v libx264 -pix_fmt yuv420p -crf 26 -preset slow -movflags +faststart -an "$out/$name.mp4"
  ffmpeg -y -loglevel error -i "$gif" -vf "$scale" -c:v libvpx-vp9 -pix_fmt yuv420p -crf 38 -b:v 0 -an "$out/$name.webm"
  ffmpeg -y -loglevel error -i "$gif" -vf "$scale" -frames:v 1 "$out/$name.webp"
done
