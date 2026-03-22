import { describe, expect, it } from 'vitest';
import { kuwaharaFilter } from '../../../src/processing/simplify/kuwahara';
import { createImageData, setPixel } from '../../utils/image';

describe('kuwaharaFilter', () => {
  it('preserves a uniform image', async () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = await kuwaharaFilter(image, 3);
    for (let i = 0; i < result.data.length; i += 4) {
      expect(result.data[i]).toBeCloseTo(128, -1);
    }
  });

  it('produces output with same dimensions as input', async () => {
    const image = createImageData(16, 12, [100, 100, 100, 255]);
    const result = await kuwaharaFilter(image, 5);
    expect(result.width).toBe(16);
    expect(result.height).toBe(12);
  });

  it('preserves alpha channel', async () => {
    const image = createImageData(4, 4, [100, 100, 100, 180]);
    const result = await kuwaharaFilter(image, 3);
    for (let i = 3; i < result.data.length; i += 4) {
      expect(result.data[i]).toBe(180);
    }
  });

  it('reduces variance within uniform regions', async () => {
    const image = createImageData(20, 20, [128, 128, 128, 255]);
    for (let y = 0; y < 20; y++) {
      for (let x = 0; x < 20; x++) {
        const v = (x + y) % 2 === 0 ? 120 : 136;
        setPixel(image, x, y, [v, v, v, 255]);
      }
    }
    const result = await kuwaharaFilter(image, 5);
    const centerIdx = (10 * 20 + 10) * 4;
    const centerVal = result.data[centerIdx];
    const neighborVal = result.data[centerIdx + 4];
    expect(Math.abs(centerVal - neighborVal)).toBeLessThan(16);
  });

  it('accepts a progress callback', async () => {
    const image = createImageData(10, 10, [128, 128, 128, 255]);
    const updates: number[] = [];
    await kuwaharaFilter(image, 3, (percent) => { updates.push(percent); });
    expect(updates.length).toBeGreaterThan(0);
  });

  describe('classic 4-sector mode', () => {
    it('preserves a uniform image with sectors=4', async () => {
      const image = createImageData(8, 8, [128, 128, 128, 255]);
      const result = await kuwaharaFilter(image, 3, undefined, undefined, 1, 8, 4);
      for (let i = 0; i < result.data.length; i += 4) {
        expect(result.data[i]).toBeCloseTo(128, -1);
      }
    });

    it('preserves alpha with sectors=4', async () => {
      const image = createImageData(4, 4, [100, 100, 100, 180]);
      const result = await kuwaharaFilter(image, 3, undefined, undefined, 1, 8, 4);
      for (let i = 3; i < result.data.length; i += 4) {
        expect(result.data[i]).toBe(180);
      }
    });
  });

  describe('generalized 8-sector mode', () => {
    it('preserves a uniform image with sectors=8', async () => {
      const image = createImageData(8, 8, [128, 128, 128, 255]);
      const result = await kuwaharaFilter(image, 5, undefined, undefined, 1, 8, 8);
      for (let i = 0; i < result.data.length; i += 4) {
        expect(result.data[i]).toBeCloseTo(128, -1);
      }
    });

    it('preserves alpha with sectors=8', async () => {
      const image = createImageData(4, 4, [100, 100, 100, 180]);
      const result = await kuwaharaFilter(image, 5, undefined, undefined, 1, 8, 8);
      for (let i = 3; i < result.data.length; i += 4) {
        expect(result.data[i]).toBe(180);
      }
    });

    it('reduces noise in a checkerboard pattern', async () => {
      const image = createImageData(20, 20, [128, 128, 128, 255]);
      for (let y = 0; y < 20; y++) {
        for (let x = 0; x < 20; x++) {
          const v = (x + y) % 2 === 0 ? 120 : 136;
          setPixel(image, x, y, [v, v, v, 255]);
        }
      }
      const result = await kuwaharaFilter(image, 5, undefined, undefined, 1, 8, 8);
      const centerIdx = (10 * 20 + 10) * 4;
      const centerVal = result.data[centerIdx];
      const neighborVal = result.data[centerIdx + 4];
      expect(Math.abs(centerVal - neighborVal)).toBeLessThan(16);
    });

    it('produces different output than 4-sector mode on noisy input', async () => {
      const image = createImageData(20, 20, [128, 128, 128, 255]);
      for (let y = 0; y < 20; y++) {
        for (let x = 0; x < 20; x++) {
          const v = (x + y) % 2 === 0 ? 100 : 160;
          setPixel(image, x, y, [v, v, v, 255]);
        }
      }
      const result4 = await kuwaharaFilter(image, 7, undefined, undefined, 1, 8, 4);
      const result8 = await kuwaharaFilter(image, 7, undefined, undefined, 1, 8, 8);
      // At least some center pixels should differ between modes
      let diffs = 0;
      for (let i = 0; i < result4.data.length; i += 4) {
        if (result4.data[i] !== result8.data[i]) diffs++;
      }
      expect(diffs).toBeGreaterThan(0);
    });
  });

  describe('multi-pass', () => {
    it('multiple passes produce stronger smoothing', async () => {
      const image = createImageData(20, 20, [128, 128, 128, 255]);
      for (let y = 0; y < 20; y++) {
        for (let x = 0; x < 20; x++) {
          const v = (x + y) % 2 === 0 ? 100 : 160;
          setPixel(image, x, y, [v, v, v, 255]);
        }
      }
      const result1 = await kuwaharaFilter(image, 5, undefined, undefined, 1, 8, 8);
      const result3 = await kuwaharaFilter(image, 5, undefined, undefined, 3, 8, 8);
      // Compute variance of center 10x10 region for each
      const variance = (data: Uint8ClampedArray, w: number) => {
        let sum = 0, sum2 = 0, n = 0;
        for (let y = 5; y < 15; y++) {
          for (let x = 5; x < 15; x++) {
            const v = data[(y * w + x) * 4];
            sum += v; sum2 += v * v; n++;
          }
        }
        const mean = sum / n;
        return sum2 / n - mean * mean;
      };
      expect(variance(result3.data, 20)).toBeLessThanOrEqual(variance(result1.data, 20));
    });
  });
});
