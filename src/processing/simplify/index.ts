import type { SimplifyConfig } from '../../types';

interface SimplifyGpuProcessor {
  // placeholder interface kept for gpu parameter compatibility
}

export async function runSimplify(
  imageData: ImageData,
  config: SimplifyConfig,
  onProgress?: (percent: number) => void,
  _abortSignal?: AbortSignal,
  _gpu?: SimplifyGpuProcessor | null,
): Promise<ImageData> {

  switch (config.method) {
    case 'ultrasharp':
      // UltraSharp is handled by UltrasharpClient / ultrasharp-worker before
      // reaching this function; return input unchanged as a clean no-op.
      onProgress?.(100);
      return imageData;
    default:
      return imageData;
  }
}
