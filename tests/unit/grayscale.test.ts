import { describe, expect, it } from 'vitest';
import { toGrayscale } from '../../src/processing/grayscale';
import { createImageData, setPixel } from '../utils/image';

describe('toGrayscale', () => {
  it('converts rgb pixels to luminance while preserving alpha', () => {
    const image = createImageData(2, 1, [0, 0, 0, 0]);
    setPixel(image, 0, 0, [255, 0, 0, 128]);
    setPixel(image, 1, 0, [0, 255, 0, 255]);

    const result = toGrayscale(image);

    expect(Array.from(result.data)).toEqual([
      54, 54, 54, 128,
      182, 182, 182, 255,
    ]);
  });
});
