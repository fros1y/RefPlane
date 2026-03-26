# Underpaint

An iOS reference-prep tool for painting and drawing, built natively with Swift and SwiftUI.

## Features

- **Image modes**: Original · Tonal · Value · Color
- **Simplify**: Core Image noise-reduction + sharpening pipeline (plug in a Core ML `.mlmodel` in `ImageSimplifier.swift` to swap in super-resolution)
- **Grid overlay**: configurable divisions, square/image-fit cells, diagonals, center-lines, opacity, custom colour
- **Compare**: drag-split before/after view
- **Palette**: extracted colour swatches with per-band isolation
- **Export**: native iOS share sheet

## Requirements

| Tool | Version |
|------|---------|
| Xcode | 15 or later |
| iOS Deployment Target | 16.0+ |
| Swift | 5.9+ |

No third-party dependencies — the project uses only Apple system frameworks (SwiftUI, PhotosUI, CoreImage, CoreML).

## Building

### Xcode

1. Open `ios/RefPlane.xcodeproj` in Xcode.
2. Select a simulator or connected device (iPhone or iPad).
3. Press **⌘R** to build and run.

### VSCode (macOS)

The workspace ships with `.vscode/tasks.json` build tasks. Use **Terminal → Run Task…**:

| Task | Description |
|------|-------------|
| **iOS: Build Debug (Simulator)** | Compile the app for the iOS Simulator (Debug) |
| **iOS: Build Release (no signing)** | Release build with code-signing disabled (CI-friendly) |
| **iOS: Clean** | Remove derived data for a clean rebuild |
| **iOS: Run on Simulator (iPhone 16)** | Boot an iPhone 16 simulator, install, and launch the app |
| **iOS: Open in Xcode** | Open `RefPlane.xcodeproj` in Xcode for full IDE workflow |

#### Recommended extensions

- **[SweetPad](https://marketplace.visualstudio.com/items?itemName=sweetpad.sweetpad)** — xcodebuild integration + simulator launch with LLDB attach
- **[Swift](https://marketplace.visualstudio.com/items?itemName=sswg.swift-lang)** — syntax highlighting, code completion, diagnostics

With SweetPad, use the **iOS: Run on Simulator** launch configuration to build, boot the simulator, and attach the debugger in one step.

## Project Structure

```
ios/
├── RefPlane.xcodeproj/       Xcode project for Underpaint
└── RefPlane/
    ├── RefPlaneApp.swift      App entry point (@main)
    ├── Models/
    │   ├── AppModels.swift    Data types (modes, configs, enums)
    │   └── AppState.swift     Observable state + processing dispatch
    ├── Processing/
    │   ├── OklabColorSpace.swift     Oklab math (RGB↔Oklab)
    │   ├── KMeansClusterer.swift     k-means++ clustering
    │   ├── RegionCleaner.swift       Flood-fill small-region cleanup
    │   ├── GrayscaleProcessor.swift  Rec 709 luminance grayscale
    │   ├── ValueStudyProcessor.swift Quantise → cleanup → band colours
    │   ├── ColorRegionsProcessor.swift Per-band k-means colour regions
    │   ├── ImageSimplifier.swift     Core Image simplification pipeline
    │   ├── ImageProcessor.swift      Actor coordinator
    │   └── UIImageExtensions.swift   UIImage pixel-data helpers
    └── Views/                        SwiftUI views
```
