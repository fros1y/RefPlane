import { describe, expect, it } from 'vitest';
import { applyTemperatureMap, getTemperature } from '../../src/color/temperature';
import { rgbToOklab } from '../../src/color/oklab';
import { createImageData, setPixel } from '../utils/image';

describe('temperature mapping', () => {
  it('classifies warm and cool hues as expected', () => {
    expect(getTemperature(rgbToOklab(228, 144, 74))).toBe('warm');
    expect(getTemperature(rgbToOklab(72, 126, 224))).toBe('cool');
  });

  it('applies a visible false-color treatment while preserving alpha', () => {
    const image = createImageData(3, 1, [0, 0, 0, 255]);
    setPixel(image, 0, 0, [228, 144, 74, 255]);
    setPixel(image, 1, 0, [72, 126, 224, 255]);
    setPixel(image, 2, 0, [128, 128, 128, 200]);

    const result = applyTemperatureMap(image, 1);

    expect(result.data[0]).toBeGreaterThan(result.data[2]);
    expect(result.data[6]).toBeGreaterThan(result.data[4]);
    expect(result.data[11]).toBe(200);
  });
});
