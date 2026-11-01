#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="$ROOT/build/upstream-SpektraLab"
CORE_LIB="$ROOT/build/upstream-probe/libspektralab-core-ios.a"
OUT="$ROOT/build/upstream-link-probe"
mkdir -p "$OUT"
CXX="$(xcrun --sdk iphoneos --find clang++)"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
test -f "$CORE_LIB" || { echo "Original C++ library not yet successfully compiled"; exit 2; }
"$CXX" -std=c++20 -O2 -c -target arm64-apple-ios17.0 -isysroot "$SDK" \
  -I"$UPSTREAM/engine/src/core" \
  "$ROOT/native-probe/upstream-core-smoke.cpp" -o "$OUT/upstream-core-smoke.o"
"$CXX" -target arm64-apple-ios17.0 -isysroot "$SDK" -dynamiclib \
  "$OUT/upstream-core-smoke.o" "$CORE_LIB" \
  -install_name @rpath/libspektralab-ios-core-smoke.dylib \
  -o "$OUT/libspektralab-ios-core-smoke.dylib"
file "$OUT/libspektralab-ios-core-smoke.dylib" | tee "$OUT/link-check.txt"
xcrun --sdk iphoneos nm -g "$OUT/libspektralab-ios-core-smoke.dylib" | grep spk_ios_upstream_core_smoke | tee -a "$OUT/link-check.txt"
