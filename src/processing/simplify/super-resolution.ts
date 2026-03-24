/**
 * Super-resolution simplification filter.
 *
 * Pipeline:
 *   1. Downsample the image by `scale` using box-filter averaging.
 *   2. Upscale back to the original dimensions with bilinear interpolation
 *      via TensorFlow.js (tf.image.resizeBilinear).
 *   3. Apply a mild unsharp-mask (also in TF.js) to recover perceptual
 *      sharpness without restoring lost fine detail.
 *
 * The net effect is a smooth, painterly simplification: fine texture and
 * noise are gone, broad shapes and gradients are preserved.
 */

import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-backend-webgpu';

// Detect whether WebGPU is available in this Worker context.
async function detectBackend(): Promise<'webgpu' | 'cpu'> {
  try {
    const gpu = (self as any).navigator?.gpu ?? (globalThis as any).navigator?.gpu;
    if (gpu) {
      const adapter = await gpu.requestAdapter();
      if (adapter) return 'webgpu';
    }
  } catch { /* fall through */ }
  return 'cpu';
}

let backendReady = false;
let activeBackend: 'webgpu' | 'cpu' = 'cpu';

async function ensureBackend() {
  if (backendReady) return;
  const backend = await detectBackend();
  activeBackend = backend;
  console.log(`[sr-worker] Using TF.js backend: ${backend}`);
  await tf.setBackend(backend);
  await tf.ready();
  backendReady = true;
}

/**
 * Downsample `imageData` by `scale` using a simple box-filter average,
 * returning a new ImageData at the reduced resolution.
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
      // Map destination pixel back to source region
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

/**
 * Run super-resolution simplification:
 *   downsample → bilinear SR (TF.js) → unsharp-mask (TF.js)
 *
 * @param imageData     Source image.
 * @param scale         Downscale factor (e.g. 2, 4, 8).  Higher = more abstract.
 * @param sharpenAmount Unsharp-mask intensity, 0–1.  0 = no sharpening.
 * @param onProgress    Optional progress callback (0–100).
 * @param abortSignal   Optional cancellation token.
 */
export async function superResolutionFilter(
  imageData: ImageData,
  scale: number,
  sharpenAmount: number,
  onProgress?: (percent: number) => void,
  abortSignal?: AbortSignal,
): Promise<ImageData> {
  await ensureBackend();
  if (abortSignal?.aborted) throw Object.assign(new Error('AbortError'), { name: 'AbortError' });

  onProgress?.(5);
  const origW = imageData.width;
  const origH = imageData.height;

  // 1. Box-filter downsample
  const small = boxDownsample(imageData, scale);
  if (abortSignal?.aborted) throw Object.assign(new Error('AbortError'), { name: 'AbortError' });

  onProgress?.(20);

  // 2. Bilinear upscale via TF.js
  const result = tf.tidy(() => {
    // [H, W, 4] tensor in [0, 255]
    const t = tf.tensor3d(new Float32Array(small.data), [small.height, small.width, 4], 'float32');
    const batch = t.expandDims(0) as tf.Tensor4D; // [1, H, W, 4]

    // Bilinear resize back to original dimensions
    const upscaled = tf.image.resizeBilinear(batch, [origH, origW], true /* alignCorners */) as tf.Tensor4D;

    if (sharpenAmount <= 0) {
      return upscaled.squeeze([0]) as tf.Tensor3D;
    }

    // 3. Unsharp mask: sharpened = original + amount * (original − blur)
    const blurKernelSize = 5;
    const sigma = 1.5;
    // Build a 2-D Gaussian kernel
    const half = Math.floor(blurKernelSize / 2);
    const kernelVals: number[] = [];
    let ksum = 0;
    for (let y = -half; y <= half; y++) {
      for (let x = -half; x <= half; x++) {
        const v = Math.exp(-(x * x + y * y) / (2 * sigma * sigma));
        kernelVals.push(v);
        ksum += v;
      }
    }
    const normKernel = kernelVals.map(v => v / ksum);

    // Apply separable Gaussian blur per channel (depthwise conv)
    const channels = 4;
    // kernel shape: [kH, kW, in_channels, channel_multiplier]
    const kTensor = tf.tensor4d(
      normKernel.flatMap(v => Array(channels).fill(v)),
      [blurKernelSize, blurKernelSize, channels, 1],
    );
    const blurred = tf.depthwiseConv2d(upscaled, kTensor, 1, 'same');

    // sharpened = upscaled + amount * (upscaled - blurred)
    const detail = upscaled.sub(blurred);
    const sharpened = upscaled.add(detail.mul(sharpenAmount));
    return tf.clipByValue(sharpened.squeeze([0]) as tf.Tensor3D, 0, 255);
  });

  if (abortSignal?.aborted) {
    result.dispose();
    throw Object.assign(new Error('AbortError'), { name: 'AbortError' });
  }

  onProgress?.(85);

  // Convert back to ImageData
  const flat = await result.data();
  result.dispose();

  const out = new Uint8ClampedArray(origW * origH * 4);
  for (let i = 0; i < flat.length; i++) {
    out[i] = flat[i];
  }

  onProgress?.(100);
  return new ImageData(out, origW, origH);
}
