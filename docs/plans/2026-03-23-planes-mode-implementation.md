# Planes Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Planes" analysis mode that uses Depth Anything v2 to extract painterly planes from any reference image, rendered as flat-shaded facets with configurable plane count and light direction.

**Architecture:** A dedicated depth worker (Transformers.js) produces a depth map from the source image. The existing processing worker derives surface normals, clusters them into plane groups (k-means), and applies flat directional shading via WGSL compute shaders (with CPU fallback). Depth is cached per source image; config changes only re-run the lightweight shading step.

**Tech Stack:** Preact + Preact Signals, @huggingface/transformers (ONNX Runtime Web), WebGPU/WGSL compute shaders, Web Workers, Vite 7, TypeScript, Vitest

**Design doc:** `docs/plans/2026-03-23-planes-mode-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `src/processing/depth-worker.ts` | Dedicated Web Worker running Depth Anything v2 via Transformers.js |
| `src/processing/depth-client.ts` | Promise-based client for communicating with the depth worker |
| `src/processing/planes.ts` | CPU implementation: normals, k-means clustering, directional shading |
| `src/processing/shaders/depth-to-normals.wgsl` | Compute shader: depth gradients → surface normals |
| `src/processing/shaders/normal-cluster.wgsl` | Compute shader: k-means assignment step on normal vectors |
| `src/processing/shaders/plane-shading.wgsl` | Compute shader: flat directional shading per plane |
| `src/components/PlanesSettings.tsx` | UI controls for plane count, light azimuth/elevation, cleanup |
| `tests/unit/planes.test.ts` | Unit tests for CPU planes processing |

### Modified Files

| File | Change |
|------|--------|
| `package.json` | Add `@huggingface/transformers` dependency |
| `vite.config.ts` | Exclude transformers from pre-bundling |
| `src/types.ts` | Add `'planes'` to `Mode`, add `PlanesConfig` interface |
| `src/processing/worker-protocol.ts` | Add `'planes'` to `WorkerRequest` union and response types |
| `src/processing/worker.ts` | Handle `'planes'` request type |
| `src/processing/webgpu.ts` | Add GPU-accelerated `processPlanes` method |
| `src/components/ModeBar.tsx` | Add "Planes" entry to `MODES` array |
| `src/hooks/useProcessingPipeline.ts` | Add depth worker lifecycle, depth caching, planes dispatch |
| `src/app.tsx` | Add `planesConfig` signal, wire `PlanesSettings` into sidebar |

---

## Task 1: Foundation — Dependencies and Types

**Files:**
- Modify: `package.json`
- Modify: `vite.config.ts`
- Modify: `src/types.ts`

- [ ] **Step 1: Install @huggingface/transformers**

```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane
npm install @huggingface/transformers
```

- [ ] **Step 2: Update Vite config to exclude transformers from pre-bundling**

In `vite.config.ts`, add `optimizeDeps` to the config object:

```typescript
export default defineConfig({
  base: './',
  optimizeDeps: {
    exclude: ['@huggingface/transformers'],
  },
  server: {
    // ... existing config
```

- [ ] **Step 3: Add PlanesConfig type and extend Mode union**

In `src/types.ts`:

Add `"planes"` to the `Mode` type:

```typescript
export type Mode = "original" | "grayscale" | "value" | "color" | "planes";
```

Add the `PlanesConfig` interface after `ColorConfig`:

```typescript
export interface PlanesConfig {
  planeCount: number;        // 3–30, default 8
  lightAzimuth: number;      // 0–360 degrees, default 225 (top-left)
  lightElevation: number;    // 10–90 degrees, default 45
  minRegionSize: "off" | "small" | "medium" | "large";
}
```

- [ ] **Step 4: Verify types compile**

```bash
npx tsc --noEmit 2>&1 | head -20
```

Expected: Type errors in files that switch on `Mode` exhaustively (ModeBar, pipeline, etc.) — this is expected and will be fixed in later tasks. No errors in `types.ts` itself.

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json vite.config.ts src/types.ts
git commit -m "feat(planes): add PlanesConfig type, install @huggingface/transformers"
```

---

## Task 2: CPU Planes Processing — Core Algorithms (TDD)

**Files:**
- Create: `src/processing/planes.ts`
- Create: `tests/unit/planes.test.ts`

### 2a: Normal computation

- [ ] **Step 1: Write failing tests for `computeNormals`**

Create `tests/unit/planes.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { computeNormals } from '../../src/processing/planes';

describe('computeNormals', () => {
  it('returns normals pointing up for a flat surface', () => {
    // Flat depth map (all same value) → normals should point straight out (0, 0, 1)
    const depth = new Float32Array([1, 1, 1, 1, 1, 1, 1, 1, 1]);
    const normals = computeNormals(depth, 3, 3);
    // Check center pixel (avoids edge effects)
    const cx = 1, cy = 1, idx = (cy * 3 + cx) * 3;
    expect(normals[idx]).toBeCloseTo(0, 4);     // nx
    expect(normals[idx + 1]).toBeCloseTo(0, 4); // ny
    expect(normals[idx + 2]).toBeCloseTo(1, 4); // nz
  });

  it('detects a surface tilting right (depth increases with x)', () => {
    // 3x3 depth map: depth = x
    const depth = new Float32Array([0, 1, 2, 0, 1, 2, 0, 1, 2]);
    const normals = computeNormals(depth, 3, 3);
    const cx = 1, cy = 1, idx = (cy * 3 + cx) * 3;
    // Normal should tilt toward negative X (away from increasing depth)
    expect(normals[idx]).toBeLessThan(0);        // nx < 0
    expect(normals[idx + 1]).toBeCloseTo(0, 4);  // ny ≈ 0
    expect(normals[idx + 2]).toBeGreaterThan(0);  // nz > 0
  });

  it('returns normalized vectors', () => {
    const depth = new Float32Array([0, 0.5, 1, 0.3, 0.8, 1.2, 0.6, 1.1, 1.5]);
    const normals = computeNormals(depth, 3, 3);
    for (let i = 0; i < 9; i++) {
      const b = i * 3;
      const len = Math.sqrt(normals[b] ** 2 + normals[b + 1] ** 2 + normals[b + 2] ** 2);
      expect(len).toBeCloseTo(1, 4);
    }
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx vitest run tests/unit/planes.test.ts
```

Expected: FAIL — `computeNormals` is not exported from `../planes`.

- [ ] **Step 3: Implement `computeNormals`**

Create `src/processing/planes.ts`:

```typescript
import type { PlanesConfig } from '../types';
import { cleanupRegions } from './regions';

/**
 * Compute surface normals from a depth map using central differences.
 * Returns Float32Array of length width * height * 3 (nx, ny, nz per pixel).
 */
export function computeNormals(
  depth: Float32Array, width: number, height: number,
): Float32Array {
  const numPixels = width * height;
  const normals = new Float32Array(numPixels * 3);

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = y * width + x;
      const left  = x > 0           ? depth[idx - 1]     : depth[idx];
      const right = x < width - 1   ? depth[idx + 1]     : depth[idx];
      const up    = y > 0           ? depth[idx - width]  : depth[idx];
      const down  = y < height - 1  ? depth[idx + width]  : depth[idx];

      const dx = (right - left) * 0.5;
      const dy = (down - up) * 0.5;

      // cross product of tangent vectors (1,0,dx) × (0,1,dy) = (-dx, -dy, 1)
      const nx = -dx;
      const ny = -dy;
      const nz = 1.0;
      const len = Math.sqrt(nx * nx + ny * ny + nz * nz);

      const base = idx * 3;
      normals[base]     = nx / len;
      normals[base + 1] = ny / len;
      normals[base + 2] = nz / len;
    }
  }
  return normals;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
npx vitest run tests/unit/planes.test.ts
```

Expected: All `computeNormals` tests PASS.

### 2b: Normal clustering

- [ ] **Step 5: Write failing tests for `clusterNormals`**

Append to `tests/unit/planes.test.ts`:

```typescript
import { computeNormals, clusterNormals } from '../../src/processing/planes';

describe('clusterNormals', () => {
  it('assigns two distinct normal groups to two clusters', () => {
    // Left half: normals pointing up-left, right half: normals pointing up-right
    // Create via depth maps: left half slopes right, right half slopes left
    const width = 4, height = 2;
    const depth = new Float32Array([
      0, 1, 2, 1,   // row 0: rises then falls
      0, 1, 2, 1,   // row 1: same
    ]);
    const normals = computeNormals(depth, width, height);
    const { labels, centroids } = clusterNormals(normals, width, height, 2);

    expect(labels.length).toBe(width * height);
    expect(centroids.length).toBe(2 * 3);
    // At minimum, left and right columns should have different labels
    // (center columns may vary due to transition)
    expect(labels[0]).not.toBe(labels[3]); // col 0 vs col 3
  });

  it('returns k centroids that are unit vectors', () => {
    const normals = new Float32Array(30 * 3);
    for (let i = 0; i < 30; i++) {
      normals[i * 3 + 2] = 1; // all pointing Z
    }
    const { centroids } = clusterNormals(normals, 10, 3, 3);
    for (let c = 0; c < 3; c++) {
      const b = c * 3;
      const len = Math.sqrt(centroids[b] ** 2 + centroids[b + 1] ** 2 + centroids[b + 2] ** 2);
      expect(len).toBeCloseTo(1, 3);
    }
  });
});
```

- [ ] **Step 6: Run tests to verify they fail**

```bash
npx vitest run tests/unit/planes.test.ts
```

Expected: FAIL — `clusterNormals` is not exported.

- [ ] **Step 7: Implement `clusterNormals`**

Add to `src/processing/planes.ts`:

```typescript
/**
 * K-means clustering on surface normal vectors.
 * Returns per-pixel labels (Uint8Array) and cluster centroids (Float32Array, k×3).
 */
export function clusterNormals(
  normals: Float32Array, width: number, height: number, k: number, maxIterations = 20,
): { labels: Uint8Array; centroids: Float32Array } {
  const numPixels = width * height;
  const labels = new Uint8Array(numPixels);

  // Initialize centroids from evenly-spaced data samples
  const centroids = new Float32Array(k * 3);
  const step = Math.max(1, Math.floor(numPixels / k));
  for (let i = 0; i < k; i++) {
    const src = Math.min(i * step, numPixels - 1) * 3;
    centroids[i * 3]     = normals[src];
    centroids[i * 3 + 1] = normals[src + 1];
    centroids[i * 3 + 2] = normals[src + 2];
  }

  for (let iter = 0; iter < maxIterations; iter++) {
    // Assignment
    let changed = 0;
    for (let i = 0; i < numPixels; i++) {
      const base = i * 3;
      const nx = normals[base], ny = normals[base + 1], nz = normals[base + 2];
      let bestDist = Infinity;
      let bestC = 0;
      for (let c = 0; c < k; c++) {
        const cb = c * 3;
        const dx = nx - centroids[cb];
        const dy = ny - centroids[cb + 1];
        const dz = nz - centroids[cb + 2];
        const dist = dx * dx + dy * dy + dz * dz;
        if (dist < bestDist) { bestDist = dist; bestC = c; }
      }
      if (labels[i] !== bestC) changed++;
      labels[i] = bestC;
    }

    // Update centroids
    const sums = new Float32Array(k * 3);
    const counts = new Uint32Array(k);
    for (let i = 0; i < numPixels; i++) {
      const c = labels[i];
      const b = i * 3;
      sums[c * 3]     += normals[b];
      sums[c * 3 + 1] += normals[b + 1];
      sums[c * 3 + 2] += normals[b + 2];
      counts[c]++;
    }
    for (let c = 0; c < k; c++) {
      if (counts[c] === 0) continue;
      const cb = c * 3;
      const mx = sums[cb] / counts[c];
      const my = sums[cb + 1] / counts[c];
      const mz = sums[cb + 2] / counts[c];
      const len = Math.sqrt(mx * mx + my * my + mz * mz);
      centroids[cb]     = len > 0 ? mx / len : 0;
      centroids[cb + 1] = len > 0 ? my / len : 0;
      centroids[cb + 2] = len > 0 ? mz / len : 1;
    }

    if (changed === 0) break;
  }

  return { labels, centroids };
}
```

- [ ] **Step 8: Run tests to verify they pass**

```bash
npx vitest run tests/unit/planes.test.ts
```

Expected: All tests PASS.

### 2c: Directional shading

- [ ] **Step 9: Write failing tests for `shadePlanes`**

Append to `tests/unit/planes.test.ts`:

```typescript
import { computeNormals, clusterNormals, shadePlanes } from '../../src/processing/planes';

describe('shadePlanes', () => {
  it('produces brighter output for planes facing the light', () => {
    // 2 planes: one facing up (0,0,1), one facing right (1,0,0)
    const labels = new Uint8Array([0, 0, 1, 1]);
    const centroids = new Float32Array([0, 0, 1, 1, 0, 0]); // plane0=up, plane1=right

    // Light from directly above: elevation=90 → light=(0,0,1)
    const result = shadePlanes(labels, centroids, 2, 2, 0, 90);

    // Plane 0 faces the light → bright; Plane 1 perpendicular → dark
    const p0shade = result.data[0]; // R of pixel 0 (plane 0)
    const p1shade = result.data[8]; // R of pixel 2 (plane 1)
    expect(p0shade).toBeGreaterThan(p1shade);
  });

  it('returns valid ImageData dimensions', () => {
    const labels = new Uint8Array([0, 0, 0, 0, 0, 0]);
    const centroids = new Float32Array([0, 0, 1]);
    const result = shadePlanes(labels, centroids, 3, 2, 225, 45);
    expect(result.width).toBe(3);
    expect(result.height).toBe(2);
    expect(result.data.length).toBe(3 * 2 * 4);
  });
});
```

- [ ] **Step 10: Run tests to verify they fail**

```bash
npx vitest run tests/unit/planes.test.ts
```

Expected: FAIL — `shadePlanes` is not exported.

- [ ] **Step 11: Implement `shadePlanes`**

Add to `src/processing/planes.ts`:

```typescript
/**
 * Render flat directional shading: each plane gets a uniform shade based on
 * the dot product of its centroid normal with the light direction.
 */
export function shadePlanes(
  labels: Uint8Array, centroids: Float32Array,
  width: number, height: number,
  lightAzimuth: number, lightElevation: number,
): ImageData {
  const azRad = (lightAzimuth * Math.PI) / 180;
  const elRad = (lightElevation * Math.PI) / 180;
  // Light direction vector (pointing toward the surface from the light)
  const lx =  Math.cos(elRad) * Math.sin(azRad);
  const ly = -Math.cos(elRad) * Math.cos(azRad);
  const lz =  Math.sin(elRad);

  const numPixels = width * height;
  const out = new Uint8ClampedArray(numPixels * 4);
  const ambient = 0.15;

  for (let i = 0; i < numPixels; i++) {
    const c = labels[i];
    const cb = c * 3;
    const dot = centroids[cb] * lx + centroids[cb + 1] * ly + centroids[cb + 2] * lz;
    const shade = Math.max(0, Math.min(1, dot * (1 - ambient) + ambient));
    const v = Math.round(shade * 255);
    const off = i * 4;
    out[off] = v;
    out[off + 1] = v;
    out[off + 2] = v;
    out[off + 3] = 255;
  }
  return new ImageData(out, width, height);
}
```

- [ ] **Step 12: Run tests to verify they pass**

```bash
npx vitest run tests/unit/planes.test.ts
```

Expected: All tests PASS.

### 2d: Orchestrator + depth resizing

- [ ] **Step 13: Write failing test for `processPlanes`**

Append to `tests/unit/planes.test.ts`:

```typescript
import { computeNormals, clusterNormals, shadePlanes, processPlanes } from '../../src/processing/planes';

describe('processPlanes', () => {
  it('produces an ImageData from a synthetic depth map', () => {
    const width = 10, height = 10;
    // Depth ramp: increases left to right
    const depth = new Float32Array(width * height);
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        depth[y * width + x] = x / (width - 1);
      }
    }
    const config = { planeCount: 3, lightAzimuth: 225, lightElevation: 45, minRegionSize: 'off' as const };
    const result = processPlanes(depth, width, height, config);
    expect(result.width).toBe(width);
    expect(result.height).toBe(height);
    expect(result.data.length).toBe(width * height * 4);
  });
});
```

- [ ] **Step 14: Run test to verify it fails**

```bash
npx vitest run tests/unit/planes.test.ts
```

Expected: FAIL — `processPlanes` is not exported.

- [ ] **Step 15: Implement `processPlanes` and `resizeDepthMap`**

Add to `src/processing/planes.ts`:

```typescript
/**
 * Bilinear resize of a float32 depth map.
 */
export function resizeDepthMap(
  data: Float32Array, srcW: number, srcH: number, dstW: number, dstH: number,
): Float32Array {
  if (srcW === dstW && srcH === dstH) return data;
  const out = new Float32Array(dstW * dstH);
  const scaleX = srcW / dstW;
  const scaleY = srcH / dstH;
  for (let y = 0; y < dstH; y++) {
    for (let x = 0; x < dstW; x++) {
      const srcX = (x + 0.5) * scaleX - 0.5;
      const srcY = (y + 0.5) * scaleY - 0.5;
      const x0 = Math.max(0, Math.floor(srcX));
      const y0 = Math.max(0, Math.floor(srcY));
      const x1 = Math.min(srcW - 1, x0 + 1);
      const y1 = Math.min(srcH - 1, y0 + 1);
      const fx = srcX - x0;
      const fy = srcY - y0;
      out[y * dstW + x] =
        data[y0 * srcW + x0] * (1 - fx) * (1 - fy) +
        data[y0 * srcW + x1] * fx * (1 - fy) +
        data[y1 * srcW + x0] * (1 - fx) * fy +
        data[y1 * srcW + x1] * fx * fy;
    }
  }
  return out;
}

/**
 * Full CPU planes pipeline: depth → normals → cluster → shade → cleanup.
 */
export function processPlanes(
  depth: Float32Array, width: number, height: number, config: PlanesConfig,
): ImageData {
  const normals = computeNormals(depth, width, height);
  const { labels, centroids } = clusterNormals(normals, width, height, config.planeCount);
  const shaded = shadePlanes(labels, centroids, width, height, config.lightAzimuth, config.lightElevation);

  // cleanupRegions operates on ImageData and uses the grayscale pixel values
  // for connected-component analysis. Since each plane has a unique shade value,
  // this works directly on the shaded output — matching how value-study uses it.
  return cleanupRegions(shaded, config.minRegionSize);
}
```

- [ ] **Step 16: Run all tests**

```bash
npx vitest run tests/unit/planes.test.ts
```

Expected: All tests PASS.

- [ ] **Step 17: Commit**

```bash
git add src/processing/planes.ts tests/unit/planes.test.ts
git commit -m "feat(planes): CPU planes processing — normals, clustering, shading"
```

---

## Task 3: Depth Worker — ML Inference Layer

**Files:**
- Create: `src/processing/depth-worker.ts`
- Create: `src/processing/depth-client.ts`

- [ ] **Step 1: Create the depth worker**

Create `src/processing/depth-worker.ts`:

```typescript
/// <reference lib="webworker" />

import { pipeline, RawImage, env } from '@huggingface/transformers';

env.allowLocalModels = false;

type DepthPipeline = Awaited<ReturnType<typeof pipeline<'depth-estimation'>>>;

let pipelineInstance: DepthPipeline | null = null;
let pipelineLoading: Promise<DepthPipeline> | null = null;

function getDepthPipeline(onProgress: (data: DepthWorkerProgress) => void): Promise<DepthPipeline> {
  if (pipelineInstance) return Promise.resolve(pipelineInstance);
  if (pipelineLoading) return pipelineLoading;

  pipelineLoading = pipeline('depth-estimation', 'onnx-community/depth-anything-v2-small', {
    device: 'wasm',
    dtype: 'q8',
    progress_callback: (event: any) => {
      if (event.status === 'progress' && typeof event.progress === 'number') {
        onProgress({ kind: 'progress', stage: 'Downloading depth model', percent: Math.round(event.progress) });
      }
    },
  }).then((p) => {
    pipelineInstance = p;
    pipelineLoading = null;
    return p;
  });

  return pipelineLoading;
}

export interface DepthWorkerRequest {
  kind: 'estimate';
  requestId: number;
  imageData: ImageData;
}

export interface DepthWorkerProgress {
  kind: 'progress';
  stage: string;
  percent: number;
}

export interface DepthWorkerResult {
  kind: 'result';
  requestId: number;
  depthData: Float32Array;
  depthWidth: number;
  depthHeight: number;
  imageWidth: number;
  imageHeight: number;
}

export interface DepthWorkerError {
  kind: 'error';
  requestId: number;
  error: string;
}

export type DepthWorkerOutbound = DepthWorkerProgress | DepthWorkerResult | DepthWorkerError;

self.onmessage = async (e: MessageEvent<DepthWorkerRequest>) => {
  const { requestId, imageData } = e.data;

  try {
    const estimator = await getDepthPipeline((progress) => {
      self.postMessage(progress);
    });

    self.postMessage({ kind: 'progress', stage: 'Estimating depth', percent: 0 } satisfies DepthWorkerProgress);

    const rawImage = new RawImage(imageData.data, imageData.width, imageData.height, 4);
    const output = await estimator(rawImage);

    const depthTensor = output.predicted_depth;
    const depthData = depthTensor.data as Float32Array;
    const [depthHeight, depthWidth] = depthTensor.dims as [number, number];

    const result: DepthWorkerResult = {
      kind: 'result',
      requestId,
      depthData,
      depthWidth,
      depthHeight,
      imageWidth: imageData.width,
      imageHeight: imageData.height,
    };

    self.postMessage(result, [depthData.buffer]);
  } catch (err) {
    const errorMsg: DepthWorkerError = {
      kind: 'error',
      requestId,
      error: err instanceof Error ? err.message : String(err),
    };
    self.postMessage(errorMsg);
  }
};

export {};
```

- [ ] **Step 2: Create the depth client**

Create `src/processing/depth-client.ts`:

```typescript
import type {
  DepthWorkerRequest,
  DepthWorkerOutbound,
  DepthWorkerResult,
} from './depth-worker';

export type DepthProgressCallback = (stage: string, percent: number) => void;

export class DepthClient {
  private worker: Worker;
  private pending = new Map<number, {
    resolve: (result: { depthData: Float32Array; depthWidth: number; depthHeight: number }) => void;
    reject: (err: Error) => void;
  }>();
  private nextId = 0;
  private onProgress?: DepthProgressCallback;

  constructor(onProgress?: DepthProgressCallback) {
    this.onProgress = onProgress;
    this.worker = new Worker(
      new URL('./depth-worker.ts', import.meta.url),
      { type: 'module' },
    );
    this.worker.addEventListener('message', this.handleMessage);
  }

  requestDepth(imageData: ImageData): { requestId: number; promise: Promise<{ depthData: Float32Array; depthWidth: number; depthHeight: number }> } {
    const requestId = ++this.nextId;
    const imgCopy = new ImageData(new Uint8ClampedArray(imageData.data), imageData.width, imageData.height);

    const promise = new Promise<{ depthData: Float32Array; depthWidth: number; depthHeight: number }>((resolve, reject) => {
      this.pending.set(requestId, { resolve, reject });

      const msg: DepthWorkerRequest = { kind: 'estimate', requestId, imageData: imgCopy };
      this.worker.postMessage(msg, [imgCopy.data.buffer]);
    });

    return { requestId, promise };
  }

  terminate() {
    this.worker.removeEventListener('message', this.handleMessage);
    for (const [, p] of this.pending) {
      p.reject(new Error('DepthClient terminated'));
    }
    this.pending.clear();
    this.worker.terminate();
  }

  private handleMessage = (e: MessageEvent<DepthWorkerOutbound>) => {
    const msg = e.data;

    if (msg.kind === 'progress') {
      this.onProgress?.(msg.stage, msg.percent);
      return;
    }

    if (msg.kind === 'error') {
      const p = this.pending.get(msg.requestId);
      if (p) {
        this.pending.delete(msg.requestId);
        p.reject(new Error(msg.error));
      }
      return;
    }

    if (msg.kind === 'result') {
      const p = this.pending.get(msg.requestId);
      if (p) {
        this.pending.delete(msg.requestId);
        p.resolve({
          depthData: msg.depthData,
          depthWidth: msg.depthWidth,
          depthHeight: msg.depthHeight,
        });
      }
    }
  };
}
```

- [ ] **Step 3: Verify files compile**

```bash
npx tsc --noEmit src/processing/depth-client.ts 2>&1 | head -20
```

Expected: No errors in these files (may have unrelated errors elsewhere).

- [ ] **Step 4: Commit**

```bash
git add src/processing/depth-worker.ts src/processing/depth-client.ts
git commit -m "feat(planes): depth worker + client for Depth Anything v2 inference"
```

---

## Task 4: Worker Protocol + Handler

**Files:**
- Modify: `src/processing/worker-protocol.ts`
- Modify: `src/processing/worker.ts`

- [ ] **Step 1: Add 'planes' to the worker protocol**

In `src/processing/worker-protocol.ts`, add to the `WorkerRequest` union (line 17-22):

```typescript
export type WorkerRequest =
  | { type: 'simplify'; imageData: ImageData; config: SimplifyConfig }
  | { type: 'value-study'; imageData: ImageData; config: ValueConfig }
  | { type: 'color-regions'; imageData: ImageData; config: ColorConfig }
  | { type: 'edges'; imageData: ImageData; config: EdgeConfig }
  | { type: 'grayscale'; imageData: ImageData }
  | { type: 'planes'; imageData: ImageData; depthMap: Float32Array; depthWidth: number; depthHeight: number; config: PlanesConfig };
```

The `depthWidth`/`depthHeight` fields carry the model's native depth resolution so the worker can resize to image dimensions.

Add `PlanesConfig` to the import at line 1:

```typescript
import type { ValueConfig, ColorConfig, EdgeConfig, SimplifyConfig, PlanesConfig } from '../types';
```

- [ ] **Step 2: Add 'planes' handler to the processing worker**

In `src/processing/worker.ts`, add import at top:

```typescript
import { processPlanes, resizeDepthMap } from './planes';
```

Add a new `else if` branch in `handleMessage` (after the `grayscale` branch, before the `catch`):

```typescript
    } else if (type === 'planes') {
      const { depthMap, depthWidth, depthHeight, config } = data;
      const resized = await measureStage(stages, 'resize-depth', () =>
        resizeDepthMap(depthMap, depthWidth, depthHeight, data.imageData.width, data.imageData.height)
      );
      const result = await measureStage(stages, 'planes-cpu', () =>
        processPlanes(resized, data.imageData.width, data.imageData.height, config)
      );
      const meta = finalizeMeta(stages, 'cpu', data.imageData, queuedAt, startedAt);
      self.postMessage(createWorkerSuccessMessage(requestId, type, meta, { result }), [result.data.buffer]);
    }
```

- [ ] **Step 3: Verify compilation**

```bash
npx tsc --noEmit 2>&1 | head -30
```

Expected: Fewer type errors than before (the protocol now knows about 'planes').

- [ ] **Step 4: Commit**

```bash
git add src/processing/worker-protocol.ts src/processing/worker.ts
git commit -m "feat(planes): add planes request type to worker protocol and handler"
```

---

## Task 5: WGSL Shaders + WebGPU Integration

**Files:**
- Create: `src/processing/shaders/depth-to-normals.wgsl`
- Create: `src/processing/shaders/normal-cluster.wgsl`
- Create: `src/processing/shaders/plane-shading.wgsl`
- Modify: `src/processing/webgpu.ts`

- [ ] **Step 1: Create depth-to-normals shader**

Create `src/processing/shaders/depth-to-normals.wgsl`:

```wgsl
struct Params {
  width: u32,
  height: u32,
  numPixels: u32,
  _pad: u32,
};

@group(0) @binding(0) var<storage, read> depth: array<f32>;
@group(0) @binding(1) var<storage, read_write> normals: array<f32>;
@group(0) @binding(2) var<uniform> params: Params;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.numPixels) { return; }

  let x = idx % params.width;
  let y = idx / params.width;

  let left  = select(depth[idx - 1u], depth[idx], x == 0u);
  let right = select(depth[idx + 1u], depth[idx], x >= params.width - 1u);
  let up    = select(depth[idx - params.width], depth[idx], y == 0u);
  let down  = select(depth[idx + params.width], depth[idx], y >= params.height - 1u);

  let dx = (right - left) * 0.5;
  let dy = (down - up) * 0.5;

  let n = normalize(vec3<f32>(-dx, -dy, 1.0));

  let base = idx * 3u;
  normals[base]      = n.x;
  normals[base + 1u] = n.y;
  normals[base + 2u] = n.z;
}
```

- [ ] **Step 2: Create normal-cluster shader (assignment step)**

Create `src/processing/shaders/normal-cluster.wgsl`:

```wgsl
struct Params {
  numPixels: u32,
  k: u32,
  _pad0: u32,
  _pad1: u32,
};

@group(0) @binding(0) var<storage, read> normals: array<f32>;
@group(0) @binding(1) var<storage, read> centroids: array<f32>;
@group(0) @binding(2) var<storage, read_write> labels: array<u32>;
@group(0) @binding(3) var<uniform> params: Params;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.numPixels) { return; }

  let base = idx * 3u;
  let nx = normals[base];
  let ny = normals[base + 1u];
  let nz = normals[base + 2u];

  var bestDist: f32 = 1e20;
  var bestC: u32 = 0u;
  for (var ci: u32 = 0u; ci < params.k; ci = ci + 1u) {
    let cBase = ci * 3u;
    let dx = nx - centroids[cBase];
    let dy = ny - centroids[cBase + 1u];
    let dz = nz - centroids[cBase + 2u];
    let dist = dx * dx + dy * dy + dz * dz;
    if (dist < bestDist) {
      bestDist = dist;
      bestC = ci;
    }
  }

  labels[idx] = bestC;
}
```

- [ ] **Step 3: Create plane-shading shader**

Create `src/processing/shaders/plane-shading.wgsl`:

```wgsl
struct Params {
  numPixels: u32,
  k: u32,
  _pad0: u32,
  _pad1: u32,
  lightX: f32,
  lightY: f32,
  lightZ: f32,
  ambient: f32,
};

@group(0) @binding(0) var<storage, read> labels: array<u32>;
@group(0) @binding(1) var<storage, read> centroids: array<f32>;
@group(0) @binding(2) var<storage, read_write> output: array<u32>;
@group(0) @binding(3) var<uniform> params: Params;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.numPixels) { return; }

  let c = labels[idx];
  let cBase = c * 3u;
  let nx = centroids[cBase];
  let ny = centroids[cBase + 1u];
  let nz = centroids[cBase + 2u];

  let dot_val = nx * params.lightX + ny * params.lightY + nz * params.lightZ;
  let shade = clamp(dot_val * (1.0 - params.ambient) + params.ambient, 0.0, 1.0);
  let v = u32(shade * 255.0);

  output[idx] = v | (v << 8u) | (v << 16u) | (255u << 24u);
}
```

- [ ] **Step 4: Add GPU planes processing to `webgpu.ts`**

In `src/processing/webgpu.ts`, add shader imports at the top (after existing imports):

```typescript
import depthToNormalsShader from './shaders/depth-to-normals.wgsl?raw';
import normalClusterShader from './shaders/normal-cluster.wgsl?raw';
import planeShadingShader from './shaders/plane-shading.wgsl?raw';
```

Add a `processPlanes` method to the `WebGpuProcessor` class (or equivalent exported object). This method should:
1. Upload depth data to GPU buffer
2. Run depth-to-normals shader
3. Initialize centroids on CPU (from evenly-spaced normal samples read back from GPU)
4. Run normal-cluster assignment shader in a loop (read labels back, update centroids on CPU, upload new centroids) for up to 20 iterations
5. Run plane-shading shader
6. Read back packed RGBA result, convert to ImageData

The implementation follows the same patterns as the existing `processValueStudy` and `kMeansAssign` methods. Key buffer layout:
- Depth input: `Float32Array` (numPixels)
- Normals: `Float32Array` (numPixels × 3)
- Centroids: `Float32Array` (k × 3)
- Labels: `Uint32Array` (numPixels)
- Output: `Uint32Array` (numPixels, packed RGBA)
- Params: uniform buffers matching each shader's struct

Use the existing `createBufferWithData`, `WORKGROUP_SIZE`, and `alignTo` helpers. Dispatch each shader with `Math.ceil(numPixels / WORKGROUP_SIZE)` workgroups.

The centroid update loop is done on CPU (read labels back, compute means, upload new centroids) since the reduction step isn't efficient as a single compute shader for small k values. This matches the existing k-means pattern used in color-regions.

- [ ] **Step 5: Update the worker handler to use GPU when available**

In `src/processing/worker.ts`, update the `'planes'` handler:

```typescript
    } else if (type === 'planes') {
      const { depthMap, depthWidth, depthHeight, config } = data;
      const resized = await measureStage(stages, 'resize-depth', () =>
        resizeDepthMap(depthMap, depthWidth, depthHeight, data.imageData.width, data.imageData.height)
      );
      if (gpu) {
        const result = await measureStage(stages, 'planes-gpu', () =>
          gpu.processPlanes(resized, data.imageData.width, data.imageData.height, config)
        );
        const meta = finalizeMeta(stages, 'gpu', data.imageData, queuedAt, startedAt);
        self.postMessage(createWorkerSuccessMessage(requestId, type, meta, { result }), [result.data.buffer]);
      } else {
        const result = await measureStage(stages, 'planes-cpu', () =>
          processPlanes(resized, data.imageData.width, data.imageData.height, config)
        );
        const meta = finalizeMeta(stages, 'cpu', data.imageData, queuedAt, startedAt);
        self.postMessage(createWorkerSuccessMessage(requestId, type, meta, { result }), [result.data.buffer]);
      }
    }
```

- [ ] **Step 6: Commit**

```bash
git add src/processing/shaders/depth-to-normals.wgsl src/processing/shaders/normal-cluster.wgsl src/processing/shaders/plane-shading.wgsl src/processing/webgpu.ts src/processing/worker.ts
git commit -m "feat(planes): WGSL shaders and GPU-accelerated planes processing"
```

---

## Task 6: UI Components

**Files:**
- Create: `src/components/PlanesSettings.tsx`
- Modify: `src/components/ModeBar.tsx`

- [ ] **Step 1: Create PlanesSettings component**

Create `src/components/PlanesSettings.tsx`:

```tsx
import type { PlanesConfig } from '../types';

interface Props {
  config: PlanesConfig;
  onChange: (cfg: Partial<PlanesConfig>) => void;
}

export function PlanesSettings({ config, onChange }: Props) {
  return (
    <div class="settings-group">
      <div class="settings-row" title="Number of distinct plane groups to detect">
        <label>Planes</label>
        <input
          type="range" min="3" max="30" step="1" value={config.planeCount}
          onInput={e => onChange({ planeCount: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
        <span class="settings-value">{config.planeCount}</span>
      </div>

      <div class="settings-row" title="Compass direction the light comes from (225° = top-left)">
        <label>Light Azimuth</label>
        <input
          type="range" min="0" max="360" step="5" value={config.lightAzimuth}
          onInput={e => onChange({ lightAzimuth: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
        <span class="settings-value">{config.lightAzimuth}°</span>
      </div>

      <div class="settings-row" title="Height of the light source (90° = directly above)">
        <label>Light Elevation</label>
        <input
          type="range" min="10" max="90" step="5" value={config.lightElevation}
          onInput={e => onChange({ lightElevation: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
        <span class="settings-value">{config.lightElevation}°</span>
      </div>

      <div class="settings-row" title="Merge small isolated plane fragments into neighbors">
        <label>Cleanup</label>
        <select
          value={config.minRegionSize}
          onChange={e => onChange({ minRegionSize: (e.target as HTMLSelectElement).value as PlanesConfig['minRegionSize'] })}
        >
          <option value="off">Off</option>
          <option value="small">Small</option>
          <option value="medium">Medium</option>
          <option value="large">Large</option>
        </select>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Add "Planes" to ModeBar**

In `src/components/ModeBar.tsx`, add to the `MODES` array (line 8-13):

```typescript
const MODES: { id: Mode; label: string; hint: string }[] = [
  { id: 'original', label: 'Original', hint: 'Reference the untouched source.' },
  { id: 'grayscale', label: 'Grayscale', hint: 'Reduce the image to tonal structure.' },
  { id: 'value', label: 'Value Study', hint: 'Shape the scene into clear light groups.' },
  { id: 'color', label: 'Color Regions', hint: 'Organize palette clusters and temperature.' },
  { id: 'planes', label: 'Planes', hint: 'Extract form planes with directional shading.' },
];
```

- [ ] **Step 3: Update `activeModeLabel` in `app.tsx`**

In `src/app.tsx`, update the `activeModeLabel` map to include planes (so clicking the new mode button doesn't show `undefined` in the header):

```typescript
  const activeModeLabel = {
    original: 'Source',
    grayscale: 'Tonal',
    value: 'Value',
    color: 'Color',
    planes: 'Planes',
  }[activeMode.value];
```

- [ ] **Step 4: Verify components compile**

```bash
npx tsc --noEmit src/components/PlanesSettings.tsx src/components/ModeBar.tsx 2>&1 | head -10
```

Expected: No errors in these files.

- [ ] **Step 5: Commit**

```bash
git add src/components/PlanesSettings.tsx src/components/ModeBar.tsx src/app.tsx
git commit -m "feat(planes): PlanesSettings component, ModeBar entry, and mode label"
```

---

## Task 7: Pipeline Integration

**Files:**
- Modify: `src/hooks/useProcessingPipeline.ts`
- Modify: `src/app.tsx`

This is the largest integration task. It wires the depth worker, depth caching, and planes dispatch into the existing reactive pipeline.

- [ ] **Step 1: Add PlanesConfig to pipeline inputs**

In `src/hooks/useProcessingPipeline.ts`, update the `ProcessingPipelineInputs` interface:

```typescript
import type { Mode, EdgeConfig, ValueConfig, ColorConfig, SimplifyConfig, PlanesConfig } from '../types';

export interface ProcessingPipelineInputs {
  sourceImageData: Signal<ImageData | null>;
  activeMode: Signal<Mode>;
  simplifyConfig: Signal<SimplifyConfig>;
  valueConfig: Signal<ValueConfig>;
  colorConfig: Signal<ColorConfig>;
  edgeConfig: Signal<EdgeConfig>;
  planesConfig: Signal<PlanesConfig>;
  onError?: (message: string) => void;
}
```

Also add `planesConfig` to the destructuring at the top of the hook body:

```typescript
const {
  sourceImageData,
  activeMode,
  simplifyConfig,
  valueConfig,
  colorConfig,
  edgeConfig,
  planesConfig,
  onError,
} = inputs;
```

- [ ] **Step 2: Add depth worker lifecycle and caching signals**

Inside `useProcessingPipeline`, add:

```typescript
import { DepthClient } from '../processing/depth-client';

// After existing signal declarations:
const depthMap = useMemo(() => signal<{ data: Float32Array; width: number; height: number } | null>(null), []);
const depthSourceRef = useRef<ImageData | null>(null);
const depthClientRef = useRef<DepthClient | null>(null);
const latestDepthRequestIdRef = useRef(0);
```

- [ ] **Step 3: Initialize and clean up the depth worker**

In the worker lifecycle `useEffect` (the one that creates the processing Worker), add depth client init:

```typescript
useEffect(() => {
  const worker = new Worker(new URL('../processing/worker.ts', import.meta.url), { type: 'module' });
  workerClientRef.current = new WorkerClient(worker);

  depthClientRef.current = new DepthClient((stage, percent) => {
    processingProgress.value = { stage, percent };
  });

  return () => {
    // ... existing cleanup ...
    depthClientRef.current?.terminate();
    depthClientRef.current = null;
  };
}, []);
```

- [ ] **Step 4: Add depth estimation trigger**

Add a new `useEffect` that triggers depth estimation when the source image changes:

```typescript
useEffect(() => {
  const src = sourceImageData.value;
  if (!src || !depthClientRef.current) return;

  // Only re-run depth if source changed
  if (depthSourceRef.current === src) return;
  depthSourceRef.current = src;
  depthMap.value = null;

  const { requestId, promise } = depthClientRef.current.requestDepth(src);
  latestDepthRequestIdRef.current = requestId;
  processingCount.value++;

  promise
    .then((result) => {
      if (requestId !== latestDepthRequestIdRef.current) return; // stale
      depthMap.value = { data: result.depthData, width: result.depthWidth, height: result.depthHeight };
      // If planes mode is active, trigger processing
      if (activeMode.value === 'planes') {
        triggerProcessing(0);
      }
    })
    .catch((err) => {
      if (requestId !== latestDepthRequestIdRef.current) return;
      onError?.('Depth estimation failed: ' + (err instanceof Error ? err.message : String(err)));
    })
    .finally(() => {
      processingCount.value = Math.max(0, processingCount.value - 1);
    });
}, [sourceImageData.value]);
```

- [ ] **Step 5: Add planes dispatch to `postMainRequest`**

In the `postMainRequest` callback, add a new `else if` branch for `'planes'`.

Note: `dispatchWorkerRequest` only transfers `imageData.data.buffer` by default. For planes, we also need to transfer `depthCopy.buffer` to avoid a costly structured-clone of the ~7MB depth map. Use `workerClient.request` directly with an explicit transfer list:

```typescript
    } else if (mode === 'planes') {
      const depth = depthMap.value;
      if (!depth) return; // depth not ready yet — will be triggered when depth completes
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      const depthCopy = new Float32Array(depth.data);
      const requestId = nextRequestId();
      latestMainRequestIdRef.current = requestId;
      processingCount.value++;

      const request = {
        type: 'planes' as const,
        imageData: imgCopy,
        depthMap: depthCopy,
        depthWidth: depth.width,
        depthHeight: depth.height,
        config: planesConfig.value,
      };

      const { promise } = workerClientRef.current!.request(request, {
        requestId,
        transfer: [imgCopy.data.buffer, depthCopy.buffer],
      });

      promise
        .then((response) => {
          if (response.requestId !== latestMainRequestIdRef.current) return;
          processingProgress.value = null;
          processedImage.value = response.payload.result;
        })
        .catch((err) => {
          const msg = err instanceof Error ? err.message : String(err);
          if (msg !== 'AbortError') onError?.(msg);
        })
        .finally(() => {
          processingCount.value = Math.max(0, processingCount.value - 1);
        });
    }
```

Add `planesConfig` to the dependency array of `postMainRequest`.

- [ ] **Step 6: Add planes config to reactive trigger**

Update the `useEffect` for Stage 2 (analysis config changes) to include `planesConfig` and `depthMap`:

```typescript
useEffect(() => {
  if (!simplifiedImageData.value) return;
  triggerProcessing(120);
}, [simplifiedImageData.value, activeMode.value, valueConfig.value, colorConfig.value, planesConfig.value, depthMap.value]);
```

- [ ] **Step 7: Add depthMap to resetProcessingState**

```typescript
const resetProcessingState = useCallback(() => {
  simplifiedImageData.value = null;
  processedImage.value = null;
  paletteColors.value = [];
  swatchBands.value = [];
  edgeData.value = null;
  depthMap.value = null;
  depthSourceRef.current = null;
}, [simplifiedImageData, processedImage, paletteColors, swatchBands, edgeData, depthMap]);
```

- [ ] **Step 8: Wire up in app.tsx**

In `src/app.tsx`:

1. Add import:
```typescript
import { PlanesSettings } from './components/PlanesSettings';
import type { Mode, GridConfig, EdgeConfig, ValueConfig, ColorConfig, SimplifyConfig, PlanesConfig } from './types';
```

2. Add default config (after `defaultSimplifyConfig`):
```typescript
const defaultPlanesConfig: PlanesConfig = {
  planeCount: 8,
  lightAzimuth: 225,
  lightElevation: 45,
  minRegionSize: 'small',
};
```

3. Add signal (after `showTemperatureMap`):
```typescript
const planesConfig = signal<PlanesConfig>(defaultPlanesConfig);
```

4. Pass to pipeline hook:
```typescript
const { ... } = useProcessingPipeline({
  sourceImageData,
  activeMode,
  simplifyConfig,
  valueConfig,
  colorConfig,
  edgeConfig,
  planesConfig,
  onError: showError,
});
```

5. Add PlanesSettings to the sidebar — in the Adjustments panel card, add alongside value/color:
```tsx
{(activeMode.value === 'value' || activeMode.value === 'color' || activeMode.value === 'planes') && (
  <section class="panel-card">
    <div class="panel-card-header">
      <div class="panel-card-title">
        <strong>Adjustments</strong>
      </div>
    </div>
    {activeMode.value === 'value' && (
      <ValueSettings config={valueConfig.value} onChange={(cfg) => { valueConfig.value = { ...valueConfig.value, ...cfg }; }} />
    )}
    {activeMode.value === 'color' && (
      <ColorSettings config={colorConfig.value} onChange={(cfg) => { colorConfig.value = { ...colorConfig.value, ...cfg }; }} />
    )}
    {activeMode.value === 'planes' && (
      <PlanesSettings config={planesConfig.value} onChange={(cfg) => { planesConfig.value = { ...planesConfig.value, ...cfg }; }} />
    )}
  </section>
)}
```

Note: `activeModeLabel` was already updated in Task 6, Step 3.

- [ ] **Step 9: Verify full build**

```bash
npx tsc --noEmit && npm run build
```

Expected: Build succeeds with no type errors.

- [ ] **Step 10: Commit**

```bash
git add src/hooks/useProcessingPipeline.ts src/app.tsx
git commit -m "feat(planes): wire depth worker, caching, and planes dispatch into pipeline"
```

---

## Task 8: Build Verification + Manual Testing

- [ ] **Step 1: Run unit tests**

```bash
npm run test:unit
```

Expected: All tests pass, including the new planes tests.

- [ ] **Step 2: Start dev server and test manually**

```bash
npm run dev
```

Test checklist:
1. Load an image
2. Switch to Planes mode → should show "Downloading depth model" progress on first use
3. After model loads, image should display as flat-shaded planes
4. Adjust plane count slider → planes should update (more/fewer facets)
5. Adjust light azimuth → shading direction changes
6. Adjust light elevation → shading intensity changes
7. Change cleanup setting → small fragments merge
8. Switch to another mode and back → should reuse cached depth (no re-download)
9. Load a new image → depth re-runs, planes update
10. Verify other modes (Value, Color, Grayscale) still work correctly

- [ ] **Step 3: Run full test suite**

```bash
npm run test
```

Expected: All unit and E2E tests pass.

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix(planes): address issues found during manual testing"
```

Only commit if changes were made. Skip if everything passed clean.
