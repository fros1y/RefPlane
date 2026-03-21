# Simplification Pipeline Design

## Problem

Bilateral filtering is currently duplicated across three processing paths (value study, color regions, simplified edges), each with its own `strength` parameter. This couples smoothing to analysis, prevents sharing the smoothed result across stages, and makes it hard to add new simplification algorithms.

## Solution

Extract smoothing into a first-class **simplification stage** that sits between source image and analysis in the processing pipeline. The worker caches the simplified result so downstream stages (analysis, edges) run from cache without re-simplifying.

## Pipeline

```
Source → [Crop] → [Simplify] → [Analyze] → [Overlay: Edges + Grid] → Export
```

Each stage feeds the next. Changing simplification re-runs everything downstream. Changing analysis settings skips simplification and runs from cache.

## Types

```typescript
export type SimplifyMethod = "none" | "bilateral" | "kuwahara" | "mean-shift" | "anisotropic";

export interface SimplifyConfig {
  method: SimplifyMethod;
  strength: number; // 0-1, maps to method-specific params
  bilateral: { sigmaS: number; sigmaR: number };
  kuwahara: { kernelSize: number };
  meanShift: { spatialRadius: number; colorRadius: number };
  anisotropic: { iterations: number; kappa: number };
}
```

Changes to existing types:
- `ValueConfig`: remove `strength`
- `ColorConfig`: remove `strength`
- `EdgeConfig`: remove `"simplified"` from `EdgeMethod`

## Worker Cache

```typescript
let cachedSimplified: {
  sourceHash: number;
  config: SimplifyConfig;
  imageData: ImageData;
  labData: Float32Array | null;
} | null = null;
```

New worker message:
```typescript
{ type: 'simplify'; imageData: ImageData; config: SimplifyConfig; requestId: number }
```

Value-study and color-regions messages receive pre-simplified image data.

## Algorithms

All algorithms take ImageData and return ImageData. They preserve edges while reducing detail.

### Bilateral Filter (existing, relocated)
- Spatial + range kernels: `weight = exp(-(spatialDist/sigmaS²) - (valueDiff²/sigmaR²))`
- GPU path exists via `bilateralGrayShader`
- Advanced params: `sigmaS` (spatial spread), `sigmaR` (range tolerance)

### Kuwahara Filter (new)
- Examines 4 overlapping quadrants of size `kernelSize` around each pixel
- Assigns pixel the mean of the quadrant with lowest variance
- Produces painterly, flat-color look with preserved edges
- CPU-only initially
- Advanced param: `kernelSize` (3-15)

### Mean-Shift Filter (new)
- Iteratively shifts each pixel toward local mode in (x, y, R, G, B) space
- Convergence: shift < 1.0 in color distance; max 10 iterations per pixel
- Naturally groups similar nearby colors
- CPU-only
- Advanced params: `spatialRadius`, `colorRadius`

### Anisotropic Diffusion / Perona-Malik (new)
- Iterative PDE: smooth along edges, not across them
- Diffusion function: `g(∇I) = exp(-(|∇I|/κ)²)`
- CPU-only initially
- Advanced params: `iterations` (1-30), `kappa` (gradient threshold)

### Strength-to-params mapping

| Strength | Bilateral | Kuwahara | Mean-Shift | Anisotropic |
|----------|-----------|----------|------------|-------------|
| 0.0 | sigmaS=2, sigmaR=0.05 | kernel=3 | spatial=5, color=10 | iter=1, κ=30 |
| 0.5 | sigmaS=10, sigmaR=0.15 | kernel=7 | spatial=15, color=25 | iter=10, κ=20 |
| 1.0 | sigmaS=25, sigmaR=0.35 | kernel=15 | spatial=30, color=50 | iter=30, κ=10 |

Advanced panel lets users override derived values.

## Reactivity

```typescript
// Source or simplify config changes → re-simplify (debounced 120ms), then re-analyze
useEffect(() => { triggerSimplify(); }, [sourceImageData.value, simplifyConfig.value]);

// Simplified result arrives or analysis config changes → re-analyze only
useEffect(() => { triggerAnalysis(); }, [simplifiedImageData.value, activeMode.value, valueConfig.value, colorConfig.value]);
```

New signals:
- `simplifyConfig: Signal<SimplifyConfig>`
- `simplifiedImageData: Signal<ImageData | null>`
- `processingProgress: Signal<{ stage: string; percent: number } | null>`

## Global Progress Reporting

Worker sends progress from any long-running stage:

```typescript
{ type: 'progress', stage: string, percent: number, requestId: number }
```

Algorithms report progress at natural intervals:

| Method | Granularity | Updates |
|--------|-------------|---------|
| Bilateral | Per row-batch (~50 rows) | ~10-20 |
| Kuwahara | Per row-batch (~50 rows) | ~10-20 |
| Mean-Shift | Per pixel-batch + convergence pass | ~10-20 |
| Anisotropic | Per iteration | 1-30 |

Shared `reportProgress(stage, percent)` helper in worker. Any pipeline stage (simplify, analysis, edges) can use it.

UI shows a global progress indicator (thin bar or percentage) when `processingProgress` is non-null. Cleared when final result arrives or new request supersedes.

## UI

New "Simplify" panel card in sidebar between Modes and Overlays:

```
┌─ Simplify ─────────────── [Pre] ──┐
│  Method: [None ▾ Bilateral ▾ ...] │
│  Strength: ────●──────── 0.5      │
│  ▶ Advanced                       │
│    ┌─ sigmaS: ──●── 10 ─────┐    │
│    │  sigmaR: ──●── 0.15    │    │
│    └─────────────────────────┘    │
└───────────────────────────────────┘
```

- Method selector: None, Bilateral, Kuwahara, Mean-Shift, Anisotropic
- Strength slider: visible when method is not "none"
- Advanced toggle: expandable, shows raw params for selected method; params update when strength moves but can be manually overridden
- When method is "none", collapses to just the selector

Removed from existing panels:
- ValueSettings: Smoothing slider removed
- ColorSettings: Smoothing slider removed
- EdgeSettings: "simplified" method option removed

## File Organization

New directory `src/processing/simplify/` containing:
- `index.ts` — dispatcher: takes SimplifyConfig, routes to correct algorithm
- `bilateral.ts` — relocated from `src/processing/bilateral.ts`
- `kuwahara.ts` — new
- `mean-shift.ts` — new
- `anisotropic.ts` — new
- `params.ts` — strength-to-params mapping for all methods

New component:
- `src/components/SimplifySettings.tsx`
