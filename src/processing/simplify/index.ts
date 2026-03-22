import type { SimplifyConfig } from '../../types';
import { bilateralFilter } from './bilateral';
import { kuwaharaFilter } from './kuwahara';
import { meanShiftFilter } from './mean-shift';
import { anisotropicDiffusion } from './anisotropic';
import { slicFilter } from './slic';

interface SimplifyGpuProcessor {
  bilateralRgb(imageData: ImageData, sigmaS: number, sigmaR: number): Promise<ImageData>;
  kuwahara(imageData: ImageData, kernelSize: number): Promise<ImageData>;
  meanShift(imageData: ImageData, spatialRadius: number, colorRadius: number): Promise<ImageData>;
  anisotropic(imageData: ImageData, iterations: number, kappa: number): Promise<ImageData>;
  painterly(imageData: ImageData, params: SimplifyConfig['painterly']): Promise<ImageData>;
}

export async function runSimplify(
  imageData: ImageData,
  config: SimplifyConfig,
  onProgress?: (percent: number) => void,
  abortSignal?: AbortSignal,
  gpu?: SimplifyGpuProcessor | null,
): Promise<ImageData> {
  switch (config.method) {
    case 'bilateral':
      if (gpu) {
        try {
          onProgress?.(5);
          const result = await gpu.bilateralRgb(imageData, config.bilateral.sigmaS, config.bilateral.sigmaR);
          onProgress?.(100);
          return result;
        } catch (error) {
          void error;
        }
      }
      return bilateralFilter(imageData, config.bilateral.sigmaS, config.bilateral.sigmaR, onProgress, abortSignal);
    case 'kuwahara':
      if (gpu) {
        try {
          onProgress?.(5);
          const result = await gpu.kuwahara(imageData, config.kuwahara.kernelSize);
          onProgress?.(100);
          return result;
        } catch (error) {
          void error;
        }
      }
      return kuwaharaFilter(imageData, config.kuwahara.kernelSize, onProgress, abortSignal);
    case 'mean-shift':
      if (gpu) {
        try {
          onProgress?.(5);
          const result = await gpu.meanShift(imageData, config.meanShift.spatialRadius, config.meanShift.colorRadius);
          onProgress?.(100);
          return result;
        } catch (error) {
          void error;
        }
      }
      return meanShiftFilter(
        imageData,
        config.meanShift.spatialRadius,
        config.meanShift.colorRadius,
        onProgress,
        abortSignal,
      );
    case 'anisotropic':
      if (gpu) {
        try {
          onProgress?.(5);
          const result = await gpu.anisotropic(imageData, config.anisotropic.iterations, config.anisotropic.kappa);
          onProgress?.(100);
          return result;
        } catch (error) {
          void error;
        }
      }
      return anisotropicDiffusion(
        imageData,
        config.anisotropic.iterations,
        config.anisotropic.kappa,
        onProgress,
        abortSignal,
      );
    case 'painterly':
      if (gpu) {
        try {
          onProgress?.(5);
          const result = await gpu.painterly(imageData, config.painterly);
          onProgress?.(100);
          return result;
        } catch (error) {
          void error;
        }
      }
      return imageData;
    case 'slic':
      return slicFilter(imageData, config.slic.detail, config.slic.compactness, onProgress, abortSignal);
    case 'none':
    default:
      return imageData;
  }
}

export { bilateralFilter } from './bilateral';
export { kuwaharaFilter } from './kuwahara';
export { meanShiftFilter } from './mean-shift';
export { anisotropicDiffusion } from './anisotropic';
export { slicFilter } from './slic';
export { strengthToMethodParams } from './params';
