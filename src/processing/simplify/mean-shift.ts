export function meanShiftFilter(
  imageData: ImageData,
  spatialRadius: number,
  colorRadius: number,
  onProgress?: (percent: number) => void,
): ImageData {
  const { data, width, height } = imageData;
  const out = new ImageData(width, height);
  const outData = out.data;
  const maxIter = 10;
  const convergenceThreshold = 1.0;
  const spatialR2 = spatialRadius * spatialRadius;
  const colorR2 = colorRadius * colorRadius;
  const progressInterval = Math.max(1, Math.floor(height / 20));

  for (let y = 0; y < height; y++) {
    if (onProgress && y % progressInterval === 0) {
      onProgress((y / height) * 100);
    }
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 4;
      let cx = x, cy = y;
      let cR = data[idx], cG = data[idx + 1], cB = data[idx + 2];

      for (let iter = 0; iter < maxIter; iter++) {
        let sumX = 0, sumY = 0;
        let sumR = 0, sumG = 0, sumB = 0;
        let count = 0;

        const iy = Math.round(cy), ix = Math.round(cx);
        const sr = Math.ceil(spatialRadius);
        const y0 = Math.max(0, iy - sr), y1 = Math.min(height - 1, iy + sr);
        const x0 = Math.max(0, ix - sr), x1 = Math.min(width - 1, ix + sr);

        for (let ny = y0; ny <= y1; ny++) {
          for (let nx = x0; nx <= x1; nx++) {
            const sdx = nx - cx, sdy = ny - cy;
            if (sdx * sdx + sdy * sdy > spatialR2) continue;

            const ni = (ny * width + nx) * 4;
            const dR = data[ni] - cR, dG = data[ni + 1] - cG, dB = data[ni + 2] - cB;
            if (dR * dR + dG * dG + dB * dB > colorR2) continue;

            sumX += nx; sumY += ny;
            sumR += data[ni]; sumG += data[ni + 1]; sumB += data[ni + 2];
            count++;
          }
        }

        if (count === 0) break;
        const newX = sumX / count, newY = sumY / count;
        const newR = sumR / count, newG = sumG / count, newB = sumB / count;

        const shift = Math.sqrt(
          (newX - cx) * (newX - cx) + (newY - cy) * (newY - cy) +
          (newR - cR) * (newR - cR) + (newG - cG) * (newG - cG) + (newB - cB) * (newB - cB)
        );

        cx = newX; cy = newY;
        cR = newR; cG = newG; cB = newB;

        if (shift < convergenceThreshold) break;
      }

      outData[idx] = Math.round(cR);
      outData[idx + 1] = Math.round(cG);
      outData[idx + 2] = Math.round(cB);
      outData[idx + 3] = data[idx + 3];
    }
  }
  return out;
}
