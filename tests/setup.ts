import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/preact';
import { afterEach } from 'vitest';

afterEach(() => {
  cleanup();
});

if (typeof globalThis.ImageData === 'undefined') {
  class TestImageData {
    data: Uint8ClampedArray;
    width: number;
    height: number;

    constructor(dataOrWidth: Uint8ClampedArray | number, width?: number, height?: number) {
      if (dataOrWidth instanceof Uint8ClampedArray) {
        if (width == null || height == null) throw new TypeError('ImageData width and height are required');
        this.data = dataOrWidth;
        this.width = width;
        this.height = height;
        return;
      }

      if (width == null) throw new TypeError('ImageData height is required');
      this.width = dataOrWidth;
      this.height = width;
      this.data = new Uint8ClampedArray(this.width * this.height * 4);
    }
  }

  Object.defineProperty(globalThis, 'ImageData', {
    value: TestImageData,
    writable: true,
    configurable: true,
  });
}
