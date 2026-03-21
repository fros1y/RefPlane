import { toGrayscale } from './grayscale';
import { applyQuantization } from './quantize';
import { cleanupRegions } from './regions';
import type { ValueConfig } from '../types';

export function processValueStudy(imageData: ImageData, config: ValueConfig): ImageData {
  const { thresholds, minRegionSize } = config;
  let result = toGrayscale(imageData);
  result = applyQuantization(result, thresholds);
  result = cleanupRegions(result, minRegionSize);
  return result;
}
