#!/bin/bash
# Draw Support/Skybg.icns with the app itself: the bokashi style a little
# before a November sunset in Maine. Run after ./build.sh, then build again
# to put the icon in the app. Needs ImageMagick; the icon is checked in, so
# building the app does not.
set -euo pipefail

SUPPORT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SKYBG=$SUPPORT/../build/Skybg.app/Contents/MacOS/Skybg
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT

"$SKYBG" render bokashi 824x824 "$WORK/sheet.png" --time 1795119900 --offset -18000 \
  --lat 43.68 --lon -70.37 --light --no-grain

# The sheet in the shape of a Mac icon, on a 1024 canvas, with a soft shadow.
magick -size 824x824 xc:none -fill white -draw "roundrectangle 0,0 823,823 185,185" "$WORK/mask.png"
magick "$WORK/sheet.png" "$WORK/mask.png" -alpha off -compose CopyOpacity -composite "$WORK/tile.png"
magick -size 1024x1024 xc:none \
  \( "$WORK/tile.png" -background black -shadow 30x12+0+10 \) -gravity center -composite \
  "$WORK/tile.png" -gravity center -composite "$WORK/icon.png"

ICONSET=$WORK/Skybg.iconset
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$WORK/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$SUPPORT/Skybg.icns"
echo "Wrote $SUPPORT/Skybg.icns"
