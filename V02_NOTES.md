# V0.2 Film Looks prototype

Implemented in the iOS UI:
- Six independently designed film-inspired looks (Original, Soft Portrait, Golden Hour, Cool Negative, Classic Color, Silver Mono), with strength slider.
- Frame styles: None, White, Black, Instant, and simplified 35mm perforated border.
- Exposure, contrast, saturation, warmth, grain and vignette adjustments.
- Preview and full-resolution image export to Photos.

Limitations:
- These are **not** Kodak/Fujifilm stock profiles, not measured spectral presets, and not the upstream SpektraLab film engine.
- 35mm frame is a stylized illustration, not a faithful upstream Film Edge simulation.
- Grain uses Core Image noise, not physically calibrated grain; halation and RAW processing are not yet implemented.
- iOS device compilation and runtime must be validated in CI and on device.

Upstream: https://github.com/JamesQiu2005/SpektraLab
