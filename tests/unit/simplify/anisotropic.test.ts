import { describe, expect, it } from 'vitest';
import { anisotropicDiffusion } from '../../../src/processing/simplify/anisotropic';
import { createImageData, setPixel } from '../../utils/image';

describe('anisotropicDiffusion', () => {
  it('preserves a uniform image', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = anisotropicDiffusion(image, 5, 20);
    for (let i = 0; i < result.data.length; i += 4) {
      expect(result.data[i]).toBeCloseTo(128, -1);
    }
  });

  it('produces output with same dimensions as input', () => {
    const image = createImageData(16, 12, [100, 100, 100, 255]);
    const result = anisotropicDiffusion(image, 3, 15);
    expect(result.width).toBe(16);
    expect(result.height).toBe(12);
  });

  it('preserves alpha channel', () => {
    const image = createImageData(4, 4, [100, 100, 100, 190]);
    const result = anisotropicDiffusion(image, 2, 20);
    for (let i = 3; i < result.data.length; i += 4) {
      expect(result.data[i]).toBe(190);
    }
  });

  it('smooths interior while preserving strong edges', () => {
    const image = createImageData(20, 10, [50, 50, 50, 255]);
    for (let y = 0; y < 10; y++) {
      for (let x = 10; x < 20; x++) {
        setPixel(image, x, y, [200, 200, 200, 255]);
      }
    }
    const result = anisotropicDiffusion(image, 10, 15);
    expect(result.data[(5 * 20 + 2) * 4]).toBeLessThan(80);
    expect(result.data[(5 * 20 + 17) * 4]).toBeGreaterThan(170);
  });

  it('more iterations produce smoother output', () => {
    const image = createImageData(20, 20, [128, 128, 128, 255]);
    for (let y = 0; y < 20; y++) {
      for (let x = 0; x < 20; x++) {
        const v = 128 + ((x * 7 + y * 13) % 20) - 10;
        setPixel(image, x, y, [v, v, v, 255]);
      }
    }
    const few = anisotropicDiffusion(image, 2, 20);
    const many = anisotropicDiffusion(image, 20, 20);

    function variance(img: ImageData): number {
      let sum = 0, sum2 = 0, count = 0;
      for (let y = 5; y < 15; y++) {
        for (let x = 5; x < 15; x++) {
          const v = img.data[(y * 20 + x) * 4];
          sum += v; sum2 += v * v; count++;
        }
      }
      const mean = sum / count;
      return sum2 / count - mean * mean;
    }
    expect(variance(many)).toBeLessThan(variance(few));
  });

  it('accepts a progress callback', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const updates: number[] = [];
    anisotropicDiffusion(image, 5, 20, (percent) => { updates.push(percent); });
    expect(updates.length).toBeGreaterThan(0);
  });
});
