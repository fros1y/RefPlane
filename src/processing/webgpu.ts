import { cleanupRegions } from './regions';
import type { ValueConfig } from '../types';

import grayscaleShader from './shaders/grayscale.wgsl?raw';
import bilateralGrayShader from './shaders/bilateral-gray.wgsl?raw';
import bilateralLabShader from './shaders/bilateral-lab.wgsl?raw';
import quantizeShader from './shaders/quantize.wgsl?raw';
import bilateralRgbShader from './shaders/bilateral-rgb.wgsl?raw';
import kuwaharaShader from './shaders/kuwahara.wgsl?raw';
import meanShiftShader from './shaders/mean-shift.wgsl?raw';
import anisotropicShader from './shaders/anisotropic.wgsl?raw';
import sobelShader from './shaders/sobel.wgsl?raw';
import kMeansAssignShader from './shaders/kmeans-assign.wgsl?raw';
import srgbToLinearShader from './shaders/srgb-to-linear.wgsl?raw';
import painterlyTensorShader from './shaders/painterly-tensor.wgsl?raw';
import painterlyAkfShader from './shaders/painterly-akf.wgsl?raw';
import painterlySharpenShader from './shaders/painterly-sharpen.wgsl?raw';
import painterlyPostColorShader from './shaders/painterly-post-color.wgsl?raw';
import depthToNormalsShader from './shaders/depth-to-normals.wgsl?raw';
import bilateralDepthShader from './shaders/bilateral-depth.wgsl?raw';
import normalClusterShader from './shaders/normal-cluster.wgsl?raw';
import planeShadingShader from './shaders/plane-shading.wgsl?raw';
import kuwaharaGuidedShader from './shaders/kuwahara-guided.wgsl?raw';

const WORKGROUP_SIZE = 64;
const GPUBufferUsageRef = (globalThis as any).GPUBufferUsage;
const GPUMapModeRef = (globalThis as any).GPUMapMode;

type WebGpuBuffer = any;
type WebGpuComputePipeline = any;
type WebGpuDevice = any;

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

function createKuwaharaParams(
  width: number, height: number, kernelSize: number,
  sharpness: number, sectors: number,
): Uint8Array {
  const buffer = new ArrayBuffer(32);
  const view = new DataView(buffer);
  view.setUint32(0, width, true);
  view.setUint32(4, height, true);
  view.setUint32(8, width * height, true);
  view.setUint32(12, Math.max(1, Math.floor(kernelSize / 2)), true);
  view.setFloat32(16, sharpness, true);
  view.setUint32(20, sectors, true);
  // _pad0, _pad1 at offsets 24 and 28 left as zero
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

function createPainterlyTensorParams(width: number, height: number, tensorSigma: number): Uint8Array {
  const buffer = new ArrayBuffer(32);
  const view = new DataView(buffer);
  view.setUint32(0, width, true);
  view.setUint32(4, height, true);
  view.setUint32(8, width * height, true);
  view.setFloat32(16, tensorSigma, true);
  return new Uint8Array(buffer);
}

function createPainterlyAkfParams(width: number, height: number, radius: number, q: number, alpha: number, zeta: number): Uint8Array {
  const buffer = new ArrayBuffer(32);
  const view = new DataView(buffer);
  view.setUint32(0, width, true);
  view.setUint32(4, height, true);
  view.setUint32(8, width * height, true);
  view.setFloat32(16, radius, true);
  view.setFloat32(20, q, true);
  view.setFloat32(24, alpha, true);
  view.setFloat32(28, zeta, true);
  return new Uint8Array(buffer);
}

function createPainterlySharpenParams(width: number, height: number, sharpenAmount: number, edgeThresholdLow: number, edgeThresholdHigh: number, detailSigma: number): Uint8Array {
  const buffer = new ArrayBuffer(32);
  const view = new DataView(buffer);
  view.setUint32(0, width, true);
  view.setUint32(4, height, true);
  view.setUint32(8, width * height, true);
  view.setFloat32(16, sharpenAmount, true);
  view.setFloat32(20, edgeThresholdLow, true);
  view.setFloat32(24, edgeThresholdHigh, true);
  view.setFloat32(28, detailSigma, true);
  return new Uint8Array(buffer);
}

function createPainterlyPostParams(pixelCount: number): Uint8Array {
  const buffer = new ArrayBuffer(16);
  const view = new DataView(buffer);
  view.setUint32(0, pixelCount, true);
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
  private readonly srgbToLinearPipeline: WebGpuComputePipeline;
  private readonly painterlyTensorPipeline: WebGpuComputePipeline;
  private readonly painterlyAkfPipeline: WebGpuComputePipeline;
  private readonly painterlySharpenPipeline: WebGpuComputePipeline;
  private readonly painterlyPostColorPipeline: WebGpuComputePipeline;
  private readonly depthToNormalsPipeline: WebGpuComputePipeline;
  private readonly bilateralDepthPipeline: WebGpuComputePipeline;
  private readonly normalClusterPipeline: WebGpuComputePipeline;
  private readonly planeShadingPipeline: WebGpuComputePipeline;
  private readonly kuwaharaGuidedPipeline: WebGpuComputePipeline;

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
    this.srgbToLinearPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: srgbToLinearShader }),
        entryPoint: 'main',
      },
    });
    this.painterlyTensorPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: painterlyTensorShader }),
        entryPoint: 'main',
      },
    });
    this.painterlyAkfPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: painterlyAkfShader }),
        entryPoint: 'main',
      },
    });
    this.painterlySharpenPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: painterlySharpenShader }),
        entryPoint: 'main',
      },
    });
    this.painterlyPostColorPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: painterlyPostColorShader }),
        entryPoint: 'main',
      },
    });
    this.depthToNormalsPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: depthToNormalsShader }),
        entryPoint: 'main',
      },
    });
    this.bilateralDepthPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: bilateralDepthShader }),
        entryPoint: 'main',
      },
    });
    this.normalClusterPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: normalClusterShader }),
        entryPoint: 'main',
      },
    });
    this.planeShadingPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: planeShadingShader }),
        entryPoint: 'main',
      },
    });
    this.kuwaharaGuidedPipeline = this.device.createComputePipeline({
      layout: 'auto',
      compute: {
        module: this.device.createShaderModule({ code: kuwaharaGuidedShader }),
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

  async kuwahara(
    imageData: ImageData,
    kernelSize: number,
    passes: number,
    sharpness: number,
    sectors: number,
  ): Promise<ImageData> {
    const pixelCount = imageData.width * imageData.height;
    const packed = imageDataToPackedRgba(imageData);
    const bufUsage = GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC | GPUBufferUsageRef.COPY_DST;
    let srcBuffer = createBufferWithData(this.device, packed, bufUsage);
    let dstBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: bufUsage,
    });
    const paramsBuffer = createBufferWithData(
      this.device,
      createKuwaharaParams(imageData.width, imageData.height, kernelSize, sharpness, sectors),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    for (let i = 0; i < passes; i++) {
      this.runCompute(this.kuwaharaPipeline, [srcBuffer, dstBuffer, paramsBuffer], pixelCount);
      const temp = srcBuffer;
      srcBuffer = dstBuffer;
      dstBuffer = temp;
    }

    const result = new Uint32Array(await readBackBuffer(this.device, srcBuffer, packed.byteLength));
    destroyBuffers(srcBuffer, dstBuffer, paramsBuffer);
    return packedRgbaToImageData(result, imageData.width, imageData.height);
  }

  async kuwaharaGuided(
    imageData: ImageData,
    kernelSize: number,
    passes: number,
    sharpness: number,
    sectors: number,
    planeLabels: Uint8Array,
  ): Promise<ImageData> {
    const pixelCount = imageData.width * imageData.height;
    const packed = imageDataToPackedRgba(imageData);
    const bufUsage = GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC | GPUBufferUsageRef.COPY_DST;
    let srcBuffer = createBufferWithData(this.device, packed, bufUsage);
    let dstBuffer = this.device.createBuffer({
      size: packed.byteLength,
      usage: bufUsage,
    });
    const paramsBuffer = createBufferWithData(
      this.device,
      createKuwaharaParams(imageData.width, imageData.height, kernelSize, sharpness, sectors),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    // Upload plane labels as u32 array for shader compatibility
    const labelsU32 = new Uint32Array(pixelCount);
    for (let i = 0; i < pixelCount; i++) labelsU32[i] = planeLabels[i];
    const labelsBuffer = createBufferWithData(
      this.device,
      labelsU32,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );

    for (let i = 0; i < passes; i++) {
      this.runCompute(this.kuwaharaGuidedPipeline, [srcBuffer, dstBuffer, paramsBuffer, labelsBuffer], pixelCount);
      const temp = srcBuffer;
      srcBuffer = dstBuffer;
      dstBuffer = temp;
    }

    const result = new Uint32Array(await readBackBuffer(this.device, srcBuffer, packed.byteLength));
    destroyBuffers(srcBuffer, dstBuffer, paramsBuffer, labelsBuffer);
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

  async painterly(imageData: ImageData, config: {
    radius: number; q: number; alpha: number; zeta: number;
    tensorSigma: number;
    sharpenAmount: number; edgeThresholdLow: number; edgeThresholdHigh: number;
    detailSigma: number;
  }): Promise<ImageData> {
    const { width, height } = imageData;
    const pixelCount = width * height;
    const packed = imageDataToPackedRgba(imageData);
    const floatBufSize = pixelCount * 16;

    const srcPackedBuf = createBufferWithData(
      this.device, packed,
      GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_DST,
    );
    const linearBuf = this.device.createBuffer({
      size: floatBufSize,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const tensorBuf = this.device.createBuffer({
      size: floatBufSize,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const akfBuf = this.device.createBuffer({
      size: floatBufSize,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const sharpenBuf = this.device.createBuffer({
      size: floatBufSize,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });
    const dstPackedBuf = this.device.createBuffer({
      size: packed.byteLength,
      usage: GPUBufferUsageRef.STORAGE | GPUBufferUsageRef.COPY_SRC,
    });

    const linearizeParams = createBufferWithData(
      this.device, createPixelCountParams(pixelCount),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );
    const tensorParams = createBufferWithData(
      this.device, createPainterlyTensorParams(width, height, config.tensorSigma),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );
    const akfParams = createBufferWithData(
      this.device, createPainterlyAkfParams(width, height, config.radius, config.q, config.alpha, config.zeta),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );
    const sharpenParams = createBufferWithData(
      this.device, createPainterlySharpenParams(width, height, config.sharpenAmount, config.edgeThresholdLow, config.edgeThresholdHigh, config.detailSigma),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );
    const postParams = createBufferWithData(
      this.device, createPainterlyPostParams(pixelCount),
      GPUBufferUsageRef.UNIFORM | GPUBufferUsageRef.COPY_DST,
    );

    // Pass 0: sRGB → Linear
    this.runCompute(this.srgbToLinearPipeline, [srcPackedBuf, linearBuf, linearizeParams], pixelCount);
    // Pass 1: Structure Tensor
    this.runCompute(this.painterlyTensorPipeline, [linearBuf, tensorBuf, tensorParams], pixelCount);
    // Pass 2: Anisotropic Kuwahara Filter
    this.runCompute(this.painterlyAkfPipeline, [linearBuf, tensorBuf, akfBuf, akfParams], pixelCount);
    // Pass 3: Edge-Aware Sharpen
    this.runCompute(this.painterlySharpenPipeline, [akfBuf, tensorBuf, sharpenBuf, sharpenParams], pixelCount);
    // Pass 4: Color Post-Processing + Linear → sRGB
    this.runCompute(this.painterlyPostColorPipeline, [sharpenBuf, dstPackedBuf, postParams], pixelCount);

    const result = new Uint32Array(await readBackBuffer(this.device, dstPackedBuf, packed.byteLength));
    destroyBuffers(srcPackedBuf, linearBuf, tensorBuf, akfBuf, sharpenBuf, dstPackedBuf,
      linearizeParams, tensorParams, akfParams, sharpenParams, postParams);
    return packedRgbaToImageData(result, width, height);
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
