import type { SimplifyConfig } from '../../types';
import { bilateralFilter } from './bilateral';
import { kuwaharaFilter } from './kuwahara';
import { meanShiftFilter } from './mean-shift';
import { anisotropicDiffusion } from './anisotropic';

export async function runSimplify(
  imageData: ImageData,
  config: SimplifyConfig,
  onProgress?: (percent: number) => void,
  abortSignal?: AbortSignal,
): Promise<ImageData> {
  switch (config.method) {
    case 'bilateral':
      return bilateralFilter(imageData, config.bilateral.sigmaS, config.bilateral.sigmaR, onProgress, abortSignal);
    case 'kuwahara':
      return kuwaharaFilter(imageData, config.kuwahara.kernelSize, onProgress, abortSignal);
    case 'mean-shift':
      return meanShiftFilter(
        imageData,
        config.meanShift.spatialRadius,
        config.meanShift.colorRadius,
        onProgress,
        abortSignal,
      );
    case 'anisotropic':
      return anisotropicDiffusion(
        imageData,
        config.anisotropic.iterations,
        config.anisotropic.kappa,
        onProgress,
        abortSignal,
      );
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
