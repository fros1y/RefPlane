import { describe, expect, it } from 'vitest';
import { bilateralFilter } from '../../../src/processing/simplify/bilateral';
import { createImageData, setPixel } from '../../utils/image';

describe('bilateralFilter', () => {
  it('preserves a uniform image', async () => {
    const image = createImageData(4, 4, [128, 128, 128, 255]);
    const result = await bilateralFilter(image, 5, 0.1);
    for (let i = 0; i < result.data.length; i += 4) {
      expect(result.data[i]).toBeCloseTo(128, -1);
    }
  });

  it('smooths interior while preserving a sharp edge', async () => {
    const image = createImageData(20, 10, [0, 0, 0, 255]);
    for (let y = 0; y < 10; y++) {
      for (let x = 10; x < 20; x++) {
        setPixel(image, x, y, [255, 255, 255, 255]);
      }
    }
    const result = await bilateralFilter(image, 5, 0.1);
    expect(result.data[0]).toBeLessThan(30);
    expect(result.data[(9 * 20 + 19) * 4]).toBeGreaterThan(225);
  });

  it('preserves alpha channel', async () => {
    const image = createImageData(2, 1, [100, 100, 100, 200]);
    const result = await bilateralFilter(image, 2, 0.1);
    expect(result.data[3]).toBe(200);
    expect(result.data[7]).toBe(200);
  });

  it('accepts a progress callback', async () => {
    const image = createImageData(10, 10, [128, 128, 128, 255]);
    const updates: number[] = [];
    await bilateralFilter(image, 5, 0.1, (percent) => { updates.push(percent); });
    expect(updates.length).toBeGreaterThan(0);
    expect(updates[updates.length - 1]).toBeLessThanOrEqual(100);
  });
});
