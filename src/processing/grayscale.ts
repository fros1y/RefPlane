export function toGrayscale(imageData: ImageData): ImageData {
  const { data, width, height } = imageData;
  const out = new ImageData(width, height);
  const outData = out.data;
  for (let i = 0; i < data.length; i += 4) {
    const L = Math.round(0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]);
    outData[i] = outData[i + 1] = outData[i + 2] = L;
    outData[i + 3] = data[i + 3];
  }
  return out;
}
