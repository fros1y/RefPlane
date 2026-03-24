import { describe, expect, it } from 'vitest';
import { strengthToMethodParams } from '../../../src/processing/simplify/params';

describe('strengthToMethodParams', () => {
  it('maps strength 0 to minimum ultrasharp downscale (2)', () => {
    const result = strengthToMethodParams('ultrasharp', 0);
    expect(result.downscale).toBe(2);
  });

  it('maps strength 1 to maximum ultrasharp downscale (8)', () => {
    const result = strengthToMethodParams('ultrasharp', 1);
    expect(result.downscale).toBe(8);
  });

  it('maps strength 0.5 to midpoint ultrasharp downscale (5)', () => {
    const result = strengthToMethodParams('ultrasharp', 0.5);
    expect(result.downscale).toBe(5);
  });
});
