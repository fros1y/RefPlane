function luminance(r: number, g: number, b: number): number {
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}

export function mergeShadows(imageData: ImageData, strength: number): ImageData {
  const threshold = 0.38;
  const clampedStrength = Math.min(1, Math.max(0, strength));
  const bins = clampedStrength >= 0.7 ? 2 : 3;
  const source = imageData.data;
  const output = new Uint8ClampedArray(source.length);

  for (let index = 0; index < source.length; index += 4) {
    const r = source[index];
    const g = source[index + 1];
    const b = source[index + 2];
    const a = source[index + 3];
    const l = luminance(r, g, b);

    if (l >= threshold) {
      output[index] = r;
      output[index + 1] = g;
      output[index + 2] = b;
      output[index + 3] = a;
      continue;
    }

    const normalized = Math.max(0, Math.min(1, l / threshold));
    const quantized = (Math.round(normalized * (bins - 1)) / (bins - 1)) * threshold;
    const shadowDepth = 1 - normalized;
    const mergeAmount = Math.min(1, 0.45 + clampedStrength * 0.4 + shadowDepth * 0.35);

    let targetR = r;
    let targetG = g;
    let targetB = b;

    if (l > 0.0001) {
      const scale = quantized / l;
      targetR = Math.min(255, r * scale);
      targetG = Math.min(255, g * scale);
      targetB = Math.min(255, b * scale);
    } else {
      const darkLevel = quantized * 255;
      targetR = darkLevel;
      targetG = darkLevel;
      targetB = darkLevel;
    }

    output[index] = Math.round(r + (targetR - r) * mergeAmount);
    output[index + 1] = Math.round(g + (targetG - g) * mergeAmount);
    output[index + 2] = Math.round(b + (targetB - b) * mergeAmount);
    output[index + 3] = a;
  }

  return new ImageData(output, imageData.width, imageData.height);
}
