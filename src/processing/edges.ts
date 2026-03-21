function gaussianBlur(imageData: ImageData, sigma: number): ImageData {
  const radius = Math.ceil(2 * sigma);
  const size = 2 * radius + 1;
  const kernel: number[] = [];
  let kernelSum = 0;
  for (let i = 0; i < size; i++) {
    const x = i - radius;
    const v = Math.exp(-(x * x) / (2 * sigma * sigma));
    kernel.push(v);
    kernelSum += v;
  }
  for (let i = 0; i < size; i++) kernel[i] /= kernelSum;

  const { data, width, height } = imageData;
  const horiz = new Float32Array(width * height);
  const temp = new Float32Array(width * height);
  const out = new ImageData(width, height);
  const outData = out.data;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sum = 0, wsum = 0;
      for (let k = 0; k < size; k++) {
        const nx = x + k - radius;
        if (nx < 0 || nx >= width) continue;
        sum += kernel[k] * data[(y * width + nx) * 4] / 255;
        wsum += kernel[k];
      }
      horiz[y * width + x] = sum / wsum;
    }
  }

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sum = 0, wsum = 0;
      for (let k = 0; k < size; k++) {
        const ny = y + k - radius;
        if (ny < 0 || ny >= height) continue;
        sum += kernel[k] * horiz[ny * width + x];
        wsum += kernel[k];
      }
      temp[y * width + x] = sum / wsum;
    }
  }

  for (let i = 0; i < width * height; i++) {
    const v = Math.round(temp[i] * 255);
    outData[i * 4] = outData[i * 4 + 1] = outData[i * 4 + 2] = v;
    outData[i * 4 + 3] = 255;
  }
  return out;
}

export function sobelEdges(imageData: ImageData, sensitivity: number): ImageData {
  const { data, width, height } = imageData;
  const out = new ImageData(width, height);
  const outData = out.data;
  const threshold = sensitivity * 0.5;

  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const idx = (y * width + x) * 4;
      const get = (dy: number, dx: number) => {
        const ni = ((y + dy) * width + (x + dx)) * 4;
        return data[ni] / 255;
      };

      const Gx = -get(-1, -1) - 2 * get(0, -1) - get(1, -1) + get(-1, 1) + 2 * get(0, 1) + get(1, 1);
      const Gy = -get(-1, -1) - 2 * get(-1, 0) - get(-1, 1) + get(1, -1) + 2 * get(1, 0) + get(1, 1);
      const mag = Math.sqrt(Gx * Gx + Gy * Gy) / 4;

      const val = mag > threshold ? Math.min(255, Math.round(mag * 255)) : 0;
      outData[idx] = outData[idx + 1] = outData[idx + 2] = val;
      outData[idx + 3] = 255;
    }
  }
  return out;
}

export function cannyEdges(imageData: ImageData, detail: number): ImageData {
  const T_low = 0.15 - detail * (0.15 - 0.03);
  const T_high = 0.40 - detail * (0.40 - 0.10);

  const { width, height } = imageData;
  const blurred = gaussianBlur(imageData, 1.4);
  const blurData = blurred.data;

  const magnitude = new Float32Array(width * height);
  const direction = new Uint8Array(width * height);

  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const get = (dy: number, dx: number) => blurData[((y + dy) * width + (x + dx)) * 4] / 255;
      const Gx = -get(-1, -1) - 2 * get(0, -1) - get(1, -1) + get(-1, 1) + 2 * get(0, 1) + get(1, 1);
      const Gy = -get(-1, -1) - 2 * get(-1, 0) - get(-1, 1) + get(1, -1) + 2 * get(1, 0) + get(1, 1);
      const idx = y * width + x;
      magnitude[idx] = Math.sqrt(Gx * Gx + Gy * Gy) / 4;
      let angle = Math.atan2(Gy, Gx) * 180 / Math.PI;
      if (angle < 0) angle += 180;
      if (angle < 22.5 || angle >= 157.5) direction[idx] = 0;
      else if (angle < 67.5) direction[idx] = 1;
      else if (angle < 112.5) direction[idx] = 2;
      else direction[idx] = 3;
    }
  }

  const suppressed = new Float32Array(width * height);
  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const idx = y * width + x;
      const mag = magnitude[idx];
      let n1: number, n2: number;
      switch (direction[idx]) {
        case 0: n1 = magnitude[idx - 1]; n2 = magnitude[idx + 1]; break;
        case 1: n1 = magnitude[(y - 1) * width + (x + 1)]; n2 = magnitude[(y + 1) * width + (x - 1)]; break;
        case 2: n1 = magnitude[(y - 1) * width + x]; n2 = magnitude[(y + 1) * width + x]; break;
        default: n1 = magnitude[(y - 1) * width + (x - 1)]; n2 = magnitude[(y + 1) * width + (x + 1)]; break;
      }
      suppressed[idx] = (mag >= n1 && mag >= n2) ? mag : 0;
    }
  }

  const STRONG = 255, WEAK = 128;
  const edges = new Uint8Array(width * height);
  for (let i = 0; i < suppressed.length; i++) {
    if (suppressed[i] >= T_high) edges[i] = STRONG;
    else if (suppressed[i] >= T_low) edges[i] = WEAK;
  }

  let changed = true;
  while (changed) {
    changed = false;
    for (let y = 1; y < height - 1; y++) {
      for (let x = 1; x < width - 1; x++) {
        const idx = y * width + x;
        if (edges[idx] !== WEAK) continue;
        outer: for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            if (edges[(y + dy) * width + (x + dx)] === STRONG) {
              edges[idx] = STRONG;
              changed = true;
              break outer;
            }
          }
        }
      }
    }
  }

  const out = new ImageData(width, height);
  const outData = out.data;
  for (let i = 0; i < width * height; i++) {
    const v = edges[i] === STRONG ? 255 : 0;
    outData[i * 4] = outData[i * 4 + 1] = outData[i * 4 + 2] = v;
    outData[i * 4 + 3] = 255;
  }
  return out;
}
