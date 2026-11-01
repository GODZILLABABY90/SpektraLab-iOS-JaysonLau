# SpektraLab iOS — original engine port plan

Goal: run the **original** SpektraLab C++20/Metal film-and-paper simulation on iOS, not the independent Core Image approximations in V0.2.

## Upstream evidence
- Original: https://github.com/JamesQiu2005/SpektraLab
- Upstream README **Credits and licence** explicitly says app/engine GPL-3.0-or-later, film and paper profiles / print LUTs CC BY-SA 4.0, metal-cpp Apache-2.0. Respect corresponding source redistribution, notices, attribution and copyleft obligations.
- `ARCHITECTURE.md`: SwiftUI/AppKit frontend -> C ABI `spk_engine.h` -> C++20 core + Metal GPU backend; 81 wavelengths (380–780 nm at 5 nm); film -> development -> enlarger/paper -> scan. Film Edge comprises three nodes around exposure, printing and scanning, **not** a composited PNG frame.
- Upstream build script currently targets macOS 15 and links macOS frameworks; an iOS-specific build and shader compilation path is required.

## Implementation sequence (not yet implemented)
1. Vendor the appropriately licensed engine source, headers, shaders and resource files at a pinned upstream commit; include complete licenses and attribution. Keep upstream history/reference and patch tracking.
2. Build core C++20 for arm64-apple-ios using Xcode toolchain; adapt platform-specific CoreText/CoreGraphics/Accelerate code and avoid AppKit.
3. Build iOS Metal kernels with upstream safe-math requirements and verify target/platform stamps; implement GPU backend and C ABI texture ownership compatible with iOS.
4. Bundle 28 measured profiles and print LUTs; expose original film/paper/format parameters via versioned JSON and an iOS Swift engine client.
5. Implement upstream Film Edge in the engine (film rebate, sprockets, edge marks, half-frame, 120, date back) rather than Core Graphics decoration.
6. Replace Core Image preview/export with original engine renders; add original settings UI and state persistence.
7. Establish golden-image/parity tests against macOS renders, measured image differences, peak memory, thermal behavior, and device export checks. Optimize full-resolution tiles and memory for iPhone.
8. Package unsigned IPA via GitHub Actions for SideStore; verify device installation, render, save, and license distribution.

## Current status
This document is a **migration plan**, not an engine port. V0.2 still uses independently written Core Image filters and stylized borders. Do not label any V0.2 IPA as the upstream spectral engine.

## Initial investigation notes
- `engine/CMakeLists.txt` already separates portable core from GPU-specific pipeline code.
- `engine/build.sh` sets `-mmacos-version-min=15.0` and links macOS Metal, Foundation, QuartzCore, CoreText, CoreGraphics and Accelerate. Its Metal math flags are explicitly fidelity-sensitive.
- iOS photo library input and export can remain SwiftUI / PhotosUI; the renderer must be swapped at the engine boundary.
