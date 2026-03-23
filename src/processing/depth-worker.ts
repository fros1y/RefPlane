/// <reference lib="webworker" />

import { pipeline, RawImage, env } from '@huggingface/transformers';

env.allowLocalModels = false;

type DepthPipeline = Awaited<ReturnType<typeof pipeline<'depth-estimation'>>>;

let pipelineInstance: DepthPipeline | null = null;
let pipelineLoading: Promise<DepthPipeline> | null = null;

function getDepthPipeline(onProgress: (data: DepthWorkerProgress) => void): Promise<DepthPipeline> {
  if (pipelineInstance) return Promise.resolve(pipelineInstance);
  if (pipelineLoading) return pipelineLoading;

  pipelineLoading = pipeline('depth-estimation', 'onnx-community/depth-anything-v2-small', {
    device: 'wasm',
    dtype: 'q8',
    progress_callback: (event: any) => {
      if (event.status === 'progress' && typeof event.progress === 'number') {
        onProgress({ kind: 'progress', stage: 'Downloading depth model', percent: Math.round(event.progress) });
      }
    },
  }).then((p) => {
    pipelineInstance = p;
    pipelineLoading = null;
    return p;
  });

  return pipelineLoading;
}

export interface DepthWorkerRequest {
  kind: 'estimate';
  requestId: number;
  imageData: ImageData;
}

export interface DepthWorkerProgress {
  kind: 'progress';
  stage: string;
  percent: number;
}

export interface DepthWorkerResult {
  kind: 'result';
  requestId: number;
  depthData: Float32Array;
  depthWidth: number;
  depthHeight: number;
  imageWidth: number;
  imageHeight: number;
}

export interface DepthWorkerError {
  kind: 'error';
  requestId: number;
  error: string;
}

export type DepthWorkerOutbound = DepthWorkerProgress | DepthWorkerResult | DepthWorkerError;

self.onmessage = async (e: MessageEvent<DepthWorkerRequest>) => {
  const { requestId, imageData } = e.data;

  try {
    const estimator = await getDepthPipeline((progress) => {
      self.postMessage(progress);
    });

    self.postMessage({ kind: 'progress', stage: 'Estimating depth', percent: 0 } satisfies DepthWorkerProgress);

    const rawImage = new RawImage(imageData.data, imageData.width, imageData.height, 4);
    const rawOutput = await estimator(rawImage);
    const output = Array.isArray(rawOutput) ? rawOutput[0] : rawOutput;

    const depthTensor = output.predicted_depth;
    const depthData = depthTensor.data as Float32Array;
    const [depthHeight, depthWidth] = depthTensor.dims as [number, number];

    const result: DepthWorkerResult = {
      kind: 'result',
      requestId,
      depthData,
      depthWidth,
      depthHeight,
      imageWidth: imageData.width,
      imageHeight: imageData.height,
    };

    self.postMessage(result, [depthData.buffer]);
  } catch (err) {
    const errorMsg: DepthWorkerError = {
      kind: 'error',
      requestId,
      error: err instanceof Error ? err.message : String(err),
    };
    self.postMessage(errorMsg);
  }
};

export {};
