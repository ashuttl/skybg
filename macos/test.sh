#!/bin/bash
# Run the tests. With Xcode, `swift test` is enough; the Command Line Tools
# alone need telling where their copy of Swift Testing is.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

if xcode-select -p | grep -q CommandLineTools; then
  TOOLS=$(xcode-select -p)
  FRAMEWORKS=$TOOLS/Library/Developer/Frameworks
  exec swift test --build-system native \
    -Xswiftc -F"$FRAMEWORKS" -Xswiftc -plugin-path -Xswiftc "$TOOLS/usr/lib/swift/host/plugins/testing" \
    -Xlinker -F"$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$TOOLS/Library/Developer/usr/lib" "$@"
fi
exec swift test "$@"
