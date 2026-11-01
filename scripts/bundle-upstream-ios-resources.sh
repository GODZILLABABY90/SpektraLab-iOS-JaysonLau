#!/usr/bin/env bash
# Bundle original profile, print and iOS Metal assets for the app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="$ROOT/build/upstream-SpektraLab"
ASSETS="$ROOT/SpektraLabIOS/OriginalEngineResources"
METAL="$ROOT/build/upstream-metal-ios/spektrafilm-ios.metallib"
test -f "$UPSTREAM/engine/resources/spektrafilm_constants.bin" || { echo "Upstream baked spectral constants missing" >&2; exit 2; }
test -f "$METAL" || { echo "iOS-original metallib missing; will not package macOS shaders" >&2; exit 2; }
mkdir -p "$ASSETS"
cp -R "$UPSTREAM/engine/resources/." "$ASSETS/"
cp "$METAL" "$ASSETS/spektrafilm.metallib"
if [ -d "$UPSTREAM/engine/resources_product/profiles" ]; then
  mkdir -p "$ASSETS/profiles"
  cp "$UPSTREAM/engine/resources_product/profiles/"*.json "$ASSETS/profiles/"
  cp "$UPSTREAM/engine/resources_product/NOTICE.md" "$ASSETS/PRODUCT_PROFILES_NOTICE.md"
fi
cp "$UPSTREAM/README.md" "$ASSETS/UPSTREAM-README.md"
printf '%s\n' "Upstream original SpektraLab GPL-3.0-or-later" \
  "Film/paper profiles and print LUTs CC BY-SA 4.0" \
  "Original source: https://github.com/JamesQiu2005/SpektraLab" \
  "See accompanying upstream source archive in CI artifacts." > "$ASSETS/SOURCE-ATTRIBUTION.txt"
du -sh "$ASSETS"
