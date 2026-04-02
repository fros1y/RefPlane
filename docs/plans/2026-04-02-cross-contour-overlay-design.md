# Cross-Contour Overlay Plan

**Date:** 2026-04-02
**Status:** Canonical plan
**Canonical Path:** `docs/plans/2026-04-02-cross-contour-overlay-design.md`

This document replaces the earlier draft and is the single source of truth for adding depth-driven cross-contour lines to the iOS app.

## 1. Overview

Add a non-destructive "Surface Contours" overlay inside the existing depth workflow. The overlay traces isolines from the current depth map, clips them to the fitted image rect, and draws them above the image in the same way the grid overlay does today.

The feature is intentionally an overlay, not a new processed image mode:

- contour geometry comes from the depth map
- contour color comes from the same line-style system used by the grid
- contour visibility is controlled from the depth section
- export bakes the overlay into the output image when enabled

## 2. Goals

- Show evenly spaced contour lines over foreground and midground forms.
- Reuse the existing overlay vocabulary: normalized line segments, `Canvas`, line styles, opacity, and auto-contrast.
- Keep contour generation off the main thread.
- Match current app behavior around depth recomputation, threshold preview, compare mode, and export.
- Add unit coverage for generation, invalidation, and export behavior.

## 3. Non-Goals

- Do not add a new processed-image mode for contours.
- Do not change the depth-estimation or depth-effects algorithms.
- Do not add editable/vector contour paths or persistent contour caches.
- Do not touch the web `src/components/CompareView.tsx`; this feature is implemented in the SwiftUI iOS app.
- Do not widen the scope into a general "depth overlays" framework yet.

## 4. Current Code Findings

The earlier draft was directionally correct, but several implementation assumptions needed tightening against the current codebase.

- `StudyImageLayer` in [ios/RefPlane/Views/ImageCanvasView.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Views/ImageCanvasView.swift#L216) is the actual overlay seam. That is where contours should be inserted.
- `CompareView` is SwiftUI in [ios/RefPlane/Views/CompareView.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Views/CompareView.swift), not the web `CompareView.tsx`.
- Depth lifecycle is already centralized in [ios/RefPlane/Models/AppState.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Models/AppState.swift). Contours should plug into that lifecycle instead of creating an unrelated pipeline.
- Depth cutoff sliders in [ios/RefPlane/Views/DepthSettingsView.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Views/DepthSettingsView.swift) show a threshold preview while dragging and only settle work on drag end. Contour recomputation must respect that interaction model.
- Export currently only bakes the grid in [ios/RefPlane/Models/AppState.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Models/AppState.swift#L387). Contours need to follow the same export contract, including original-mode export preferring the full-resolution source image.
- The project already has test patterns for `AppState`, export, and grid line resolution in `ios/RefPlaneTests`, so contour work should extend those tests instead of relying only on manual verification.

## 5. Product Behavior

### 5.1 User-facing behavior

- A new `Surface Contours` toggle appears inside the existing depth section, below `Intensity`.
- The controls appear only when depth effects are enabled and a depth map exists.
- When enabled, contours draw over the current image on the canvas and on the processed side of compare mode.
- Contours do not appear on the "before" side of compare mode.
- If depth effects are disabled or the depth map is cleared, contours disappear immediately.

### 5.2 Threshold-preview behavior

Contours should be hidden while the user is actively dragging a depth cutoff slider.

Reasoning:

- the threshold preview is a diagnostic view and should stay legible
- contour geometry is intentionally recomputed only after drag end
- auto-contrast should not sample the temporary threshold-preview image

This keeps the interaction consistent: drag shows the preview only, release restores the processed image and updated contour overlay.

### 5.3 Overlay order

Overlay stacking should be:

1. image
2. grid
3. contours

Contours should sit above the grid because they carry subject-form information and are visually harder to read when interrupted by grid lines. Export must preserve the same order.

## 6. Architecture

```text
depth map settles or contour-driving config changes
    -> AppState.recomputeContours()
        -> build a small sendable depth sample buffer
        -> ContourGenerator.generateSegments(...)
        -> publish [GridLineSegment] on MainActor

render
    -> StudyImageLayer
        -> GridOverlayView
        -> ContourOverlayView

export
    -> AppState.exportCurrentImage()
        -> renderGridOnto(...)
        -> renderContoursOnto(...)
```

### 6.1 Data model

Add `ContourConfig` to [ios/RefPlane/Models/AppModels.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Models/AppModels.swift):

```swift
struct ContourConfig {
    var enabled: Bool = false
    var levels: Int = 5
    var lineStyle: LineStyle = .autoContrast
    var customColor: Color = .white
    var opacity: Double = 0.7
}
```

Add to `AppState`:

```swift
@Published var contourConfig: ContourConfig = ContourConfig()
@Published var contourSegments: [GridLineSegment] = []

private var contourTask: Task<Void, Never>? = nil
private var contourGeneration: Int = 0
```

### 6.2 Generation inputs

Contour geometry depends on only three things:

- the current depth map
- `depthConfig.backgroundCutoff`
- `contourConfig.levels`

It does not depend on:

- `depthConfig.foregroundCutoff`
- `depthConfig.effectIntensity`
- `depthConfig.backgroundMode`
- contour line style or opacity

That distinction matters because it defines when recomputation is required.

### 6.3 Concurrency rule

Do not pass `UIImage` directly into a detached contour-generation task.

Instead:

- extract or resample the depth map into a small immutable grayscale buffer first
- pass only sendable value data into the background worker
- return normalized `[GridLineSegment]`

This avoids actor-isolation and sendability problems while keeping the heavy work off the main actor.

A practical shape is:

```swift
struct ContourDepthField: Sendable {
    let width: Int
    let height: Int
    let samples: [UInt8]
}
```

`ContourGenerator` can then work entirely on pure Swift value data.

### 6.4 Contour generation

Create [ios/RefPlane/Support/ContourGenerator.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Support/ContourGenerator.swift).

Responsibilities:

- resample the depth map to a fixed `(gridWidth + 1) x (gridHeight + 1)` scalar field
- compute evenly spaced thresholds inside `depthRange.lowerBound..<backgroundCutoff`
- run marching squares for each threshold
- skip fully background cells
- output normalized `GridLineSegment` values in `[0, 1]`

Recommended defaults:

- grid size: `200 x 200` cells
- thresholds:

```swift
let lo = depthRange.lowerBound
let hi = min(backgroundCutoff, depthRange.upperBound)
guard hi > lo else { return [] }
let thresholds = (0..<levels).map {
    lo + (hi - lo) * Double($0 + 1) / Double(levels + 1)
}
```

Per-cell rules:

- skip the cell when all four corners are `>= backgroundCutoff`
- compute the standard 4-bit marching-squares case for each threshold
- use linear interpolation on crossing edges
- handle saddle cases `5` and `10` with the cell-average disambiguation rule
- discard degenerate segments

### 6.5 Color resolution

Create [ios/RefPlane/Support/ContourLineColorResolver.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Support/ContourLineColorResolver.swift).

This should stay intentionally small and reuse `GridLineColorResolver` behavior rather than duplicating luminance sampling logic.

Recommended implementation:

- direct-map `.black`, `.white`, and `.custom`
- for `.autoContrast`, build a proxy `GridConfig` and delegate to `GridLineColorResolver.resolvedSegments`

This keeps contour color behavior aligned with grid behavior.

### 6.6 Overlay rendering

Create [ios/RefPlane/Views/ContourOverlayView.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Views/ContourOverlayView.swift).

The view should mirror `GridOverlayView` structurally, with these specifics:

- accept the currently displayed image as an input for auto-contrast sampling
- read precomputed `state.contourSegments`
- clip drawing to the fitted image rect
- use round line caps
- use a slightly heavier stroke than the grid if needed, but keep it subtle

Recommended starting stroke:

```swift
StrokeStyle(lineWidth: 0.6, lineCap: .round)
```

## 7. AppState Integration

### 7.1 `recomputeContours()`

Add `recomputeContours()` to [ios/RefPlane/Models/AppState.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Models/AppState.swift).

Required behavior:

- cancel any in-flight contour task
- clear segments immediately when contours are disabled or depth is unavailable
- increment a generation token before starting new work
- build the sendable depth sample field
- run `ContourGenerator.generateSegments(...)` off the main actor
- publish only the latest generation result

Pseudo-shape:

```swift
func recomputeContours() {
    contourTask?.cancel()

    guard contourConfig.enabled, let depth = depthMap else {
        contourSegments = []
        return
    }

    contourGeneration += 1
    let generation = contourGeneration
    let config = contourConfig
    let depthRange = depthRange
    let backgroundCutoff = depthConfig.backgroundCutoff
    let field = ContourDepthField.make(from: depth, sampleWidth: 201, sampleHeight: 201)

    contourTask = Task {
        let segments = await ContourGenerator.generateSegments(
            field: field,
            levels: config.levels,
            depthRange: depthRange,
            backgroundCutoff: backgroundCutoff
        )

        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard self.contourGeneration == generation else { return }
            self.contourSegments = segments
        }
    }
}
```

The exact helper split may vary, but the lifecycle rules should not.

### 7.2 Recompute triggers

Contours should recompute in these cases:

- after `computeDepthMap()` stores a new depth map and depth range
- when `Surface Contours` is toggled on
- when contour `Levels` changes and the slider drag ends
- when the background cutoff slider drag ends

Contours should be cleared in these cases:

- `resetDepthProcessing()`
- `loadImage(_:)`
- disabling depth effects
- toggling contours off

Contours should not recompute for these changes:

- foreground cutoff drag
- background mode changes
- intensity changes
- contour line style changes
- contour opacity changes
- contour custom color changes

Those settings affect either the processed image or the draw style, not contour geometry.

### 7.3 Interaction with current depth flow

The refined plan must preserve current depth behavior:

- `computeDepthMap()` remains the source of truth for depth-map replacement
- `applyDepthEffects()` remains responsible for the processed image
- contour generation is a sibling computation, not a replacement for either

The order after a new depth map lands should be:

1. store `depthMap`
2. store `depthRange`
3. update default cutoffs
4. trigger `recomputeContours()`
5. trigger `applyDepthEffects()`

## 8. View Integration

### 8.1 Settings UI

Create [ios/RefPlane/Views/ContourSettingsView.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Views/ContourSettingsView.swift).

This view should follow the same control vocabulary as `GridSettingsView`:

- `Toggle("Surface Contours", ...)`
- `LabeledSlider("Levels", range: 2...12, step: 1, ...)`
- `LabeledPicker("Line Style", ...)`
- conditional `ColorPicker`
- `LabeledSlider("Opacity", ...)`

Embed it in [ios/RefPlane/Views/DepthSettingsView.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Views/DepthSettingsView.swift) only when:

- `state.depthConfig.enabled`
- `state.depthMap != nil`

Placement:

- immediately after the existing `Intensity` slider

### 8.2 `StudyImageLayer`

Update [ios/RefPlane/Views/ImageCanvasView.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Views/ImageCanvasView.swift) so `StudyImageLayer` accepts:

```swift
let showsGrid: Bool
let showsContours: Bool
```

Render order:

```swift
Image(...)
if showsGrid { GridOverlayView(image: image) }
if showsContours { ContourOverlayView(image: image) }
```

When wiring call sites, `showsContours` should be false while `state.isEditingDepthThreshold` is true.

### 8.3 Compare mode

Update [ios/RefPlane/Views/CompareView.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Views/CompareView.swift):

- processed side: pass `showsContours: state.contourConfig.enabled && state.depthConfig.enabled && !state.isEditingDepthThreshold`
- before side: always pass `showsContours: false`

No additional compare-model changes are required for this feature.

## 9. Export

Extend [ios/RefPlane/Models/AppState.swift](/Users/martingalese/Documents/Projects/Programming/RefPlane/ios/RefPlane/Models/AppState.swift#L387).

Export rules:

- preserve the current contract where original mode prefers `fullResolutionOriginalImage`
- bake grid first, then contours
- if contours are enabled but no contour segments exist, skip contour rendering

Target shape:

```swift
func exportCurrentImage() -> UIImage? {
    let base = ...
    guard let image = base else { return nil }

    var rendered = image
    if gridConfig.enabled {
        rendered = renderGridOnto(rendered)
    }
    if contourConfig.enabled && !contourSegments.isEmpty {
        rendered = renderContoursOnto(rendered)
    }
    return rendered
}
```

`renderContoursOnto(_:)` should:

- mirror `renderGridOnto(_:)`
- map normalized segments into the export rect
- use contour color resolution against the image being exported
- use round caps

Using normalized segments means the same contour geometry can scale from the working-resolution depth map to the full-resolution export safely.

## 10. File Map

### New files

- `ios/RefPlane/Support/ContourGenerator.swift`
- `ios/RefPlane/Support/ContourLineColorResolver.swift`
- `ios/RefPlane/Views/ContourOverlayView.swift`
- `ios/RefPlane/Views/ContourSettingsView.swift`
- `ios/RefPlaneTests/ContourGeneratorTests.swift`

### Modified files

- `ios/RefPlane/Models/AppModels.swift`
- `ios/RefPlane/Models/AppState.swift`
- `ios/RefPlane/Views/DepthSettingsView.swift`
- `ios/RefPlane/Views/ImageCanvasView.swift`
- `ios/RefPlane/Views/CompareView.swift`
- `ios/RefPlaneTests/AppStateTests.swift`
- `ios/RefPlaneTests/ExportContractTests.swift`
- `ios/RefPlane.xcodeproj/project.pbxproj`

## 11. Test Plan

### 11.1 Unit tests

Add contour-specific tests for:

- threshold generation stays inside the foreground-to-background span
- fully background cells emit no segments
- simple synthetic depth ramps produce at least one contour segment
- degenerate or zero-span inputs return no segments

Extend `AppStateTests` for:

- toggling contours off clears `contourSegments`
- enabling contours with an existing depth map triggers recomputation
- background cutoff recomputes on drag end, not on every intermediate change
- foreground cutoff changes do not recompute contours

Extend `ExportContractTests` for:

- export still prefers the full-resolution original in original mode
- export includes contours when enabled
- export preserves overlay order when both grid and contours are enabled

### 11.2 Manual verification

- Enable depth effects and wait for a depth map to appear.
- Verify `Surface Contours` appears only after a depth map exists.
- Enable contours and confirm lines draw only over subject areas, not empty background.
- Change `Levels` and verify contour density updates only after the drag ends.
- Drag the background cutoff and verify the threshold preview hides contours during drag and restored contours reflect the new cutoff after release.
- Change line style among Auto, Black, White, and Custom.
- Verify compare mode shows contours only on the processed side.
- Export an image with grid plus contours and verify both overlays are baked in with contours above the grid.

## 12. Risks And Guardrails

- The biggest implementation risk is crossing actor boundaries with UIKit image types. Keep background generation on pure value data.
- The second risk is accidental over-recomputation. Only background cutoff, depth map replacement, contour enablement, and level changes should regenerate geometry.
- Keep contour rendering visually quiet. If the first pass feels too dense, adjust line width before adding new settings.
