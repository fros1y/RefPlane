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

export function applyTemperatureMap(imageData: ImageData, intensity: number, classificationSource?: ImageData): ImageData {
  const { data, width, height } = imageData;
  const classData = classificationSource?.data ?? data;
  const out = new ImageData(width, height);
  const outData = out.data;
  const warmColor = [244, 146, 84];
  const coolColor = [92, 156, 255];
  const neutralColor = [196, 196, 196];

  for (let i = 0; i < data.length; i += 4) {
    const r = data[i], g = data[i + 1], b = data[i + 2], a = data[i + 3];
    const lab = rgbToOklab(classData[i], classData[i + 1], classData[i + 2]);
    const lch = oklabToOklch(lab);
    const temp = getTemperature(lab);
    const luma = Math.max(0, Math.min(1, lab.L));

    let target = neutralColor;
    let blend = 0.18 + intensity * 0.16;

    if (temp === "warm") {
      target = warmColor;
      blend = 0.34 + Math.min(0.56, lch.C * (0.9 + intensity));
    } else if (temp === "cool") {
      target = coolColor;
      blend = 0.34 + Math.min(0.56, lch.C * (0.9 + intensity));
    } else {
      blend = 0.12 + Math.min(0.18, lch.C * 0.6);
    }

    const mappedR = target[0] * (0.28 + luma * 0.72);
    const mappedG = target[1] * (0.28 + luma * 0.72);
    const mappedB = target[2] * (0.28 + luma * 0.72);
    const mix = Math.max(0, Math.min(0.9, blend));

    outData[i] = Math.round(r * (1 - mix) + mappedR * mix);
    outData[i + 1] = Math.round(g * (1 - mix) + mappedG * mix);
    outData[i + 2] = Math.round(b * (1 - mix) + mappedB * mix);
    outData[i + 3] = a;
  }
  return out;
}
