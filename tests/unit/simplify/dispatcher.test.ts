import { describe, expect, it } from 'vitest';
import { runSimplify } from '../../../src/processing/simplify';
import { createImageData } from '../../utils/image';
import type { SimplifyConfig } from '../../../src/types';

function makeConfig(): SimplifyConfig {
  return {
    method: 'ultrasharp',
    ultrasharp: { downscale: 4 },
  };
}

describe('runSimplify', () => {
  it('passes image through unchanged when method is "ultrasharp"', async () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const result = await runSimplify(image, makeConfig());
    expect(result.width).toBe(8);
    expect(result.height).toBe(8);
    expect(result.data).toEqual(image.data);
  });

  it('calls progress callback for ultrasharp method', async () => {
    const image = createImageData(8, 8, [128, 128, 128, 255]);
    const updates: number[] = [];
    await runSimplify(image, makeConfig(), (p) => { updates.push(p); });
    expect(updates.length).toBeGreaterThan(0);
  });
});
