export function createImageData(width: number, height: number, fill: [number, number, number, number] = [0, 0, 0, 255]): ImageData {
  const data = new Uint8ClampedArray(width * height * 4);
  for (let i = 0; i < data.length; i += 4) {
    data[i] = fill[0];
    data[i + 1] = fill[1];
    data[i + 2] = fill[2];
    data[i + 3] = fill[3];
  }
  return new ImageData(data, width, height);
}

export function setPixel(image: ImageData, x: number, y: number, rgba: [number, number, number, number]): void {
  const i = (y * image.width + x) * 4;
  image.data[i] = rgba[0];
  image.data[i + 1] = rgba[1];
  image.data[i + 2] = rgba[2];
  image.data[i + 3] = rgba[3];
}

export function countPixels(image: ImageData, predicate: (r: number, g: number, b: number, a: number) => boolean): number {
  let count = 0;
  for (let i = 0; i < image.data.length; i += 4) {
    if (predicate(image.data[i], image.data[i + 1], image.data[i + 2], image.data[i + 3])) {
      count += 1;
    }
  }
  return count;
}
