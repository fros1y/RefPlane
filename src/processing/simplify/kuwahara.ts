export function kuwaharaFilter(
  imageData: ImageData,
  kernelSize: number,
  onProgress?: (percent: number) => void,
): ImageData {
  const { data, width, height } = imageData;
  const out = new ImageData(width, height);
  const outData = out.data;
  const radius = Math.floor(kernelSize / 2);
  const progressInterval = Math.max(1, Math.floor(height / 20));

  for (let y = 0; y < height; y++) {
    if (onProgress && y % progressInterval === 0) {
      onProgress((y / height) * 100);
    }
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 4;
      const quadrants = [
        { y0: y - radius, y1: y, x0: x - radius, x1: x },
        { y0: y - radius, y1: y, x0: x, x1: x + radius },
        { y0: y, y1: y + radius, x0: x - radius, x1: x },
        { y0: y, y1: y + radius, x0: x, x1: x + radius },
      ];

      let bestVar = Infinity;
      let bestR = 0, bestG = 0, bestB = 0;

      for (const q of quadrants) {
        let sumR = 0, sumG = 0, sumB = 0;
        let sumR2 = 0, sumG2 = 0, sumB2 = 0;
        let count = 0;

        for (let qy = q.y0; qy <= q.y1; qy++) {
          if (qy < 0 || qy >= height) continue;
          for (let qx = q.x0; qx <= q.x1; qx++) {
            if (qx < 0 || qx >= width) continue;
            const qi = (qy * width + qx) * 4;
            const r = data[qi], g = data[qi + 1], b = data[qi + 2];
            sumR += r; sumG += g; sumB += b;
            sumR2 += r * r; sumG2 += g * g; sumB2 += b * b;
            count++;
          }
        }

        if (count === 0) continue;
        const meanR = sumR / count, meanG = sumG / count, meanB = sumB / count;
        const varR = sumR2 / count - meanR * meanR;
        const varG = sumG2 / count - meanG * meanG;
        const varB = sumB2 / count - meanB * meanB;
        const totalVar = varR + varG + varB;

        if (totalVar < bestVar) {
          bestVar = totalVar;
          bestR = meanR;
          bestG = meanG;
          bestB = meanB;
        }
      }

      outData[idx] = Math.round(bestR);
      outData[idx + 1] = Math.round(bestG);
      outData[idx + 2] = Math.round(bestB);
      outData[idx + 3] = data[idx + 3];
    }
  }
  return out;
}
