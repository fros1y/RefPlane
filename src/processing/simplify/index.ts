import type { SimplifyConfig } from '../../types';
import { bilateralFilter } from './bilateral';
import { kuwaharaFilter } from './kuwahara';
import { meanShiftFilter } from './mean-shift';
import { anisotropicDiffusion } from './anisotropic';

export function runSimplify(
  imageData: ImageData,
  config: SimplifyConfig,
  onProgress?: (percent: number) => void,
): ImageData {
  switch (config.method) {
    case 'bilateral':
      return bilateralFilter(imageData, config.bilateral.sigmaS, config.bilateral.sigmaR, onProgress);
    case 'kuwahara':
      return kuwaharaFilter(imageData, config.kuwahara.kernelSize, onProgress);
    case 'mean-shift':
      return meanShiftFilter(imageData, config.meanShift.spatialRadius, config.meanShift.colorRadius, onProgress);
    case 'anisotropic':
      return anisotropicDiffusion(imageData, config.anisotropic.iterations, config.anisotropic.kappa, onProgress);
    case 'none':
    default:
      return imageData;
  }
}

export { bilateralFilter } from './bilateral';
export { kuwaharaFilter } from './kuwahara';
export { meanShiftFilter } from './mean-shift';
export { anisotropicDiffusion } from './anisotropic';
export { strengthToMethodParams } from './params';
