import { cleanupRegions } from './regions';
import type { ValueConfig } from '../types';

const WORKGROUP_SIZE = 64;
const GPUBufferUsageRef = (globalThis as any).GPUBufferUsage;
const GPUMapModeRef = (globalThis as any).GPUMapMode;

type WebGpuBuffer = any;
type WebGpuComputePipeline = any;
type WebGpuDevice = any;

const grayscaleShader = /* wgsl */`
struct GrayParams {
  pixelCount: u32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: GrayParams;

fn unpack_rgba(pixel: u32) -> vec4<f32> {
  return vec4<f32>(
    f32(pixel & 0xffu),
    f32((pixel >> 8u) & 0xffu),
    f32((pixel >> 16u) & 0xffu),
    f32((pixel >> 24u) & 0xffu)
  );
}

@compute @workgroup_size(${WORKGROUP_SIZE})
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) {
    return;
  }

  let rgba = unpack_rgba(src[idx]);
  let gray = u32(clamp(round(0.2126 * rgba.x + 0.7152 * rgba.y + 0.0722 * rgba.z), 0.0, 255.0));
  let alpha = u32(rgba.w);
  dst[idx] = gray | (gray << 8u) | (gray << 16u) | (alpha << 24u);
}
`;

const bilateralGrayShader = /* wgsl */`
struct BilateralParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  radius: u32,
  sigmaS2: f32,
  sigmaR2: f32,
  _pad0: f32,
  _pad1: f32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: BilateralParams;

fn unpack_rgba(pixel: u32) -> vec4<f32> {
  return vec4<f32>(
    f32(pixel & 0xffu),
    f32((pixel >> 8u) & 0xffu),
    f32((pixel >> 16u) & 0xffu),
    f32((pixel >> 24u) & 0xffu)
  );
}

fn luminance(pixel: u32) -> f32 {
  let rgba = unpack_rgba(pixel);
  return (0.2126 * rgba.x + 0.7152 * rgba.y + 0.0722 * rgba.z) / 255.0;
}

@compute @workgroup_size(${WORKGROUP_SIZE})
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) {
    return;
  }

  let width = i32(params.width);
  let height = i32(params.height);
  let radius = i32(params.radius);
  let x = i32(idx % params.width);
  let y = i32(idx / params.width);
  let center = src[idx];
  let centerValue = luminance(center);

  var sum = 0.0;
  var weightSum = 0.0;

  for (var dy = -radius; dy <= radius; dy = dy + 1) {
    let ny = y + dy;
    if (ny < 0 || ny >= height) {
      continue;
    }

    for (var dx = -radius; dx <= radius; dx = dx + 1) {
      let nx = x + dx;
      if (nx < 0 || nx >= width) {
        continue;
      }

      let sampleIndex = u32(ny * width + nx);
      let sampleValue = luminance(src[sampleIndex]);
      let spatialDist = f32(dx * dx + dy * dy);
      let valueDiff = centerValue - sampleValue;
      let weight = exp(-spatialDist / params.sigmaS2 - (valueDiff * valueDiff) / params.sigmaR2);
      sum = sum + weight * sampleValue;
      weightSum = weightSum + weight;
    }
  }

  let result = u32(clamp(round((sum / weightSum) * 255.0), 0.0, 255.0));
  let alpha = u32((center >> 24u) & 0xffu);
  dst[idx] = result | (result << 8u) | (result << 16u) | (alpha << 24u);
}
`;

const bilateralLabShader = /* wgsl */`
struct BilateralParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  radius: u32,
  sigmaS2: f32,
  sigmaR2: f32,
  _pad0: f32,
  _pad1: f32,
};

@group(0) @binding(0) var<storage, read> src: array<f32>;
@group(0) @binding(1) var<storage, read_write> dst: array<f32>;
@group(0) @binding(2) var<uniform> params: BilateralParams;

@compute @workgroup_size(${WORKGROUP_SIZE})
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) {
    return;
  }

  let width = i32(params.width);
  let height = i32(params.height);
  let radius = i32(params.radius);
  let x = i32(idx % params.width);
  let y = i32(idx / params.width);
  let base = idx * 3u;

  let cL = src[base];
  let cA = src[base + 1u];
  let cB = src[base + 2u];

  var sumL = 0.0;
  var sumA = 0.0;
  var sumB = 0.0;
  var weightSum = 0.0;

  for (var dy = -radius; dy <= radius; dy = dy + 1) {
    let ny = y + dy;
    if (ny < 0 || ny >= height) {
      continue;
    }

    for (var dx = -radius; dx <= radius; dx = dx + 1) {
      let nx = x + dx;
      if (nx < 0 || nx >= width) {
        continue;
      }

      let sampleIndex = u32(ny * width + nx) * 3u;
      let nL = src[sampleIndex];
      let nA = src[sampleIndex + 1u];
      let nB = src[sampleIndex + 2u];
      let dL = cL - nL;
      let dA = cA - nA;
      let dB = cB - nB;
      let spatialDist = f32(dx * dx + dy * dy);
      let valueDiff2 = dL * dL + dA * dA + dB * dB;
      let weight = exp(-spatialDist / params.sigmaS2 - valueDiff2 / params.sigmaR2);
      sumL = sumL + weight * nL;
      sumA = sumA + weight * nA;
      sumB = sumB + weight * nB;
      weightSum = weightSum + weight;
    }
  }

  dst[base] = sumL / weightSum;
  dst[base + 1u] = sumA / weightSum;
  dst[base + 2u] = sumB / weightSum;
}
`;

const quantizeShader = /* wgsl */`
struct QuantizeParams {
  pixelCount: u32,
  thresholdCount: u32,
  totalLevels: u32,
  _pad0: u32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: QuantizeParams;
@group(0) @binding(3) var<storage, read> thresholds: array<f32>;

@compute @workgroup_size(${WORKGROUP_SIZE})
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) {
    return;
  }

  let pixel = src[idx];
  let value = f32(pixel & 0xffu) / 255.0;
  var level = params.thresholdCount;
  for (var i = 0u; i < params.thresholdCount; i = i + 1u) {
    if (value < thresholds[i]) {
      level = i;
      break;
    }
  }

  var gray = 128u;
  if (params.totalLevels > 1u) {
    gray = u32(clamp(round((f32(level) / f32(params.totalLevels - 1u)) * 255.0), 0.0, 255.0));
  }

  let alpha = (pixel >> 24u) & 0xffu;
  dst[idx] = gray | (gray << 8u) | (gray << 16u) | (alpha << 24u);
}
`;

const bilateralRgbShader = /* wgsl */`
struct BilateralParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  radius: u32,
  sigmaS2: f32,
  sigmaR2: f32,
  _pad0: f32,
  _pad1: f32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: BilateralParams;

fn unpack_rgba(pixel: u32) -> vec4<f32> {
  return vec4<f32>(
    f32(pixel & 0xffu),
    f32((pixel >> 8u) & 0xffu),
    f32((pixel >> 16u) & 0xffu),
    f32((pixel >> 24u) & 0xffu)
  );
}

@compute @workgroup_size(${WORKGROUP_SIZE})
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) {
    return;
  }

  let width = i32(params.width);
  let height = i32(params.height);
  let radius = i32(params.radius);
  let x = i32(idx % params.width);
  let y = i32(idx / params.width);
  let center = unpack_rgba(src[idx]);
  let cR = center.x / 255.0;
  let cG = center.y / 255.0;
  let cB = center.z / 255.0;

  var sumR = 0.0;
  var sumG = 0.0;
  var sumB = 0.0;
  var weightSum = 0.0;

  for (var dy = -radius; dy <= radius; dy = dy + 1) {
    let ny = y + dy;
    if (ny < 0 || ny >= height) {
      continue;
    }
    for (var dx = -radius; dx <= radius; dx = dx + 1) {
      let nx = x + dx;
      if (nx < 0 || nx >= width) {
        continue;
      }

      let sample = unpack_rgba(src[u32(ny * width + nx)]);
      let nR = sample.x / 255.0;
      let nG = sample.y / 255.0;
      let nB = sample.z / 255.0;
      let spatialDist = f32(dx * dx + dy * dy);
      let dR = cR - nR;
      let dG = cG - nG;
      let dB = cB - nB;
      let colorDist = dR * dR + dG * dG + dB * dB;
      let weight = exp(-spatialDist / params.sigmaS2 - colorDist / params.sigmaR2);

      sumR = sumR + weight * sample.x;
      sumG = sumG + weight * sample.y;
      sumB = sumB + weight * sample.z;
      weightSum = weightSum + weight;
    }
  }

  let r = u32(clamp(round(sumR / weightSum), 0.0, 255.0));
  let g = u32(clamp(round(sumG / weightSum), 0.0, 255.0));
  let b = u32(clamp(round(sumB / weightSum), 0.0, 255.0));
  let a = u32(center.w);
  dst[idx] = r | (g << 8u) | (b << 16u) | (a << 24u);
}
`;

const kuwaharaShader = /* wgsl */`
struct KuwaharaParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  radius: u32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: KuwaharaParams;

fn unpack_rgba(pixel: u32) -> vec4<f32> {
  return vec4<f32>(
    f32(pixel & 0xffu),
    f32((pixel >> 8u) & 0xffu),
    f32((pixel >> 16u) & 0xffu),
    f32((pixel >> 24u) & 0xffu)
  );
}

fn accumulate_q(x0: i32, x1: i32, y0: i32, y1: i32, width: i32, height: i32) -> vec4<f32> {
  var sum = vec3<f32>(0.0);
  var sum2 = vec3<f32>(0.0);
  var count = 0.0;
  for (var y = y0; y <= y1; y = y + 1) {
    if (y < 0 || y >= height) { continue; }
    for (var x = x0; x <= x1; x = x + 1) {
      if (x < 0 || x >= width) { continue; }
      let c = unpack_rgba(src[u32(y * width + x)]).xyz;
      sum = sum + c;
      sum2 = sum2 + c * c;
      count = count + 1.0;
    }
  }
  if (count <= 0.0) {
    return vec4<f32>(0.0, 0.0, 0.0, 1e12);
  }
  let mean = sum / count;
  let variance = sum2 / count - mean * mean;
  return vec4<f32>(mean, variance.x + variance.y + variance.z);
}

@compute @workgroup_size(${WORKGROUP_SIZE})
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) {
    return;
  }
  let width = i32(params.width);
  let height = i32(params.height);
  let radius = i32(params.radius);
  let x = i32(idx % params.width);
  let y = i32(idx / params.width);

  let q0 = accumulate_q(x - radius, x, y - radius, y, width, height);
  let q1 = accumulate_q(x, x + radius, y - radius, y, width, height);
  let q2 = accumulate_q(x - radius, x, y, y + radius, width, height);
  let q3 = accumulate_q(x, x + radius, y, y + radius, width, height);

  var best = q0;
  if (q1.w < best.w) { best = q1; }
  if (q2.w < best.w) { best = q2; }
  if (q3.w < best.w) { best = q3; }

  let alpha = (src[idx] >> 24u) & 0xffu;
  let r = u32(clamp(round(best.x), 0.0, 255.0));
  let g = u32(clamp(round(best.y), 0.0, 255.0));
  let b = u32(clamp(round(best.z), 0.0, 255.0));
  dst[idx] = r | (g << 8u) | (b << 16u) | (alpha << 24u);
}
`;

const meanShiftShader = /* wgsl */`
struct MeanShiftParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  maxIter: u32,
  spatialRadius: f32,
  colorRadius2: f32,
  convergenceThreshold: f32,
  _pad0: f32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: MeanShiftParams;

fn unpack_rgba(pixel: u32) -> vec4<f32> {
  return vec4<f32>(
    f32(pixel & 0xffu),
    f32((pixel >> 8u) & 0xffu),
    f32((pixel >> 16u) & 0xffu),
    f32((pixel >> 24u) & 0xffu)
  );
}

@compute @workgroup_size(${WORKGROUP_SIZE})
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) { return; }

  let width = i32(params.width);
  let height = i32(params.height);
  var cx = f32(i32(idx % params.width));
  var cy = f32(i32(idx / params.width));

  let center = unpack_rgba(src[idx]);
  var cR = center.x;
  var cG = center.y;
  var cB = center.z;
  let alpha = u32(center.w);

  let sr = i32(ceil(params.spatialRadius));
  let spatialR2 = params.spatialRadius * params.spatialRadius;

  for (var iter = 0u; iter < params.maxIter; iter = iter + 1u) {
    let ix = i32(round(cx));
    let iy = i32(round(cy));
    let y0 = max(0, iy - sr);
    let y1 = min(height - 1, iy + sr);
    let x0 = max(0, ix - sr);
    let x1 = min(width - 1, ix + sr);

    var sumX = 0.0;
    var sumY = 0.0;
    var sumR = 0.0;
    var sumG = 0.0;
    var sumB = 0.0;
    var count = 0.0;

    for (var ny = y0; ny <= y1; ny = ny + 1) {
      for (var nx = x0; nx <= x1; nx = nx + 1) {
        let dx = f32(nx) - cx;
        let dy = f32(ny) - cy;
        if (dx * dx + dy * dy > spatialR2) { continue; }

        let s = unpack_rgba(src[u32(ny * width + nx)]);
        let dR = s.x - cR;
        let dG = s.y - cG;
        let dB = s.z - cB;
        if (dR * dR + dG * dG + dB * dB > params.colorRadius2) { continue; }

        sumX = sumX + f32(nx);
        sumY = sumY + f32(ny);
        sumR = sumR + s.x;
        sumG = sumG + s.y;
        sumB = sumB + s.z;
        count = count + 1.0;
      }
    }

    if (count <= 0.0) { break; }

    let newX = sumX / count;
    let newY = sumY / count;
    let newR = sumR / count;
    let newG = sumG / count;
    let newB = sumB / count;

    let shift = sqrt((newR - cR) * (newR - cR) + (newG - cG) * (newG - cG) + (newB - cB) * (newB - cB));

    cx = newX;
    cy = newY;
    cR = newR;
    cG = newG;
    cB = newB;

    if (shift < params.convergenceThreshold) { break; }
  }

  let r = u32(clamp(round(cR), 0.0, 255.0));
  let g = u32(clamp(round(cG), 0.0, 255.0));
  let b = u32(clamp(round(cB), 0.0, 255.0));
  dst[idx] = r | (g << 8u) | (b << 16u) | (alpha << 24u);
}
`;

const anisotropicShader = /* wgsl */`
struct AnisoParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  _pad0: u32,
  kappa2: f32,
  lambda: f32,
  _pad1: f32,
  _pad2: f32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: AnisoParams;

fn unpack_rgba(pixel: u32) -> vec4<f32> {
  return vec4<f32>(
    f32(pixel & 0xffu),
    f32((pixel >> 8u) & 0xffu),
    f32((pixel >> 16u) & 0xffu),
    f32((pixel >> 24u) & 0xffu)
  );
}

fn get_rgb(x: i32, y: i32, width: i32) -> vec3<f32> {
  let p = unpack_rgba(src[u32(y * width + x)]);
  return p.xyz;
}

@compute @workgroup_size(${WORKGROUP_SIZE})
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) { return; }

  let width = i32(params.width);
  let height = i32(params.height);
  let x = i32(idx % params.width);
  let y = i32(idx / params.width);
  let centerPixel = unpack_rgba(src[idx]);
  let center = centerPixel.xyz;
  let alpha = u32(centerPixel.w);

  var delta = vec3<f32>(0.0);

  if (y > 0) {
    let n = get_rgb(x, y - 1, width);
    let d = n - center;
    let gradSq = dot(d, d);
    delta = delta + exp(-gradSq / params.kappa2) * d;
  }
  if (y < height - 1) {
    let n = get_rgb(x, y + 1, width);
    let d = n - center;
    let gradSq = dot(d, d);
    delta = delta + exp(-gradSq / params.kappa2) * d;
  }
  if (x > 0) {
    let n = get_rgb(x - 1, y, width);
    let d = n - center;
    let gradSq = dot(d, d);
    delta = delta + exp(-gradSq / params.kappa2) * d;
  }
  if (x < width - 1) {
    let n = get_rgb(x + 1, y, width);
    let d = n - center;
    let gradSq = dot(d, d);
    delta = delta + exp(-gradSq / params.kappa2) * d;
  }

  let out = center + params.lambda * delta;
  let r = u32(clamp(round(out.x), 0.0, 255.0));
  let g = u32(clamp(round(out.y), 0.0, 255.0));
  let b = u32(clamp(round(out.z), 0.0, 255.0));
  dst[idx] = r | (g << 8u) | (b << 16u) | (alpha << 24u);
}
`;

const sobelShader = /* wgsl */`
struct SobelParams {
  width: u32,
  height: u32,
  pixelCount: u32,
  _pad0: u32,
  threshold: f32,
  _pad1: f32,
  _pad2: f32,
  _pad3: f32,
};

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> dst: array<u32>;
@group(0) @binding(2) var<uniform> params: SobelParams;

fn gray01(p: u32) -> f32 {
  return f32(p & 0xffu) / 255.0;
}

fn at(x: i32, y: i32, width: i32) -> f32 {
  return gray01(src[u32(y * width + x)]);
}

@compute @workgroup_size(${WORKGROUP_SIZE})
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.pixelCount) { return; }

  let width = i32(params.width);
  let height = i32(params.height);
  let x = i32(idx % params.width);
  let y = i32(idx / params.width);
  if (x <= 0 || y <= 0 || x >= width - 1 || y >= height - 1) {
    let a = (src[idx] >> 24u) & 0xffu;
    dst[idx] = a << 24u;
    return;
  }

  let gx = -at(x - 1, y - 1, width) - 2.0 * at(x - 1, y, width) - at(x - 1, y + 1, width)
    + at(x + 1, y - 1, width) + 2.0 * at(x + 1, y, width) + at(x + 1, y + 1, width);
  let gy = -at(x - 1, y - 1, width) - 2.0 * at(x, y - 1, width) - at(x + 1, y - 1, width)
    + at(x - 1, y + 1, width) + 2.0 * at(x, y + 1, width) + at(x + 1, y + 1, width);

  let mag = sqrt(gx * gx + gy * gy) / 4.0;
  var v = 0u;
  if (mag > params.threshold) {
    v = u32(clamp(round(mag * 255.0), 0.0, 255.0));
  }
  dst[idx] = v | (v << 8u) | (v << 16u) | (0xffu << 24u);
}
`;

const kMeansAssignShader = /* wgsl */`
struct KMeansParams {
  numPixels: u32,
  k: u32,
  _pad0: u32,
  _pad1: u32,
  lWeight: f32,
  _pad2: f32,
  _pad3: f32,
  _pad4: f32,
};

@group(0) @binding(0) var<storage, read> pixels: array<f32>;
@group(0) @binding(1) var<storage, read> centroids: array<f32>;
@group(0) @binding(2) var<storage, read_write> assignments: array<u32>;
@group(0) @binding(3) var<uniform> params: KMeansParams;

@compute @workgroup_size(${WORKGROUP_SIZE})
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx >= params.numPixels) { return; }

  let base = idx * 3u;
  let pL = pixels[base];
  let pA = pixels[base + 1u];
  let pB = pixels[base + 2u];

  var bestDist = 1e20;
  var bestC = 0u;
  for (var ci = 0u; ci < params.k; ci = ci + 1u) {
    let cBase = ci * 3u;
    let dL = pL - centroids[cBase];
    let dA = pA - centroids[cBase + 1u];
    let dB = pB - centroids[cBase + 2u];
    let dist = params.lWeight * dL * dL + dA * dA + dB * dB;
    if (dist < bestDist) {
      bestDist = dist;
      bestC = ci;
    }
  }

  assignments[idx] = bestC;
}
`;

function imageDataToPackedRgba(imageData: ImageData): Uint32Array {
  const { data, width, height } = imageData;
  const packed = new Uint32Array(width * height);
  for (let i = 0, pixel = 0; i < data.length; i += 4, pixel++) {
    packed[pixel] = data[i]
      | (data[i + 1] << 8)
      | (data[i + 2] << 16)
      | (data[i + 3] << 24);
  }
  return packed;
}

function packedRgbaToImageData(packed: Uint32Array, width: number, height: number): ImageData {
  const out = new Uint8ClampedArray(width * height * 4);
  for (let i = 0; i < packed.length; i++) {
    const pixel = packed[i];
    const offset = i * 4;
    out[offset] = pixel & 0xff;
    out[offset + 1] = (pixel >>> 8) & 0xff;
    out[offset + 2] = (pixel >>> 16) & 0xff;
    out[offset + 3] = (pixel >>> 24) & 0xff;
  }
  return new ImageData(out, width, height);
}

function toUint8View(data: ArrayBuffer | ArrayBufferView): Uint8Array {
  if (data instanceof ArrayBuffer) {
    return new Uint8Array(data);
  }
  return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
}

function createBufferWithData(device: WebGpuDevice, data: ArrayBuffer | ArrayBufferView, usage: number): WebGpuBuffer {
  const bytes = toUint8View(data);
  const buffer = device.createBuffer({
    size: alignTo(bytes.byteLength, 4),
    usage,
    mappedAtCreation: true,
  });
  const mapped = buffer.getMappedRange();
  new Uint8Array(mapped).set(bytes);
  buffer.unmap();
  return buffer;
}

function createBilateralParams(width: number, height: number, radius: number, sigmaS: number, sigmaR: number): Uint8Array {
  const buffer = new ArrayBuffer(32);
  const view = new DataView(buffer);
  const pixelCount = width * height;
  view.setUint32(0, width, true);
  view.setUint32(4, height, true);
  view.setUint32(8, pixelCount, true);
  view.setUint32(12, radius, true);
  view.setFloat32(16, 2 * sigmaS * sigmaS, true);
  view.setFloat32(20, 2 * sigmaR * sigmaR, true);
  return new Uint8Array(buffer);
}

function createPixelCountParams(pixelCount: number): Uint8Array {
  const buffer = new ArrayBuffer(16);
  new DataView(buffer).setUint32(0, pixelCount, true);
  return new Uint8Array(buffer);
}

function createQuantizeParams(pixelCount: number, thresholdCount: number): Uint8Array {
  const buffer = new ArrayBuffer(16);
  const view = new DataView(buffer);
  view.setUint32(0, pixelCount, true);
  view.setUint32(4, thresholdCount, true);
  view.setUint32(8, thresholdCount + 1, true);
  return new Uint8Array(buffer);
}

function createKuwaharaParams(width: number, height: number, kernelSize: number): Uint8Array {
  const buffer = new ArrayBuffer(16);
  const view = new DataView(buffer);
  view.setUint32(0, width, true);
  view.setUint32(4, height, true);
  view.setUint32(8, width * height, true);
  view.setUint32(12, Math.max(1, Math.floor(kernelSize / 2)), true);
  return new Uint8Array(buffer);
}

function createMeanShiftParams(width: number, height: number, spatialRadius: number, colorRadius: number): Uint8Array {
  const buffer = new ArrayBuffer(32);
  const view = new DataView(buffer);
  view.setUint32(0, width, true);
  view.setUint32(4, height, true);
  view.setUint32(8, width * height, true);
  view.setUint32(12, 10, true);
  view.setFloat32(16, spatialRadius, true);
  view.setFloat32(20, colorRadius * colorRadius, true);
  view.setFloat32(24, 1.0, true);
  return new Uint8Array(buffer);
}

function createAnisotropicParams(width: number, height: number, kappa: number): Uint8Array {
  const buffer = new ArrayBuffer(32);
  const view = new DataView(buffer);
  view.setUint32(0, width, true);
  view.setUint32(4, height, true);
  view.setUint32(8, width * height, true);
  view.setFloat32(16, kappa * kappa, true);
  view.setFloat32(20, 0.25, true);
  return new Uint8Array(buffer);
}

function createSobelParams(width: number, height: number, threshold: number): Uint8Array {
  const buffer = new ArrayBuffer(32);
  const view = new DataView(buffer);
  view.setUint32(0, width, true);
  view.setUint32(4, height, true);
  view.setUint32(8, width * height, true);
  view.setFloat32(16, threshold, true);
  return new Uint8Array(buffer);
}

function createKMeansParams(numPixels: number, k: number, lWeight: number): Uint8Array {
  const buffer = new ArrayBuffer(32);
  const view = new DataView(buffer);
  view.setUint32(0, numPixels, true);
  view.setUint32(4, k, true);
  view.setFloat32(16, lWeight, true);
  return new Uint8Array(buffer);
}

function alignTo(value: number, alignment: number): number {
  return Math.ceil(value / alignment) * alignment;
}

async function readBackBuffer(device: WebGpuDevice, source: WebGpuBuffer, byteLength: number): Promise<ArrayBuffer> {
  const readback = device.createBuffer({
    size: alignTo(byteLength, 4),
    usage: GPUBufferUsageRef.COPY_DST | GPUBufferUsageRef.MAP_READ,
  });

  const encoder = device.createCommandEncoder();
  encoder.copyBufferToBuffer(source, 0, readback, 0, byteLength);
  device.queue.submit([encoder.finish()]);

  await readback.mapAsync(GPUMapModeRef.READ);
  const mapped = readback.getMappedRange();
  const copy = mapped.slice(0);
  readback.unmap();
  readback.destroy();
  return copy;
}

export class WebGpuProcessor {
  private readonly grayscalePipeline: WebGpuComputePipeline;
  private readonly bilateralGrayPipeline: WebGpuComputePipeline;
  private readonly bilateralLabPipeline: WebGpuComputePipeline;
  private readonly quantizePipeline: WebGpuComputePipeline;
  private readonly bilateralRgbPipeline: WebGpuComputePipeline;
  private readonly kuwaharaPipeline: WebGpuComputePipeline;
  private readonly meanShiftPipeline: WebGpuComputePipeline;
  private readonly anisotropicPipeline: WebGpuComputePipeline;
  private readonly sobelPipeline: WebGpuComputePipeline;
  private readonly kMeansAssignPipeline: WebGpuComputePipeline;

  private constructor(private readonly device: WebGpuDevice) {
    this.grayscalePipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: grayscaleShader }),
        entryPoint: 'main',
      },
    });
    this.bilateralGrayPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: bilateralGrayShader }),
        entryPoint: 'main',
      },
    });
    this.bilateralLabPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: bilateralLabShader }),
        entryPoint: 'main',
      },
    });
    this.quantizePipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: quantizeShader }),
        entryPoint: 'main',
      },
    });
    this.bilateralRgbPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: bilateralRgbShader }),
        entryPoint: 'main',
      },
    });
    this.kuwaharaPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: kuwaharaShader }),
        entryPoint: 'main',
      },
    });
    this.meanShiftPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: meanShiftShader }),
        entryPoint: 'main',
      },
    });
    this.anisotropicPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: anisotropicShader }),
        entryPoint: 'main',
      },
    });
    this.sobelPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: sobelShader }),
        entryPoint: 'main',
      },
    });
    this.kMeansAssignPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: kMeansAssignShader }),
        entryPoint: 'main',
      },
    });
  }

  static async create(): Promise<WebGpuProcessor | null> {
    const nav = typeof navigator === 'undefined' ? undefined : (navigator as Navigator & { gpu?: any });
    if (nav?.webdriver) {
      return null;
    }
    if (!nav?.gpu) {
      return null;
    }

    const adapter = await nav.gpu.requestAdapter({ powerPreference: 'high-performance' });
    if (!adapter) {
      return null;
    }

    const device = await adapter.requestDevice();
    return new WebGpuProcessor(device);
  }

  async toGrayscale(imageData: ImageData): Promise<ImageData> {
    const pixelCount = imageData.width * imageData.height;
    const packed = imageDataToPackedRgba(imageData);
    const srcBuffer = createBufferWithData(
      this.device,
      packed,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const dstBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const paramsBuffer = createBufferWithData(
      this.device,
      createPixelCountParams(pixelCount),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    this.runCompute(this.grayscalePipeline, [srcBuffer, dstBuffer, paramsBuffer], pixelCount);

    const result = new Uint32Array(await readBackBuffer(this.device, dstBuffer, packed.byteLength));
    srcBuffer.destroy();
    dstBuffer.destroy();
    paramsBuffer.destroy();
    return packedRgbaToImageData(result, imageData.width, imageData.height);
  }

  async bilateralGrayscale(imageData: ImageData, sigmaS: number, sigmaR: number): Promise<ImageData> {
    const pixelCount = imageData.width * imageData.height;
    const packed = imageDataToPackedRgba(imageData);
    const srcBuffer = createBufferWithData(
      this.device,
      packed,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const dstBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const paramsBuffer = createBufferWithData(
      this.device,
      createBilateralParams(imageData.width, imageData.height, Math.ceil(2 * sigmaS), sigmaS, sigmaR),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    this.runCompute(this.bilateralGrayPipeline, [srcBuffer, dstBuffer, paramsBuffer], pixelCount);

    const result = new Uint32Array(await readBackBuffer(this.device, dstBuffer, packed.byteLength));
    srcBuffer.destroy();
    dstBuffer.destroy();
    paramsBuffer.destroy();
    return packedRgbaToImageData(result, imageData.width, imageData.height);
  }

  async quantizeGrayscale(imageData: ImageData, thresholds: number[]): Promise<ImageData> {
    const pixelCount = imageData.width * imageData.height;
    const packed = imageDataToPackedRgba(imageData);
    const srcBuffer = createBufferWithData(
      this.device,
      packed,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const dstBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const paramsBuffer = createBufferWithData(
      this.device,
      createQuantizeParams(pixelCount, thresholds.length),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );
    const thresholdBuffer = createBufferWithData(
      this.device,
      new Float32Array(thresholds.length > 0 ? thresholds : [0]),
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );

    this.runCompute(this.quantizePipeline, [srcBuffer, dstBuffer, paramsBuffer, thresholdBuffer], pixelCount);

    const result = new Uint32Array(await readBackBuffer(this.device, dstBuffer, packed.byteLength));
    destroyBuffers(srcBuffer, dstBuffer, paramsBuffer, thresholdBuffer);
    return packedRgbaToImageData(result, imageData.width, imageData.height);
  }

  async bilateralRgb(imageData: ImageData, sigmaS: number, sigmaR: number): Promise<ImageData> {
    const pixelCount = imageData.width * imageData.height;
    const packed = imageDataToPackedRgba(imageData);
    const srcBuffer = createBufferWithData(
      this.device,
      packed,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const dstBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const paramsBuffer = createBufferWithData(
      this.device,
      createBilateralParams(imageData.width, imageData.height, Math.ceil(2 * sigmaS), sigmaS, sigmaR),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    this.runCompute(this.bilateralRgbPipeline, [srcBuffer, dstBuffer, paramsBuffer], pixelCount);
    const result = new Uint32Array(await readBackBuffer(this.device, dstBuffer, packed.byteLength));
    destroyBuffers(srcBuffer, dstBuffer, paramsBuffer);
    return packedRgbaToImageData(result, imageData.width, imageData.height);
  }

  async kuwahara(imageData: ImageData, kernelSize: number): Promise<ImageData> {
    const pixelCount = imageData.width * imageData.height;
    const packed = imageDataToPackedRgba(imageData);
    const srcBuffer = createBufferWithData(
      this.device,
      packed,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const dstBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const paramsBuffer = createBufferWithData(
      this.device,
      createKuwaharaParams(imageData.width, imageData.height, kernelSize),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    this.runCompute(this.kuwaharaPipeline, [srcBuffer, dstBuffer, paramsBuffer], pixelCount);
    const result = new Uint32Array(await readBackBuffer(this.device, dstBuffer, packed.byteLength));
    destroyBuffers(srcBuffer, dstBuffer, paramsBuffer);
    return packedRgbaToImageData(result, imageData.width, imageData.height);
  }

  async meanShift(imageData: ImageData, spatialRadius: number, colorRadius: number): Promise<ImageData> {
    const pixelCount = imageData.width * imageData.height;
    const packed = imageDataToPackedRgba(imageData);
    const srcBuffer = createBufferWithData(
      this.device,
      packed,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const dstBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const paramsBuffer = createBufferWithData(
      this.device,
      createMeanShiftParams(imageData.width, imageData.height, spatialRadius, colorRadius),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    this.runCompute(this.meanShiftPipeline, [srcBuffer, dstBuffer, paramsBuffer], pixelCount);
    const result = new Uint32Array(await readBackBuffer(this.device, dstBuffer, packed.byteLength));
    destroyBuffers(srcBuffer, dstBuffer, paramsBuffer);
    return packedRgbaToImageData(result, imageData.width, imageData.height);
  }

  async anisotropic(imageData: ImageData, iterations: number, kappa: number): Promise<ImageData> {
    const pixelCount = imageData.width * imageData.height;
    const packed = imageDataToPackedRgba(imageData);
    let srcBuffer = createBufferWithData(
      this.device,
      packed,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    let dstBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC | GPUBufferUsageRef.COPY_DST,
    });
    const paramsBuffer = createBufferWithData(
      this.device,
      createAnisotropicParams(imageData.width, imageData.height, kappa),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    for (let i = 0; i < iterations; i++) {
      this.runCompute(this.anisotropicPipeline, [srcBuffer, dstBuffer, paramsBuffer], pixelCount);
      const temp = srcBuffer;
      srcBuffer = dstBuffer;
      dstBuffer = temp;
    }

    const result = new Uint32Array(await readBackBuffer(this.device, srcBuffer, packed.byteLength));
    destroyBuffers(srcBuffer, dstBuffer, paramsBuffer);
    return packedRgbaToImageData(result, imageData.width, imageData.height);
  }

  async sobelEdges(imageData: ImageData, sensitivity: number): Promise<ImageData> {
    const pixelCount = imageData.width * imageData.height;
    const packed = imageDataToPackedRgba(imageData);
    const threshold = 0.16 - sensitivity * 0.145;
    const srcBuffer = createBufferWithData(
      this.device,
      packed,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const dstBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const paramsBuffer = createBufferWithData(
      this.device,
      createSobelParams(imageData.width, imageData.height, threshold),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    this.runCompute(this.sobelPipeline, [srcBuffer, dstBuffer, paramsBuffer], pixelCount);
    const result = new Uint32Array(await readBackBuffer(this.device, dstBuffer, packed.byteLength));
    destroyBuffers(srcBuffer, dstBuffer, paramsBuffer);
    return packedRgbaToImageData(result, imageData.width, imageData.height);
  }

  async cannyEdges(imageData: ImageData, detail: number): Promise<ImageData> {
    const boostedDetail = Math.pow(detail, 0.72);
    const sensitivity = Math.max(0, Math.min(1, 1 - boostedDetail * 0.4));
    return this.sobelEdges(imageData, sensitivity);
  }

  async kMeansAssign(
    pixels: Float32Array,
    numPixels: number,
    centroids: Float32Array,
    lWeight: number,
  ): Promise<Int32Array> {
    const srcBuffer = createBufferWithData(
      this.device,
      pixels,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const centroidsBuffer = createBufferWithData(
      this.device,
      centroids,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const outBuffer = this.device.createBuffer({
      size: alignTo(numPixels * 4, 4),
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const paramsBuffer = createBufferWithData(
      this.device,
      createKMeansParams(numPixels, Math.floor(centroids.length / 3), lWeight),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    this.runCompute(this.kMeansAssignPipeline, [srcBuffer, centroidsBuffer, outBuffer, paramsBuffer], numPixels);
    const mapped = new Uint32Array(await readBackBuffer(this.device, outBuffer, numPixels * 4));
    destroyBuffers(srcBuffer, centroidsBuffer, outBuffer, paramsBuffer);

    const out = new Int32Array(numPixels);
    for (let i = 0; i < numPixels; i++) {
      out[i] = mapped[i];
    }
    return out;
  }

  async bilateralLab(labData: Float32Array, width: number, height: number, sigmaS: number, sigmaR: number): Promise<Float32Array> {
    const pixelCount = width * height;
    const srcBuffer = createBufferWithData(
      this.device,
      labData,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const dstBuffer = this.device.createBuffer({
      size: labData.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const paramsBuffer = createBufferWithData(
      this.device,
      createBilateralParams(width, height, Math.ceil(2 * sigmaS), sigmaS, sigmaR),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    this.runCompute(this.bilateralLabPipeline, [srcBuffer, dstBuffer, paramsBuffer], pixelCount);

    const result = new Float32Array(await readBackBuffer(this.device, dstBuffer, labData.byteLength));
    srcBuffer.destroy();
    dstBuffer.destroy();
    paramsBuffer.destroy();
    return result;
  }

  async processValueStudy(imageData: ImageData, config: ValueConfig): Promise<ImageData> {
    const pixelCount = imageData.width * imageData.height;
    const packed = imageDataToPackedRgba(imageData);

    // Stage 1: Grayscale
    const srcBuffer = createBufferWithData(
      this.device,
      packed,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const grayBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC | GPUBufferUsageRef.COPY_DST,
    });
    const grayParamsBuffer = createBufferWithData(
      this.device,
      createPixelCountParams(pixelCount),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    this.runCompute(this.grayscalePipeline, [srcBuffer, grayBuffer, grayParamsBuffer], pixelCount);

    // Stage 2: Quantize (no bilateral — input is pre-simplified upstream)
    const quantizedBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const quantizeParamsBuffer = createBufferWithData(
      this.device,
      createQuantizeParams(pixelCount, config.thresholds.length),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );
    const thresholdBuffer = createBufferWithData(
      this.device,
      new Float32Array(config.thresholds.length > 0 ? config.thresholds : [0]),
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );

    this.runCompute(this.quantizePipeline, [grayBuffer, quantizedBuffer, quantizeParamsBuffer, thresholdBuffer], pixelCount);

    const quantizedPacked = new Uint32Array(await readBackBuffer(this.device, quantizedBuffer, packed.byteLength));
    destroyBuffers(srcBuffer, grayBuffer, grayParamsBuffer, quantizedBuffer, quantizeParamsBuffer, thresholdBuffer);

    const quantized = packedRgbaToImageData(quantizedPacked, imageData.width, imageData.height);
    if (config.minRegionSize === 'off') {
      return quantized;
    }
    return cleanupRegions(quantized, config.minRegionSize);
  }

  private runCompute(pipeline: WebGpuComputePipeline, bindings: WebGpuBuffer[], pixelCount: number): void {
    const bindGroup = this.device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: bindings.map((buffer, binding) => ({
        binding,
        resource: { buffer },
      })),
    });

    const encoder = this.device.createCommandEncoder();
    const pass = encoder.beginComputePass();
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    pass.dispatchWorkgroups(Math.ceil(pixelCount / WORKGROUP_SIZE));
    pass.end();

    this.device.queue.submit([encoder.finish()]);
  }
}

function destroyBuffers(...buffers: WebGpuBuffer[]): void {
  for (const buffer of buffers) {
    buffer.destroy();
  }
}

let gpuProcessorPromise: Promise<WebGpuProcessor | null> | null = null;

export async function getWebGpuProcessor(): Promise<WebGpuProcessor | null> {
  gpuProcessorPromise ??= WebGpuProcessor.create().catch(() => null);
  return gpuProcessorPromise;
}
