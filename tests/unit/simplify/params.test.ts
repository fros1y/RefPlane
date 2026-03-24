import { describe, expect, it } from 'vitest';
import { strengthToMethodParams } from '../../../src/processing/simplify/params';

describe('strengthToMethodParams', () => {
  it('maps strength 0 to minimum bilateral params', () => {
    const result = strengthToMethodParams('bilateral', 0);
    expect(result).toEqual({ sigmaS: 2, sigmaR: 0.05 });
  });

  it('maps strength 0.5 to midpoint bilateral params', () => {
    const result = strengthToMethodParams('bilateral', 0.5);
    expect(result).toEqual({ sigmaS: 10, sigmaR: 0.15 });
  });

  it('maps strength 1 to maximum bilateral params', () => {
    const result = strengthToMethodParams('bilateral', 1);
    expect(result).toEqual({ sigmaS: 25, sigmaR: 0.35 });
  });

  it('maps strength 0 to minimum kuwahara params', () => {
    const result = strengthToMethodParams('kuwahara', 0);
    expect(result).toEqual({ kernelSize: 3, passes: 1, sharpness: 8, sectors: 8 });
  });

  it('maps strength 1 to maximum kuwahara params', () => {
    const result = strengthToMethodParams('kuwahara', 1);
    expect(result).toEqual({ kernelSize: 15, passes: 1, sharpness: 8, sectors: 8 });
  });

  it('maps strength 0 to minimum mean-shift params', () => {
    const result = strengthToMethodParams('mean-shift', 0);
    expect(result).toEqual({ spatialRadius: 5, colorRadius: 10 });
  });

  it('maps strength 1 to maximum mean-shift params', () => {
    const result = strengthToMethodParams('mean-shift', 1);
    expect(result).toEqual({ spatialRadius: 30, colorRadius: 50 });
  });

  it('maps strength 0 to minimum anisotropic params', () => {
    const result = strengthToMethodParams('anisotropic', 0);
    expect(result).toEqual({ iterations: 1, kappa: 30 });
  });

  it('maps strength 1 to maximum anisotropic params', () => {
    const result = strengthToMethodParams('anisotropic', 1);
    expect(result).toEqual({ iterations: 30, kappa: 10 });
  });

  it('returns empty object for "none"', () => {
    const result = strengthToMethodParams('none', 0.5);
    expect(result).toEqual({});
  });

  it('maps strength 0 to minimum super-resolution scale (2)', () => {
    const result = strengthToMethodParams('super-resolution', 0);
    expect(result.scale).toBe(2);
    expect(result.sharpenAmount).toBe(0.3);
  });

  it('maps strength 1 to maximum super-resolution scale (8)', () => {
    const result = strengthToMethodParams('super-resolution', 1);
    expect(result.scale).toBe(8);
    expect(result.sharpenAmount).toBe(0.3);
  });
});
