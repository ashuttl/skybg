#!/bin/bash
# Build Skybg.app into macos/build/. Needs only the Command Line Tools.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
APP=$ROOT/build/Skybg.app
cd "$ROOT"

# Some Command Line Tools releases ship a default build system that fails to
# start; SwiftPM's own is the fallback.
FLAGS=(-c release)
swift build "${FLAGS[@]}" 2>/dev/null || {
  FLAGS+=(--build-system native)
  swift build "${FLAGS[@]}"
}
BINARY=$(swift build "${FLAGS[@]}" --show-bin-path 2>/dev/null)/Skybg

rm -rf -- "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp -f "$BINARY" "$APP/Contents/MacOS/Skybg"
cp -f Support/Info.plist "$APP/Contents/Info.plist"
cp -f Support/com.skybg.agent.plist "$APP/Contents/Library/LaunchAgents/"
cp -f ../data/stars.bin "$APP/Contents/Resources/"
gunzip -c ../data/milkyway.bin.gz > "$APP/Contents/Resources/milkyway.bin"
[[ -f Support/Skybg.icns ]] && cp -f Support/Skybg.icns "$APP/Contents/Resources/"

# Signed to run here. Handing the app to someone else needs a Developer ID
# and notarisation.
codesign --force --sign - "$APP"
echo "Built $APP"
