# Plane-Guided Simplification Implementation Plan

> **For agentic workers:** Execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use the existing planes detection pipeline to improve image simplification in two ways: add a new `plane-fill` simplification method that flat-fills detected planes with representative colors, and make `Kuwahara` and `SLIC` respect detected plane boundaries so they do not smooth or cluster across major surface transitions.

**Architecture:** Promote planes detection from a render-only endpoint into a reusable guidance layer. A cached `PlaneGuidance` artifact is derived from the source image's depth map and shared by both planes mode and simplification. The guidance contains cleaned plane labels and plane metadata. Depth estimation remains lazy and cached per source image.

**Tech Stack:** Preact + Preact Signals, TypeScript, Web Workers, existing Depth Anything v2 integration, existing CPU/WebGPU processing stack, Vitest

**Design basis:** Extends the approved planes-mode design in `docs/plans/2026-03-23-planes-mode-design.md` and the approved follow-on design discussion from 2026-03-23.

---

## Scope

### In scope

- Add a new simplification method: `plane-fill`
- Add configurable plane color strategy: `average`, `median`, `dominant`
- Add plane-boundary-aware variants of `Kuwahara` and `SLIC`
- Reuse cached depth results and derive reusable `PlaneGuidance`
- Sample `plane-fill` colors from the source image
- Rename `SLIC Planes` UI copy so it does not conflict with actual detected planes
- Add unit coverage for guidance extraction and plane-aware simplification

### Out of scope

- Gradient or textured fills inside planes
- Plane-aware support for every simplification method
- GPU acceleration for plane-aware `Kuwahara` in the first pass
- Replacing the existing planes render mode

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `src/processing/plane-guidance.ts` | Shared extraction helpers for cleaned labels and per-plane metadata |
| `src/processing/simplify/plane-fill.ts` | `planeFillFilter` implementation: representative color strategies and flat-fill rendering |
| `tests/unit/plane-guidance.test.ts` | Unit tests for guidance extraction and label cleanup |
| `tests/unit/simplify/plane-fill.test.ts` | Unit tests for representative color strategies and plane fill rendering |

### Modified Files

| File | Change |
|------|--------|
| `src/types.ts` | Add `plane-fill` simplify method and plane-guidance-related config/types |
| `src/app.tsx` | Add default plane-guided simplification settings and wire UI changes |
| `src/components/SimplifySettings.tsx` | Add `plane-fill` method, color strategy control, boundary-aware toggle, rename SLIC label |
| `src/hooks/useProcessingPipeline.ts` | Cache `PlaneGuidance`, request it lazily, and pass it into simplify requests when needed |
| `src/processing/worker-protocol.ts` | Extend `simplify` request shape with optional `planeGuidance` payload |
| `src/processing/worker.ts` | Forward optional plane guidance into simplification |
| `src/processing/planes.ts` | Refactor planes processing to expose reusable labels/centroids instead of only final shading |
| `src/processing/simplify/index.ts` | Route `plane-fill` and plane-aware requests to the correct implementations |
| `src/processing/simplify/kuwahara.ts` | Add optional plane-label barriers for sample collection |
| `src/processing/simplify/slic.ts` | Constrain assignment and merging to detected planes |
| `src/processing/simplify/params.ts` | Handle `plane-fill` in `strengthToMethodParams` (return empty object) |
| `tests/unit/simplify/dispatcher.test.ts` | Cover `plane-fill` dispatch and plane-aware simplify routing |
| `tests/unit/simplify/kuwahara.test.ts` | Add plane-boundary preservation tests |
| `tests/unit/simplify/slic.test.ts` | Add plane-boundary preservation tests |

---

## Architecture Changes

### Shared `PlaneGuidance` artifact

Add a reusable processing type that captures the structure simplification needs:

```typescript
export type PlaneColorStrategy = 'average' | 'median' | 'dominant';

export interface PlaneGuidance {
  width: number;
  height: number;
  labels: Uint8Array;
  planeCount: number;
}
```

Notes:

- `labels` should represent cleaned plane regions, not raw k-means output.
- `Uint8Array` matches the existing `clusterNormals` return type and is sufficient for `PlanesConfig.planeCount` (max 30).
- No `boundaryMask` field in v1 — all consumers (`kuwaharaFilter`, `slicFilter`, `planeFillFilter`) compare labels directly, making a separate mask redundant. Add it later if a consumer needs pre-computed boundary pixels.

### Simplify config expansion

Extend `SimplifyConfig` so the UI and pipeline can express both new behaviors:

```typescript
export type SimplifyMethod =
  | 'none'
  | 'bilateral'
  | 'kuwahara'
  | 'mean-shift'
  | 'anisotropic'
  | 'painterly'
  | 'slic'
  | 'plane-fill';

export interface SimplifyConfig {
  // existing fields...
  planeFill: {
    colorStrategy: PlaneColorStrategy;
  };
  planeGuidance: {
    preserveBoundaries: boolean;
  };
}
```

Behavior rules:

- `method === 'plane-fill'` always requires plane guidance
- `planeGuidance.preserveBoundaries` only affects supported methods in v1: `kuwahara` and `slic`
- Unsupported methods ignore the toggle

### Conventions

**Typed array transfer:** When sending `PlaneGuidance` to the worker via the simplify channel, clone the backing `labels` array (`new Uint8Array(guidance.labels)`) and transfer the clone. The pipeline retains its cached original so guidance is not consumed.

**`strengthToMethodParams` handling:** `plane-fill` does not use a strength slider. `strengthToMethodParams('plane-fill', n)` should return `{}` to avoid runtime errors from the existing mapping logic.

**Depth trigger expansion:** The current depth estimation effect in `useProcessingPipeline.ts` guards on `activeMode.value !== 'planes'`. This guard must be expanded to also trigger depth when the simplify config requires plane guidance. The same progress UI ("Downloading depth model...") should display regardless of which feature triggered depth.

### Pipeline shape

The target data flow becomes:

```text
Source ──┬── [Depth Worker] ──────────────→ Depth Map ──→ [Plane Guidance] ──┐
         │                                                                   ├── [Planes Mode Render]
         └── [Simplify Worker + optional Plane Guidance] ─────────────────────┘
```

Key decisions:

1. Guidance is extracted from the source image's depth result, not from the simplified image.
2. Guidance is cached alongside depth and invalidated on source image change or crop.
3. `plane-fill` samples colors from the original source image.
4. Existing planes mode should be refactored to consume the same reusable labels where possible.

---

## Task 1: Types and Config Surface

**Files:**
- Modify: `src/types.ts`
- Modify: `src/app.tsx`

- [ ] **Step 1: Add plane-guided simplification types**

In `src/types.ts`:

- Add `PlaneColorStrategy`
- Add `PlaneGuidance` (with `labels: Uint8Array`, no `boundaryMask`)
- Add `'plane-fill'` to `SimplifyMethod`
- Add `planeFill` and `planeGuidance` sections to `SimplifyConfig`

- [ ] **Step 2: Initialize defaults in app state**

In `src/app.tsx`:

- Add default `planeFill.colorStrategy = 'average'`
- Add default `planeGuidance.preserveBoundaries = false`

- [ ] **Step 3: Handle `plane-fill` in `strengthToMethodParams`**

In `src/processing/simplify/params.ts`:

- Add a `'plane-fill'` case that returns `{}` (no strength-driven parameters)

- [ ] **Step 4: Verify type fallout**

```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane
npx tsc --noEmit
```

Expected:

- type errors in simplify UI and dispatcher until later tasks are complete
- no type errors in the new core type definitions themselves

---

## Task 2: Extract Reusable Plane Guidance

**Files:**
- Create: `src/processing/plane-guidance.ts`
- Modify: `src/processing/planes.ts`
- Create: `tests/unit/plane-guidance.test.ts`

- [ ] **Step 1: Add failing tests for label cleanup**

Cover at least:

- label cleanup merges or removes tiny isolated fragments (connected-component analysis)
- single-pixel orphan labels are absorbed into their largest neighbor
- output dimensions match the requested image dimensions

- [ ] **Step 2: Refactor planes processing to expose reusable intermediate data**

In `src/processing/planes.ts`:

- keep the existing planes render entrypoint
- extract helpers that return clustered labels before shading
- avoid duplicating depth smoothing and normal clustering logic

Suggested split:

```typescript
export interface PlaneSegmentation {
  labels: Uint8Array;          // matches clusterNormals return type
  centroids: Float32Array;     // k × 3 stride (nx, ny, nz per centroid)
  width: number;
  height: number;
}

export function segmentPlanes(
  depth: Float32Array,
  width: number,
  height: number,
  config: PlanesConfig,
): PlaneSegmentation;
```

Note: `clusterNormals` already returns `labels: Uint8Array`. The new `segmentPlanes` wraps `bilateralDepthSmooth → computeNormals → clusterNormals` and returns the result directly.

- [ ] **Step 3: Implement `buildPlaneGuidance` in `plane-guidance.ts`**

Responsibilities:

- consume clustered plane labels (`Uint8Array`) from `segmentPlanes`
- clean labels into stable plane regions via connected-component small-region merge on the label array (not via `cleanupRegions`, which operates on `ImageData` pixel colors and cannot be applied to typed label arrays)
- return a `PlaneGuidance` object

Implementation notes:

- use 4-connected flood fill on the `Uint8Array` labels to identify connected components
- merge components below a size threshold into their largest adjacent neighbor
- this is a new algorithm — `cleanupRegions` in `regions.ts` works on RGBA `ImageData` and is not reusable here

- [ ] **Step 4: Update planes mode to reuse the refactored segmentation path**

Refactor `processPlanes` to call `segmentPlanes` internally, then continue with `shadePlanes(labels, centroids, ...) → cleanupRegions(shaded, ...)`. This is a one-line change to the entry point.

- [ ] **Step 5: Run tests**

```bash
npx vitest run tests/unit/plane-guidance.test.ts tests/unit/planes.test.ts
```

Expected: new guidance tests pass, existing planes tests still pass

---

## Task 3: Add `plane-fill` Simplification

**Files:**
- Create: `src/processing/simplify/plane-fill.ts`
- Create: `tests/unit/simplify/plane-fill.test.ts`
- Modify: `src/processing/simplify/index.ts`

Rationale: `planeFillFilter` is a pure function with no pipeline or worker dependencies. Implementing and testing it before wiring the pipeline gives an early verifiable checkpoint.

- [ ] **Step 1: Add failing tests for representative color strategies**

Cover at least:

- `average` returns the mean plane color
- `median` ignores a small outlier better than average
- `dominant` selects the most frequent quantized color bin
- output is strictly flat within each plane region

- [ ] **Step 2: Implement `planeFillFilter`**

Create `src/processing/simplify/plane-fill.ts`:

```typescript
export function planeFillFilter(
  imageData: ImageData,
  guidance: PlaneGuidance,
  strategy: PlaneColorStrategy,
): ImageData;
```

Implementation notes:

- iterate plane-by-plane over `guidance.labels`
- use source image pixels directly from `imageData`
- write one solid RGB value per plane
- preserve alpha as fully opaque, consistent with the rest of the simplify pipeline
- for `dominant`: quantize into 32×32×32 RGB bins and pick the most frequent bin per plane

- [ ] **Step 3: Add `plane-fill` to the simplify dispatcher**

In `src/processing/simplify/index.ts`:

- route `plane-fill` through `planeFillFilter`
- throw a clear error if `plane-fill` is requested without `planeGuidance`
- bypass GPU for this method in v1

- [ ] **Step 4: Run tests**

```bash
npx vitest run tests/unit/simplify/plane-fill.test.ts tests/unit/simplify/dispatcher.test.ts
```

---

## Task 4: Pipeline Caching, Worker Protocol, and UI

**Files:**
- Modify: `src/hooks/useProcessingPipeline.ts`
- Modify: `src/processing/worker-protocol.ts`
- Modify: `src/processing/worker.ts`
- Modify: `src/components/SimplifySettings.tsx`
- Modify: `src/app.tsx`

Rationale: Merges original Tasks 3 (Pipeline) and 7 (UI) because the UI and pipeline wiring are tightly coupled — neither is independently testable. Completing this task yields an end-to-end working `plane-fill` in the app.

- [ ] **Step 1: Extend simplify worker requests with optional plane guidance**

Update the simplify request type in `worker-protocol.ts` from:

```typescript
{ type: 'simplify'; imageData: ImageData; config: SimplifyConfig }
```

to:

```typescript
{
  type: 'simplify';
  imageData: ImageData;
  config: SimplifyConfig;
  planeGuidance?: PlaneGuidance;
}
```

In `worker.ts`: forward `planeGuidance` into `runSimplify` when present.

- [ ] **Step 2: Add cached guidance state to `useProcessingPipeline`**

Add:

- `planeGuidance: Signal<PlaneGuidance | null>`
- a source ref parallel to `depthSourceRef` if needed
- a helper: `requiresPlaneGuidance(simplifyConfig): boolean`

- [ ] **Step 3: Expand depth estimation trigger**

The current depth effect guards on `activeMode.value !== 'planes'` and returns early. Expand the guard:

```typescript
const needsDepth = activeMode.value === 'planes' || requiresPlaneGuidance(simplifyConfig.value);
if (!needsDepth) return;
```

This means depth model download can now trigger from simplify mode. The existing progress UI (`processingProgress`) should display the same "Downloading depth model..." / "Estimating depth..." messages regardless of which feature triggered it — no UI changes needed since the progress callback is already connected.

- [ ] **Step 4: Build guidance from depth and pass into simplify requests**

When depth completes and `requiresPlaneGuidance` is true:

1. Call `segmentPlanes` (from Task 2) on the resized depth map
2. Call `buildPlaneGuidance` on the segmentation result
3. Cache as `planeGuidance.value`

When dispatching a simplify request:

- clone the labels array: `new Uint8Array(guidance.labels)`
- transfer the clone as a transferable
- keep normal simplification paths unchanged when guidance is absent

- [ ] **Step 5: Add `plane-fill` to the method selector UI**

In `SimplifySettings.tsx`:

- Add `'plane-fill': 'Plane Fill'` to the method labels
- Rename `'slic': 'SLIC Planes'` → `'slic': 'SLIC Regions'`
- Show `Color Strategy` selector (average / median / dominant) when method is `plane-fill`
- Show `Preserve Plane Boundaries` toggle when method is `kuwahara` or `slic`
- Hide the strength slider for `plane-fill` (like SLIC today)
- Hide the toggle for unsupported methods

- [ ] **Step 6: Keep advanced controls coherent**

Rules:

- `plane-fill` does not need the generic strength slider
- `Kuwahara` and `SLIC` keep their existing parameter controls
- enabling `Preserve Plane Boundaries` does not reset existing method parameters

- [ ] **Step 7: Preserve current UX behavior**

Keep:

- depth model download progress in the existing progress UI
- no mandatory depth inference on image load
- no extra work when plane-aware features are off

---

## Task 5: Plane-Aware `Kuwahara`

**Files:**
- Modify: `src/processing/simplify/kuwahara.ts`
- Modify: `src/processing/simplify/index.ts`
- Modify: `tests/unit/simplify/kuwahara.test.ts`

- [ ] **Step 1: Add failing boundary-preservation tests**

Use a synthetic image where color is smooth across a depth boundary but plane labels split the image. Verify:

- regular `Kuwahara` can bleed across the split
- plane-aware `Kuwahara` keeps each side independent

- [ ] **Step 2: Extend `kuwaharaFilter` with optional plane labels**

Use an options object to avoid 8+ positional parameters:

```typescript
export interface KuwaharaOptions {
  onProgress?: (percent: number) => void;
  abortSignal?: AbortSignal;
  passes?: number;        // default 1
  sharpness?: number;     // default 8
  sectors?: 4 | 8;        // default 8
  planeLabels?: Uint8Array;
}

export async function kuwaharaFilter(
  imageData: ImageData,
  kernelSize: number,
  options?: KuwaharaOptions,
): Promise<ImageData>
```

This is an API-breaking change to the internal function. Update all call sites in `simplify/index.ts` and `worker.ts`.

Sampling rule:

- the center pixel's label is authoritative
- neighbor samples with a different label are skipped
- if a sector becomes empty, fall back to the center pixel rather than leaking across the boundary

- [ ] **Step 3: Update simplify dispatch**

Behavior:

- when `preserveBoundaries` is true and method is `kuwahara`, pass labels into `kuwaharaFilter`
- disable the GPU `Kuwahara` fast path for this case in v1

- [ ] **Step 4: Run tests**

```bash
npx vitest run tests/unit/simplify/kuwahara.test.ts tests/unit/simplify/dispatcher.test.ts
```

---

## Task 6: Plane-Aware `SLIC`

> This is the most complex boundary-aware integration due to SLIC's iterative center-update loop.

**Files:**
- Modify: `src/processing/simplify/slic.ts`
- Modify: `src/processing/simplify/index.ts`
- Modify: `tests/unit/simplify/slic.test.ts`

- [ ] **Step 1: Add failing tests for label-constrained segmentation**

Verify:

- regions never cross a supplied plane boundary
- RAG merging does not merge components with different plane labels
- when no guidance is supplied, current behavior is unchanged

- [ ] **Step 2: Constrain assignment by plane label**

Implementation rule:

- each pixel may only be assigned to centers that belong to the same detected plane

Practical approach:

- add a `planeLabel: number` field to the `Superpixel` interface
- at initialization, set each center's `planeLabel` from the plane guidance label at its grid position
- the `planeLabel` is **fixed at initialization** and does not update even as the center's spatial position drifts during iteration — this prevents a center from migrating into another plane's territory and pulling pixels across boundaries
- during assignment, skip candidate centers whose `planeLabel` differs from the pixel's plane label

- [ ] **Step 3: Constrain RAG merging by plane label**

Implementation rule:

- do not build or merge adjacency edges across different detected plane labels

- [ ] **Step 4: Update simplify dispatch**

Behavior:

- when `preserveBoundaries` is true and method is `slic`, pass plane guidance labels into `slicFilter`

- [ ] **Step 5: Run tests**

```bash
npx vitest run tests/unit/simplify/slic.test.ts tests/unit/simplify/dispatcher.test.ts
```

---

## Task 7: Full Verification

**Files:**
- Modify tests as needed

- [ ] **Step 1: Run targeted unit tests**

```bash
npx vitest run \
  tests/unit/plane-guidance.test.ts \
  tests/unit/planes.test.ts \
  tests/unit/simplify/plane-fill.test.ts \
  tests/unit/simplify/kuwahara.test.ts \
  tests/unit/simplify/slic.test.ts \
  tests/unit/simplify/dispatcher.test.ts
```

- [ ] **Step 2: Run full typecheck**

```bash
npx tsc --noEmit
```

- [ ] **Step 3: Manual behavior checks**

Verify in the app:

1. `plane-fill` produces flat per-plane color fills
2. switching `average` / `median` / `dominant` changes plane colors without re-running depth
3. `Kuwahara` with `Preserve Plane Boundaries` enabled no longer bleeds across major form transitions
4. `SLIC Regions` with `Preserve Plane Boundaries` enabled stays inside plane regions
5. disabling plane-aware features returns to the existing fast path
6. changing source image or crop invalidates cached depth and guidance

---

## Implementation Notes and Risks

### Risk: inaccurate depth on hair, foliage, or clutter

Mitigation:

- derive barriers from cleaned labels, not raw gradients
- keep plane-aware simplification optional

### Risk: over-fragmented planes create noisy fills

Mitigation:

- apply connected-component label cleanup in `buildPlaneGuidance` before building guidance
- do not compute representative colors from raw, fragmented labels
- note: `cleanupRegions` in `regions.ts` operates on `ImageData` pixel colors and cannot be reused for label arrays — the guidance module needs its own cleanup

### Risk: GPU/CPU behavior divergence

Mitigation:

- explicitly route plane-aware `Kuwahara` to CPU in v1
- keep unmodified GPU paths for normal `Kuwahara`

### Risk: large images make `dominant` color expensive

Mitigation:

- quantize RGB bins for dominant-color counting
- compute per-plane stats in a single pass

---

### Risk: GPU planes path divergence

Mitigation:

- `worker.ts` has an existing GPU path for planes processing; `segmentPlanes` refactor only affects the CPU path
- if the GPU path has its own segmentation, guidance extraction would need a separate path — verify during Task 2 Step 4
- for v1, GPU planes rendering continues to use its own pipeline; only CPU-based guidance extraction feeds simplification

---

## Suggested Commit Breakdown

- [ ] `feat(planes): refactor planes.ts to expose segmentPlanes`
- [ ] `feat(simplify): add plane guidance types and extraction`
- [ ] `feat(simplify): add plane-fill simplification method`
- [ ] `feat(simplify): wire pipeline caching, worker protocol, and UI`
- [ ] `feat(simplify): make kuwahara respect detected plane boundaries`
- [ ] `feat(simplify): constrain slic by detected planes`
