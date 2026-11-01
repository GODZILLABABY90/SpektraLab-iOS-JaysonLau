# SpektraLab iOS port status

## Current milestone
This repository contains an independently written SwiftUI + Core Image proof-of-concept, NOT a port of the original spectral simulation engine. The workflow attempts an unsigned iOS device build and packages an IPA for subsequent sideload signing.

## Upstream
Original project: https://github.com/JamesQiu2005/SpektraLab

The upstream macOS implementation uses a C++/Metal film simulation pipeline. Its README describes 81-wavelength spectral film/paper modeling, physical grain, halation, film edges and half-frame support. None of those features are reproduced faithfully in this prototype. Before copying or adapting upstream source or assets, identify and comply with its license and any third-party licensing requirements.

## Planned engine migration
1. Inventory engine C++ sources, Metal kernels, resource data and platform-specific dependencies.
2. Separate portable numerical core from macOS-only UI, I/O and build scripts.
3. Add iOS Metal compilation and resource packaging.
4. Expose C ABI to Swift with iOS-compatible headers/module map.
5. Validate outputs against desktop reference images and add regression tests.
6. Optimize memory, thermal load and large RAW decode on devices.

## Install notes
GitHub Actions creates an **unsigned** IPA. It must be signed by SideStore/AltStore or another appropriate signing service before it can be installed. A successful workflow is necessary but not yet verified.
