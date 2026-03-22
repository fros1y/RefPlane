import { describe, expect, it } from 'vitest';
import fc from 'fast-check';
import { oklabToRgb, rgbToOklab } from '../../src/color/oklab';
import { oklabToOklch, oklchToOklab } from '../../src/color/oklch';

const CHANNEL_TOLERANCE = 1;
const LAB_TOLERANCE = 1e-10;

const edgeBiasedChannel = fc.oneof(
  fc.constantFrom(0, 1, 2, 253, 254, 255),
  fc.integer({ min: 0, max: 255 }),
);

describe('oklab round-trip conversions', () => {
  it('preserves sRGB channels within tolerance for rgb -> oklab -> rgb', () => {
    fc.assert(
      fc.property(edgeBiasedChannel, edgeBiasedChannel, edgeBiasedChannel, (r, g, b) => {
        const lab = rgbToOklab(r, g, b);
        const [roundTrippedR, roundTrippedG, roundTrippedB] = oklabToRgb(lab.L, lab.a, lab.b);

        expect(Math.abs(roundTrippedR - r)).toBeLessThanOrEqual(CHANNEL_TOLERANCE);
        expect(Math.abs(roundTrippedG - g)).toBeLessThanOrEqual(CHANNEL_TOLERANCE);
        expect(Math.abs(roundTrippedB - b)).toBeLessThanOrEqual(CHANNEL_TOLERANCE);
      }),
      { numRuns: 2000 },
    );
  });

  it('preserves lab components for oklab -> oklch -> oklab', () => {
    fc.assert(
      fc.property(
        fc.float({ min: 0, max: 1, noNaN: true }),
        fc.float({ min: -0.5, max: 0.5, noNaN: true }),
        fc.float({ min: -0.5, max: 0.5, noNaN: true }),
        (L, a, b) => {
          const lch = oklabToOklch({ L, a, b });
          const roundTrippedLab = oklchToOklab(lch);

          expect(Math.abs(roundTrippedLab.L - L)).toBeLessThanOrEqual(LAB_TOLERANCE);
          expect(Math.abs(roundTrippedLab.a - a)).toBeLessThanOrEqual(LAB_TOLERANCE);
          expect(Math.abs(roundTrippedLab.b - b)).toBeLessThanOrEqual(LAB_TOLERANCE);
        },
      ),
      { numRuns: 2000 },
    );
  });
});