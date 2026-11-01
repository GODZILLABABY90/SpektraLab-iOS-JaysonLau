#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="$ROOT/build/upstream-SpektraLab"
if [ ! -d "$UPSTREAM/engine/src" ]; then
  echo "Run scripts/probe-upstream-ios.sh first to fetch the pinned original sources" >&2
  exit 2
fi
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CXX="$(xcrun --sdk iphoneos --find clang++)"
OUT="$ROOT/build/upstream-pipeline-probe"
mkdir -p "$OUT"
: > "$OUT/results.txt"
passes=0
failures=0
for file in "$UPSTREAM"/engine/src/pipeline/*.cpp; do
  name="$(basename "$file" .cpp)"
  if "$CXX" -std=c++20 -O2 -c -target arm64-apple-ios17.0 -isysroot "$SDK" \
      -I"$UPSTREAM/engine/include" -I"$UPSTREAM/engine/src" \
      -I"$UPSTREAM/engine/src/core" -I"$UPSTREAM/engine/src/pipeline" \
      -I"$UPSTREAM/engine/src/gpu" \
      "$file" -o "$OUT/$name.o" >"$OUT/$name.log" 2>&1; then
    echo "PASS $name" | tee -a "$OUT/results.txt"
    passes=$((passes+1))
  else
    echo "FAIL $name" | tee -a "$OUT/results.txt"
    sed -n '1,30p' "$OUT/$name.log"
    failures=$((failures+1))
  fi
done
echo "Pipeline compiled: $passes; failed: $failures" | tee -a "$OUT/results.txt"
if [ "$failures" -eq 0 ]; then
  xcrun --sdk iphoneos ar rcs "$OUT/libspektralab-pipeline-ios.a" "$OUT"/*.o
fi
test "$failures" -eq 0
