import { describe, expect, it } from 'vitest';
import { meanShiftFilter } from '../../../src/processing/simplify/mean-shift';
import { createImageData, setPixel } from '../../utils/image';

describe('meanShiftFilter', () => {
  it('preserves a uniform image', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = meanShiftFilter(image, 10, 20);
    for (let i = 0; i < result.data.length; i += 4) {
      expect(result.data[i]).toBeCloseTo(128, -1);
    }
  });

  it('produces output with same dimensions as input', () => {
    const image = createImageData(12, 8, [100, 100, 100, 255]);
    const result = meanShiftFilter(image, 5, 10);
    expect(result.width).toBe(12);
    expect(result.height).toBe(8);
  });

  it('preserves alpha channel', () => {
    const image = createImageData(4, 4, [100, 100, 100, 170]);
    const result = meanShiftFilter(image, 5, 10);
    for (let i = 3; i < result.data.length; i += 4) {
      expect(result.data[i]).toBe(170);
    }
  });

  it('converges similar nearby colors', () => {
    const image = createImageData(10, 10, [50, 50, 50, 255]);
    for (let y = 5; y < 10; y++) {
      for (let x = 0; x < 10; x++) {
        setPixel(image, x, y, [200, 200, 200, 255]);
      }
    }
    const result = meanShiftFilter(image, 8, 20);
    expect(result.data[(2 * 10 + 5) * 4]).toBeLessThan(80);
    expect(result.data[(7 * 10 + 5) * 4]).toBeGreaterThan(170);
  });

  it('accepts a progress callback', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const updates: number[] = [];
    meanShiftFilter(image, 5, 10, (percent) => { updates.push(percent); });
    expect(updates.length).toBeGreaterThan(0);
  });
});
