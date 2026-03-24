import type { PlanesConfig, PlaneColorStrategy } from '../types';
import { cleanupRegions } from './regions';

/**
 * Bilateral filter on a single-channel Float32 depth map.
 * Edge-preserving smoothing: flattens noise while keeping depth discontinuities sharp.
 */
export function bilateralDepthSmooth(
  depth: Float32Array, width: number, height: number, passes: number,
): Float32Array {
  if (passes <= 0) return depth;

  const radius = 3;
  const sigmaS = radius * 0.6667; // spatial sigma
  const sigmaS2 = 2 * sigmaS * sigmaS;

  // Estimate depth range for adaptive range sigma
  let minD = Infinity, maxD = -Infinity;
  for (let i = 0; i < depth.length; i++) {
    if (depth[i] < minD) minD = depth[i];
    if (depth[i] > maxD) maxD = depth[i];
  }
  const range = maxD - minD || 1;
  const sigmaR = range * 0.1; // tolerate ~10% of depth range
  const sigmaR2 = 2 * sigmaR * sigmaR;

  let src = new Float32Array(depth);
  let dst = new Float32Array(width * height);

  for (let pass = 0; pass < passes; pass++) {
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const idx = y * width + x;
        const center = src[idx];
        let sum = 0;
        let wSum = 0;

        for (let dy = -radius; dy <= radius; dy++) {
          const ny = y + dy;
          if (ny < 0 || ny >= height) continue;
          for (let dx = -radius; dx <= radius; dx++) {
            const nx = x + dx;
            if (nx < 0 || nx >= width) continue;
            const sample = src[ny * width + nx];
            const spatialDist = dx * dx + dy * dy;
            const valueDiff = center - sample;
            const w = Math.exp(-spatialDist / sigmaS2 - (valueDiff * valueDiff) / sigmaR2);
            sum += w * sample;
            wSum += w;
          }
        }
        dst[idx] = sum / wSum;
      }
    }
    // Ping-pong buffers
    if (pass < passes - 1) {
      const tmp = src;
      src = dst;
      dst = tmp;
    }
  }
  return dst;
}

/**
 * Compute surface normals from a depth map using central differences.
 * Returns Float32Array of length width * height * 3 (nx, ny, nz per pixel).
 */
export function computeNormals(
  depth: Float32Array, width: number, height: number, depthScale = 1,
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

      const dx = (right - left) * 0.5 * depthScale;
      const dy = (down - up) * 0.5 * depthScale;

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
 * Intermediate plane segmentation result.
 */
export interface PlaneSegmentation {
  labels: Uint8Array;
  centroids: Float32Array;
  width: number;
  height: number;
}

/**
 * Segment planes from a depth map.
 */
export function segmentPlanes(
  depth: Float32Array, width: number, height: number, config: PlanesConfig,
): PlaneSegmentation {
  const smoothed = bilateralDepthSmooth(depth, width, height, config.depthSmooth);
  const normals = computeNormals(smoothed, width, height, config.depthScale);
  const { labels, centroids } = clusterNormals(normals, width, height, config.planeCount);
  return { labels, centroids, width, height };
}

/**
 * Fill each plane region with a representative color from the source image.
 */
export function flatColorFill(
  imageData: ImageData,
  labels: Uint8Array,
  width: number,
  height: number,
  strategy: PlaneColorStrategy,
): ImageData {
  const numPixels = width * height;
  const source = imageData.data;
  const out = new Uint8ClampedArray(source.length);

  // Group pixels by plane
  const planePixels = new Map<number, number[]>();
  for (let i = 0; i < numPixels; i++) {
    const label = labels[i];
    if (!planePixels.has(label)) planePixels.set(label, []);
    planePixels.get(label)!.push(i);
  }

  // Calculate representative color per plane
  const planeColors = new Map<number, { r: number; g: number; b: number }>();
  for (const [label, pixels] of planePixels.entries()) {
    let r = 0, g = 0, b = 0;
    if (strategy === 'average') {
      for (const idx of pixels) {
        r += source[idx * 4]; g += source[idx * 4 + 1]; b += source[idx * 4 + 2];
      }
      r /= pixels.length; g /= pixels.length; b /= pixels.length;
    } else if (strategy === 'median') {
      const rs = pixels.map(i => source[i * 4]).sort((x, y) => x - y);
      const gs = pixels.map(i => source[i * 4 + 1]).sort((x, y) => x - y);
      const bs = pixels.map(i => source[i * 4 + 2]).sort((x, y) => x - y);
      r = rs[Math.floor(rs.length / 2)];
      g = gs[Math.floor(gs.length / 2)];
      b = bs[Math.floor(bs.length / 2)];
    } else if (strategy === 'dominant') {
      const bins = new Map<number, number>();
      for (const idx of pixels) {
        const br = source[idx * 4] >> 3;
        const bg = source[idx * 4 + 1] >> 3;
        const bb = source[idx * 4 + 2] >> 3;
        const bin = (br << 10) | (bg << 5) | bb;
        bins.set(bin, (bins.get(bin) || 0) + 1);
      }
      let maxCount = -1, dominantBin = 0;
      for (const [bin, count] of bins.entries()) {
        if (count > maxCount) { maxCount = count; dominantBin = bin; }
      }
      r = (dominantBin >> 10) << 3;
      g = ((dominantBin >> 5) & 0x1F) << 3;
      b = (dominantBin & 0x1F) << 3;
    }
    planeColors.set(label, { r: Math.round(r), g: Math.round(g), b: Math.round(b) });
  }

  for (let i = 0; i < numPixels; i++) {
    const color = planeColors.get(labels[i])!;
    const off = i * 4;
    out[off] = color.r; out[off + 1] = color.g; out[off + 2] = color.b; out[off + 3] = 255;
  }
  return new ImageData(out, width, height);
}

/**
 * Full CPU planes pipeline: depth → normals → cluster → shade/color → cleanup.
 */
export function processPlanes(
  depth: Float32Array, width: number, height: number, config: PlanesConfig,
  sourceImage?: ImageData,
): ImageData {
  const { labels, centroids } = segmentPlanes(depth, width, height, config);
  let result: ImageData;
  if (config.colorMode === 'flat-color' && sourceImage) {
    result = flatColorFill(sourceImage, labels, width, height, config.colorStrategy);
  } else {
    result = shadePlanes(labels, centroids, width, height, config.lightAzimuth, config.lightElevation);
  }
  return cleanupRegions(result, config.minRegionSize);
}
