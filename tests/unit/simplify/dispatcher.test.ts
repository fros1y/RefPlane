import { describe, expect, it } from 'vitest';
import { runSimplify } from '../../../src/processing/simplify';
import { createImageData } from '../../utils/image';
import type { SimplifyConfig } from '../../../src/types';

function makeConfig(method: SimplifyConfig['method'], strength = 0.5): SimplifyConfig {
  return {
    method,
    strength,
    bilateral: { sigmaS: 10, sigmaR: 0.15 },
    kuwahara: { kernelSize: 7 },
    meanShift: { spatialRadius: 15, colorRadius: 25 },
    anisotropic: { iterations: 10, kappa: 20 },
  };
}

describe('runSimplify', () => {
  it('returns input unchanged for method "none"', () => {
    const image = createImageData(4, 4, [128, 128, 128, 255]);
    const result = runSimplify(image, makeConfig('none'));
    expect(result.data).toEqual(image.data);
  });

  it('applies bilateral filter when method is "bilateral"', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = runSimplify(image, makeConfig('bilateral'));
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('applies kuwahara filter when method is "kuwahara"', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = runSimplify(image, makeConfig('kuwahara'));
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('applies mean-shift filter when method is "mean-shift"', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = runSimplify(image, makeConfig('mean-shift'));
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('applies anisotropic filter when method is "anisotropic"', () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = runSimplify(image, makeConfig('anisotropic'));
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
  });

  it('passes progress callback through to algorithm', () => {
    const image = createImageData(10, 10, [128, 128, 128, 255]);
    const updates: number[] = [];
    runSimplify(image, makeConfig('bilateral'), (p) => { updates.push(p); });
    expect(updates.length).toBeGreaterThan(0);
  });
});
