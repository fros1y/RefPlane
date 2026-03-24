import { throwIfAborted, yieldToEventLoop } from './cancel';

export interface KuwaharaOptions {
  onProgress?: (percent: number) => void;
  abortSignal?: AbortSignal;
  passes?: number;
  sharpness?: number;
  sectors?: 4 | 8;
  planeLabels?: Uint8Array;
}

export async function kuwaharaFilter(
  imageData: ImageData,
  kernelSize: number,
  options: KuwaharaOptions = {},
): Promise<ImageData> {
  const {
    onProgress,
    abortSignal,
    passes = 1,
    sharpness = 8,
    sectors = 8,
    planeLabels,
  } = options;

  let current = imageData;
  for (let pass = 0; pass < passes; pass++) {
    current = await kuwaharaPass(
      current, kernelSize, sharpness, sectors,
      onProgress
        ? (pct) => onProgress(((pass + pct / 100) / passes) * 100)
        : undefined,
      abortSignal,
      planeLabels,
    );
  }
  return current;
}

// Precomputed Gaussian weights for a sector, keyed by radius
const gaussianCache = new Map<number, Float64Array>();
function getGaussianKernel(radius: number): Float64Array {
  let kern = gaussianCache.get(radius);
  if (kern) return kern;
  const size = (2 * radius + 1);
  kern = new Float64Array(size * size);
  const sigma = radius / 2;
  const s2 = 2 * sigma * sigma;
  for (let dy = -radius; dy <= radius; dy++) {
    for (let dx = -radius; dx <= radius; dx++) {
      kern[(dy + radius) * size + (dx + radius)] = Math.exp(-(dx * dx + dy * dy) / s2);
    }
  }
  gaussianCache.set(radius, kern);
  return kern;
}

/**
 * Classic 4-quadrant Kuwahara pass (non-overlapping rectangular regions).
 */
async function classicPass(
  imageData: ImageData,
  kernelSize: number,
  sharpness: number,
  onProgress?: (percent: number) => void,
  abortSignal?: AbortSignal,
  planeLabels?: Uint8Array,
): Promise<ImageData> {
  const { data, width, height } = imageData;
  const out = new ImageData(width, height);
  const outData = out.data;
  const radius = Math.floor(kernelSize / 2);
  const progressInterval = Math.max(1, Math.floor(height / 20));
  const yieldInterval = 8;
  const hardSelect = sharpness >= 20;

  for (let y = 0; y < height; y++) {
    throwIfAborted(abortSignal);
    if (y > 0 && y % yieldInterval === 0) await yieldToEventLoop();
    if (onProgress && y % progressInterval === 0) onProgress((y / height) * 100);

    for (let x = 0; x < width; x++) {
      const idx = y * width + x;
      const targetLabel = planeLabels ? planeLabels[idx] : -1;
      const pixIdx = idx * 4;

      const quads = [
        { y0: y - radius, y1: y, x0: x - radius, x1: x },
        { y0: y - radius, y1: y, x0: x, x1: x + radius },
        { y0: y, y1: y + radius, x0: x - radius, x1: x },
        { y0: y, y1: y + radius, x0: x, x1: x + radius },
      ];

      const means: { r: number; g: number; b: number; var: number }[] = [];
      for (const q of quads) {
        let sumR = 0, sumG = 0, sumB = 0;
        let sumR2 = 0, sumG2 = 0, sumB2 = 0;
        let count = 0;
        for (let qy = q.y0; qy <= q.y1; qy++) {
          if (qy < 0 || qy >= height) continue;
          for (let qx = q.x0; qx <= q.x1; qx++) {
            if (qx < 0 || qx >= width) continue;

            const nIdx = qy * width + qx;
            if (planeLabels && planeLabels[nIdx] !== targetLabel) continue;

            const qi = nIdx * 4;
            const r = data[qi], g = data[qi + 1], b = data[qi + 2];
            sumR += r; sumG += g; sumB += b;
            sumR2 += r * r; sumG2 += g * g; sumB2 += b * b;
            count++;
          }
        }
        if (count === 0) continue;
        const mR = sumR / count, mG = sumG / count, mB = sumB / count;
        means.push({
          r: mR, g: mG, b: mB,
          var: (sumR2 / count - mR * mR) + (sumG2 / count - mG * mG) + (sumB2 / count - mB * mB),
        });
      }

      writeBlended(outData, pixIdx, data, means, hardSelect, sharpness);
    }
  }
  return out;
}

/**
 * Generalized Kuwahara with N overlapping circular sectors and Gaussian
 * weighting (Papari, Petkov & Campisi, 2007).
 *
 * Each sector spans (2π / N) centered at angle (i * 2π / N), with a cosine
 * membership function that provides ~50% angular overlap between neighbors.
 * Pixel contributions are weighted by a radial Gaussian, producing smooth
 * statistics that eliminate the blocky artifacts of rectangular quadrants.
 */
async function generalizedPass(
  imageData: ImageData,
  kernelSize: number,
  sharpness: number,
  numSectors: number,
  onProgress?: (percent: number) => void,
  abortSignal?: AbortSignal,
  planeLabels?: Uint8Array,
): Promise<ImageData> {
  const { data, width, height } = imageData;
  const out = new ImageData(width, height);
  const outData = out.data;
  const radius = Math.floor(kernelSize / 2);
  const progressInterval = Math.max(1, Math.floor(height / 20));
  const yieldInterval = 8;
  const hardSelect = sharpness >= 20;

  const gauss = getGaussianKernel(radius);
  const kSize = 2 * radius + 1;

  // Precompute sector center angles
  const sectorAngle = (2 * Math.PI) / numSectors;
  const centerAngles = new Float64Array(numSectors);
  for (let i = 0; i < numSectors; i++) centerAngles[i] = i * sectorAngle;

  // Precompute per-pixel sector membership weights for the kernel window.
  // membership[s][kernelIdx] = Gaussian(r) * cosMembership(angle, sectorCenter)
  const membership: Float64Array[] = [];
  for (let s = 0; s < numSectors; s++) {
    const m = new Float64Array(kSize * kSize);
    const ca = centerAngles[s];
    for (let dy = -radius; dy <= radius; dy++) {
      for (let dx = -radius; dx <= radius; dx++) {
        const ki = (dy + radius) * kSize + (dx + radius);
        if (dx === 0 && dy === 0) {
          // Center pixel belongs equally to all sectors
          m[ki] = gauss[ki] / numSectors;
          continue;
        }
        const angle = Math.atan2(dy, dx);
        // Angular distance, wrapped to [-π, π]
        let diff = angle - ca;
        if (diff > Math.PI) diff -= 2 * Math.PI;
        if (diff < -Math.PI) diff += 2 * Math.PI;
        // Raised cosine membership: 1 at center, 0 at ±sectorAngle
        const absDiff = Math.abs(diff);
        if (absDiff >= sectorAngle) {
          m[ki] = 0;
        } else {
          m[ki] = gauss[ki] * (0.5 * (1 + Math.cos(Math.PI * absDiff / sectorAngle)));
        }
      }
    }
    membership.push(m);
  }

  for (let y = 0; y < height; y++) {
    throwIfAborted(abortSignal);
    if (y > 0 && y % yieldInterval === 0) await yieldToEventLoop();
    if (onProgress && y % progressInterval === 0) onProgress((y / height) * 100);

    for (let x = 0; x < width; x++) {
      const idx = y * width + x;
      const targetLabel = planeLabels ? planeLabels[idx] : -1;
      const pixIdx = idx * 4;

      const means: { r: number; g: number; b: number; var: number }[] = [];

      for (let s = 0; s < numSectors; s++) {
        const mem = membership[s];
        let wSumR = 0, wSumG = 0, wSumB = 0;
        let wSumR2 = 0, wSumG2 = 0, wSumB2 = 0;
        let wTotal = 0;

        for (let dy = -radius; dy <= radius; dy++) {
          const ny = y + dy;
          if (ny < 0 || ny >= height) continue;
          for (let dx = -radius; dx <= radius; dx++) {
            const nx = x + dx;
            if (nx < 0 || nx >= width) continue;

            const nIdx = ny * width + nx;
            if (planeLabels && planeLabels[nIdx] !== targetLabel) continue;

            const ki = (dy + radius) * kSize + (dx + radius);
            const w = mem[ki];
            if (w === 0) continue;
            const ni = nIdx * 4;
            const r = data[ni], g = data[ni + 1], b = data[ni + 2];
            wSumR += w * r; wSumG += w * g; wSumB += w * b;
            wSumR2 += w * r * r; wSumG2 += w * g * g; wSumB2 += w * b * b;
            wTotal += w;
          }
        }

        if (wTotal < 1e-10) continue;
        const mR = wSumR / wTotal, mG = wSumG / wTotal, mB = wSumB / wTotal;
        means.push({
          r: mR, g: mG, b: mB,
          var: (wSumR2 / wTotal - mR * mR) + (wSumG2 / wTotal - mG * mG) + (wSumB2 / wTotal - mB * mB),
        });
      }

      writeBlended(outData, pixIdx, data, means, hardSelect, sharpness);
    }
  }
  return out;
}

/** Writes the blended or hard-selected output pixel. */
function writeBlended(
  outData: Uint8ClampedArray,
  idx: number,
  srcData: Uint8ClampedArray,
  means: { r: number; g: number; b: number; var: number }[],
  hardSelect: boolean,
  sharpness: number,
): void {
  if (means.length === 0) {
    outData[idx] = srcData[idx];
    outData[idx + 1] = srcData[idx + 1];
    outData[idx + 2] = srcData[idx + 2];
  } else if (hardSelect) {
    let best = means[0];
    for (let i = 1; i < means.length; i++) {
      if (means[i].var < best.var) best = means[i];
    }
    outData[idx] = Math.round(best.r);
    outData[idx + 1] = Math.round(best.g);
    outData[idx + 2] = Math.round(best.b);
  } else {
    let wR = 0, wG = 0, wB = 0, wSum = 0;
    for (const m of means) {
      const w = 1 / Math.pow(1 + m.var, sharpness / 2);
      wR += w * m.r; wG += w * m.g; wB += w * m.b;
      wSum += w;
    }
    outData[idx] = Math.round(wR / wSum);
    outData[idx + 1] = Math.round(wG / wSum);
    outData[idx + 2] = Math.round(wB / wSum);
  }
  outData[idx + 3] = srcData[idx + 3];
}

async function kuwaharaPass(
  imageData: ImageData,
  kernelSize: number,
  sharpness: number,
  sectors: 4 | 8,
  onProgress?: (percent: number) => void,
  abortSignal?: AbortSignal,
  planeLabels?: Uint8Array,
): Promise<ImageData> {
  if (sectors === 4) {
    return classicPass(imageData, kernelSize, sharpness, onProgress, abortSignal, planeLabels);
  }
  return generalizedPass(imageData, kernelSize, sharpness, sectors, onProgress, abortSignal, planeLabels);
}
