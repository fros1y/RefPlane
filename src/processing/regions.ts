export type MinRegionSize = "off" | "small" | "medium" | "large";

function sizeForOption(option: MinRegionSize, totalPixels: number): number {
  switch (option) {
    case "off": return 0;
    case "small": return Math.floor(totalPixels * 0.002);
    case "medium": return Math.floor(totalPixels * 0.005);
    case "large": return Math.floor(totalPixels * 0.01);
  }
}

export function cleanupRegions(imageData: ImageData, minSize: MinRegionSize): ImageData {
  if (minSize === "off") return imageData;
  const { data, width, height } = imageData;
  const totalPixels = width * height;
  const threshold = sizeForOption(minSize, totalPixels);

  const labels = new Int32Array(totalPixels).fill(-1);
  const grayValues = new Uint8Array(totalPixels);
  for (let i = 0; i < totalPixels; i++) {
    grayValues[i] = data[i * 4];
  }

  let numLabels = 0;
  const componentSize: number[] = [];
  const componentGray: number[] = [];

  for (let i = 0; i < totalPixels; i++) {
    if (labels[i] !== -1) continue;
    const gray = grayValues[i];
    const label = numLabels++;
    componentSize.push(0);
    componentGray.push(gray);

    const queue: number[] = [i];
    labels[i] = label;
    let qi = 0;
    while (qi < queue.length) {
      const p = queue[qi++];
      componentSize[label]++;
      const py = Math.floor(p / width);
      const px = p % width;

      const neighbors = [
        py > 0 ? p - width : -1,
        py < height - 1 ? p + width : -1,
        px > 0 ? p - 1 : -1,
        px < width - 1 ? p + 1 : -1,
      ];

      for (const n of neighbors) {
        if (n < 0 || labels[n] !== -1) continue;
        if (grayValues[n] === gray) {
          labels[n] = label;
          queue.push(n);
        }
      }
    }
  }

  const out = new ImageData(new Uint8ClampedArray(data), width, height);
  const outData = out.data;

  for (let i = 0; i < totalPixels; i++) {
    const label = labels[i];
    if (componentSize[label] < threshold) {
      const y = Math.floor(i / width);
      const x = i % width;
      let bestGray = componentGray[label];
      const neighbors = [
        y > 0 ? i - width : -1,
        y < height - 1 ? i + width : -1,
        x > 0 ? i - 1 : -1,
        x < width - 1 ? i + 1 : -1,
      ];
      for (const n of neighbors) {
        if (n < 0) continue;
        if (grayValues[n] !== componentGray[label]) {
          bestGray = grayValues[n];
          break;
        }
      }
      outData[i * 4] = outData[i * 4 + 1] = outData[i * 4 + 2] = bestGray;
    }
  }
  return out;
}
