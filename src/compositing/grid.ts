import type { GridConfig } from '../types';

export function renderGrid(
  canvas: OffscreenCanvas | HTMLCanvasElement,
  imageWidth: number,
  imageHeight: number,
  config: GridConfig
): void {
  const ctx = canvas.getContext('2d') as CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D | null;
  if (!ctx) return;

  ctx.clearRect(0, 0, canvas.width, canvas.height);
  if (!config.enabled) return;

  const { divisions, cellAspect, showDiagonals, showCenterLines, lineStyle, opacity, customColor } = config;

  const shortEdge = Math.min(imageWidth, imageHeight);
  const cellSize = shortEdge / divisions;

  let cellW: number, cellH: number;
  if (cellAspect === 'square') {
    cellW = cellH = cellSize;
  } else {
    if (imageWidth <= imageHeight) {
      cellW = cellSize;
      cellH = cellSize * (imageHeight / imageWidth);
    } else {
      cellH = cellSize;
      cellW = cellSize * (imageWidth / imageHeight);
    }
  }

  const cols = Math.ceil(imageWidth / cellW);
  const rows = Math.ceil(imageHeight / cellH);

  ctx.globalAlpha = opacity;

  const drawLine = (x1: number, y1: number, x2: number, y2: number) => {
    if (lineStyle === 'auto-contrast') {
      ctx.strokeStyle = 'rgba(0,0,0,0.6)';
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
      ctx.strokeStyle = 'rgba(255,255,255,0.4)';
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(x1 + 0.5, y1 + 0.5); ctx.lineTo(x2 + 0.5, y2 + 0.5); ctx.stroke();
    } else {
      ctx.strokeStyle = lineStyle === 'custom' ? customColor : lineStyle;
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
    }
  };

  for (let col = 0; col <= cols; col++) {
    const x = col * cellW;
    drawLine(x, 0, x, imageHeight);
  }
  for (let row = 0; row <= rows; row++) {
    const y = row * cellH;
    drawLine(0, y, imageWidth, y);
  }

  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const x0 = col * cellW, y0 = row * cellH;
      const x1 = x0 + cellW, y1 = y0 + cellH;

      if (showDiagonals) {
        drawLine(x0, y0, x1, y1);
        drawLine(x1, y0, x0, y1);
      }
      if (showCenterLines) {
        const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
        drawLine(cx, y0, cx, y1);
        drawLine(x0, cy, x1, cy);
      }
    }
  }

  ctx.globalAlpha = 1;
}
