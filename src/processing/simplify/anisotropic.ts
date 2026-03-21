import { throwIfAborted, yieldToEventLoop } from './cancel';

export async function anisotropicDiffusion(
  imageData: ImageData,
  iterations: number,
  kappa: number,
  onProgress?: (percent: number) => void,
  abortSignal?: AbortSignal,
): Promise<ImageData> {
  const { data, width, height } = imageData;
  const numPixels = width * height;
  const lambda = 0.25; // stability for 4-connected

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
    throwIfAborted(abortSignal);
    if (iter > 0) {
      await yieldToEventLoop();
    }
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
