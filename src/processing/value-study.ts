import { toGrayscale } from './grayscale';
import { bilateralFilter, strengthToParams } from './bilateral';
import { applyQuantization } from './quantize';
import { cleanupRegions } from './regions';
import type { ValueConfig } from '../types';

export function processValueStudy(imageData: ImageData, config: ValueConfig): ImageData {
  const { strength, thresholds, minRegionSize } = config;
  let result = toGrayscale(imageData);
  const { sigmaS, sigmaR } = strengthToParams(strength);
  result = bilateralFilter(result, sigmaS, sigmaR);
  result = applyQuantization(result, thresholds);
  result = cleanupRegions(result, minRegionSize);
  return result;
}
