import { oklabToOklch } from './oklch';
import { rgbToOklab } from './oklab';
import type { OKLab } from './oklab';

export type Temperature = "warm" | "neutral" | "cool";

export function getTemperature(lab: OKLab): Temperature {
  const lch = oklabToOklch(lab);
  if (lch.C < 0.05) return "neutral";
  const h = lch.h;
  if (h >= 20 && h <= 110) return "warm";
  if (h > 110 && h <= 170) return "neutral";
  if (h > 170 && h <= 340) return "cool";
  return "neutral";
}

export function applyTemperatureMap(imageData: ImageData, intensity: number): ImageData {
  const { data, width, height } = imageData;
  const out = new ImageData(width, height);
  const outData = out.data;

  for (let i = 0; i < data.length; i += 4) {
    const r = data[i], g = data[i + 1], b = data[i + 2], a = data[i + 3];
    const lab = rgbToOklab(r, g, b);
    const lch = oklabToOklch(lab);
    const temp = getTemperature(lab);

    let tr = r, tg = g, tb = b;
    const tintStrength = Math.min(1, lch.C * intensity * 2);
    if (temp === "warm") {
      tr = Math.min(255, r + 40 * tintStrength);
      tg = Math.min(255, g + 10 * tintStrength);
      tb = Math.max(0, b - 30 * tintStrength);
    } else if (temp === "cool") {
      tr = Math.max(0, r - 30 * tintStrength);
      tg = Math.min(255, g + 10 * tintStrength);
      tb = Math.min(255, b + 40 * tintStrength);
    }
    outData[i] = tr; outData[i + 1] = tg; outData[i + 2] = tb; outData[i + 3] = a;
  }
  return out;
}
