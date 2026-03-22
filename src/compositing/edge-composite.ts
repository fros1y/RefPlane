import type { EdgeConfig } from '../types';

/** Create a canvas, falling back to HTMLCanvasElement when OffscreenCanvas is unavailable. */
function makeCanvas(w: number, h: number): OffscreenCanvas | HTMLCanvasElement {
  if (typeof OffscreenCanvas !== 'undefined') {
    return new OffscreenCanvas(w, h);
  }
  const el = document.createElement('canvas');
  el.width = w;
  el.height = h;
  return el;
}

/**
 * Dilate edge pixels by the given line weight.
 * lineWeight=1 means no dilation; higher values expand edge pixels
 * within a circular radius of (lineWeight - 1).
 */
export function dilateEdges(edgeData: ImageData, lineWeight: number): ImageData {
  const radius = Math.max(0, Math.round(lineWeight) - 1);
  const { width, height, data } = edgeData;
  if (radius === 0) {
    const copy = new ImageData(width, height);
    copy.data.set(data);
    return copy;
  }

  const out = new ImageData(width, height);
  const outData = out.data;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let maxV = 0;
      for (let dy = -radius; dy <= radius; dy++) {
        for (let dx = -radius; dx <= radius; dx++) {
          if (dx * dx + dy * dy > radius * radius) continue;
          const ny = y + dy, nx = x + dx;
          if (ny < 0 || ny >= height || nx < 0 || nx >= width) continue;
          const v = data[(ny * width + nx) * 4];
          if (v > maxV) maxV = v;
        }
      }
      const i = (y * width + x) * 4;
      outData[i] = outData[i + 1] = outData[i + 2] = maxV;
      outData[i + 3] = 255;
    }
  }
  return out;
}

function makeEdgeMaskCanvas(edgeData: ImageData): OffscreenCanvas | HTMLCanvasElement {
  const { width, height, data } = edgeData;
  const canvas = makeCanvas(width, height);
  const ctx = canvas.getContext('2d') as CanvasRenderingContext2D;
  const mask = new ImageData(width, height);

  for (let i = 0; i < data.length; i += 4) {
    const v = data[i];
    mask.data[i] = 255;
    mask.data[i + 1] = 255;
    mask.data[i + 2] = 255;
    mask.data[i + 3] = v;
  }

  ctx.putImageData(mask, 0, 0);
  return canvas;
}

export function compositeEdges(
  destCtx: CanvasRenderingContext2D,
  edgeData: ImageData,
  config: EdgeConfig
): void {
  if (!config.enabled) return;

  const { compositeMode, lineColor, lineCustomColor, lineOpacity, edgesOnlyPolarity, lineKnockoutColor, lineKnockoutCustomColor, lineWeight } = config;

  // Apply dilation upfront so ALL composite modes honour lineWeight.
  const dilated = dilateEdges(edgeData, lineWeight);
  const { width, height } = dilated;

  const maskCanvas = makeEdgeMaskCanvas(dilated);
  const tmpCanvas = makeCanvas(width, height);
  const tmpCtx = tmpCanvas.getContext('2d') as CanvasRenderingContext2D;
  tmpCtx.drawImage(maskCanvas, 0, 0);

  switch (compositeMode) {
    case 'lines-over': {
      const color = lineColor === 'custom' ? lineCustomColor : lineColor;
      const colorCanvas = makeCanvas(width, height);
      const colorCtx = colorCanvas.getContext('2d') as CanvasRenderingContext2D;
      colorCtx.drawImage(maskCanvas, 0, 0);
      colorCtx.globalCompositeOperation = 'source-in';
      colorCtx.fillStyle = color;
      colorCtx.fillRect(0, 0, width, height);
      destCtx.globalAlpha = lineOpacity;
      destCtx.drawImage(colorCanvas, 0, 0);
      destCtx.globalAlpha = 1;
      break;
    }

    case 'edges-only': {
      destCtx.clearRect(0, 0, width, height);
      if (edgesOnlyPolarity === 'dark-on-light') {
        destCtx.fillStyle = 'white';
        destCtx.fillRect(0, 0, width, height);
        const inv = new ImageData(width, height);
        for (let i = 0; i < dilated.data.length; i += 4) {
          const v = dilated.data[i];
          inv.data[i] = 0;
          inv.data[i + 1] = 0;
          inv.data[i + 2] = 0;
          inv.data[i + 3] = v;
        }
        const invCanvas = makeCanvas(width, height);
        (invCanvas.getContext('2d') as CanvasRenderingContext2D).putImageData(inv, 0, 0);
        destCtx.drawImage(invCanvas, 0, 0);
      } else {
        destCtx.fillStyle = 'black';
        destCtx.fillRect(0, 0, width, height);
        destCtx.drawImage(tmpCanvas, 0, 0);
      }
      break;
    }

    case 'multiply': {
      destCtx.globalAlpha = lineOpacity;
      destCtx.globalCompositeOperation = 'multiply';
      destCtx.drawImage(tmpCanvas, 0, 0);
      destCtx.globalAlpha = 1;
      destCtx.globalCompositeOperation = 'source-over';
      break;
    }

    case 'knockout': {
      const color = lineKnockoutColor === 'custom' ? lineKnockoutCustomColor :
        lineKnockoutColor === 'dark-gray' ? '#333333' : 'black';
      const strokeCanvas = makeCanvas(width, height);
      const strokeCtx = strokeCanvas.getContext('2d') as CanvasRenderingContext2D;
      strokeCtx.drawImage(maskCanvas, 0, 0);
      strokeCtx.globalCompositeOperation = 'source-in';
      strokeCtx.fillStyle = color;
      strokeCtx.fillRect(0, 0, width, height);
      destCtx.globalAlpha = lineOpacity;
      destCtx.drawImage(strokeCanvas, 0, 0);
      destCtx.globalAlpha = 1;
      break;
    }
  }
}
