import type { SimplifyMethod } from '../../types';

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function strengthToMethodParams(
  method: SimplifyMethod,
  strength: number,
): Record<string, number> {
  const s = Math.max(0, Math.min(1, strength));
  switch (method) {
    case 'bilateral': {
      let sigmaS: number, sigmaR: number;
      if (s <= 0.5) {
        const t = s / 0.5;
        sigmaS = lerp(2, 10, t);
        sigmaR = lerp(0.05, 0.15, t);
      } else {
        const t = (s - 0.5) / 0.5;
        sigmaS = lerp(10, 25, t);
        sigmaR = lerp(0.15, 0.35, t);
      }
      return { sigmaS, sigmaR };
    }
    case 'kuwahara':
      return { kernelSize: Math.round(lerp(3, 15, s)) };
    case 'mean-shift':
      return { spatialRadius: lerp(5, 30, s), colorRadius: lerp(10, 50, s) };
    case 'anisotropic':
      return { iterations: Math.round(lerp(1, 30, s)), kappa: lerp(30, 10, s) };
    case 'none':
    default:
      return {};
  }
}
