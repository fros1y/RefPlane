export function quantize(value: number, thresholds: number[]): number {
  for (let i = 0; i < thresholds.length; i++) {
    if (value < thresholds[i]) return i;
  }
  return thresholds.length;
}

export function getDefaultThresholds(levels: number): number[] {
  const thresholds: number[] = [];
  for (let i = 1; i < levels; i++) {
    thresholds.push(i / levels);
  }
  return thresholds;
}

export function levelToGray(level: number, totalLevels: number): number {
  if (totalLevels === 1) return 128;
  return Math.round((level / (totalLevels - 1)) * 255);
}

export function applyQuantization(grayscaleData: ImageData, thresholds: number[]): ImageData {
  const { data, width, height } = grayscaleData;
  const out = new ImageData(width, height);
  const outData = out.data;
  const levels = thresholds.length + 1;

  for (let i = 0; i < data.length; i += 4) {
    const value = data[i] / 255;
    const level = quantize(value, thresholds);
    const gray = levelToGray(level, levels);
    outData[i] = outData[i + 1] = outData[i + 2] = gray;
    outData[i + 3] = data[i + 3];
  }
  return out;
}
