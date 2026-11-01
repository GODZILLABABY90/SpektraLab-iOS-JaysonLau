#!/usr/bin/env bash
# iOS arm64 compilation probe for the original SpektraLab portable core.
# Does not modify or ship upstream code. All source files are fetched at CI runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM_DIR="$ROOT/build/upstream-SpektraLab"
mkdir -p "$ROOT/build"
if [ ! -d "$UPSTREAM_DIR/.git" ]; then
  git clone --filter=blob:none --no-checkout https://github.com/JamesQiu2005/SpektraLab.git "$UPSTREAM_DIR"
fi
git -C "$UPSTREAM_DIR" checkout --detach 267ee24380091e5bee87658d00f6c33d77321194
 git -C "$UPSTREAM_DIR" rev-parse HEAD | tee "$ROOT/build/upstream-revision.txt"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CXX="$(xcrun --sdk iphoneos --find clang++)"
CORE="$UPSTREAM_DIR/engine/src/core"
mkdir -p "$ROOT/build/upstream-probe"
failures=0
passes=0
for file in "$CORE"/*.cpp; do
  name="$(basename "$file" .cpp)"
  echo "=== Probing $name for arm64 iOS ==="
  if "$CXX" -std=c++20 -O2 -c -target arm64-apple-ios17.0 -isysroot "$SDK" \
    -I"$CORE" -I"$UPSTREAM_DIR/engine/include" -I"$UPSTREAM_DIR/engine/src" \
    "$file" -o "$ROOT/build/upstream-probe/$name.o" >"$ROOT/build/upstream-probe/$name.log" 2>&1; then
    echo "PASS $name" | tee -a "$ROOT/build/upstream-probe/results.txt"
    passes=$((passes+1))
  else
    echo "FAIL $name" | tee -a "$ROOT/build/upstream-probe/results.txt"
    sed -n '1,35p' "$ROOT/build/upstream-probe/$name.log"
    failures=$((failures+1))
  fi
done
printf 'Passed: %s; failed: %s\n' "$passes" "$failures" | tee -a "$ROOT/build/upstream-probe/results.txt"
# This is an exploratory diagnostic gate. Keep the existing IPA build independent.

if [ "$failures" -eq 0 ]; then
  "$CXX" -std=c++20 -O2 -c -target arm64-apple-ios17.0 -isysroot "$SDK" \
    -I"$CORE" -I"$UPSTREAM_DIR/engine/include" -I"$UPSTREAM_DIR/engine/src" \
    "$ROOT/native/UpstreamBridge.cpp" -o "$ROOT/build/upstream-probe/UpstreamBridge.o"
  xcrun --sdk iphoneos ar rcs "$ROOT/build/upstream-probe/libspektralab-core-ios.a" "$ROOT"/build/upstream-probe/*.o
  echo "Original C++ core static library produced" | tee -a "$ROOT/build/upstream-probe/results.txt"
  xcrun --sdk iphoneos nm "$ROOT/build/upstream-probe/libspektralab-core-ios.a" | grep -q spektralab_ios_blackbody_radiance
  shasum -a 256 "$ROOT/build/upstream-probe/libspektralab-core-ios.a" > "$ROOT/build/upstream-probe/library.sha256"
  mkdir -p "$ROOT/build/upstream-probe/license-notices"
  cp "$UPSTREAM_DIR/README.md" "$ROOT/build/upstream-probe/license-notices/UPSTREAM-README.md"
fi

# Mark the probe unsuccessful when any upstream source is incompatible.
if [ "$failures" -ne 0 ]; then exit 1; fi

if [ "$failures" -ne 0 ]; then
  echo "Original upstream core is not yet fully portable to iOS: $failures failures" >&2
  exit 1
fi
