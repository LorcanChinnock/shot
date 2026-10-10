#!/bin/sh
# Converts the 2× recordings in docs/media into the site's looping videos and poster frames.
# Run after docs/media changes: npm run media
set -eu
src=../docs/media
out=public/media
mkdir -p "$out"
for name in hero capture recording; do
  clip="$src/$name.mp4"
  # Even dimensions for yuv420p, which every browser decodes.
  scale="scale=trunc(iw/2)*2:trunc(ih/2)*2"
  ffmpeg -y -loglevel error -i "$clip" -vf "$scale" -c:v libx264 -pix_fmt yuv420p -crf 26 -preset slow -movflags +faststart -an "$out/$name.mp4"
  ffmpeg -y -loglevel error -i "$clip" -vf "$scale" -c:v libvpx-vp9 -pix_fmt yuv420p -crf 38 -b:v 0 -an "$out/$name.webm"
  # The first frame is the poster. Some ffmpeg builds have no WebP encoder, so fall back to cwebp.
  if ! ffmpeg -y -loglevel quiet -i "$clip" -vf "$scale" -frames:v 1 "$out/$name.webp"; then
    ffmpeg -y -loglevel error -i "$clip" -vf "$scale" -frames:v 1 "$out/$name.png"
    cwebp -quiet -q 80 "$out/$name.png" -o "$out/$name.webp"
    rm "$out/$name.png"
  fi
done
