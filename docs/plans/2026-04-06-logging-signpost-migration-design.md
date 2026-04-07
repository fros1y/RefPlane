# Logging and Signpost Migration Design

## Goal

Remove legacy logging under `ios/RefPlane` by replacing ad hoc `print` statements with structured `Logger` calls and moving all timing instrumentation to `os_signpost` so the processing pipeline is visible in Instruments.

## Scope

- Replace `CFAbsoluteTimeGetCurrent` timing code in the image-processing pipeline with signpost intervals.
- Replace legacy `print` diagnostics in processing and support files with `Logger` messages.
- Keep the existing subsystem, `com.refplane.app`, and assign per-file categories so logs and signposts remain easy to filter.

## Design

- Add a small shared instrumentation helper in `Support/` that exposes:
  - `Logger` factory by category.
  - `OSLog` factory by category.
  - sync and async interval wrappers around `os_signpost(.begin/.end)`.
- Keep logging ownership local to each file with file-scoped `logger` and `signpostLog` statics.
- Namespace processing categories as `Processing.*` so Instruments filtering groups related intervals together.
- Use verb-oriented signpost names for intervals so the timeline reads as pipeline steps rather than generic stopwatch blocks.
- Migrate the current stopwatch-style timing in:
  - `ImageProcessor`
  - `ColorRegionsProcessor`
  - `GrayscaleProcessor`
  - `ValueStudyProcessor`
  - `PaintPaletteBuilder`
- Migrate remaining legacy diagnostics in:
  - `MetalContext`
  - `ImageAbstractor`
  - `SpectralDataStore`

## Validation

- Search `ios/RefPlane` for remaining legacy `print(` calls.
- Search `ios/RefPlane` for remaining `CFAbsoluteTimeGetCurrent` timing code.
- Run the Debug simulator build to confirm the app target still compiles.
