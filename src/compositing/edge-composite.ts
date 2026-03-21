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

export function compositeEdges(
  destCtx: CanvasRenderingContext2D,
  edgeData: ImageData,
  config: EdgeConfig
): void {
  if (!config.enabled) return;

  const { compositeMode, lineColor, lineCustomColor, lineOpacity, edgesOnlyPolarity, lineKnockoutColor, lineKnockoutCustomColor } = config;
  const { width, height } = edgeData;

  const tmpCanvas = makeCanvas(width, height);
  const tmpCtx = tmpCanvas.getContext('2d') as CanvasRenderingContext2D;
  tmpCtx.putImageData(edgeData, 0, 0);

  switch (compositeMode) {
    case 'lines-over': {
      const color = lineColor === 'custom' ? lineCustomColor : lineColor;
      const colorCanvas = makeCanvas(width, height);
      const colorCtx = colorCanvas.getContext('2d') as CanvasRenderingContext2D;
      colorCtx.putImageData(edgeData, 0, 0);
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
        for (let i = 0; i < edgeData.data.length; i += 4) {
          const v = edgeData.data[i];
          inv.data[i] = 255 - v;
          inv.data[i + 1] = 255 - v;
          inv.data[i + 2] = 255 - v;
          inv.data[i + 3] = v > 128 ? 255 : 0;
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
      destCtx.globalCompositeOperation = 'multiply';
      destCtx.drawImage(tmpCanvas, 0, 0);
      destCtx.globalCompositeOperation = 'source-over';
      break;
    }

    case 'knockout': {
      const color = lineKnockoutColor === 'custom' ? lineKnockoutCustomColor :
        lineKnockoutColor === 'dark-gray' ? '#333333' : 'black';
      const strokeCanvas = makeCanvas(width, height);
      const strokeCtx = strokeCanvas.getContext('2d') as CanvasRenderingContext2D;
      strokeCtx.putImageData(edgeData, 0, 0);
      strokeCtx.globalCompositeOperation = 'source-in';
      strokeCtx.fillStyle = color;
      strokeCtx.fillRect(0, 0, width, height);
      destCtx.drawImage(strokeCanvas, 0, 0);
      break;
    }
  }
}
