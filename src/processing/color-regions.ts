import { rgbToOklab, oklabToRgb } from '../color/oklab';
import { oklabToOklch, oklchToOklab } from '../color/oklch';
import { bilateralFilterLab, strengthToParams } from './bilateral';
import { quantize } from './quantize';
import { kMeans } from './kmeans';
import type { ColorConfig } from '../types';

export interface ColorRegionsResult {
  imageData: ImageData;
  palette: string[];
  paletteBands: number[];
}

export function processColorRegions(imageData: ImageData, config: ColorConfig): ColorRegionsResult {
  const { data, width, height } = imageData;
  const numPixels = width * height;

  const labData = new Float32Array(numPixels * 3);
  for (let i = 0; i < numPixels; i++) {
    const r = data[i * 4], g = data[i * 4 + 1], b = data[i * 4 + 2];
    const lab = rgbToOklab(r, g, b);
    labData[i * 3] = lab.L;
    labData[i * 3 + 1] = lab.a;
    labData[i * 3 + 2] = lab.b;
  }

  const { sigmaS, sigmaR } = strengthToParams(config.strength);
  const filteredLab = bilateralFilterLab(labData, width, height, sigmaS, sigmaR);

  const bandAssignments = new Int32Array(numPixels);
  for (let i = 0; i < numPixels; i++) {
    const L = filteredLab[i * 3];
    bandAssignments[i] = quantize(L, config.thresholds);
  }

  const palette: string[] = [];
  const paletteBands: number[] = [];
  const allCentroids: Array<{ band: number; centroid: { L: number; a: number; b: number } }> = [];

  for (let band = 0; band < config.bands; band++) {
    const bandPixels: number[] = [];
    for (let i = 0; i < numPixels; i++) {
      if (bandAssignments[i] === band) bandPixels.push(i);
    }
    if (bandPixels.length === 0) continue;

    const maxSamples = 100000;
    const samplePixels = bandPixels.length > maxSamples
      ? bandPixels.filter(() => Math.random() < maxSamples / bandPixels.length)
      : bandPixels;

    const pixelLab = new Float32Array(samplePixels.length * 3);
    for (let i = 0; i < samplePixels.length; i++) {
      const pi = samplePixels[i];
      pixelLab[i * 3] = filteredLab[pi * 3];
      pixelLab[i * 3 + 1] = filteredLab[pi * 3 + 1];
      pixelLab[i * 3 + 2] = filteredLab[pi * 3 + 2];
    }

    const { centroids } = kMeans(pixelLab, samplePixels.length, config.colorsPerBand);
    for (const c of centroids) {
      allCentroids.push({ band, centroid: c });
    }
  }

  const emphasizedCentroids = allCentroids.map(({ band, centroid }) => {
    let c = centroid;
    if (config.warmCoolEmphasis > 0) {
      const lch = oklabToOklch(c);
      if (lch.C > 0.02) {
        const h = lch.h;
        let shift = 0;
        if (h >= 20 && h <= 110) {
          shift = (60 - h) * config.warmCoolEmphasis * 0.3;
        } else if (h > 170 && h <= 340) {
          const dist = h > 270 ? 240 + (360 - h) : 240 - h;
          shift = dist * config.warmCoolEmphasis * 0.3;
        }
        const newLch = { L: lch.L, C: lch.C, h: (lch.h + shift + 360) % 360 };
        c = oklchToOklab(newLch);
      }
    }
    return { band, centroid: c };
  });

  for (const { band, centroid } of emphasizedCentroids) {
    const [r, g, b] = oklabToRgb(centroid.L, centroid.a, centroid.b);
    palette.push(`#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`);
    paletteBands.push(band);
  }

  // Pre-group centroids by band index to avoid repeated filter() calls in the pixel loop
  const centroidsByBand: Array<Array<{ L: number; a: number; b: number }>> = Array.from(
    { length: config.bands }, () => []
  );
  for (const { band, centroid } of emphasizedCentroids) {
    centroidsByBand[band]?.push(centroid);
  }

  const out = new ImageData(width, height);
  const outData = out.data;

  for (let i = 0; i < numPixels; i++) {
    const band = bandAssignments[i];
    const bandCentroids = centroidsByBand[band] ?? [];
    if (bandCentroids.length === 0) {
      outData[i * 4] = data[i * 4];
      outData[i * 4 + 1] = data[i * 4 + 1];
      outData[i * 4 + 2] = data[i * 4 + 2];
      outData[i * 4 + 3] = 255;
      continue;
    }

    const pL = filteredLab[i * 3], pa = filteredLab[i * 3 + 1], pb = filteredLab[i * 3 + 2];
    let bestDist = Infinity, bestC = bandCentroids[0];
    for (const centroid of bandCentroids) {
      const dL = pL - centroid.L, da = pa - centroid.a, db = pb - centroid.b;
      const dist = dL * dL + da * da + db * db;
      if (dist < bestDist) { bestDist = dist; bestC = centroid; }
    }

    const [r, g, b] = oklabToRgb(bestC.L, bestC.a, bestC.b);
    outData[i * 4] = r; outData[i * 4 + 1] = g; outData[i * 4 + 2] = b; outData[i * 4 + 3] = 255;
  }

  return { imageData: out, palette, paletteBands };
}
