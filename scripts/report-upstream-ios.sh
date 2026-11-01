#!/usr/bin/env bash
# Summarize original upstream iPhoneOS compilation diagnostics for CI and local use.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/UPSTREAM-IOS-REPORT.md"
mkdir -p "$ROOT/build"
{
  echo "# Original SpektraLab — iPhoneOS compatibility report"
  echo
  echo "Generated from actual compiler logs. A successful probe is not proof that the full photographic pipeline works."
  echo
  if [ -f "$ROOT/build/upstream-revision.txt" ]; then
    printf 'Upstream revision: `%s`\n\n' "$(cat "$ROOT/build/upstream-revision.txt")"
  fi
  for item in "C++ core|upstream-probe" "C++ pipeline|upstream-pipeline-probe" "Metal GPU backend|upstream-gpu-probe" "Metal shaders|upstream-metal-ios"; do
    title="${item%%|*}"
    directory="${item#*|}"
    echo "## $title"
    report="$ROOT/build/$directory/results.txt"
    if [ -f "$report" ]; then
      echo '~~~text'
      cat "$report"
      echo '~~~'
    else
      echo "Not executed / no results."
    fi
    echo
    shopt -s nullglob
    for log in "$ROOT/build/$directory/"*.log; do
      if [ -s "$log" ] && grep -Eq '(^| )error:|fatal error:|Error:|FAILED' "$log"; then
        echo "### $(basename "$log")"
        echo '~~~text'
        grep -m 12 -E '(^| )error:|fatal error:|Error:|FAILED' "$log" || true
        echo '~~~'
        echo
      fi
    done
  done
  echo "## Artifacts"
  for path in "$ROOT/build/upstream-probe/libspektralab-core-ios.a" \
              "$ROOT/build/upstream-probe/SpektraLabCore.xcframework" \
              "$ROOT/build/upstream-metal-ios/spektrafilm-ios.metallib"; do
    if [ -e "$path" ]; then
      echo "- Built: `$(basename "$path")`"
    else
      echo "- Missing: `$(basename "$path")`"
    fi
  done
} > "$OUT"
cat "$OUT"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$OUT" >> "$GITHUB_STEP_SUMMARY"
fi
