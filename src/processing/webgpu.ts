import { cleanupRegions } from './regions';
import { strengthToParams } from './bilateral';
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
  }

  static async create(): Promise<WebGpuProcessor | null> {
    const nav = typeof navigator === 'undefined' ? undefined : (navigator as Navigator & { gpu?: any });
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
    const { sigmaS, sigmaR } = strengthToParams(config.strength);
    const packed = imageDataToPackedRgba(imageData);
    const srcBuffer = createBufferWithData(
      this.device,
      packed,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const filteredBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC | GPUBufferUsageRef.COPY_DST,
    });
    const quantizedBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const bilateralParamsBuffer = createBufferWithData(
      this.device,
      createBilateralParams(imageData.width, imageData.height, Math.ceil(2 * sigmaS), sigmaS, sigmaR),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );
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

    this.runCompute(this.bilateralGrayPipeline, [srcBuffer, filteredBuffer, bilateralParamsBuffer], pixelCount);
    this.runCompute(this.quantizePipeline, [filteredBuffer, quantizedBuffer, quantizeParamsBuffer, thresholdBuffer], pixelCount);

    const quantizedPacked = new Uint32Array(await readBackBuffer(this.device, quantizedBuffer, packed.byteLength));
    destroyBuffers(srcBuffer, filteredBuffer, quantizedBuffer, bilateralParamsBuffer, quantizeParamsBuffer, thresholdBuffer);

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
