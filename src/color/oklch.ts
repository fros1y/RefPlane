import type { OKLab } from './oklab';

export interface OKLCH { L: number; C: number; h: number; }

export function oklabToOklch(lab: OKLab): OKLCH {
  const C = Math.sqrt(lab.a * lab.a + lab.b * lab.b);
  let h = Math.atan2(lab.b, lab.a) * (180 / Math.PI);
  if (h < 0) h += 360;
  return { L: lab.L, C, h };
}

export function oklchToOklab(lch: OKLCH): OKLab {
  const hRad = lch.h * (Math.PI / 180);
  return { L: lch.L, a: lch.C * Math.cos(hRad), b: lch.C * Math.sin(hRad) };
}
