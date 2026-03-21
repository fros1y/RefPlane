import { describe, expect, it } from 'vitest';
import { kuwaharaFilter } from '../../../src/processing/simplify/kuwahara';
import { createImageData, setPixel } from '../../utils/image';

describe('kuwaharaFilter', () => {
  it('preserves a uniform image', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = kuwaharaFilter(image, 3);
    for (let i = 0; i < result.data.length; i += 4) {
      expect(result.data[i]).toBeCloseTo(128, -1);
    }
  });

  it('produces output with same dimensions as input', () => {
    const image = createImageData(16, 12, [100, 100, 100, 255]);
    const result = kuwaharaFilter(image, 5);
    expect(result.width).toBe(16);
    expect(result.height).toBe(12);
  });

  it('preserves alpha channel', () => {
    const image = createImageData(4, 4, [100, 100, 100, 180]);
    const result = kuwaharaFilter(image, 3);
    for (let i = 3; i < result.data.length; i += 4) {
      expect(result.data[i]).toBe(180);
    }
  });

  it('reduces variance within uniform regions', () => {
    const image = createImageData(20, 20, [128, 128, 128, 255]);
    for (let y = 0; y < 20; y++) {
      for (let x = 0; x < 20; x++) {
        const v = (x + y) % 2 === 0 ? 120 : 136;
        setPixel(image, x, y, [v, v, v, 255]);
      }
    }
    const result = kuwaharaFilter(image, 5);
    const centerIdx = (10 * 20 + 10) * 4;
    const centerVal = result.data[centerIdx];
    const neighborVal = result.data[centerIdx + 4];
    expect(Math.abs(centerVal - neighborVal)).toBeLessThan(16);
  });

  it('accepts a progress callback', () => {
    const image = createImageData(10, 10, [128, 128, 128, 255]);
    const updates: number[] = [];
    kuwaharaFilter(image, 3, (percent) => { updates.push(percent); });
    expect(updates.length).toBeGreaterThan(0);
  });
});
