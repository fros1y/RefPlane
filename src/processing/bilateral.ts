export function bilateralFilter(imageData: ImageData, sigmaS: number, sigmaR: number): ImageData {
  const { data, width, height } = imageData;
  const out = new ImageData(width, height);
  const outData = out.data;
  const radius = Math.ceil(2 * sigmaS);
  const sigmaS2 = 2 * sigmaS * sigmaS;
  const sigmaR2 = 2 * sigmaR * sigmaR;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 4;
      const centerVal = data[idx] / 255;
      let sum = 0, weightSum = 0;

      for (let dy = -radius; dy <= radius; dy++) {
        const ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        for (let dx = -radius; dx <= radius; dx++) {
          const nx = x + dx;
          if (nx < 0 || nx >= width) continue;
          const nIdx = (ny * width + nx) * 4;
          const nVal = data[nIdx] / 255;
          const spatialDist = dx * dx + dy * dy;
          const valueDiff = centerVal - nVal;
          const weight = Math.exp(-spatialDist / sigmaS2 - valueDiff * valueDiff / sigmaR2);
          sum += weight * nVal;
          weightSum += weight;
        }
      }

      const result = Math.round((sum / weightSum) * 255);
      outData[idx] = outData[idx + 1] = outData[idx + 2] = result;
      outData[idx + 3] = data[idx + 3];
    }
  }
  return out;
}

export function bilateralFilterLab(
  labData: Float32Array,
  width: number,
  height: number,
  sigmaS: number,
  sigmaR: number
): Float32Array {
  const out = new Float32Array(labData.length);
  const radius = Math.ceil(2 * sigmaS);
  const sigmaS2 = 2 * sigmaS * sigmaS;
  const sigmaR2 = 2 * sigmaR * sigmaR;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 3;
      const cL = labData[idx], ca = labData[idx + 1], cb = labData[idx + 2];
      let sumL = 0, sumA = 0, sumB = 0, weightSum = 0;

      for (let dy = -radius; dy <= radius; dy++) {
        const ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        for (let dx = -radius; dx <= radius; dx++) {
          const nx = x + dx;
          if (nx < 0 || nx >= width) continue;
          const nIdx = (ny * width + nx) * 3;
          const nL = labData[nIdx], na = labData[nIdx + 1], nb = labData[nIdx + 2];
          const spatialDist = dx * dx + dy * dy;
          const dL = cL - nL, da = ca - na, db = cb - nb;
          const valueDiff2 = dL * dL + da * da + db * db;
          const weight = Math.exp(-spatialDist / sigmaS2 - valueDiff2 / sigmaR2);
          sumL += weight * nL; sumA += weight * na; sumB += weight * nb;
          weightSum += weight;
        }
      }
      out[idx] = sumL / weightSum;
      out[idx + 1] = sumA / weightSum;
      out[idx + 2] = sumB / weightSum;
    }
  }
  return out;
}

export function strengthToParams(strength: number): { sigmaS: number; sigmaR: number } {
  const s = strength;
  let sigmaS: number, sigmaR: number;
  if (s <= 0.5) {
    sigmaS = 2 + (10 - 2) * (s / 0.5);
    sigmaR = 0.05 + (0.15 - 0.05) * (s / 0.5);
  } else {
    sigmaS = 10 + (25 - 10) * ((s - 0.5) / 0.5);
    sigmaR = 0.15 + (0.35 - 0.15) * ((s - 0.5) / 0.5);
  }
  return { sigmaS, sigmaR };
}
