import { describe, expect, it } from 'vitest';
import { runSimplify } from '../../../src/processing/simplify';
import { createImageData } from '../../utils/image';
import type { SimplifyConfig } from '../../../src/types';

function makeConfig(method: SimplifyConfig['method'], strength = 0.5): SimplifyConfig {
  return {
    method,
    strength,
    shadowMerge: false,
    bilateral: { sigmaS: 10, sigmaR: 0.15 },
    kuwahara: { kernelSize: 7, passes: 1, sharpness: 8, sectors: 8 },
    meanShift: { spatialRadius: 15, colorRadius: 25 },
    anisotropic: { iterations: 10, kappa: 20 },
    painterly: {
      radius: 8,
      q: 8,
      alpha: 1,
      zeta: 1,
      tensorSigma: 2,
      sharpenAmount: 0.35,
      edgeThresholdLow: 0.03,
      edgeThresholdHigh: 0.12,
      detailSigma: 1.5,
    },
    slic: { detail: 0.55, compactness: 0.15 },
    planeGuidance: { preserveBoundaries: false },
  };
}

describe('runSimplify', () => {
  it('returns input unchanged for method "none"', async () => {
    const image = createImageData(4, 4, [128, 128, 128, 255]);
    const result = await runSimplify(image, makeConfig('none'));
    expect(result.data).toEqual(image.data);
  });

  it('applies bilateral filter when method is "bilateral"', async () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = await runSimplify(image, makeConfig('bilateral'));
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('applies kuwahara filter when method is "kuwahara"', async () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = await runSimplify(image, makeConfig('kuwahara'));
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('applies mean-shift filter when method is "mean-shift"', async () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = await runSimplify(image, makeConfig('mean-shift'));
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('applies anisotropic filter when method is "anisotropic"', async () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = await runSimplify(image, makeConfig('anisotropic'));
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('passes progress callback through to algorithm', async () => {
    const image = createImageData(10, 10, [128, 128, 128, 255]);
    const updates: number[] = [];
    await runSimplify(image, makeConfig('bilateral'), (p) => { updates.push(p); });
    expect(updates.length).toBeGreaterThan(0);
  });

  it('aborts simplify when abort signal is already set', async () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const controller = new AbortController();
    controller.abort();

    await expect(runSimplify(image, makeConfig('bilateral'), undefined, controller.signal)).rejects.toMatchObject({
      name: 'AbortError',
    });
  });

  it('merges shadows more aggressively when shadow merge is enabled', async () => {
    const image = createImageData(2, 1, [180, 180, 180, 255]);
    image.data[0] = 20;
    image.data[1] = 20;
    image.data[2] = 20;

    const withoutMerge = await runSimplify(image, makeConfig('bilateral', 0.75));
    const withMerge = await runSimplify(image, { ...makeConfig('bilateral', 0.75), shadowMerge: true });

    const darkWithout = withoutMerge.data[0];
    const darkWith = withMerge.data[0];
    const midWithout = withoutMerge.data[4];
    const midWith = withMerge.data[4];

    expect(Math.abs(darkWith - darkWithout)).toBeGreaterThan(0);
    expect(Math.abs(midWith - midWithout)).toBeLessThanOrEqual(1);
  });
});
