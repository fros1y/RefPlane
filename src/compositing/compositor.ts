import { renderGrid } from './grid';
import { compositeEdges } from './edge-composite';
import { applyTemperatureMap } from '../color/temperature';
import type { GridConfig, EdgeConfig } from '../types';

export interface CompositeOptions {
  showTemperatureMap?: boolean;
  tempIntensity?: number;
  isolatedBand?: number | null;
  isolationThresholds?: number[];
}

export function composite(
  displayCanvas: HTMLCanvasElement,
  source: ImageData,
  gridConfig: GridConfig,
  edgeConfig: EdgeConfig,
  edgeData: ImageData | null,
  options?: CompositeOptions
): void {
  const { width, height } = source;
  displayCanvas.width = width;
  displayCanvas.height = height;
  const ctx = displayCanvas.getContext('2d')!;

  let displayData = source;

  if (options?.showTemperatureMap) {
    displayData = applyTemperatureMap(displayData, options.tempIntensity ?? 1.0);
  }

  if (options?.isolatedBand != null && options.isolationThresholds) {
    displayData = applyBandIsolation(displayData, options.isolatedBand, options.isolationThresholds);
  }

  ctx.putImageData(displayData, 0, 0);

  if (edgeConfig.enabled && edgeData) {
    compositeEdges(ctx, edgeData, edgeConfig);
  }

  if (gridConfig.enabled) {
    const gridCanvas = new OffscreenCanvas(width, height);
    renderGrid(gridCanvas, width, height, gridConfig);
    ctx.drawImage(gridCanvas, 0, 0);
  }
}

const DIMMED_ALPHA = 0.2;
// App background is #1a1a1a (26,26,26); blend isolated pixels toward it
const DIMMED_BG = 26;

function getLumaBand(luma: number, thresholds: number[]): number {
  for (let b = 0; b < thresholds.length; b++) {
    if (luma < thresholds[b]) return b;
  }
  return thresholds.length;
}

function applyBandIsolation(source: ImageData, band: number, thresholds: number[]): ImageData {
  const { data, width, height } = source;
  const out = new ImageData(width, height);
  const outData = out.data;

  for (let i = 0; i < data.length; i += 4) {
    const r = data[i], g = data[i + 1], b = data[i + 2], a = data[i + 3];
    // Use BT.709 coefficients to match grayscale.ts luminance conversion
    const luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
    const pixelBand = getLumaBand(luma, thresholds);
    if (pixelBand === band) {
      outData[i] = r; outData[i + 1] = g; outData[i + 2] = b; outData[i + 3] = a;
    } else {
      // dim by blending with dark background
      outData[i] = Math.round(r * DIMMED_ALPHA + DIMMED_BG * (1 - DIMMED_ALPHA));
      outData[i + 1] = Math.round(g * DIMMED_ALPHA + DIMMED_BG * (1 - DIMMED_ALPHA));
      outData[i + 2] = Math.round(b * DIMMED_ALPHA + DIMMED_BG * (1 - DIMMED_ALPHA));
      outData[i + 3] = a;
    }
  }
  return out;
}
