#!/usr/bin/env bash
# Compile original upstream Metal shaders for the iPhone GPU.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/build/upstream-SpektraLab/engine/src/shaders"
OUT="$ROOT/build/upstream-metal-ios"
mkdir -p "$OUT"
: > "$OUT/results.txt"
if [ ! -d "$SOURCE" ]; then
  echo "Original shaders absent: fetch pinned upstream first" | tee -a "$OUT/results.txt"
  exit 2
fi
shopt -s nullglob
shaders=("$SOURCE"/*.metal)
if [ "${#shaders[@]}" -eq 0 ]; then
  echo "No original .metal shader files found" | tee -a "$OUT/results.txt"
  exit 2
fi
airs=()
failed=0
for shader in "${shaders[@]}"; do
  name="$(basename "$shader" .metal)"
  air="$OUT/$name.air"
  if xcrun --sdk iphoneos metal -std=ios-metal2.4 -fmetal-math-mode=safe \
    -fmetal-math-fp32-functions=precise -mios-version-min=17.0 \
    -I"$SOURCE" -I"$ROOT/build/upstream-SpektraLab/engine/include" \
    -c "$shader" -o "$air" >"$OUT/$name.log" 2>&1; then
    airs+=("$air")
    echo "PASS $name" | tee -a "$OUT/results.txt"
  else
    echo "FAIL $name" | tee -a "$OUT/results.txt"
    sed -n '1,30p' "$OUT/$name.log"
    failed=$((failed+1))
  fi
done
if [ "$failed" -eq 0 ]; then
  xcrun --sdk iphoneos metallib "${airs[@]}" -o "$OUT/spektrafilm-ios.metallib"
  xcrun --sdk iphoneos metal-readobj --file-headers "$OUT/spektrafilm-ios.metallib" >"$OUT/platform-stamp.txt" 2>&1 || true
fi
echo "Metal shaders: ${#airs[@]} passed; $failed failed" | tee -a "$OUT/results.txt"
test "$failed" -eq 0
