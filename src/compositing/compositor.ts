import { renderGrid } from './grid';
import type { GridConfig } from '../types';

export interface CompositeOptions {
  isolatedBand?: number | null;
  isolationThresholds?: number[];
}

/** Create a canvas, falling back to HTMLCanvasElement on platforms where OffscreenCanvas is unavailable (e.g. some iOS Safari versions). */
function makeCanvas(w: number, h: number): OffscreenCanvas | HTMLCanvasElement {
  if (typeof OffscreenCanvas !== 'undefined') {
    return new OffscreenCanvas(w, h);
  }
  const el = document.createElement('canvas');
  el.width = w;
  el.height = h;
  return el;
}

// Cached scratch canvas for grid rendering — reused across frames to avoid per-render allocations.
let gridScratch: OffscreenCanvas | HTMLCanvasElement | null = null;

export function composite(
  displayCanvas: HTMLCanvasElement,
  source: ImageData,
  gridConfig: GridConfig,
  options?: CompositeOptions
): void {
  const { width, height } = source;
  displayCanvas.width = width;
  displayCanvas.height = height;
  const ctx = displayCanvas.getContext('2d')!;

  let displayData = source;

  if (options?.isolatedBand != null && options.isolationThresholds) {
    displayData = applyBandIsolation(displayData, options.isolatedBand, options.isolationThresholds);
  }

  ctx.putImageData(displayData, 0, 0);

  if (gridConfig.enabled) {
    if (!gridScratch || gridScratch.width !== width || gridScratch.height !== height) {
      gridScratch = makeCanvas(width, height);
    } else {
      // Clear the cached canvas so previous frame's grid lines don't bleed through
      (gridScratch.getContext('2d') as CanvasRenderingContext2D).clearRect(0, 0, width, height);
    }
    renderGrid(gridScratch, width, height, gridConfig);
    if (gridConfig.lineStyle === 'auto-contrast') {
      ctx.globalCompositeOperation = 'difference';
    }
    ctx.drawImage(gridScratch, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
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
