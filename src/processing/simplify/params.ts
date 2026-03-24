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
    case 'ultrasharp': {
      // Map strength to downscale factor fed into the 4x UltraSharp model.
      // Low strength = mild 2x downsample before upscaling (subtle simplification);
      // high strength = 8x downsample (strong abstraction).
      const downscale = Math.round(lerp(2, 8, s));
      return { downscale };
    }
    default:
      return {};
  }
}
