import type { PlaneColorStrategy, PlaneGuidance } from '../../types';

/**
 * Simplification filter that flat-fills each plane with a representative color
 * from the source image.
 */
export function planeFillFilter(
  imageData: ImageData,
  guidance: PlaneGuidance,
  strategy: PlaneColorStrategy,
): ImageData {
  const { width, height, labels } = guidance;
  const numPixels = width * height;
  const source = imageData.data;
  const out = new Uint8ClampedArray(imageData.data.length);

  // Group pixels by plane
  const planePixels = new Map<number, number[]>();
  for (let i = 0; i < numPixels; i++) {
    const label = labels[i];
    if (!planePixels.has(label)) {
      planePixels.set(label, []);
    }
    planePixels.get(label)!.push(i);
  }

  // Calculate representative color per plane
  const planeColors = new Map<number, { r: number, g: number, b: number }>();
  for (const [label, pixels] of planePixels.entries()) {
    let r = 0, g = 0, b = 0;

    if (strategy === 'average') {
      for (const idx of pixels) {
        r += source[idx * 4];
        g += source[idx * 4 + 1];
        b += source[idx * 4 + 2];
      }
      r /= pixels.length;
      g /= pixels.length;
      b /= pixels.length;
    } else if (strategy === 'median') {
      const rs = pixels.map(i => source[i * 4]).sort((x, y) => x - y);
      const gs = pixels.map(i => source[i * 4 + 1]).sort((x, y) => x - y);
      const bs = pixels.map(i => source[i * 4 + 2]).sort((x, y) => x - y);
      r = rs[Math.floor(rs.length / 2)];
      g = gs[Math.floor(gs.length / 2)];
      b = bs[Math.floor(bs.length / 2)];
    } else if (strategy === 'dominant') {
      // 32-bin quantization (5 bits per channel)
      const bins = new Map<number, number>();
      for (const idx of pixels) {
        const br = source[idx * 4] >> 3;
        const bg = source[idx * 4 + 1] >> 3;
        const bb = source[idx * 4 + 2] >> 3;
        const bin = (br << 10) | (bg << 5) | bb;
        bins.set(bin, (bins.get(bin) || 0) + 1);
      }
      let maxCount = -1;
      let dominantBin = 0;
      for (const [bin, count] of bins.entries()) {
        if (count > maxCount) {
          maxCount = count;
          dominantBin = bin;
        }
      }
      r = (dominantBin >> 10) << 3;
      g = ((dominantBin >> 5) & 0x1F) << 3;
      b = (dominantBin & 0x1F) << 3;
    }

    planeColors.set(label, { r: Math.round(r), g: Math.round(g), b: Math.round(b) });
  }

  // Fill output image
  for (let i = 0; i < numPixels; i++) {
    const label = labels[i];
    const color = planeColors.get(label)!;
    const off = i * 4;
    out[off] = color.r;
    out[off + 1] = color.g;
    out[off + 2] = color.b;
    out[off + 3] = 255;
  }

  return new ImageData(out, width, height);
}
