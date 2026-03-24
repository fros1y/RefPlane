/// <reference lib="webworker" />

import { pipeline, AutoModelForDepthEstimation, AutoProcessor, RawImage, env } from '@huggingface/transformers';

env.allowLocalModels = false;

type DepthPipeline = Awaited<ReturnType<typeof pipeline<'depth-estimation'>>>;

interface DepthProModel {
  kind: 'depth-pro';
  model: any;
  processor: any;
}

let pipelineInstance: DepthPipeline | null = null;
let depthProInstance: DepthProModel | null = null;
let pipelineLoading: Promise<DepthPipeline | DepthProModel> | null = null;

async function detectDevice(): Promise<'webgpu' | 'wasm'> {
  try {
    const gpu = (navigator as any).gpu;
    if (gpu) {
      const adapter = await gpu.requestAdapter();
      if (adapter) return 'webgpu';
    }
  } catch { /* fall through */ }
  return 'wasm';
}

let currentModelSize: string | null = null;

function getDepthPipeline(onProgress: (data: DepthWorkerProgress) => void, modelSize: string = 'base'): Promise<DepthPipeline | DepthProModel> {
  if (currentModelSize === modelSize) {
    if (modelSize === 'depth-pro' && depthProInstance) return Promise.resolve(depthProInstance);
    if (modelSize !== 'depth-pro' && pipelineInstance) return Promise.resolve(pipelineInstance);
    if (pipelineLoading) return pipelineLoading;
  }

  // Model changed — dispose old instance
  if (pipelineInstance) {
    pipelineInstance.dispose?.();
    pipelineInstance = null;
  }
  if (depthProInstance) {
    depthProInstance.model.dispose?.();
    depthProInstance = null;
  }
  pipelineLoading = null;
  currentModelSize = modelSize;

  if (modelSize === 'depth-pro') {
    pipelineLoading = detectDevice().then(async (device) => {
      const modelId = 'onnx-community/DepthPro-ONNX';
      console.log(`[depth-worker] Using device: ${device}, model: ${modelId}`);
      const model = await AutoModelForDepthEstimation.from_pretrained(modelId, {
        device,
        dtype: 'q4',
        progress_callback: (event: any) => {
          if (event.status === 'progress' && typeof event.progress === 'number') {
            onProgress({ kind: 'progress', stage: 'Downloading depth model', percent: Math.round(event.progress) });
          }
        },
      });
      const processor = await AutoProcessor.from_pretrained(modelId);
      const instance: DepthProModel = { kind: 'depth-pro', model, processor };
      depthProInstance = instance;
      pipelineLoading = null;
      return instance;
    });
    return pipelineLoading;
  }

  const modelId = `onnx-community/depth-anything-v2-${modelSize}`;
  pipelineLoading = detectDevice().then((device) => {
    console.log(`[depth-worker] Using device: ${device}, model: ${modelId}`);
    return pipeline('depth-estimation', modelId, {
      device,
      dtype: 'q8',
      progress_callback: (event: any) => {
        if (event.status === 'progress' && typeof event.progress === 'number') {
          onProgress({ kind: 'progress', stage: 'Downloading depth model', percent: Math.round(event.progress) });
        }
      },
    });
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
  modelSize?: 'small' | 'base' | 'large' | 'depth-pro';
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
  const { requestId, imageData, modelSize } = e.data;

  try {
    const estimatorOrModel = await getDepthPipeline((progress) => {
      self.postMessage(progress);
    }, modelSize);

    self.postMessage({ kind: 'progress', stage: 'Estimating depth', percent: 0 } satisfies DepthWorkerProgress);

    const rawImage = new RawImage(imageData.data, imageData.width, imageData.height, 4);

    let depthData: Float32Array;
    let depthWidth: number;
    let depthHeight: number;

    if (modelSize === 'depth-pro') {
      // DepthPro path — manual model + processor
      const { model, processor } = estimatorOrModel as DepthProModel;
      const inputs = await processor(rawImage);
      const output = await model(inputs);
      const depthTensor = output.predicted_depth;
      depthData = depthTensor.data as Float32Array;
      [depthHeight, depthWidth] = depthTensor.dims as [number, number];
    } else {
      // Depth Anything pipeline path
      const estimator = estimatorOrModel as DepthPipeline;
      const rawOutput = await estimator(rawImage);
      const output = Array.isArray(rawOutput) ? rawOutput[0] : rawOutput;
      const depthTensor = output.predicted_depth;
      depthData = depthTensor.data as Float32Array;
      [depthHeight, depthWidth] = depthTensor.dims as [number, number];
    }

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
