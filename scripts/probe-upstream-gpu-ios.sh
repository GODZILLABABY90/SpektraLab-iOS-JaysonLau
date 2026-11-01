#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="$ROOT/build/upstream-SpektraLab"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CXX="$(xcrun --sdk iphoneos --find clang++)"
OUT="$ROOT/build/upstream-gpu-probe"
mkdir -p "$OUT"
: > "$OUT/results.txt"
passes=0
failures=0
for file in "$UPSTREAM"/engine/src/gpu/*.cpp; do
  [ -f "$file" ] || continue
  name="$(basename "$file" .cpp)"
  if "$CXX" -std=c++20 -O2 -c -target arm64-apple-ios17.0 -isysroot "$SDK" \
      -I"$UPSTREAM/engine/include" -I"$UPSTREAM/engine/src" \
      -I"$UPSTREAM/engine/src/core" -I"$UPSTREAM/engine/src/pipeline" \
      -I"$UPSTREAM/engine/src/gpu" -I"$UPSTREAM/engine/third_party/metal-cpp" \
      "$file" -o "$OUT/$name.o" >"$OUT/$name.log" 2>&1; then
    echo "PASS $name" | tee -a "$OUT/results.txt"
    passes=$((passes+1))
  else
    echo "FAIL $name" | tee -a "$OUT/results.txt"
    sed -n '1,35p' "$OUT/$name.log"
    failures=$((failures+1))
  fi
done
echo "GPU source compiled: $passes; failed: $failures" | tee -a "$OUT/results.txt"
if [ "$failures" -eq 0 ] && [ "$passes" -gt 0 ]; then
  xcrun --sdk iphoneos ar rcs "$OUT/libspektralab-gpu-ios.a" "$OUT"/*.o
fi
test "$failures" -eq 0
