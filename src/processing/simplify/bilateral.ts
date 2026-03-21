import { throwIfAborted, yieldToEventLoop } from './cancel';

export async function bilateralFilter(
  imageData: ImageData,
  sigmaS: number,
  sigmaR: number,
  onProgress?: (percent: number) => void,
  abortSignal?: AbortSignal,
): Promise<ImageData> {
  const { data, width, height } = imageData;
  const out = new ImageData(width, height);
  const outData = out.data;
  const radius = Math.ceil(2 * sigmaS);
  const sigmaS2 = 2 * sigmaS * sigmaS;
  const sigmaR2 = 2 * sigmaR * sigmaR;
  const progressInterval = Math.max(1, Math.floor(height / 20));
  const yieldInterval = 8;

  for (let y = 0; y < height; y++) {
    throwIfAborted(abortSignal);
    if (y > 0 && y % yieldInterval === 0) {
      await yieldToEventLoop();
    }
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
