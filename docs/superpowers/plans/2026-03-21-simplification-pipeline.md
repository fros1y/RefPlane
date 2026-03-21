# Simplification Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract image smoothing into a first-class pipeline stage with four algorithms (bilateral, kuwahara, mean-shift, anisotropic diffusion), cached intermediates, global progress reporting, and a new SimplifySettings UI component.

**Architecture:** The app maintains a `simplifiedImageData` signal as the cached intermediate. When simplification settings change, the worker runs simplification and returns the result; the app stores it and re-dispatches analysis using the simplified image. This app-side caching approach (vs. the worker-side cache in the design spec) is simpler — it avoids duplicating state in the worker and eliminates structured-clone overhead for cache hits. A global progress reporting mechanism lets any worker stage push percent-complete updates to the UI.

**Note on GPU paths:** The new simplification stage is CPU-only for all four algorithms. The existing WebGPU bilateral shaders (grayscale + Lab) remain available in `webgpu.ts` but are not wired into the simplify dispatcher in this iteration. GPU acceleration for the simplify stage is a future enhancement.

**Tech Stack:** Preact + Preact Signals, TypeScript, Web Workers, WebGPU (bilateral GPU path), Vitest (unit tests), Vite

**Design doc:** `docs/plans/2026-03-21-simplification-pipeline-design.md`

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `src/processing/simplify/params.ts` | Strength-to-params mapping for all methods |
| `src/processing/simplify/bilateral.ts` | Bilateral filter (relocated from `src/processing/bilateral.ts`) |
| `src/processing/simplify/kuwahara.ts` | Kuwahara filter implementation |
| `src/processing/simplify/mean-shift.ts` | Mean-shift filter implementation |
| `src/processing/simplify/anisotropic.ts` | Anisotropic diffusion implementation |
| `src/processing/simplify/index.ts` | Dispatcher: routes SimplifyConfig to correct algorithm |
| `src/processing/progress.ts` | Shared `reportProgress` helper for worker |
| `src/components/SimplifySettings.tsx` | UI panel for simplification method + strength + advanced |
| `tests/unit/simplify/params.test.ts` | Tests for strength-to-params mapping |
| `tests/unit/simplify/bilateral.test.ts` | Tests for relocated bilateral filter |
| `tests/unit/simplify/kuwahara.test.ts` | Tests for kuwahara filter |
| `tests/unit/simplify/mean-shift.test.ts` | Tests for mean-shift filter |
| `tests/unit/simplify/anisotropic.test.ts` | Tests for anisotropic diffusion |
| `tests/unit/simplify/dispatcher.test.ts` | Tests for simplify dispatcher |

### Modified files

| File | Changes |
|------|---------|
| `src/types.ts` | Add `SimplifyMethod`, `SimplifyConfig`; remove `strength` from `ValueConfig` and `ColorConfig`; remove `"simplified"` from `EdgeMethod` |
| `src/processing/worker.ts` | Add `simplify` message handler with cache; add progress message support; remove bilateral imports from value-study/edges paths |
| `src/processing/value-study.ts` | Remove bilateral filter call; accept pre-simplified image |
| `src/processing/color-regions.ts` | Remove bilateral filter call; accept pre-simplified image |
| `src/processing/webgpu.ts` | Update `processValueStudy` to skip bilateral step; keep `bilateralGrayscale`/`bilateralLab` for simplify stage |
| `src/app.tsx` | Add `simplifyConfig`/`simplifiedImageData`/`processingProgress` signals; rewire reactivity for two-stage pipeline; add SimplifySettings panel |
| `src/components/ValueSettings.tsx` | Remove Smoothing slider; update Notan preset to not set strength |
| `src/components/ColorSettings.tsx` | Remove Smoothing slider |
| `src/components/EdgeSettings.tsx` | Remove "simplified" method option |
| `src/components/ImageCanvas.tsx` | Show global progress indicator |
| `tests/unit/edges.test.ts` | No changes needed (tests don't use simplified method) |

---

## Task 1: Types & Params Module

**Files:**
- Modify: `src/types.ts`
- Create: `src/processing/simplify/params.ts`
- Create: `tests/unit/simplify/params.test.ts`

- [ ] **Step 1: Write failing tests for strength-to-params mapping**

```typescript
// tests/unit/simplify/params.test.ts
import { describe, expect, it } from 'vitest';
import { strengthToMethodParams } from '../../../src/processing/simplify/params';

describe('strengthToMethodParams', () => {
  it('maps strength 0 to minimum bilateral params', () => {
    const result = strengthToMethodParams('bilateral', 0);
    expect(result).toEqual({ sigmaS: 2, sigmaR: 0.05 });
  });

  it('maps strength 0.5 to midpoint bilateral params', () => {
    const result = strengthToMethodParams('bilateral', 0.5);
    expect(result).toEqual({ sigmaS: 10, sigmaR: 0.15 });
  });

  it('maps strength 1 to maximum bilateral params', () => {
    const result = strengthToMethodParams('bilateral', 1);
    expect(result).toEqual({ sigmaS: 25, sigmaR: 0.35 });
  });

  it('maps strength 0 to minimum kuwahara params', () => {
    const result = strengthToMethodParams('kuwahara', 0);
    expect(result).toEqual({ kernelSize: 3 });
  });

  it('maps strength 1 to maximum kuwahara params', () => {
    const result = strengthToMethodParams('kuwahara', 1);
    expect(result).toEqual({ kernelSize: 15 });
  });

  it('maps strength 0 to minimum mean-shift params', () => {
    const result = strengthToMethodParams('mean-shift', 0);
    expect(result).toEqual({ spatialRadius: 5, colorRadius: 10 });
  });

  it('maps strength 1 to maximum mean-shift params', () => {
    const result = strengthToMethodParams('mean-shift', 1);
    expect(result).toEqual({ spatialRadius: 30, colorRadius: 50 });
  });

  it('maps strength 0 to minimum anisotropic params', () => {
    const result = strengthToMethodParams('anisotropic', 0);
    expect(result).toEqual({ iterations: 1, kappa: 30 });
  });

  it('maps strength 1 to maximum anisotropic params', () => {
    const result = strengthToMethodParams('anisotropic', 1);
    expect(result).toEqual({ iterations: 30, kappa: 10 });
  });

  it('returns empty object for "none"', () => {
    const result = strengthToMethodParams('none', 0.5);
    expect(result).toEqual({});
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run tests/unit/simplify/params.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Update types.ts with new types**

Add to `src/types.ts`:

```typescript
export type SimplifyMethod = "none" | "bilateral" | "kuwahara" | "mean-shift" | "anisotropic";

export interface SimplifyConfig {
  method: SimplifyMethod;
  strength: number;
  bilateral: { sigmaS: number; sigmaR: number };
  kuwahara: { kernelSize: number };
  meanShift: { spatialRadius: number; colorRadius: number };
  anisotropic: { iterations: number; kappa: number };
}
```

Make `strength` optional in `ValueConfig` and `ColorConfig` (`strength?: number`) to maintain backward compatibility until Task 7 removes all usages. This avoids compilation breakage between Tasks 1-6.
Change `EdgeMethod` to `"canny" | "sobel"` (remove `"simplified"`).

- [ ] **Step 4: Implement params.ts**

```typescript
// src/processing/simplify/params.ts
import type { SimplifyMethod } from '../../types';

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function strengthToMethodParams(
  method: SimplifyMethod,
  strength: number,
): Record<string, number> {
  const s = Math.max(0, Math.min(1, strength));
  switch (method) {
    case 'bilateral': {
      let sigmaS: number, sigmaR: number;
      if (s <= 0.5) {
        const t = s / 0.5;
        sigmaS = lerp(2, 10, t);
        sigmaR = lerp(0.05, 0.15, t);
      } else {
        const t = (s - 0.5) / 0.5;
        sigmaS = lerp(10, 25, t);
        sigmaR = lerp(0.15, 0.35, t);
      }
      return { sigmaS, sigmaR };
    }
    case 'kuwahara':
      return { kernelSize: Math.round(lerp(3, 15, s)) };
    case 'mean-shift':
      return { spatialRadius: lerp(5, 30, s), colorRadius: lerp(10, 50, s) };
    case 'anisotropic':
      return { iterations: Math.round(lerp(1, 30, s)), kappa: lerp(30, 10, s) };
    case 'none':
    default:
      return {};
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `npx vitest run tests/unit/simplify/params.test.ts`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/types.ts src/processing/simplify/params.ts tests/unit/simplify/params.test.ts
git commit -m "feat: add SimplifyConfig types and strength-to-params mapping"
```

---

## Task 2: Bilateral Filter Relocation

**Files:**
- Create: `src/processing/simplify/bilateral.ts`
- Create: `tests/unit/simplify/bilateral.test.ts`
- Modify: `src/processing/bilateral.ts` (will be deleted after all consumers migrate)

- [ ] **Step 1: Write failing tests for relocated bilateral**

```typescript
// tests/unit/simplify/bilateral.test.ts
import { describe, expect, it } from 'vitest';
import { bilateralFilter } from '../../../src/processing/simplify/bilateral';
import { createImageData, setPixel } from '../../utils/image';

describe('bilateralFilter', () => {
  it('preserves a uniform image', () => {
    const image = createImageData(4, 4, [128, 128, 128, 255]);
    const result = bilateralFilter(image, 5, 0.1);
    // All pixels should remain ~128
    for (let i = 0; i < result.data.length; i += 4) {
      expect(result.data[i]).toBeCloseTo(128, -1);
    }
  });

  it('smooths interior while preserving a sharp edge', () => {
    // Left half black, right half white
    const image = createImageData(20, 10, [0, 0, 0, 255]);
    for (let y = 0; y < 10; y++) {
      for (let x = 10; x < 20; x++) {
        setPixel(image, x, y, [255, 255, 255, 255]);
      }
    }
    const result = bilateralFilter(image, 5, 0.1);
    // Far-left pixel should stay dark, far-right should stay bright
    expect(result.data[0]).toBeLessThan(30);
    expect(result.data[(9 * 20 + 19) * 4]).toBeGreaterThan(225);
  });

  it('preserves alpha channel', () => {
    const image = createImageData(2, 1, [100, 100, 100, 200]);
    const result = bilateralFilter(image, 2, 0.1);
    expect(result.data[3]).toBe(200);
    expect(result.data[7]).toBe(200);
  });

  it('accepts a progress callback', () => {
    const image = createImageData(10, 10, [128, 128, 128, 255]);
    const updates: number[] = [];
    bilateralFilter(image, 5, 0.1, (percent) => { updates.push(percent); });
    expect(updates.length).toBeGreaterThan(0);
    expect(updates[updates.length - 1]).toBeLessThanOrEqual(100);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run tests/unit/simplify/bilateral.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Create bilateral.ts in simplify directory**

Copy the `bilateralFilter` function from `src/processing/bilateral.ts` into `src/processing/simplify/bilateral.ts`. Add an optional `onProgress?: (percent: number) => void` parameter. Report progress every ~50 rows:

```typescript
// src/processing/simplify/bilateral.ts
export function bilateralFilter(
  imageData: ImageData,
  sigmaS: number,
  sigmaR: number,
  onProgress?: (percent: number) => void,
): ImageData {
  const { data, width, height } = imageData;
  const out = new ImageData(width, height);
  const outData = out.data;
  const radius = Math.ceil(2 * sigmaS);
  const sigmaS2 = 2 * sigmaS * sigmaS;
  const sigmaR2 = 2 * sigmaR * sigmaR;
  const progressInterval = Math.max(1, Math.floor(height / 20));

  for (let y = 0; y < height; y++) {
    if (onProgress && y % progressInterval === 0) {
      onProgress((y / height) * 100);
    }
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 4;
      const cR = data[idx], cG = data[idx + 1], cB = data[idx + 2];
      let sumR = 0, sumG = 0, sumB = 0, weightSum = 0;

      for (let dy = -radius; dy <= radius; dy++) {
        const ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        for (let dx = -radius; dx <= radius; dx++) {
          const nx = x + dx;
          if (nx < 0 || nx >= width) continue;
          const nIdx = (ny * width + nx) * 4;
          const nR = data[nIdx], nG = data[nIdx + 1], nB = data[nIdx + 2];
          const spatialDist = dx * dx + dy * dy;
          const dR = (cR - nR) / 255, dG = (cG - nG) / 255, dB = (cB - nB) / 255;
          const colorDist = dR * dR + dG * dG + dB * dB;
          const weight = Math.exp(-spatialDist / sigmaS2 - colorDist / sigmaR2);
          sumR += weight * nR;
          sumG += weight * nG;
          sumB += weight * nB;
          weightSum += weight;
        }
      }

      outData[idx] = Math.round(sumR / weightSum);
      outData[idx + 1] = Math.round(sumG / weightSum);
      outData[idx + 2] = Math.round(sumB / weightSum);
      outData[idx + 3] = data[idx + 3];
    }
  }
  return out;
}
```

**Note:** This version works in **RGB** space (not grayscale), since the simplify stage processes the full-color source image. The old grayscale bilateral stays in `src/processing/bilateral.ts` until the WebGPU value-study path is refactored (Task 7).

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run tests/unit/simplify/bilateral.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/processing/simplify/bilateral.ts tests/unit/simplify/bilateral.test.ts
git commit -m "feat: add RGB bilateral filter with progress reporting for simplify stage"
```

---

## Task 3: Kuwahara Filter

**Files:**
- Create: `src/processing/simplify/kuwahara.ts`
- Create: `tests/unit/simplify/kuwahara.test.ts`

- [ ] **Step 1: Write failing tests**

```typescript
// tests/unit/simplify/kuwahara.test.ts
import { describe, expect, it } from 'vitest';
import { kuwaharaFilter } from '../../../src/processing/simplify/kuwahara';
import { createImageData, setPixel } from '../../utils/image';

describe('kuwaharaFilter', () => {
  it('preserves a uniform image', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = kuwaharaFilter(image, 3);
    for (let i = 0; i < result.data.length; i += 4) {
      expect(result.data[i]).toBeCloseTo(128, -1);
    }
  });

  it('produces output with same dimensions as input', () => {
    const image = createImageData(16, 12, [100, 100, 100, 255]);
    const result = kuwaharaFilter(image, 5);
    expect(result.width).toBe(16);
    expect(result.height).toBe(12);
  });

  it('preserves alpha channel', () => {
    const image = createImageData(4, 4, [100, 100, 100, 180]);
    const result = kuwaharaFilter(image, 3);
    for (let i = 3; i < result.data.length; i += 4) {
      expect(result.data[i]).toBe(180);
    }
  });

  it('reduces variance within uniform regions', () => {
    // Create a noisy image: alternating 120 and 136 pixels
    const image = createImageData(20, 20, [128, 128, 128, 255]);
    for (let y = 0; y < 20; y++) {
      for (let x = 0; x < 20; x++) {
        const v = (x + y) % 2 === 0 ? 120 : 136;
        setPixel(image, x, y, [v, v, v, 255]);
      }
    }
    const result = kuwaharaFilter(image, 5);
    // Center pixels should be more uniform than the input
    const centerIdx = (10 * 20 + 10) * 4;
    const centerVal = result.data[centerIdx];
    const neighborVal = result.data[centerIdx + 4];
    expect(Math.abs(centerVal - neighborVal)).toBeLessThan(16);
  });

  it('accepts a progress callback', () => {
    const image = createImageData(10, 10, [128, 128, 128, 255]);
    const updates: number[] = [];
    kuwaharaFilter(image, 3, (percent) => { updates.push(percent); });
    expect(updates.length).toBeGreaterThan(0);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run tests/unit/simplify/kuwahara.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Implement kuwahara.ts**

```typescript
// src/processing/simplify/kuwahara.ts
export function kuwaharaFilter(
  imageData: ImageData,
  kernelSize: number,
  onProgress?: (percent: number) => void,
): ImageData {
  const { data, width, height } = imageData;
  const out = new ImageData(width, height);
  const outData = out.data;
  const radius = Math.floor(kernelSize / 2);
  const progressInterval = Math.max(1, Math.floor(height / 20));

  for (let y = 0; y < height; y++) {
    if (onProgress && y % progressInterval === 0) {
      onProgress((y / height) * 100);
    }
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 4;
      // Four quadrants: top-left, top-right, bottom-left, bottom-right
      const quadrants = [
        { y0: y - radius, y1: y, x0: x - radius, x1: x },
        { y0: y - radius, y1: y, x0: x, x1: x + radius },
        { y0: y, y1: y + radius, x0: x - radius, x1: x },
        { y0: y, y1: y + radius, x0: x, x1: x + radius },
      ];

      let bestVar = Infinity;
      let bestR = 0, bestG = 0, bestB = 0;

      for (const q of quadrants) {
        let sumR = 0, sumG = 0, sumB = 0;
        let sumR2 = 0, sumG2 = 0, sumB2 = 0;
        let count = 0;

        for (let qy = q.y0; qy <= q.y1; qy++) {
          if (qy < 0 || qy >= height) continue;
          for (let qx = q.x0; qx <= q.x1; qx++) {
            if (qx < 0 || qx >= width) continue;
            const qi = (qy * width + qx) * 4;
            const r = data[qi], g = data[qi + 1], b = data[qi + 2];
            sumR += r; sumG += g; sumB += b;
            sumR2 += r * r; sumG2 += g * g; sumB2 += b * b;
            count++;
          }
        }

        if (count === 0) continue;
        const meanR = sumR / count, meanG = sumG / count, meanB = sumB / count;
        const varR = sumR2 / count - meanR * meanR;
        const varG = sumG2 / count - meanG * meanG;
        const varB = sumB2 / count - meanB * meanB;
        const totalVar = varR + varG + varB;

        if (totalVar < bestVar) {
          bestVar = totalVar;
          bestR = meanR;
          bestG = meanG;
          bestB = meanB;
        }
      }

      outData[idx] = Math.round(bestR);
      outData[idx + 1] = Math.round(bestG);
      outData[idx + 2] = Math.round(bestB);
      outData[idx + 3] = data[idx + 3];
    }
  }
  return out;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run tests/unit/simplify/kuwahara.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/processing/simplify/kuwahara.ts tests/unit/simplify/kuwahara.test.ts
git commit -m "feat: add Kuwahara filter for painterly simplification"
```

---

## Task 4: Mean-Shift Filter

**Files:**
- Create: `src/processing/simplify/mean-shift.ts`
- Create: `tests/unit/simplify/mean-shift.test.ts`

- [ ] **Step 1: Write failing tests**

```typescript
// tests/unit/simplify/mean-shift.test.ts
import { describe, expect, it } from 'vitest';
import { meanShiftFilter } from '../../../src/processing/simplify/mean-shift';
import { createImageData, setPixel } from '../../utils/image';

describe('meanShiftFilter', () => {
  it('preserves a uniform image', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = meanShiftFilter(image, 10, 20);
    for (let i = 0; i < result.data.length; i += 4) {
      expect(result.data[i]).toBeCloseTo(128, -1);
    }
  });

  it('produces output with same dimensions as input', () => {
    const image = createImageData(12, 8, [100, 100, 100, 255]);
    const result = meanShiftFilter(image, 5, 10);
    expect(result.width).toBe(12);
    expect(result.height).toBe(8);
  });

  it('preserves alpha channel', () => {
    const image = createImageData(4, 4, [100, 100, 100, 170]);
    const result = meanShiftFilter(image, 5, 10);
    for (let i = 3; i < result.data.length; i += 4) {
      expect(result.data[i]).toBe(170);
    }
  });

  it('converges similar nearby colors', () => {
    // Two clusters: one around 50, one around 200
    const image = createImageData(10, 10, [50, 50, 50, 255]);
    for (let y = 5; y < 10; y++) {
      for (let x = 0; x < 10; x++) {
        setPixel(image, x, y, [200, 200, 200, 255]);
      }
    }
    const result = meanShiftFilter(image, 8, 20);
    // Center of dark region should stay dark
    expect(result.data[(2 * 10 + 5) * 4]).toBeLessThan(80);
    // Center of bright region should stay bright
    expect(result.data[(7 * 10 + 5) * 4]).toBeGreaterThan(170);
  });

  it('accepts a progress callback', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const updates: number[] = [];
    meanShiftFilter(image, 5, 10, (percent) => { updates.push(percent); });
    expect(updates.length).toBeGreaterThan(0);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run tests/unit/simplify/mean-shift.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Implement mean-shift.ts**

```typescript
// src/processing/simplify/mean-shift.ts
export function meanShiftFilter(
  imageData: ImageData,
  spatialRadius: number,
  colorRadius: number,
  onProgress?: (percent: number) => void,
): ImageData {
  const { data, width, height } = imageData;
  const out = new ImageData(width, height);
  const outData = out.data;
  const maxIter = 10;
  const convergenceThreshold = 1.0;
  const spatialR2 = spatialRadius * spatialRadius;
  const colorR2 = colorRadius * colorRadius;
  const progressInterval = Math.max(1, Math.floor(height / 20));

  for (let y = 0; y < height; y++) {
    if (onProgress && y % progressInterval === 0) {
      onProgress((y / height) * 100);
    }
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 4;
      let cx = x, cy = y;
      let cR = data[idx], cG = data[idx + 1], cB = data[idx + 2];

      for (let iter = 0; iter < maxIter; iter++) {
        let sumX = 0, sumY = 0;
        let sumR = 0, sumG = 0, sumB = 0;
        let count = 0;

        const iy = Math.round(cy), ix = Math.round(cx);
        const sr = Math.ceil(spatialRadius);
        const y0 = Math.max(0, iy - sr), y1 = Math.min(height - 1, iy + sr);
        const x0 = Math.max(0, ix - sr), x1 = Math.min(width - 1, ix + sr);

        for (let ny = y0; ny <= y1; ny++) {
          for (let nx = x0; nx <= x1; nx++) {
            const sdx = nx - cx, sdy = ny - cy;
            if (sdx * sdx + sdy * sdy > spatialR2) continue;

            const ni = (ny * width + nx) * 4;
            const dR = data[ni] - cR, dG = data[ni + 1] - cG, dB = data[ni + 2] - cB;
            if (dR * dR + dG * dG + dB * dB > colorR2) continue;

            sumX += nx; sumY += ny;
            sumR += data[ni]; sumG += data[ni + 1]; sumB += data[ni + 2];
            count++;
          }
        }

        if (count === 0) break;
        const newX = sumX / count, newY = sumY / count;
        const newR = sumR / count, newG = sumG / count, newB = sumB / count;

        const shift = Math.sqrt(
          (newX - cx) * (newX - cx) + (newY - cy) * (newY - cy) +
          (newR - cR) * (newR - cR) + (newG - cG) * (newG - cG) + (newB - cB) * (newB - cB)
        );

        cx = newX; cy = newY;
        cR = newR; cG = newG; cB = newB;

        if (shift < convergenceThreshold) break;
      }

      outData[idx] = Math.round(cR);
      outData[idx + 1] = Math.round(cG);
      outData[idx + 2] = Math.round(cB);
      outData[idx + 3] = data[idx + 3];
    }
  }
  return out;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run tests/unit/simplify/mean-shift.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/processing/simplify/mean-shift.ts tests/unit/simplify/mean-shift.test.ts
git commit -m "feat: add mean-shift filter for color-grouping simplification"
```

---

## Task 5: Anisotropic Diffusion Filter

**Files:**
- Create: `src/processing/simplify/anisotropic.ts`
- Create: `tests/unit/simplify/anisotropic.test.ts`

- [ ] **Step 1: Write failing tests**

```typescript
// tests/unit/simplify/anisotropic.test.ts
import { describe, expect, it } from 'vitest';
import { anisotropicDiffusion } from '../../../src/processing/simplify/anisotropic';
import { createImageData, setPixel } from '../../utils/image';

describe('anisotropicDiffusion', () => {
  it('preserves a uniform image', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = anisotropicDiffusion(image, 5, 20);
    for (let i = 0; i < result.data.length; i += 4) {
      expect(result.data[i]).toBeCloseTo(128, -1);
    }
  });

  it('produces output with same dimensions as input', () => {
    const image = createImageData(16, 12, [100, 100, 100, 255]);
    const result = anisotropicDiffusion(image, 3, 15);
    expect(result.width).toBe(16);
    expect(result.height).toBe(12);
  });

  it('preserves alpha channel', () => {
    const image = createImageData(4, 4, [100, 100, 100, 190]);
    const result = anisotropicDiffusion(image, 2, 20);
    for (let i = 3; i < result.data.length; i += 4) {
      expect(result.data[i]).toBe(190);
    }
  });

  it('smooths interior while preserving strong edges', () => {
    // Left half 50, right half 200 — strong edge in middle
    const image = createImageData(20, 10, [50, 50, 50, 255]);
    for (let y = 0; y < 10; y++) {
      for (let x = 10; x < 20; x++) {
        setPixel(image, x, y, [200, 200, 200, 255]);
      }
    }
    const result = anisotropicDiffusion(image, 10, 15);
    // Far interior pixels should stay close to original
    expect(result.data[(5 * 20 + 2) * 4]).toBeLessThan(80);
    expect(result.data[(5 * 20 + 17) * 4]).toBeGreaterThan(170);
  });

  it('more iterations produce smoother output', () => {
    // Add noise to a uniform region
    const image = createImageData(20, 20, [128, 128, 128, 255]);
    for (let y = 0; y < 20; y++) {
      for (let x = 0; x < 20; x++) {
        const v = 128 + ((x * 7 + y * 13) % 20) - 10; // deterministic noise
        setPixel(image, x, y, [v, v, v, 255]);
      }
    }
    const few = anisotropicDiffusion(image, 2, 20);
    const many = anisotropicDiffusion(image, 20, 20);

    // Compute variance for center region
    function variance(img: ImageData): number {
      let sum = 0, sum2 = 0, count = 0;
      for (let y = 5; y < 15; y++) {
        for (let x = 5; x < 15; x++) {
          const v = img.data[(y * 20 + x) * 4];
          sum += v; sum2 += v * v; count++;
        }
      }
      const mean = sum / count;
      return sum2 / count - mean * mean;
    }
    expect(variance(many)).toBeLessThan(variance(few));
  });

  it('accepts a progress callback', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const updates: number[] = [];
    anisotropicDiffusion(image, 5, 20, (percent) => { updates.push(percent); });
    expect(updates.length).toBeGreaterThan(0);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run tests/unit/simplify/anisotropic.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Implement anisotropic.ts**

Uses Perona-Malik diffusion with `g(∇I) = exp(-(|∇I|/κ)²)` and a fixed time step (λ = 0.25 for stability with 4-connected neighbors):

```typescript
// src/processing/simplify/anisotropic.ts
export function anisotropicDiffusion(
  imageData: ImageData,
  iterations: number,
  kappa: number,
  onProgress?: (percent: number) => void,
): ImageData {
  const { data, width, height } = imageData;
  const numPixels = width * height;
  const lambda = 0.25; // stability for 4-connected

  // Work in floating-point per channel
  let currR = new Float32Array(numPixels);
  let currG = new Float32Array(numPixels);
  let currB = new Float32Array(numPixels);
  const alpha = new Uint8ClampedArray(numPixels);

  for (let i = 0; i < numPixels; i++) {
    currR[i] = data[i * 4];
    currG[i] = data[i * 4 + 1];
    currB[i] = data[i * 4 + 2];
    alpha[i] = data[i * 4 + 3];
  }

  const kappa2 = kappa * kappa;

  function g(gradSq: number): number {
    return Math.exp(-gradSq / kappa2);
  }

  for (let iter = 0; iter < iterations; iter++) {
    if (onProgress) {
      onProgress((iter / iterations) * 100);
    }
    const nextR = new Float32Array(numPixels);
    const nextG = new Float32Array(numPixels);
    const nextB = new Float32Array(numPixels);

    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const idx = y * width + x;
        const r = currR[idx], gv = currG[idx], b = currB[idx];

        // 4-connected neighbors: north, south, east, west
        const neighbors: number[] = [];
        if (y > 0) neighbors.push((y - 1) * width + x);
        if (y < height - 1) neighbors.push((y + 1) * width + x);
        if (x > 0) neighbors.push(y * width + (x - 1));
        if (x < width - 1) neighbors.push(y * width + (x + 1));

        let dR = 0, dG = 0, dB = 0;
        for (const ni of neighbors) {
          const dnR = currR[ni] - r;
          const dnG = currG[ni] - gv;
          const dnB = currB[ni] - b;
          const gradSq = dnR * dnR + dnG * dnG + dnB * dnB;
          const coeff = g(gradSq);
          dR += coeff * dnR;
          dG += coeff * dnG;
          dB += coeff * dnB;
        }

        nextR[idx] = r + lambda * dR;
        nextG[idx] = gv + lambda * dG;
        nextB[idx] = b + lambda * dB;
      }
    }

    currR = nextR;
    currG = nextG;
    currB = nextB;
  }

  const out = new ImageData(width, height);
  const outData = out.data;
  for (let i = 0; i < numPixels; i++) {
    outData[i * 4] = Math.round(Math.max(0, Math.min(255, currR[i])));
    outData[i * 4 + 1] = Math.round(Math.max(0, Math.min(255, currG[i])));
    outData[i * 4 + 2] = Math.round(Math.max(0, Math.min(255, currB[i])));
    outData[i * 4 + 3] = alpha[i];
  }
  return out;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run tests/unit/simplify/anisotropic.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/processing/simplify/anisotropic.ts tests/unit/simplify/anisotropic.test.ts
git commit -m "feat: add Perona-Malik anisotropic diffusion filter"
```

---

## Task 6: Simplify Dispatcher

**Files:**
- Create: `src/processing/simplify/index.ts`
- Create: `tests/unit/simplify/dispatcher.test.ts`

- [ ] **Step 1: Write failing tests**

```typescript
// tests/unit/simplify/dispatcher.test.ts
import { describe, expect, it, vi } from 'vitest';
import { runSimplify } from '../../../src/processing/simplify';
import { createImageData } from '../../utils/image';
import type { SimplifyConfig } from '../../../src/types';

function makeConfig(method: SimplifyConfig['method'], strength = 0.5): SimplifyConfig {
  return {
    method,
    strength,
    bilateral: { sigmaS: 10, sigmaR: 0.15 },
    kuwahara: { kernelSize: 7 },
    meanShift: { spatialRadius: 15, colorRadius: 25 },
    anisotropic: { iterations: 10, kappa: 20 },
  };
}

describe('runSimplify', () => {
  it('returns input unchanged for method "none"', () => {
    const image = createImageData(4, 4, [128, 128, 128, 255]);
    const result = runSimplify(image, makeConfig('none'));
    expect(result.data).toEqual(image.data);
  });

  it('applies bilateral filter when method is "bilateral"', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = runSimplify(image, makeConfig('bilateral'));
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('applies kuwahara filter when method is "kuwahara"', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = runSimplify(image, makeConfig('kuwahara'));
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('applies mean-shift filter when method is "mean-shift"', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = runSimplify(image, makeConfig('mean-shift'));
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('applies anisotropic filter when method is "anisotropic"', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = runSimplify(image, makeConfig('anisotropic'));
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('passes progress callback through to algorithm', () => {
    const image = createImageData(10, 10, [128, 128, 128, 255]);
    const updates: number[] = [];
    runSimplify(image, makeConfig('bilateral'), (p) => { updates.push(p); });
    expect(updates.length).toBeGreaterThan(0);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run tests/unit/simplify/dispatcher.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Implement dispatcher**

```typescript
// src/processing/simplify/index.ts
import type { SimplifyConfig } from '../../types';
import { bilateralFilter } from './bilateral';
import { kuwaharaFilter } from './kuwahara';
import { meanShiftFilter } from './mean-shift';
import { anisotropicDiffusion } from './anisotropic';

export function runSimplify(
  imageData: ImageData,
  config: SimplifyConfig,
  onProgress?: (percent: number) => void,
): ImageData {
  switch (config.method) {
    case 'bilateral':
      return bilateralFilter(imageData, config.bilateral.sigmaS, config.bilateral.sigmaR, onProgress);
    case 'kuwahara':
      return kuwaharaFilter(imageData, config.kuwahara.kernelSize, onProgress);
    case 'mean-shift':
      return meanShiftFilter(imageData, config.meanShift.spatialRadius, config.meanShift.colorRadius, onProgress);
    case 'anisotropic':
      return anisotropicDiffusion(imageData, config.anisotropic.iterations, config.anisotropic.kappa, onProgress);
    case 'none':
    default:
      return imageData;
  }
}

export { bilateralFilter } from './bilateral';
export { kuwaharaFilter } from './kuwahara';
export { meanShiftFilter } from './mean-shift';
export { anisotropicDiffusion } from './anisotropic';
export { strengthToMethodParams } from './params';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run tests/unit/simplify/dispatcher.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/processing/simplify/index.ts tests/unit/simplify/dispatcher.test.ts
git commit -m "feat: add simplify dispatcher routing to algorithm by method"
```

---

## Task 7: Worker Pipeline Refactoring

**Files:**
- Create: `src/processing/progress.ts`
- Modify: `src/processing/worker.ts`
- Modify: `src/processing/value-study.ts`
- Modify: `src/processing/color-regions.ts`
- Modify: `src/processing/webgpu.ts`

This is the most complex task — it rewires the worker to handle the two-stage pipeline.

- [ ] **Step 1: Create progress helper**

```typescript
// src/processing/progress.ts
export type ProgressCallback = (stage: string, percent: number) => void;

export function createProgressReporter(requestId: number): ProgressCallback {
  return (stage: string, percent: number) => {
    self.postMessage({ type: 'progress', stage, percent, requestId });
  };
}
```

- [ ] **Step 2: Update value-study.ts to remove bilateral filtering**

Remove the `bilateralFilter` and `strengthToParams` imports. Remove the `strength` usage. The function now receives pre-simplified image data:

```typescript
// src/processing/value-study.ts
import { toGrayscale } from './grayscale';
import { applyQuantization } from './quantize';
import { cleanupRegions } from './regions';
import type { ValueConfig } from '../types';

export function processValueStudy(imageData: ImageData, config: ValueConfig): ImageData {
  const { thresholds, minRegionSize } = config;
  let result = toGrayscale(imageData);
  result = applyQuantization(result, thresholds);
  result = cleanupRegions(result, minRegionSize);
  return result;
}
```

- [ ] **Step 3: Update color-regions.ts to remove bilateral filtering**

Remove the bilateral filter call and GPU bilateral path. The function receives pre-simplified RGB data, converts to Lab (no filtering), then clusters. Key changes:

1. Remove imports: `bilateralFilterLab`, `strengthToParams` from `'./bilateral'`
2. Remove the `gpu?: WebGpuProcessor` parameter from `processColorRegions`
3. Remove `config.strength` usage
4. Replace `filteredLab` with direct Lab conversion (`labData`):

```typescript
// Before:
const { sigmaS, sigmaR } = strengthToParams(config.strength);
const filteredLab = gpu
  ? await gpu.bilateralLab(labData, width, height, sigmaS, sigmaR)
  : bilateralFilterLab(labData, width, height, sigmaS, sigmaR);

// After:
// No filtering — the input is already simplified upstream.
// Use labData directly wherever filteredLab was used.
```

5. The function signature becomes `processColorRegions(imageData: ImageData, config: ColorConfig)` (no longer async, no GPU param)
6. Replace all references to `filteredLab` with `labData` throughout the function

Also update the worker.ts call site to not pass `gpu` to `processColorRegions`.

- [ ] **Step 4: Update webgpu.ts processValueStudy to skip bilateral step**

The GPU value-study path currently runs bilateral → quantize. Update it to skip bilateral (just grayscale → quantize), since the input is already simplified:

In `WebGpuProcessor.processValueStudy`, remove the bilateral step — pipe grayscale directly into quantize. Remove the `strengthToParams` import.

- [ ] **Step 5: Remove `strength` from ValueConfig and ColorConfig**

Now that all consumers of `strength` have been updated, change `strength?: number` (made optional in Task 1) to fully removed from both interfaces in `src/types.ts`. Run `npx tsc --noEmit` to verify no remaining usages.

- [ ] **Step 6: Update worker.ts with simplify message and progress reporting**

Add the `simplify` message type. Add progress reporting. Remove the `simplified` edge method handling (just use canny for all remaining edge methods):

Key changes:
- Import `runSimplify` from `./simplify`
- Import `createProgressReporter` from `./progress`
- Add `{ type: 'simplify'; imageData: ImageData; config: SimplifyConfig; requestId: number }` to `WorkerMessage`
- Handle `'simplify'` in `handleMessage`: run simplification with progress, return result
- Remove the `simplified` branch from edges handling
- Remove `bilateralFilter` / `strengthToParams` imports (no longer needed in worker directly)
- Update `processColorRegions` call to not pass `gpu` parameter

- [ ] **Step 7: Run all existing tests to verify no regressions**

Run: `npx vitest run`
Expected: All tests PASS (edge tests don't reference the `simplified` method)

- [ ] **Step 8: Commit**

```bash
git add src/types.ts src/processing/progress.ts src/processing/worker.ts src/processing/value-study.ts src/processing/color-regions.ts src/processing/webgpu.ts
git commit -m "refactor: rewire worker for two-stage simplify → analyze pipeline"
```

---

## Task 8: SimplifySettings UI Component

**Files:**
- Create: `src/components/SimplifySettings.tsx`
- Modify: `src/components/ValueSettings.tsx`
- Modify: `src/components/ColorSettings.tsx`
- Modify: `src/components/EdgeSettings.tsx`

- [ ] **Step 1: Create SimplifySettings component**

```tsx
// src/components/SimplifySettings.tsx
import type { SimplifyConfig, SimplifyMethod } from '../types';
import { strengthToMethodParams } from '../processing/simplify/params';
import { useState } from 'preact/hooks';

interface Props {
  config: SimplifyConfig;
  onChange: (cfg: Partial<SimplifyConfig>) => void;
}

const methodLabels: Record<SimplifyMethod, string> = {
  'none': 'None',
  'bilateral': 'Bilateral',
  'kuwahara': 'Kuwahara',
  'mean-shift': 'Mean-Shift',
  'anisotropic': 'Anisotropic',
};

export function SimplifySettings({ config, onChange }: Props) {
  const [showAdvanced, setShowAdvanced] = useState(false);

  const handleMethodChange = (method: SimplifyMethod) => {
    // When method changes, reset advanced params to strength-derived defaults
    const params = strengthToMethodParams(method, config.strength);
    const update: Partial<SimplifyConfig> = { method };
    switch (method) {
      case 'bilateral':
        update.bilateral = { sigmaS: params.sigmaS, sigmaR: params.sigmaR };
        break;
      case 'kuwahara':
        update.kuwahara = { kernelSize: params.kernelSize };
        break;
      case 'mean-shift':
        update.meanShift = { spatialRadius: params.spatialRadius, colorRadius: params.colorRadius };
        break;
      case 'anisotropic':
        update.anisotropic = { iterations: params.iterations, kappa: params.kappa };
        break;
    }
    onChange(update);
  };

  const handleStrengthChange = (strength: number) => {
    // Update strength and derived params for current method
    const params = strengthToMethodParams(config.method, strength);
    const update: Partial<SimplifyConfig> = { strength };
    switch (config.method) {
      case 'bilateral':
        update.bilateral = { sigmaS: params.sigmaS, sigmaR: params.sigmaR };
        break;
      case 'kuwahara':
        update.kuwahara = { kernelSize: params.kernelSize };
        break;
      case 'mean-shift':
        update.meanShift = { spatialRadius: params.spatialRadius, colorRadius: params.colorRadius };
        break;
      case 'anisotropic':
        update.anisotropic = { iterations: params.iterations, kappa: params.kappa };
        break;
    }
    onChange(update);
  };

  return (
    <div class="settings-group">
      <div class="settings-row" title="Image simplification algorithm">
        <label>Method</label>
        <select
          value={config.method}
          onChange={e => handleMethodChange((e.target as HTMLSelectElement).value as SimplifyMethod)}
        >
          {Object.entries(methodLabels).map(([value, label]) => (
            <option key={value} value={value}>{label}</option>
          ))}
        </select>
      </div>

      {config.method !== 'none' && (
        <>
          <div class="settings-row" title="Overall simplification intensity">
            <label>Strength</label>
            <input
              type="range" min="0" max="1" step="0.05" value={config.strength}
              onInput={e => handleStrengthChange(Number((e.target as HTMLInputElement).value))}
              style="flex:1"
            />
          </div>

          <div class="settings-row settings-actions">
            <button
              class="btn-ghost"
              style={{ fontSize: '11px', padding: '4px 12px', borderRadius: '999px' }}
              onClick={() => setShowAdvanced(!showAdvanced)}
            >
              {showAdvanced ? '▼ Advanced' : '▶ Advanced'}
            </button>
          </div>

          {showAdvanced && config.method === 'bilateral' && (
            <>
              <div class="settings-row" title="Spatial spread of the filter kernel">
                <label>Sigma S</label>
                <input
                  type="range" min="1" max="30" step="0.5" value={config.bilateral.sigmaS}
                  onInput={e => onChange({ bilateral: { ...config.bilateral, sigmaS: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.bilateral.sigmaS.toFixed(1)}</span>
              </div>
              <div class="settings-row" title="Range tolerance — how similar values must be to be smoothed together">
                <label>Sigma R</label>
                <input
                  type="range" min="0.01" max="0.5" step="0.01" value={config.bilateral.sigmaR}
                  onInput={e => onChange({ bilateral: { ...config.bilateral, sigmaR: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.bilateral.sigmaR.toFixed(2)}</span>
              </div>
            </>
          )}

          {showAdvanced && config.method === 'kuwahara' && (
            <div class="settings-row" title="Size of the sampling quadrants">
              <label>Kernel</label>
              <input
                type="range" min="3" max="15" step="2" value={config.kuwahara.kernelSize}
                onInput={e => onChange({ kuwahara: { kernelSize: Number((e.target as HTMLInputElement).value) } })}
                style="flex:1"
              />
              <span class="settings-value">{config.kuwahara.kernelSize}</span>
            </div>
          )}

          {showAdvanced && config.method === 'mean-shift' && (
            <>
              <div class="settings-row" title="Pixel neighborhood radius">
                <label>Spatial R</label>
                <input
                  type="range" min="2" max="40" step="1" value={config.meanShift.spatialRadius}
                  onInput={e => onChange({ meanShift: { ...config.meanShift, spatialRadius: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.meanShift.spatialRadius}</span>
              </div>
              <div class="settings-row" title="Color similarity threshold">
                <label>Color R</label>
                <input
                  type="range" min="5" max="60" step="1" value={config.meanShift.colorRadius}
                  onInput={e => onChange({ meanShift: { ...config.meanShift, colorRadius: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.meanShift.colorRadius}</span>
              </div>
            </>
          )}

          {showAdvanced && config.method === 'anisotropic' && (
            <>
              <div class="settings-row" title="Number of diffusion passes">
                <label>Iterations</label>
                <input
                  type="range" min="1" max="30" step="1" value={config.anisotropic.iterations}
                  onInput={e => onChange({ anisotropic: { ...config.anisotropic, iterations: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.anisotropic.iterations}</span>
              </div>
              <div class="settings-row" title="Edge sensitivity — lower values preserve more edges">
                <label>Kappa</label>
                <input
                  type="range" min="5" max="40" step="1" value={config.anisotropic.kappa}
                  onInput={e => onChange({ anisotropic: { ...config.anisotropic, kappa: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.anisotropic.kappa}</span>
              </div>
            </>
          )}
        </>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Update ValueSettings — remove Smoothing slider**

In `src/components/ValueSettings.tsx`:
- Remove the Smoothing slider (`<div class="settings-row" title="How much to blur...">`)
- Update the Notan preset to not set `strength` (it's no longer in ValueConfig)

- [ ] **Step 3: Update ColorSettings — remove Smoothing slider**

In `src/components/ColorSettings.tsx`:
- Remove the Smoothing slider

- [ ] **Step 4: Update EdgeSettings — remove "simplified" option**

In `src/components/EdgeSettings.tsx`:
- Remove `<option value="simplified">Simplified</option>`
- Remove the `config.method === 'simplified'` condition from the Line Density display (it was OR'd with `'canny'`)

- [ ] **Step 5: Run all tests**

Run: `npx vitest run`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/components/SimplifySettings.tsx src/components/ValueSettings.tsx src/components/ColorSettings.tsx src/components/EdgeSettings.tsx
git commit -m "feat: add SimplifySettings panel; remove per-mode smoothing controls"
```

---

## Task 9: App.tsx Pipeline Rewiring

**Files:**
- Modify: `src/app.tsx`
- Modify: `src/components/ImageCanvas.tsx`

This wires everything together in the main application.

- [ ] **Step 1: Add new signals and default config to app.tsx**

Add to `src/app.tsx`:

```typescript
import { SimplifySettings } from './components/SimplifySettings';
import type { SimplifyConfig } from './types';
import { strengthToMethodParams } from './processing/simplify/params';

const defaultSimplifyConfig: SimplifyConfig = {
  method: 'none',
  strength: 0.5,
  bilateral: { sigmaS: 10, sigmaR: 0.15 },
  kuwahara: { kernelSize: 7 },
  meanShift: { spatialRadius: 15, colorRadius: 25 },
  anisotropic: { iterations: 10, kappa: 20 },
};

const simplifyConfig = signal<SimplifyConfig>(defaultSimplifyConfig);
const simplifiedImageData = signal<ImageData | null>(null);
const processingProgress = signal<{ stage: string; percent: number } | null>(null);
```

- [ ] **Step 2: Add simplify message dispatch and progress handling**

Update the worker `onmessage` handler to:
- Handle `type: 'progress'` messages → update `processingProgress` signal
- Handle `type: 'result'` for `requestType: 'simplify'` → store in `simplifiedImageData`, then trigger analysis
- Clear `processingProgress` when a result arrives

Add a `postSimplifyRequest` function that sends the source image + simplify config to the worker.

Add a `triggerSimplify` function (debounced 120ms) that calls `postSimplifyRequest` when simplify config is not `'none'`, or directly sets `simplifiedImageData = sourceImageData` when method is `'none'`.

- [ ] **Step 3: Rewire reactivity**

Replace the existing processing effects with two-stage reactivity:

```typescript
// Stage 1: source or simplify config changes → re-simplify
useEffect(() => {
  if (!sourceImageData.value) return;
  if (simplifyConfig.value.method === 'none') {
    simplifiedImageData.value = sourceImageData.value;
    return;
  }
  triggerSimplify();
}, [sourceImageData.value, simplifyConfig.value]);

// Stage 2: simplified result or analysis config changes → re-analyze
useEffect(() => {
  if (!simplifiedImageData.value) return;
  triggerAnalysis();
}, [simplifiedImageData.value, activeMode.value, valueConfig.value, colorConfig.value]);
```

Update `postMainRequest` to use `simplifiedImageData.value` as source instead of `sourceImageData.value`.

Update edge request to also use `simplifiedImageData.value` as source.

- [ ] **Step 4: Add SimplifySettings panel to JSX**

Insert between the Modes and Overlays sections:

```tsx
<section class="panel-card">
  <div class="panel-card-header">
    <div class="panel-card-title">
      <strong>Simplify</strong>
    </div>
    <span class="panel-chip">Pre</span>
  </div>
  <SimplifySettings
    config={simplifyConfig.value}
    onChange={(cfg) => { simplifyConfig.value = { ...simplifyConfig.value, ...cfg }; }}
  />
</section>
```

- [ ] **Step 5: Add global progress indicator to ImageCanvas**

Pass `processingProgress` to `ImageCanvas` and render a thin progress bar when non-null. This is a minimal CSS bar positioned at the top of the canvas area.

- [ ] **Step 6: Update handleFileChange and handleCropConfirm**

Reset `simplifiedImageData.value = null` when a new image is loaded or crop is applied. The source change will trigger re-simplification via the effect.

- [ ] **Step 7: Remove old defaultValueConfig/defaultColorConfig strength values**

Update `defaultValueConfig` and `defaultColorConfig` to remove `strength` property.

- [ ] **Step 8: Build and verify**

Run: `npx tsc -b && npx vite build`
Expected: No type errors, successful build

- [ ] **Step 9: Run all tests**

Run: `npx vitest run`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add src/app.tsx src/components/ImageCanvas.tsx
git commit -m "feat: wire simplification pipeline with cached intermediates and progress UI"
```

---

## Task 10: Cleanup & Delete Old Bilateral

**Files:**
- Delete: `src/processing/bilateral.ts` (if no longer imported)
- Verify: No remaining imports of old bilateral

- [ ] **Step 1: Check for remaining imports of old bilateral.ts**

Run: `grep -r "from.*['\"].*processing/bilateral" src/`

If any imports remain (e.g., webgpu.ts still importing `strengthToParams`), update them to import from `src/processing/simplify/params.ts` instead.

- [ ] **Step 2: Delete old bilateral.ts if fully migrated**

```bash
rm src/processing/bilateral.ts
```

- [ ] **Step 3: Build and test**

Run: `npx tsc -b && npx vite build && npx vitest run`
Expected: No errors, all tests pass

- [ ] **Step 4: Commit**

```bash
git add -u
git commit -m "chore: remove old bilateral.ts — fully replaced by simplify pipeline"
```

---

## Task 11: Manual Verification

- [ ] **Step 1: Start dev server and test pipeline**

Run: `npx vite dev`

Test each simplification method:
1. Load an image
2. Set method to Bilateral, drag Strength slider — image should re-render with smoothing
3. Switch to Kuwahara — should show painterly effect
4. Switch to Mean-Shift — should show color grouping
5. Switch to Anisotropic — should show smooth interiors, sharp edges
6. Switch to None — should show original
7. While simplified, switch to Value mode — should quantize the simplified image
8. While simplified, switch to Color mode — should cluster the simplified image
9. Enable edges — should detect edges from simplified image
10. Adjust Value levels — should NOT re-run simplification (check console timing logs)
11. Adjust Simplify strength — should re-run simplification AND downstream
12. Verify progress bar appears during slow operations (Mean-Shift, Anisotropic at high strength)
13. Open Advanced panel, tweak raw params — should update output
14. Crop image — should re-simplify from cropped source

- [ ] **Step 2: Run full test suite**

Run: `npm test`
Expected: All unit and e2e tests pass

- [ ] **Step 3: Final commit if any fixes needed**
