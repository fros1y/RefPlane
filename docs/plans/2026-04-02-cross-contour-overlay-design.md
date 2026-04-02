# Cross-Contour (Surface Contour) Line Overlay

**Date:** 2026-04-02
**Status:** Planning

## Context

Add depth-driven cross-contour/surface contour lines to the depth section of the app. Isolines are traced at evenly-spaced depth levels, revealing the 3D surface form of foreground objects. Lines overlay the image (like the existing grid) and only appear on non-background subjects. The feature mirrors the existing grid overlay pattern: normalized `GridLineSegment` arrays, `Canvas`-based rendering, auto-contrast coloring, and export support.

---

## Architecture Overview

```
depthMap changes / config changes
    → AppState.recomputeContours()  [background Task]
        → ContourGenerator.generateSegments()   [new file]
            → sample depth map at 200×200 grid
            → marching squares at N thresholds
            → [GridLineSegment] in [0,1] coords
        → contourSegments = segs  [MainActor]

SwiftUI render
    → StudyImageLayer → ContourOverlayView  [new file]
        → ContourLineColorResolver.resolvedSegments()  [new file]
        → Canvas draws segments

Export
    → AppState.exportCurrentImage() → renderContoursOnto()
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `ios/RefPlane/Support/ContourGenerator.swift` | Marching squares algorithm |
| `ios/RefPlane/Support/ContourLineColorResolver.swift` | Color resolution (reuses GridLineColorResolver) |
| `ios/RefPlane/Views/ContourOverlayView.swift` | Canvas overlay (mirrors GridOverlayView) |
| `ios/RefPlane/Views/ContourSettingsView.swift` | Settings UI (mirrors GridSettingsView) |

---

## Files to Modify

| File | Change |
|------|--------|
| `ios/RefPlane/Models/AppModels.swift` | Add `ContourConfig` struct |
| `ios/RefPlane/Models/AppState.swift` | Add config, segments, `recomputeContours()`, `renderContoursOnto()`, update export |
| `ios/RefPlane/Views/DepthSettingsView.swift` | Embed `ContourSettingsView` when depth + depthMap available |
| `ios/RefPlane/Views/ImageCanvasView.swift` | Add `showsContours` to `StudyImageLayer`, pass at call site |
| `ios/RefPlane/Views/CompareView.swift` | Update `StudyImageLayer` call |
| `ios/RefPlane.xcodeproj/project.pbxproj` | Register 4 new source files |

---

## Step 1 — `ContourConfig` in `AppModels.swift`

Add after `struct DepthConfig` (line 196):

```swift
struct ContourConfig {
    var enabled: Bool        = false
    var levels: Int          = 5          // number of isoline levels (2–12)
    var lineStyle: LineStyle = .autoContrast
    var customColor: Color   = .white
    var opacity: Double      = 0.7
}
```

`LineStyle` already exists and is shared with `GridConfig` — no new enum needed.

---

## Step 2 — `ContourGenerator.swift` (new file)

**Algorithm:** Marching squares on a 200×200 cell grid sampled from the depth map.

**Threshold computation** — contours span the visible (non-background) zone only:
```swift
let lo = depthRange.lowerBound
let hi = min(backgroundCutoff, depthRange.upperBound)
// levels thresholds evenly placed inside the open interval (lo, hi)
threshold[i] = lo + (hi - lo) * Double(i + 1) / Double(levels + 1)
// for i in 0..<levels
```

This mirrors how `defaultThresholds(for:)` distributes value levels — evenly spaced, never landing exactly on a boundary.

**Depth sampling:**
- Draw `depthMap` into a 201×201 single-channel `CGContext` (grayscale, `CGColorSpaceCreateDeviceGray()`)
- Read the pixel buffer to produce a `[Double]` vertex grid of size (gridW+1) × (gridH+1)

**Per-cell marching squares logic** (200×200 cells × N thresholds):
- Skip cell if all 4 corners ≥ backgroundCutoff (background zone)
- For each threshold `t`, compute 4-bit case index:
  `(tl<t ? 8:0) | (tr<t ? 4:0) | (br<t ? 2:0) | (bl<t ? 1:0)`
- Look up 16-case table → 0, 1, or 2 segment endpoints per cell
- Use **linear interpolation** on each crossing edge for sub-cell precision:
  e.g. top edge: `x = col + (t - tl) / (tr - tl)`
- Saddle cases (5 and 10): disambiguate using avg of 4 corners to pick correct pair
- Convert to normalized [0,1] coords: divide by gridW/gridH

**Signature:**
```swift
enum ContourGenerator {
    static func generateSegments(
        depthMap: UIImage,
        levels: Int,
        depthRange: ClosedRange<Double>,
        backgroundCutoff: Double
    ) -> [GridLineSegment]
}
```

---

## Step 3 — `ContourLineColorResolver.swift` (new file)

For `.autoContrast`, use a proxy `GridConfig` to delegate to `GridLineColorResolver.resolvedSegments`. This reuses the private `ImageLuminanceSampler` without duplicating it. The `divisions` and `showDiagonals` fields are irrelevant to color resolution.

```swift
enum ContourLineColorResolver {
    static func resolvedSegments(
        config: ContourConfig,
        image: UIImage?,
        segments: [GridLineSegment]
    ) -> [ResolvedGridLineSegment] {
        switch config.lineStyle {
        case .black:
            return segments.map { ResolvedGridLineSegment(segment: $0, color: .black) }
        case .white:
            return segments.map { ResolvedGridLineSegment(segment: $0, color: .white) }
        case .custom:
            return segments.map { ResolvedGridLineSegment(segment: $0, color: config.customColor) }
        case .autoContrast:
            let proxy = GridConfig(enabled: true, divisions: 0, showDiagonals: false,
                                   lineStyle: .autoContrast, customColor: config.customColor,
                                   opacity: config.opacity)
            return GridLineColorResolver.resolvedSegments(config: proxy, image: image, segments: segments)
        }
    }
}
```

---

## Step 4 — `ContourOverlayView.swift` (new file)

Mirrors `GridOverlayView.swift` exactly, replacing grid logic with contour logic:
- Reads `state.contourSegments` (pre-computed — no heavy work in the Canvas closure)
- Calls `ContourLineColorResolver.resolvedSegments()`
- `StrokeStyle(lineWidth: 0.6, lineCap: .round)` — round caps suit organic contour lines
- `.allowsHitTesting(false)`

---

## Step 5 — `ContourSettingsView.swift` (new file)

Mirrors `GridSettingsView.swift`:
- `Toggle("Surface Contours", ...)` — calls `state.recomputeContours()` on change
- `LabeledSlider("Levels", range: 2...12, step: 1)` — calls `state.recomputeContours()` on drag end
- `Picker("Line Style", ...)` using `LineStyle.allCases`
- `ColorPicker` shown only when `.custom`
- `LabeledSlider("Opacity", range: 0...1)`

---

## Step 6 — `AppState.swift` additions

**New properties:**
```swift
@Published var contourConfig: ContourConfig = ContourConfig()
@Published var contourSegments: [GridLineSegment] = []
private var contourTask: Task<Void, Never>? = nil
private var contourGeneration: Int = 0
```

**`recomputeContours()` method:**
```swift
func recomputeContours() {
    contourTask?.cancel()
    guard contourConfig.enabled, let depth = depthMap else {
        contourSegments = []
        return
    }
    contourGeneration += 1
    let gen = contourGeneration
    let cfg = contourConfig
    let depthCfg = depthConfig
    let range = depthRange
    contourTask = Task {
        let segs = await Task.detached(priority: .userInitiated) {
            ContourGenerator.generateSegments(
                depthMap: depth,
                levels: cfg.levels,
                depthRange: range,
                backgroundCutoff: depthCfg.backgroundCutoff
            )
        }.value
        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard self.contourGeneration == gen else { return }
            self.contourSegments = segs
        }
    }
}
```

**Invalidation call sites:**
- `computeDepthMap()` — call `recomputeContours()` after `self.depthMap = result`
- `resetDepthProcessing()` — set `contourSegments = []`
- `loadImage(_:)` — set `contourSegments = []`
- **Do NOT** call during threshold preview drag — only on drag end (matching the pattern of `applyDepthEffects()` in `DepthSettingsView`'s `onEditingChanged`)

**`exportCurrentImage()` update:**
```swift
func exportCurrentImage() -> UIImage? {
    // existing base selection logic (unchanged)...
    guard let image = base else { return nil }
    var rendered = image
    if gridConfig.enabled { rendered = renderGridOnto(rendered) }
    if contourConfig.enabled && !contourSegments.isEmpty {
        rendered = renderContoursOnto(rendered)
    }
    return rendered
}

private func renderContoursOnto(_ image: UIImage) -> UIImage {
    // Mirrors renderGridOnto — UIGraphicsImageRenderer + CoreGraphics
    // Uses ContourLineColorResolver.resolvedSegments()
    // lineCap: .round, lineWidth: max(1.0, min(size.width, size.height) / 1000.0)
}
```

---

## Step 7 — `DepthSettingsView.swift`

Inside `if state.depthConfig.enabled { ... }`, after the Intensity slider:

```swift
if state.depthMap != nil {
    ContourSettingsView()
}
```

No changes to `ControlPanelView.swift` — contours inherit the existing `Section("Depth")`.

---

## Step 8 — `ImageCanvasView.swift` + `CompareView.swift`

**`StudyImageLayer` signature change:**
```swift
struct StudyImageLayer: View {
    let image: UIImage
    let showsGrid: Bool
    let showsContours: Bool   // new

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsGrid { GridOverlayView(image: image) }
            if showsContours { ContourOverlayView(image: image) }  // new
        }
    }
}
```

**Call site in `ImageCanvasView.swift` (line ~58):**
```swift
StudyImageLayer(
    image: image,
    showsGrid: state.gridConfig.enabled,
    showsContours: state.contourConfig.enabled && state.depthConfig.enabled
)
```

**Call sites in `CompareView.swift`:**
```swift
// after image:
StudyImageLayer(image: afterImage, showsGrid: state.gridConfig.enabled,
                showsContours: state.contourConfig.enabled && state.depthConfig.enabled)
// before image:
StudyImageLayer(image: beforeImage, showsGrid: false, showsContours: false)
```

---

## Step 9 — Xcode project file (`project.pbxproj`)

Add `PBXFileReference` + `PBXBuildFile` entries for the 4 new Swift files. Add file references to their groups (Support, Views). Add build file refs to the main target's Sources build phase.

Recommended approach: add the files to the Xcode project via the UI after creating them, which handles pbxproj edits automatically. Alternatively, edit pbxproj manually following the existing UUID naming conventions.

---

## Key Implementation Notes

1. **Marching squares saddle cases (5 and 10):** Average the 4 corner depth values. If average < threshold, connect top↔right and bottom↔left; otherwise connect top↔left and bottom↔right.

2. **No recompute during slider drag:** `recomputeContours()` is expensive (background task). Call it only in `onEditingChanged: { editing in if !editing { ... } }` — never in the slider's `set:` closure during dragging.

3. **`GridLineSegment` is a value type (struct):** Safe to publish across tasks without additional synchronization.

4. **Background zone exclusion:** Cells where all 4 corners ≥ `backgroundCutoff` are skipped entirely. Cells straddling the boundary are processed normally, producing a clean edge where contours meet the background.

5. **Grid resolution (200×200):** Fine enough for meaningful detail on typical photos, fast enough to run in ~50 ms. The depth map is already full-res; we downsample to 200×200 only for the marching squares grid.

---

## Verification Checklist

- [ ] Enable Depth Effects → depth map computed
- [ ] "Surface Contours" toggle appears below Intensity slider
- [ ] Enable Surface Contours → contour lines appear as overlay on foreground/midground only
- [ ] Levels slider (2–12) updates contour count after drag end
- [ ] Line Style: Auto/Black/White/Custom all work correctly
- [ ] Toggling off Depth Effects hides contour overlay
- [ ] Background cutoff slider change → contours recompute correctly after release
- [ ] Export → contour lines baked into the exported image
- [ ] Compare mode → contours on "after" panel, not "before"
- [ ] No contour lines bleed into letterbox/padding areas
