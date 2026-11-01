#!/usr/bin/env bash
# Package upstream portable core for an iOS Xcode target once compiled.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="$ROOT/build/upstream-SpektraLab"
OUT="$ROOT/build/upstream-probe"
LIB="$OUT/libspektralab-core-ios.a"
if [ ! -f "$LIB" ]; then
  echo "Original upstream C++ library not produced; inspect compilation diagnostics" >&2
  exit 2
fi
HEADERS="$ROOT/build/upstream-ios-headers"
mkdir -p "$HEADERS"
cp "$UPSTREAM/engine/src/core/"*.hpp "$HEADERS/"
# Include the original C ABI as an interface reference (full engine not linked yet).
mkdir -p "$OUT/licensing"
cp "$UPSTREAM/README.md" "$OUT/licensing/UPSTREAM-README.md"
cat > "$OUT/licensing/ATTRIBUTION.txt" <<'EOF'
SpektraLab upstream: https://github.com/JamesQiu2005/SpektraLab
App and engine: GPL-3.0-or-later.
Film / paper profiles and print LUTs: CC BY-SA 4.0.
metal-cpp: Apache-2.0.
This archive contains a compilation probe, not a complete redistributable app.
The full original license notices and corresponding source must accompany a distribution.
EOF
rm -rf "$OUT/SpektraLabCore.xcframework"
xcodebuild -create-xcframework -library "$LIB" -headers "$HEADERS" \
   -output "$OUT/SpektraLabCore.xcframework"
echo "Created original-engine core framework for iPhone arm64"
