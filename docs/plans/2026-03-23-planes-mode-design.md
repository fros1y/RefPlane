# Planes Mode — Design Document

**Date:** 2026-03-23
**Status:** Approved

## Goal

Add a "Planes" analysis mode that extracts painterly planes from any reference image — the flat directional surfaces painters use to block in form (front of forehead, side of cheek, top of nose, etc.). The output is a flat-shaded faceted rendering similar to an Asaro head study, with user control over plane granularity and light direction.

## Approach

**Depth Anything v2 via Transformers.js** running in-browser. A monocular depth estimation model produces a depth map, from which surface normals are derived and clustered into discrete plane groups. The planes are rendered with flat directional shading.

### Why this approach

- Works for any subject (faces, figures, still life, landscape)
- Depth Anything v2 small is proven in-browser via Transformers.js (~25MB model, cached in IndexedDB)
- Normal derivation + clustering + shading fit naturally into the existing WebGPU/WGSL pipeline
- The depth-to-normals softness at creases is mitigated by the clustering step (which snaps nearby normals together)

## Architecture

### Pipeline overview

```
Source ──┬── [Simplify Worker] ──→ Simplified ──┐
         │                                       ├── [Planes Analysis] → Processed
         └── [Depth Worker] ──→ Depth Map ───────┘
```

Key architectural decisions:

1. **Separate Web Worker for ML inference.** Transformers.js/ONNX Runtime is heavy — isolating it from the existing processing worker avoids blocking simplification, edges, or other modes.
2. **Depth runs on the source image**, not the simplified version. Simplification removes detail that helps depth estimation.
3. **Depth is cached per source image.** Only re-runs when the source image changes (new file or crop). Changing plane count or light direction only re-runs the clustering + shading step.

### Processing pipeline (depth → planes)

**Step 1: Depth → Surface Normals** (`depth-to-normals.wgsl`)
- Compute shader reads the depth map as a texture
- Central differences on depth values give X and Y gradients
- Cross product of gradient vectors gives the surface normal
- Output: RGB normal map (nx, ny, nz per pixel) as Float32 texture

**Step 2: Normal Clustering** (`normal-cluster.wgsl`)
- K-means clustering in normal space (each pixel's normal as a 3D unit vector)
- Iterative GPU passes: assignment + centroid update (same pattern as existing `kmeans-assign.wgsl`)
- Input: normal map + user's `planeCount` setting
- Output: label map (plane ID per pixel) + centroid normals array

**Step 3: Directional Shading** (`plane-shading.wgsl`)
- Reads label map + centroid normals + light direction vector (derived from user's azimuth/elevation)
- Per pixel: look up plane's centroid normal, compute `dot(normal, lightDir)`
- Map dot product to luminance — uniform shade per plane, no per-pixel variation
- Produces the flat faceted "Asaro head" look

**Step 4: Region Cleanup** — reuses existing `regions.ts` connected-component cleanup to merge tiny plane fragments. Controlled by the same `minRegionSize` pattern as Value/Color modes.

Steps 1–3 run as WGSL compute shaders in the existing processing worker. Only depth estimation runs in the separate ML worker.

## ML Inference Layer

### Depth Worker (`src/processing/depth-worker.ts`)

- Imports Transformers.js (`@huggingface/transformers`)
- Loads `Xenova/depth-anything-v2-small` on first request
- Accepts ImageData, returns Float32Array depth map (same dimensions)
- Reports progress: model download %, then inference status
- Model cached in IndexedDB automatically by Transformers.js

### Depth Client (`src/processing/depth-client.ts`)

- Thin wrapper matching the existing `WorkerClient` pattern
- `requestDepth(imageData): Promise<Float32Array>`
- Tracks loading state: `idle | downloading-model | running | ready`
- Model status surfaced to UI for first-time download UX

### Model loading UX

- First time: progress bar shows "Downloading depth model… 45%" via the existing `processingProgress` signal
- Subsequent loads: model is cached, inference starts immediately (~1-3s)
- Depth worker stays alive after inference — no re-loading between images

## Types & Config

### Mode union expansion

```typescript
export type Mode = "original" | "grayscale" | "value" | "color" | "planes";
```

### PlanesConfig

```typescript
export interface PlanesConfig {
  planeCount: number;        // 3–30, default 8
  lightAzimuth: number;      // 0–360 degrees, default 225 (top-left)
  lightElevation: number;    // 10–90 degrees, default 45
  minRegionSize: "off" | "small" | "medium" | "large";
}
```

- **`planeCount`**: K-means cluster count. Low (3–5) = big primary forms. Medium (8–12) = secondary planes. High (20–30) = Asaro-level detail.
- **`lightAzimuth`**: Compass direction light comes from. 225° = top-left (classic painter's lighting).
- **`lightElevation`**: Height of light. 45° = natural default.
- **`minRegionSize`**: Same control as Value/Color. Cleans up small noisy plane fragments.

## UI Components

### ModeBar

Add "Planes" button to the existing mode toggle strip. Same pattern as the other modes.

### PlanesSettings (`src/components/PlanesSettings.tsx`)

Shown in the "Adjustments" card when `activeMode === 'planes'`. Same structure as `ValueSettings`:

```
┌─ Adjustments ─────────────────────┐
│                                   │
│  Plane Count          ●───── 8    │
│  [3]                       [30]   │
│                                   │
│  Light Azimuth       ●──── 225°   │
│  [0°]                     [360°]  │
│                                   │
│  Light Elevation      ●──── 45°   │
│  [10°]                     [90°]  │
│                                   │
│  Cleanup         [off][sm][md][lg] │
│                                   │
└───────────────────────────────────┘
```

Three range sliders + the standard segmented cleanup control.

### Depth model progress

No new UI component. Pipe depth worker progress through the existing `processingProgress` signal, displayed in `ImageCanvas`'s progress bar.

## Data Flow Integration

### New signals in `useProcessingPipeline`

- `depthMap: Signal<Float32Array | null>` — cached depth output
- `depthSourceId: ref<ImageData | null>` — tracks which source image the depth belongs to

### New worker ref

- `depthClientRef` — dedicated depth worker, initialized alongside the existing processing worker

### Trigger logic

1. **Source image changes** (new file or crop) → kick off depth estimation AND simplification in parallel
2. **Depth completes** → store in `depthMap`. If mode is `planes`, trigger plane analysis.
3. **Mode switches to `planes`** → if `depthMap` exists, run plane analysis immediately. If still loading, wait.
4. **PlanesConfig changes** → re-run only clustering + shading (no depth re-estimation)

### Worker protocol

New request type `'planes'` in the `WorkerRequest` union:

```typescript
{ type: 'planes'; imageData: ImageData; depthMap: Float32Array; config: PlanesConfig }
```

Response follows the existing pattern: `{ result: ImageData }`.

### Edge compositing

Works the same as other modes — edges composite on top of planes output when enabled.

## Dependencies

- `@huggingface/transformers` — ONNX Runtime Web + model loading/caching (~2MB JS, models cached separately)
- Model: `Xenova/depth-anything-v2-small` (~25MB, cached in IndexedDB after first download)

## New files

| File | Purpose |
|------|---------|
| `src/processing/depth-worker.ts` | Dedicated ML worker for depth estimation |
| `src/processing/depth-client.ts` | Worker client wrapper for depth requests |
| `src/processing/planes.ts` | Planes analysis orchestration (CPU fallback) |
| `src/processing/shaders/depth-to-normals.wgsl` | Compute shader: depth → surface normals |
| `src/processing/shaders/normal-cluster.wgsl` | Compute shader: k-means on normal vectors |
| `src/processing/shaders/plane-shading.wgsl` | Compute shader: flat directional shading |
| `src/components/PlanesSettings.tsx` | UI controls for plane count, light, cleanup |

## Modified files

| File | Change |
|------|--------|
| `src/types.ts` | Add `'planes'` to Mode, add `PlanesConfig` |
| `src/app.tsx` | Add `planesConfig` signal, wire up `PlanesSettings` |
| `src/hooks/useProcessingPipeline.ts` | Add depth worker, depth caching, planes dispatch |
| `src/processing/worker.ts` | Handle `'planes'` request type |
| `src/processing/worker-protocol.ts` | Add planes request/response types |
| `src/components/ModeBar.tsx` | Add "Planes" button |
| `package.json` | Add `@huggingface/transformers` dependency |
