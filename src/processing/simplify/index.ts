import type { SimplifyConfig, PlaneGuidance } from '../../types';
import { bilateralFilter } from './bilateral';
import { kuwaharaFilter } from './kuwahara';
import { meanShiftFilter } from './mean-shift';
import { anisotropicDiffusion } from './anisotropic';
import { slicFilter } from './slic';
import { planeFillFilter } from './plane-fill';
import { mergeShadows } from './shadow-merge';

interface SimplifyGpuProcessor {
  bilateralRgb(imageData: ImageData, sigmaS: number, sigmaR: number): Promise<ImageData>;
  kuwahara(imageData: ImageData, kernelSize: number, passes: number, sharpness: number, sectors: number): Promise<ImageData>;
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
  planeGuidance?: PlaneGuidance,
): Promise<ImageData> {
  const finalize = (result: ImageData) => (config.shadowMerge ? mergeShadows(result, config.strength) : result);

  switch (config.method) {
    case 'plane-fill':
      if (!planeGuidance) {
        throw new Error('Plane guidance required for plane-fill simplification method');
      }
      return finalize(planeFillFilter(imageData, planeGuidance, config.planeFill.colorStrategy));
    case 'bilateral':
      if (gpu) {
        try {
          onProgress?.(5);
          const result = await gpu.bilateralRgb(imageData, config.bilateral.sigmaS, config.bilateral.sigmaR);
          onProgress?.(100);
          return finalize(result);
        } catch (error) {
          void error;
        }
      }
      return finalize(await bilateralFilter(imageData, config.bilateral.sigmaS, config.bilateral.sigmaR, onProgress, abortSignal));
    case 'kuwahara': {
      const usePlaneLabels = config.planeGuidance.preserveBoundaries && planeGuidance?.labels;
      if (gpu && !usePlaneLabels) {
        try {
          onProgress?.(5);
          const result = await gpu.kuwahara(
            imageData,
            config.kuwahara.kernelSize,
            config.kuwahara.passes,
            config.kuwahara.sharpness,
            config.kuwahara.sectors,
          );
          onProgress?.(100);
          return finalize(result);
        } catch (error) {
          void error;
        }
      }
      return finalize(await kuwaharaFilter(imageData, config.kuwahara.kernelSize, {
        onProgress,
        abortSignal,
        passes: config.kuwahara.passes,
        sharpness: config.kuwahara.sharpness,
        sectors: config.kuwahara.sectors,
        planeLabels: config.planeGuidance.preserveBoundaries ? planeGuidance?.labels : undefined,
      }));
    }
    case 'mean-shift':
      if (gpu) {
        try {
          onProgress?.(5);
          const result = await gpu.meanShift(imageData, config.meanShift.spatialRadius, config.meanShift.colorRadius);
          onProgress?.(100);
          return finalize(result);
        } catch (error) {
          void error;
        }
      }
      return finalize(await meanShiftFilter(
        imageData,
        config.meanShift.spatialRadius,
        config.meanShift.colorRadius,
        onProgress,
        abortSignal,
      ));
    case 'anisotropic':
      if (gpu) {
        try {
          onProgress?.(5);
          const result = await gpu.anisotropic(imageData, config.anisotropic.iterations, config.anisotropic.kappa);
          onProgress?.(100);
          return finalize(result);
        } catch (error) {
          void error;
        }
      }
      return finalize(await anisotropicDiffusion(
        imageData,
        config.anisotropic.iterations,
        config.anisotropic.kappa,
        onProgress,
        abortSignal,
      ));
    case 'painterly':
      if (gpu) {
        try {
          onProgress?.(5);
          const result = await gpu.painterly(imageData, config.painterly);
          onProgress?.(100);
          return finalize(result);
        } catch (error) {
          void error;
        }
      }
      return finalize(imageData);
    case 'slic':
      return finalize(await slicFilter(imageData, config.slic.detail, config.slic.compactness, onProgress, abortSignal));
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
