import { describe, expect, it } from 'vitest';
import { superResolutionFilter } from '../../../src/processing/simplify/super-resolution';
import { createImageData } from '../../utils/image';

describe('superResolutionFilter', () => {
  it('returns output with the same dimensions as the input', async () => {
    const image = createImageData(16, 16, [128, 128, 128, 255]);
    const result = await superResolutionFilter(image, 2, 0);
    expect(result.width).toBe(16);
    expect(result.height).toBe(16);
  });

  it('preserves a uniform image (all pixels identical)', async () => {
    const image = createImageData(8, 8, [100, 150, 200, 255]);
    const result = await superResolutionFilter(image, 2, 0);
    for (let i = 0; i < result.data.length; i += 4) {
      expect(result.data[i]).toBeCloseTo(100, -1);
      expect(result.data[i + 1]).toBeCloseTo(150, -1);
      expect(result.data[i + 2]).toBeCloseTo(200, -1);
    }
  });

  it('handles scale=1 (no downsampling) gracefully', async () => {
    const image = createImageData(8, 8, [64, 64, 64, 255]);
    const result = await superResolutionFilter(image, 1, 0);
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('handles large scale values without throwing', async () => {
    const image = createImageData(16, 16, [200, 100, 50, 255]);
    const result = await superResolutionFilter(image, 8, 0);
    expect(result.width).toBe(16);
    expect(result.height).toBe(16);
  });

  it('applies sharpening without changing output size', async () => {
    const image = createImageData(12, 12, [128, 128, 128, 255]);
    const result = await superResolutionFilter(image, 2, 0.5);
    expect(result.width).toBe(12);
    expect(result.height).toBe(12);
  });

  it('reports progress from 0 to 100', async () => {
    const image = createImageData(8, 8, [80, 80, 80, 255]);
    const updates: number[] = [];
    await superResolutionFilter(image, 2, 0, (p) => updates.push(p));
    expect(updates.length).toBeGreaterThan(0);
    expect(Math.max(...updates)).toBe(100);
  });

  it('rejects with AbortError when signal is already aborted', async () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const controller = new AbortController();
    controller.abort();
    await expect(
      superResolutionFilter(image, 2, 0, undefined, controller.signal),
    ).rejects.toMatchObject({ name: 'AbortError' });
  });

  it('preserves alpha channel', async () => {
    const image = createImageData(8, 8, [100, 100, 100, 200]);
    const result = await superResolutionFilter(image, 2, 0);
    for (let i = 3; i < result.data.length; i += 4) {
      expect(result.data[i]).toBeCloseTo(200, -1);
    }
  });
});
