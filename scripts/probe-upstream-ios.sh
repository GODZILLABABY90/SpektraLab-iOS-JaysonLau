#!/usr/bin/env bash
# iOS arm64 compilation probe for the original SpektraLab portable core.
# Does not modify or ship upstream code. All source files are fetched at CI runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM_DIR="$ROOT/build/upstream-SpektraLab"
mkdir -p "$ROOT/build"
if [ ! -d "$UPSTREAM_DIR/.git" ]; then
  git clone --depth 1 https://github.com/JamesQiu2005/SpektraLab.git "$UPSTREAM_DIR"
fi
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
  if "$CXX" -std=c++20 -fsyntax-only -target arm64-apple-ios17.0 -isysroot "$SDK" \
    -I"$CORE" -I"$UPSTREAM_DIR/engine/include" -I"$UPSTREAM_DIR/engine/src" \
    "$file" >"$ROOT/build/upstream-probe/$name.log" 2>&1; then
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
