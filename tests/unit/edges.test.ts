import { describe, expect, it } from 'vitest';
import { cannyEdges, sobelEdges } from '../../src/processing/edges';
import { createImageData, countPixels, setPixel } from '../utils/image';

function makeVerticalStepImage(): ImageData {
  const image = createImageData(12, 12, [0, 0, 0, 255]);
  for (let y = 0; y < image.height; y += 1) {
    for (let x = 6; x < image.width; x += 1) {
      setPixel(image, x, y, [255, 255, 255, 255]);
    }
  }
  return image;
}

describe('edge detection', () => {
  it('detects more canny edges when line density is increased', () => {
    const image = makeVerticalStepImage();

    const sparse = cannyEdges(image, 0);
    const dense = cannyEdges(image, 1);

    const sparseCount = countPixels(sparse, (r) => r > 0);
    const denseCount = countPixels(dense, (r) => r > 0);

    expect(sparseCount).toBeGreaterThan(0);
    expect(denseCount).toBeGreaterThanOrEqual(sparseCount);
  });

  it('makes sobel output more permissive as sensitivity increases', () => {
    const image = makeVerticalStepImage();

    const lowSensitivity = sobelEdges(image, 0);
    const highSensitivity = sobelEdges(image, 1);

    const lowCount = countPixels(lowSensitivity, (r) => r > 0);
    const highCount = countPixels(highSensitivity, (r) => r > 0);

    expect(highCount).toBeGreaterThanOrEqual(lowCount);
    expect(highCount).toBeGreaterThan(0);
  });
});
