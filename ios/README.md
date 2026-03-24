# RefPlane – iOS Native App

An iOS native version of RefPlane built in Swift using SwiftUI and Apple frameworks.

## Features

- **Image modes**: Source · Tonal (grayscale) · Value Study · Color Regions
- **Simplify**: Core Image noise-reduction + sharpening pipeline (plug-in a Core ML `.mlmodel` in `ImageSimplifier.swift` to swap in super-resolution)
- **Grid overlay**: configurable divisions, square/image-fit cells, diagonals, center-lines, opacity, custom colour
- **Crop**: non-destructive corner-handle crop tool
- **Compare**: drag-split before/after view
- **Palette**: extracted colour swatches with per-band isolation
- **Export**: native iOS share sheet

## Requirements

| Tool | Version |
|------|---------|
| Xcode | 15 or later |
| iOS Deployment Target | 16.0+ |
| Swift | 5.9+ |

## Opening in Xcode

1. Open `ios/RefPlane.xcodeproj` in Xcode.
2. Select a simulator or connected device (iPhone or iPad).
3. Press **⌘R** to build and run.

No third-party dependencies are required – the project uses only Apple system frameworks (SwiftUI, PhotosUI, CoreImage, CoreML).

## Project Structure

```
ios/
├── RefPlane.xcodeproj/       Xcode project
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
    └── Views/
        ├── ContentView.swift         Root adaptive layout
        ├── ImageCanvasView.swift     Pinch/pan/zoom canvas + grid
        ├── ControlPanelView.swift    Scrollable side/bottom panel
        ├── ModeBarView.swift         Mode selector
        ├── ValueSettingsView.swift   Levels, thresholds, min-region
        ├── ColorSettingsView.swift   Bands, colours/band, warm/cool
        ├── GridSettingsView.swift    Grid overlay controls
        ├── GridOverlayView.swift     Canvas-drawn grid
        ├── CompareView.swift         Drag-split before/after
        ├── CropView.swift            Corner-handle crop tool
        ├── PaletteView.swift         Colour swatch strips
        ├── ActionBarView.swift       Open/Crop/Compare/Export toolbar
        ├── ThresholdSliderView.swift Multi-handle threshold slider
        ├── ImagePickerView.swift     PHPickerViewController wrapper
        └── ErrorToastView.swift      Dismissible error banner
```

## Swapping in a Core ML Model for Simplify

`ImageSimplifier.swift` currently uses a Core Image pipeline (Lanczos upscale → noise reduction → sharpen → downscale). To replace it with a Core ML super-resolution model:

1. Add your `.mlmodel` file to the Xcode project (drag into the **RefPlane** group).
2. In `ImageSimplifier.swift`, replace the CI pipeline with a `VNCoreMLRequest` or direct `MLModel.prediction(from:)` call.

The `AppState.applySimplify()` / `resetSimplify()` wiring is already in place.

## Algorithms

The iOS app implements the same algorithms as the web version:

| Feature | Web | iOS |
|---------|-----|-----|
| Grayscale | Rec 709 in JS | Rec 709 in Swift (`linearizeSRGB`) |
| Value quantisation | `applyQuantization` | `ValueStudyProcessor` |
| Region cleanup | BFS flood-fill | `RegionCleaner` |
| Color regions | Oklab k-means++ | `ColorRegionsProcessor` + `KMeansClusterer` |
| Grid overlay | Canvas 2D | SwiftUI `Canvas` |
