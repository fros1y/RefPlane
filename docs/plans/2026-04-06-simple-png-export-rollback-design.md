# Simple PNG Export Rollback Design

## Goal

Restore iOS export to a predictable image-only path that does not preserve or inject metadata.

## Scope

- Always export the rendered image as PNG.
- Stop using ImageIO destination-based export for share payloads.
- Remove export-specific provenance and metadata writing logic from `AppState`.
- Keep the separate settings-copy flow unchanged.

## Design

- `AppState.exportCurrentImage()` remains the source of truth for what gets exported:
  - Original mode exports the full-resolution original when available.
  - Other modes export the current rendered display image, including grid and contour overlays.
- `AppState.exportCurrentImagePayload()` now calls `pngData()` on that rendered image and returns `.png` unconditionally.
- The old source-type preference, metadata merging, and provenance JSON helpers are deleted to reduce the chance of aspect-ratio or wrong-source regressions.

## Validation

- Update export contract tests to assert PNG output and rendered-image dimensions.
- Run the export contract tests on the iOS simulator.