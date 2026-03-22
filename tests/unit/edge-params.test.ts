import { describe, expect, it } from 'vitest';
import { cannyEdges, sobelEdges } from '../../src/processing/edges';
import { dilateEdges } from '../../src/compositing/edge-composite';
import { createImageData, countPixels, setPixel } from '../utils/image';

/* ---------------------------------------------------------------------------
 * Test helpers
 * --------------------------------------------------------------------------- */

/** 12×12 image: left half black, right half white — a sharp vertical edge. */
function makeVerticalStepImage(): ImageData {
  const img = createImageData(12, 12, [0, 0, 0, 255]);
  for (let y = 0; y < img.height; y++) {
    for (let x = 6; x < img.width; x++) {
      setPixel(img, x, y, [255, 255, 255, 255]);
    }
  }
  return img;
}

/** A larger image with a gradient ramp from black to white. */
function makeGradientImage(w = 32, h = 32): ImageData {
  const img = createImageData(w, h, [0, 0, 0, 255]);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const v = Math.round((x / (w - 1)) * 255);
      setPixel(img, x, y, [v, v, v, 255]);
    }
  }
  return img;
}

/** Count non-zero (edge-lit) pixels. */
function edgePixelCount(img: ImageData): number {
  return countPixels(img, (r) => r > 0);
}

/** Sum of all R-channel values (proxy for total edge energy). */
function totalEnergy(img: ImageData): number {
  let sum = 0;
  for (let i = 0; i < img.data.length; i += 4) sum += img.data[i];
  return sum;
}

/** Make synthetic "edge detection output": single pixel at center is white. */
function makeSingleEdgePixel(w = 11, h = 11): ImageData {
  const img = createImageData(w, h, [0, 0, 0, 255]);
  const cx = Math.floor(w / 2);
  const cy = Math.floor(h / 2);
  setPixel(img, cx, cy, [255, 255, 255, 255]);
  return img;
}

/** Make a thin vertical line of white pixels in the center column. */
function makeThinVerticalLine(w = 21, h = 21): ImageData {
  const img = createImageData(w, h, [0, 0, 0, 255]);
  const cx = Math.floor(w / 2);
  for (let y = 2; y < h - 2; y++) {
    setPixel(img, cx, y, [255, 255, 255, 255]);
  }
  return img;
}

/* ---------------------------------------------------------------------------
 * sobelEdges — sensitivity parameter
 * --------------------------------------------------------------------------- */

describe('sobelEdges – sensitivity', () => {
  it('produces edges on a step image at default sensitivity', () => {
    const edges = sobelEdges(makeVerticalStepImage(), 0.5);
    expect(edgePixelCount(edges)).toBeGreaterThan(0);
  });

  it('detects more edges as sensitivity increases', () => {
    const img = makeGradientImage();
    const low = sobelEdges(img, 0);
    const mid = sobelEdges(img, 0.5);
    const high = sobelEdges(img, 1);

    const lowCount = edgePixelCount(low);
    const midCount = edgePixelCount(mid);
    const highCount = edgePixelCount(high);

    // More edge pixels as sensitivity grows
    expect(midCount).toBeGreaterThanOrEqual(lowCount);
    expect(highCount).toBeGreaterThanOrEqual(midCount);
    // The extreme values differ
    expect(highCount).toBeGreaterThan(lowCount);
  });

  it('total edge energy increases with sensitivity', () => {
    const img = makeGradientImage();
    const lowEnergy = totalEnergy(sobelEdges(img, 0.1));
    const highEnergy = totalEnergy(sobelEdges(img, 0.9));
    expect(highEnergy).toBeGreaterThan(lowEnergy);
  });

  it('different sensitivity values produce different outputs', () => {
    const img = makeGradientImage();
    const a = sobelEdges(img, 0.2);
    const b = sobelEdges(img, 0.8);
    // At least one pixel must differ
    let differ = false;
    for (let i = 0; i < a.data.length; i += 4) {
      if (a.data[i] !== b.data[i]) { differ = true; break; }
    }
    expect(differ).toBe(true);
  });
});

/* ---------------------------------------------------------------------------
 * cannyEdges — detail parameter
 * --------------------------------------------------------------------------- */

describe('cannyEdges – detail', () => {
  it('produces edges on a step image at default detail', () => {
    const edges = cannyEdges(makeVerticalStepImage(), 0.5);
    expect(edgePixelCount(edges)).toBeGreaterThan(0);
  });

  it('detects more edges as detail increases', () => {
    const img = makeGradientImage();
    const sparse = cannyEdges(img, 0);
    const dense = cannyEdges(img, 1);

    const sparseCount = edgePixelCount(sparse);
    const denseCount = edgePixelCount(dense);

    expect(denseCount).toBeGreaterThanOrEqual(sparseCount);
  });

  it('different detail values produce different outputs', () => {
    const img = makeGradientImage();
    const a = cannyEdges(img, 0.1);
    const b = cannyEdges(img, 0.9);
    let differ = false;
    for (let i = 0; i < a.data.length; i += 4) {
      if (a.data[i] !== b.data[i]) { differ = true; break; }
    }
    expect(differ).toBe(true);
  });

  it('mid-range detail differs from extremes', () => {
    const img = makeGradientImage();
    const low = edgePixelCount(cannyEdges(img, 0));
    const mid = edgePixelCount(cannyEdges(img, 0.5));
    const high = edgePixelCount(cannyEdges(img, 1));
    // At least one pair must differ
    expect(low !== mid || mid !== high).toBe(true);
  });
});

/* ---------------------------------------------------------------------------
 * dilateEdges — lineWeight parameter
 * --------------------------------------------------------------------------- */

describe('dilateEdges – lineWeight', () => {
  it('lineWeight 1 returns an identical copy (no dilation)', () => {
    const src = makeSingleEdgePixel();
    const result = dilateEdges(src, 1);
    // Pixel counts match
    expect(edgePixelCount(result)).toBe(edgePixelCount(src));
    // Same pixel values
    for (let i = 0; i < src.data.length; i++) {
      expect(result.data[i]).toBe(src.data[i]);
    }
  });

  it('lineWeight 1 does not alias the input buffer', () => {
    const src = makeSingleEdgePixel();
    const result = dilateEdges(src, 1);
    expect(result.data.buffer).not.toBe(src.data.buffer);
  });

  it('lineWeight 2 expands a single pixel into a larger area', () => {
    const src = makeSingleEdgePixel();
    const thin = edgePixelCount(dilateEdges(src, 1));
    const thick = edgePixelCount(dilateEdges(src, 2));
    expect(thick).toBeGreaterThan(thin);
  });

  it('lineWeight 3 expands more than lineWeight 2', () => {
    const src = makeSingleEdgePixel();
    const w2 = edgePixelCount(dilateEdges(src, 2));
    const w3 = edgePixelCount(dilateEdges(src, 3));
    expect(w3).toBeGreaterThan(w2);
  });

  it('increasing lineWeight monotonically increases edge pixel count', () => {
    const src = makeSingleEdgePixel();
    let prev = edgePixelCount(dilateEdges(src, 1));
    for (let w = 2; w <= 6; w++) {
      const cur = edgePixelCount(dilateEdges(src, w));
      expect(cur).toBeGreaterThanOrEqual(prev);
      prev = cur;
    }
    // Weight 6 must be strictly greater than weight 1
    expect(edgePixelCount(dilateEdges(src, 6))).toBeGreaterThan(
      edgePixelCount(dilateEdges(src, 1)),
    );
  });

  it('dilates a thin line into a thicker band', () => {
    const src = makeThinVerticalLine();
    const dilated = dilateEdges(src, 4);

    // The original line is 1px wide; after dilation it should be wider
    const srcCount = edgePixelCount(src);
    const dilCount = edgePixelCount(dilated);
    expect(dilCount).toBeGreaterThan(srcCount);

    // Verify that pixels adjacent to the original line are now lit
    const cx = Math.floor(src.width / 2);
    const midY = Math.floor(src.height / 2);
    const adj = dilated.data[(midY * dilated.width + cx + 1) * 4];
    expect(adj).toBeGreaterThan(0);
  });

  it('dilation uses circular kernel (corner pixels excluded at radius)', () => {
    // lineWeight=2 → radius=1, so diagonal (1,1) is excluded (1+1 > 1)
    const src = makeSingleEdgePixel(5, 5);
    const result = dilateEdges(src, 2);
    const cx = 2, cy = 2;

    // Cardinal neighbours should be lit
    expect(result.data[(cy * 5 + cx + 1) * 4]).toBe(255); // right
    expect(result.data[(cy * 5 + cx - 1) * 4]).toBe(255); // left
    expect(result.data[((cy + 1) * 5 + cx) * 4]).toBe(255); // below
    expect(result.data[((cy - 1) * 5 + cx) * 4]).toBe(255); // above

    // Diagonal is excluded at radius 1 (1² + 1² = 2 > 1² = 1)
    expect(result.data[((cy + 1) * 5 + cx + 1) * 4]).toBe(0);
  });

  it('total edge energy increases with lineWeight', () => {
    const src = makeThinVerticalLine();
    const e1 = totalEnergy(dilateEdges(src, 1));
    const e4 = totalEnergy(dilateEdges(src, 4));
    expect(e4).toBeGreaterThan(e1);
  });

  it('preserves image dimensions', () => {
    const src = makeSingleEdgePixel(15, 20);
    const result = dilateEdges(src, 4);
    expect(result.width).toBe(15);
    expect(result.height).toBe(20);
  });

  it('handles an all-black image (no edges)', () => {
    const src = createImageData(10, 10, [0, 0, 0, 255]);
    const result = dilateEdges(src, 4);
    expect(edgePixelCount(result)).toBe(0);
  });

  it('handles an all-white image', () => {
    const src = createImageData(10, 10, [255, 255, 255, 255]);
    const result = dilateEdges(src, 4);
    // All pixels should remain lit
    expect(edgePixelCount(result)).toBe(100);
  });
});
