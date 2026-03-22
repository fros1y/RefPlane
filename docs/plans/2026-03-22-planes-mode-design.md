# Planes Mode Design

**Date:** 2026-03-22  
**Status:** Approved

## Motivation

RefPlane's existing Value Study mode groups pixels by luminance bands, but this is a global operation — all pixels at a given luminance end up in the same band regardless of spatial location. For painting reference, what artists actually need is identification of **planes**: spatially coherent regions of similar color and value that correspond to the surfaces of forms as they catch light.

Planes are closely linked to **light families** (light, halftone, core shadow, reflected light, cast shadow). Each plane's orientation to the light source determines which family it belongs to. The Planes mode decomposes an image into these spatially coherent color/value regions.

## Algorithm: SLIC Superpixels + RAG Merging

Two-phase approach operating on the simplified image (post-simplify cache).

### Phase 1 — SLIC Superpixels

[Simple Linear Iterative Clustering](https://en.wikipedia.org/wiki/Simple_linear_iterative_clustering) in 5D OkLab+spatial space.

1. Convert simplified image to OkLab.
2. Initialize a grid of cluster centers. Target count: `sqrt(pixelCount / targetSuperpixelSize)` where `targetSuperpixelSize ≈ 200–500 pixels`.
3. Each pixel is a 5D vector: `[L, a, b, x/S, y/S]` where `S` is the grid step size and `x, y` are normalized by `S`.
4. A **compactness** parameter `m` weights spatial vs. color distance in the combined metric: `D = sqrt(d_color² + (m/S)² * d_spatial²)`.
5. 5–10 iterations of local K-means: each pixel only searches a `2S × 2S` window around its nearest cluster center, making the algorithm O(N) per iteration.
6. **Cancellation**: check `abortSignal?.aborted` at row boundaries; yield to event loop every ~8 rows.
7. **Output**: per-pixel label array (`Uint32Array`) + per-superpixel average OkLab color.

### Phase 2 — Region Adjacency Graph (RAG) Merging

1. Build adjacency graph: for each pair of neighboring superpixels, compute edge weight = OkLab Euclidean distance between their average colors.
2. Use a priority queue (min-heap): repeatedly merge the most-similar adjacent pair.
3. On merge: update the merged region's average color (area-weighted), recompute neighbor distances.
4. **Stop** when the minimum edge weight exceeds a `mergeThreshold` derived from the user's **detail** slider.
5. **Output**: final label map (`Uint32Array`) + palette of merged-region average OkLab colors, converted to sRGB for display.

### Optional: Light Family Labeling (Nice-to-Have)

After merging, classify each plane by average luminance:
- **Light**: L > 0.7
- **Halftone**: 0.3 ≤ L ≤ 0.7
- **Shadow**: L < 0.3

These labels can feed into band isolation for "show me just the halftone planes."

## Pipeline Integration

```
Source → [Crop] → [Simplify] → [Planes Analysis] → [Overlay: Edges + Grid] → Export
```

Planes is an analysis mode consuming `simplifiedImageData`, identical in position to Value Study and Color Regions. Pre-simplification smooths out texture/noise, producing cleaner superpixels.

## Configuration

```typescript
interface PlanesConfig {
  detail: number;       // 0–1. 0 = few bold planes, 1 = many fine planes
  compactness: number;  // 0–1. 0 = follow edges closely, 1 = regular grid-like regions
}
```

### Detail → Merge Threshold Mapping

| detail | mergeThreshold (OkLab distance) | Approximate result |
|--------|--------------------------------|-------------------|
| 0.0    | ~0.02                          | 5–15 bold planes  |
| 0.5    | ~0.06                          | 30–60 planes      |
| 1.0    | ~0.15                          | 100+ fine planes   |

Values are approximate; will be tuned against real images.

### Compactness → Spatial Weight Mapping

| compactness | m (spatial weight) | Effect |
|-------------|-------------------|--------|
| 0.0         | 5                 | Loose, follows color boundaries tightly |
| 0.5         | 20                | Balanced |
| 1.0         | 40                | Very regular, grid-like |

## UI

### PlanesSettings Component

Visible when `activeMode === 'planes'`. Two sliders:

- **Detail** (0–1, default 0.5) — labeled endpoints: "Bold" ← → "Fine"
- **Compactness** (0–1, default 0.5) — labeled endpoints: "Organic" ← → "Regular"

### ModeBar

Add `'planes'` button with label **"Planes"** after Color Regions.

## Worker Integration

### Message Type

```typescript
case 'planes': {
  const { imageData, config, requestId } = msg;
  const result = await computePlanes(imageData, config, onProgress, abortSignal);
  postMessage({
    type: 'result',
    requestType: 'planes',
    result: result.imageData,
    palette: result.palette,
    requestId,
    meta
  });
}
```

### Progress Reporting

Split ~70/30 between SLIC (Phase 1) and RAG merge (Phase 2):
- Phase 1: reports per-iteration progress (5–10 updates)
- Phase 2: reports per-merge-step (less frequent, Phase 2 is faster)

### Cancellation

Follows the existing cooperative cancellation pattern via `AbortSignal`. Checks at row boundaries during SLIC iterations and yields to event loop every ~8 rows via `yieldToEventLoop()`.

## Reactivity (app.tsx)

- Add `planesConfig` signal (default `{ detail: 0.5, compactness: 0.5 }`)
- When `activeMode === 'planes'` and `simplifiedImageData` changes → dispatch `'planes'` to worker
- When `planesConfig` changes while mode is planes → re-dispatch
- Result feeds `processedImage`; palette feeds `paletteColors` / `swatchBands`

## Compositing & Display

No new compositing code needed. Reuses existing compositor:
- **Base layer**: flat-color ImageData (each pixel painted with its plane's average color)
- **Edge overlay**: Canny/Sobel on the simplified image (existing)
- **Grid overlay**: existing
- **Band isolation**: clicking a swatch in PaletteStrip highlights that plane, dims others (existing)
- **Temperature map**: works on plane-averaged luminance values (existing)

## Export

No changes. Export composites whatever `processedImage` contains, with overlays.

## File Changes

| Action | File | Description |
|--------|------|-------------|
| New | `src/processing/planes.ts` | SLIC + RAG merge algorithm |
| New | `src/components/PlanesSettings.tsx` | Detail + compactness sliders |
| Modify | `src/types.ts` | Add `'planes'` to Mode union, `PlanesConfig` interface |
| Modify | `src/processing/worker.ts` | Add `'planes'` message handler |
| Modify | `src/components/ModeBar.tsx` | Add Planes button |
| Modify | `src/app.tsx` | Add `planesConfig` signal, wire reactivity, dispatch |

## Performance Considerations

- SLIC is O(N) per iteration with ~5–10 iterations — fast even on large images
- RAG merge is O(S log S) where S = superpixel count (~500), negligible
- No GPU acceleration needed initially; SLIC's local search pattern could be GPU-accelerated later if needed
- Pre-simplification (especially bilateral or kuwahara) significantly improves superpixel quality by removing texture noise

## Alternatives Considered

1. **Mean-shift segmentation in joint (x,y,L,a,b) space** — O(N²) naive, too slow for interactive use
2. **Felzenszwalb graph-based segmentation** — O(N log N) but produces irregular, spindly regions less useful for painting reference
3. **SLIC + RAG (chosen)** — best balance of speed, boundary quality, and user control
