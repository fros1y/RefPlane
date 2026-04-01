# GitHub Copilot Instructions — RefPlane / Underpaint

## Project Overview

**Underpaint** is a native iOS reference-preparation tool for painters and draughtsmen. It processes a reference photograph through four display modes (Original, Tonal, Value, Color), applies optional ML-based image abstraction, extracts a paint palette, and matches colours to real pigments using Kubelka-Munk spectral mixing.

The iOS app module is named **Underpaint** and lives in `ios/`.

## Tech Stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI (iOS 16.0+)
- **Frameworks used**: SwiftUI, PhotosUI, CoreImage, CoreML, Metal, Accelerate
- **Build tool**: Xcode 15+
- **Dependencies**: None — the project uses only Apple system frameworks; do not add third-party packages

## Architecture

### State management

`AppState` (`ios/RefPlane/Models/AppState.swift`) is the single `@MainActor ObservableObject` that owns all published UI state. Every property mutation must happen on the main actor. Closures that update `AppState` from a `Task` must use `Task { @MainActor [weak self] in … }` or `await MainActor.run { … }`.

### Processing pipeline

`ImageProcessor` (`ios/RefPlane/Processing/ImageProcessor.swift`) is a Swift `actor` that runs all heavy image work off the main thread. It exposes a single `process(image:mode:valueConfig:colorConfig:onProgress:)` async-throwing method and returns a `ProcessingResult` struct.

### Concurrency patterns

- Every long-running operation is a cancellable `Task<Void, Never>` stored on `AppState`.
- **Generation counters** (`processingGeneration`, `abstractionGeneration`) guard against stale results: increment before each new task, and bail out if the counter has changed by the time the task finishes.
- Always call `try Task.checkCancellation()` at natural suspension points.

### Image modes

| Mode | Class |
|------|-------|
| Tonal | `GrayscaleProcessor` (Rec 709 luminance) |
| Value | `ValueStudyProcessor` (quantised luminance bands) |
| Color | `ColorRegionsProcessor` + `PaintPaletteBuilder` |

### Color science

- Perceptual colour work uses **Oklab** (`OklabColorSpace.swift`): prefer `RGB.toOklab()` / `.fromOklab()` over other colour-space conversions.
- Paint mixing uses **Kubelka-Munk** (`KubelkaMunkMixer.swift`): operate on `SpectralData` (31-band reflectance), not sRGB.
- Colour clustering uses **k-means++** (`KMeansClusterer.swift`).

### ML abstraction

`ImageAbstractor` wraps a CoreML `.mlpackage` (APISR_GRL_x4 ×4 super-resolution). The selected method is `AbstractionMethod` (enum) with `processingKind: AbstractionProcessingKind`.

## Coding Conventions

- Follow **Swift API Design Guidelines**: clear, expressive names; no abbreviations except established ones (`cg`, `ctx`, `UI*`, `CG*`).
- Mark all types and functions that must run on the main thread with `@MainActor`.
- Use `actor` (not classes with locks) for off-thread state.
- Prefer `async`/`await` over completion handlers.
- Use `[weak self]` in closures captured by long-lived tasks.
- Organise related declarations with `// MARK: -` sections.
- Do **not** add force-unwraps (`!`) to production code; use `guard let` or `if let`.
- Test new processing logic with Swift Testing (`@Test`, `#expect`, `@Suite`); see `ios/RefPlaneTests/` for examples.

## Testing

- Framework: **Swift Testing** (not XCTest) — use `@Test`, `#expect`, `@Suite`.
- Tests import the app module with `@testable import Underpaint`.
- For `@MainActor` tests, annotate both the suite and each test function.
- Inject operations via `AppState.init(processOperation:abstractionOperation:)` to keep unit tests fast and deterministic.
- `TestImageFactory` provides solid-colour and split-colour `UIImage` helpers.
- Run tests with: `xcodebuild test -project ios/RefPlane.xcodeproj -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16'`

## Build Commands

```bash
# Debug build (simulator)
xcodebuild -project ios/RefPlane.xcodeproj -scheme RefPlane \
  -configuration Debug -destination 'generic/platform=iOS Simulator' build

# Release build (no signing, CI-friendly)
xcodebuild -project ios/RefPlane.xcodeproj -scheme RefPlane \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# Run tests
xcodebuild test -project ios/RefPlane.xcodeproj -scheme RefPlane \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Clean
xcodebuild -project ios/RefPlane.xcodeproj -scheme RefPlane clean
```

VSCode tasks for the above are defined in `.vscode/tasks.json`.

## Project Structure

```
ios/
├── RefPlane.xcodeproj/
└── RefPlane/
    ├── RefPlaneApp.swift          App entry point (@main)
    ├── Models/
    │   ├── AppModels.swift        Enums, config structs, mode definitions
    │   ├── AppState.swift         @MainActor ObservableObject — all UI state
    │   └── SpectralData.swift     31-band reflectance model
    ├── Processing/
    │   ├── ImageProcessor.swift   Actor coordinator — entry point for processing
    │   ├── GrayscaleProcessor.swift
    │   ├── ValueStudyProcessor.swift
    │   ├── ColorRegionsProcessor.swift
    │   ├── PaintPaletteBuilder.swift
    │   ├── KMeansClusterer.swift
    │   ├── KubelkaMunkMixer.swift
    │   ├── OklabColorSpace.swift
    │   ├── RegionCleaner.swift
    │   ├── ImageAbstractor.swift
    │   ├── MetalContext.swift
    │   ├── Shaders.metal
    │   └── UIImageExtensions.swift
    ├── Views/                     SwiftUI view hierarchy
    └── Support/                   Utility helpers
```
