import { renderGrid } from './grid';
import { compositeEdges } from './edge-composite';
import type { GridConfig, EdgeConfig } from '../types';

export function composite(
  displayCanvas: HTMLCanvasElement,
  source: ImageData,
  gridConfig: GridConfig,
  edgeConfig: EdgeConfig,
  edgeData: ImageData | null
): void {
  const { width, height } = source;
  displayCanvas.width = width;
  displayCanvas.height = height;
  const ctx = displayCanvas.getContext('2d')!;

  ctx.putImageData(source, 0, 0);

  if (edgeConfig.enabled && edgeData) {
    compositeEdges(ctx, edgeData, edgeConfig);
  }

  if (gridConfig.enabled) {
    const gridCanvas = new OffscreenCanvas(width, height);
    renderGrid(gridCanvas, width, height, gridConfig);
    ctx.drawImage(gridCanvas, 0, 0);
  }
}
