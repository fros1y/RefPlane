/// <reference lib="webworker" />

import { pipeline, RawImage, env } from '@huggingface/transformers';

env.allowLocalModels = false;

const MODEL_ID = 'Xenova/4x-UltraSharp';

type UpscalePipeline = Awaited<ReturnType<typeof pipeline<'image-to-image'>>>;

let pipelineInstance: UpscalePipeline | null = null;
let pipelineLoading: Promise<UpscalePipeline> | null = null;

async function detectDevice(): Promise<'webgpu' | 'wasm'> {
  try {
    const gpu = (navigator as any).gpu;
    if (gpu) {
      const adapter = await gpu.requestAdapter();
      if (adapter) return 'webgpu';
    }
  } catch { /* fall through */ }
  return 'wasm';
}

function getUpscalePipeline(onProgress: (data: UltrasharpWorkerProgress) => void): Promise<UpscalePipeline> {
  if (pipelineInstance) return Promise.resolve(pipelineInstance);
  if (pipelineLoading) return pipelineLoading;

  pipelineLoading = detectDevice().then((device) => {
    console.log(`[ultrasharp-worker] Using device: ${device}, model: ${MODEL_ID}`);
    return pipeline('image-to-image', MODEL_ID, {
      device,
      dtype: 'fp32',
      progress_callback: (event: any) => {
        if (event.status === 'progress' && typeof event.progress === 'number') {
          onProgress({ kind: 'progress', stage: 'Downloading UltraSharp model', percent: Math.round(event.progress) });
        }
      },
    });
  }).then((p) => {
    pipelineInstance = p;
    pipelineLoading = null;
    return p;
  });

  return pipelineLoading;
}

/**
 * Downsample imageData by scale using box-filter averaging.
 */
function boxDownsample(imageData: ImageData, scale: number): ImageData {
  const srcW = imageData.width;
  const srcH = imageData.height;
  const dstW = Math.max(1, Math.round(srcW / scale));
  const dstH = Math.max(1, Math.round(srcH / scale));
  const src = imageData.data;
  const dst = new Uint8ClampedArray(dstW * dstH * 4);

  for (let dy = 0; dy < dstH; dy++) {
    for (let dx = 0; dx < dstW; dx++) {
      const x0 = Math.floor((dx / dstW) * srcW);
      const x1 = Math.min(srcW, Math.ceil(((dx + 1) / dstW) * srcW));
      const y0 = Math.floor((dy / dstH) * srcH);
      const y1 = Math.min(srcH, Math.ceil(((dy + 1) / dstH) * srcH));

      let r = 0, g = 0, b = 0, a = 0, count = 0;
      for (let sy = y0; sy < y1; sy++) {
        for (let sx = x0; sx < x1; sx++) {
          const idx = (sy * srcW + sx) * 4;
          r += src[idx];
          g += src[idx + 1];
          b += src[idx + 2];
          a += src[idx + 3];
          count++;
        }
      }
      const di = (dy * dstW + dx) * 4;
      dst[di]     = r / count;
      dst[di + 1] = g / count;
      dst[di + 2] = b / count;
      dst[di + 3] = a / count;
    }
  }

  return new ImageData(dst, dstW, dstH);
}

export interface UltrasharpWorkerRequest {
  kind: 'ultrasharp';
  requestId: number;
  imageData: ImageData;
  downscale: number;
}

export interface UltrasharpWorkerProgress {
  kind: 'progress';
  requestId?: number;
  stage: string;
  percent: number;
}

export interface UltrasharpWorkerResult {
  kind: 'result';
  requestId: number;
  imageData: ImageData;
}

export interface UltrasharpWorkerError {
  kind: 'error';
  requestId: number;
  error: string;
}

export type UltrasharpWorkerOutbound =
  | UltrasharpWorkerProgress
  | UltrasharpWorkerResult
  | UltrasharpWorkerError;

self.onmessage = async (e: MessageEvent<UltrasharpWorkerRequest>) => {
  const { requestId, imageData, downscale } = e.data;

  try {
    const upscaler = await getUpscalePipeline((progress) => {
      self.postMessage({ ...progress, requestId } satisfies UltrasharpWorkerProgress);
    });

    self.postMessage({
      kind: 'progress',
      requestId,
      stage: 'Upscaling with UltraSharp',
      percent: 0,
    } satisfies UltrasharpWorkerProgress);

    const origW = imageData.width;
    const origH = imageData.height;

    // Downsample first to control the level of simplification
    const small = downscale > 1 ? boxDownsample(imageData, downscale) : imageData;

    // Run through the 4x UltraSharp model
    const rawInput = new RawImage(new Uint8ClampedArray(small.data), small.width, small.height, 4);
    const rawOutput = await upscaler(rawInput);
    const output = Array.isArray(rawOutput) ? rawOutput[0] : rawOutput;

    self.postMessage({
      kind: 'progress',
      requestId,
      stage: 'Upscaling with UltraSharp',
      percent: 80,
    } satisfies UltrasharpWorkerProgress);

    // Convert RawImage (typically RGB) to RGBA ImageData
    const outW = output.width;
    const outH = output.height;
    const channels = output.channels;
    const rgba = new Uint8ClampedArray(outW * outH * 4);

    if (channels === 4) {
      rgba.set(output.data);
    } else if (channels === 3) {
      // RGB → RGBA
      for (let i = 0, j = 0; i < output.data.length; i += 3, j += 4) {
        rgba[j]     = output.data[i];
        rgba[j + 1] = output.data[i + 1];
        rgba[j + 2] = output.data[i + 2];
        rgba[j + 3] = 255;
      }
    } else {
      // Grayscale (channels=1) or other — replicate first channel
      for (let i = 0, j = 0; i < output.data.length; i += channels, j += 4) {
        rgba[j]     = output.data[i];
        rgba[j + 1] = output.data[i];
        rgba[j + 2] = output.data[i];
        rgba[j + 3] = 255;
      }
    }

    let resultImageData = new ImageData(rgba, outW, outH);

    // Scale back to original dimensions if the model output differs
    if (outW !== origW || outH !== origH) {
      const offscreen = new OffscreenCanvas(origW, origH);
      const ctx = offscreen.getContext('2d')!;
      const tmp = new OffscreenCanvas(outW, outH);
      const tmpCtx = tmp.getContext('2d')!;
      tmpCtx.putImageData(resultImageData, 0, 0);
      ctx.drawImage(tmp, 0, 0, origW, origH);
      resultImageData = ctx.getImageData(0, 0, origW, origH);
    }

    const result: UltrasharpWorkerResult = {
      kind: 'result',
      requestId,
      imageData: resultImageData,
    };

    self.postMessage(result, [resultImageData.data.buffer]);
  } catch (err) {
    const errorMsg: UltrasharpWorkerError = {
      kind: 'error',
      requestId,
      error: err instanceof Error ? err.message : String(err),
    };
    self.postMessage(errorMsg);
  }
};

export {};
