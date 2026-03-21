/// <reference lib="webworker" />

import { processValueStudy } from './value-study';
import { processColorRegions } from './color-regions';
import { cannyEdges, sobelEdges } from './edges';
import { toGrayscale } from './grayscale';
import { bilateralFilter, strengthToParams } from './bilateral';
import { getWebGpuProcessor } from './webgpu';
import type { ValueConfig, ColorConfig, EdgeConfig } from '../types';

type WorkerMessage =
  | { type: 'value-study'; imageData: ImageData; config: ValueConfig; requestId: number }
  | { type: 'color-regions'; imageData: ImageData; config: ColorConfig; requestId: number }
  | { type: 'edges'; imageData: ImageData; config: EdgeConfig; requestId: number }
  | { type: 'grayscale'; imageData: ImageData; requestId: number };

interface TimingStage {
  label: string;
  ms: number;
}

interface ProcessingMeta {
  backend: 'cpu' | 'gpu' | 'mixed';
  queueWaitMs: number;
  totalMs: number;
  width: number;
  height: number;
  stages: TimingStage[];
}

async function measureStage<T>(stages: TimingStage[], label: string, fn: () => Promise<T> | T): Promise<T> {
  const startedAt = performance.now();
  const result = await fn();
  stages.push({ label, ms: performance.now() - startedAt });
  return result;
}

function finalizeMeta(
  stages: TimingStage[],
  backend: ProcessingMeta['backend'],
  imageData: ImageData,
  queuedAt: number,
  startedAt: number,
): ProcessingMeta {
  return {
    backend,
    queueWaitMs: startedAt - queuedAt,
    totalMs: performance.now() - startedAt,
    width: imageData.width,
    height: imageData.height,
    stages,
  };
}

async function handleMessage(data: WorkerMessage, queuedAt: number) {
  const { type, requestId } = data;
  const startedAt = performance.now();
  const stages: TimingStage[] = [];
  const gpu = await getWebGpuProcessor();

  try {
    if (type === 'value-study') {
      const result = gpu
        ? await measureStage(stages, 'value-study-gpu', () => gpu.processValueStudy(data.imageData, data.config))
        : await measureStage(stages, 'value-study-cpu', () => processValueStudy(data.imageData, data.config));
      const meta = finalizeMeta(stages, gpu ? 'gpu' : 'cpu', data.imageData, queuedAt, startedAt);
      self.postMessage({ type: 'result', result, requestType: type, requestId, meta }, [result.data.buffer]);
    } else if (type === 'color-regions') {
      const result = await measureStage(stages, gpu ? 'color-regions-mixed' : 'color-regions-cpu', () =>
        processColorRegions(data.imageData, data.config, gpu ?? undefined));
      const meta = finalizeMeta(stages, gpu ? 'mixed' : 'cpu', data.imageData, queuedAt, startedAt);
      self.postMessage({
        type: 'result',
        result: result.imageData,
        palette: result.palette,
        paletteBands: result.paletteBands,
        requestType: type,
        requestId,
        meta,
      }, [result.imageData.data.buffer]);
    } else if (type === 'edges') {
      const gray = await measureStage(stages, 'grayscale', () => toGrayscale(data.imageData));
      const cfg = data.config;
      let edgeData: ImageData;
      let backend: ProcessingMeta['backend'] = 'cpu';
      if (cfg.method === 'simplified') {
        // Simplified: bilateral-smooth the grayscale image first to reduce noise,
        // then run Canny — produces cleaner, more structured contours.
        const { sigmaS, sigmaR } = strengthToParams(0.5);
        const smoothed = gpu
          ? await measureStage(stages, 'simplified-bilateral-gpu', () => gpu.bilateralGrayscale(data.imageData, sigmaS, sigmaR))
          : await measureStage(stages, 'simplified-bilateral-cpu', () => bilateralFilter(gray, sigmaS, sigmaR));
        edgeData = await measureStage(stages, 'canny', () => cannyEdges(smoothed, cfg.detail));
        backend = gpu ? 'mixed' : 'cpu';
      } else if (cfg.method === 'canny') {
        edgeData = await measureStage(stages, 'canny', () => cannyEdges(gray, cfg.detail));
      } else {
        edgeData = await measureStage(stages, 'sobel', () => sobelEdges(gray, cfg.sensitivity));
      }
      const meta = finalizeMeta(stages, backend, data.imageData, queuedAt, startedAt);
      self.postMessage({ type: 'result', result: edgeData, requestType: type, requestId, meta }, [edgeData.data.buffer]);
    } else if (type === 'grayscale') {
      const result = gpu
        ? await measureStage(stages, 'grayscale-gpu', () => gpu.toGrayscale(data.imageData))
        : await measureStage(stages, 'grayscale-cpu', () => toGrayscale(data.imageData));
      const meta = finalizeMeta(stages, gpu ? 'gpu' : 'cpu', data.imageData, queuedAt, startedAt);
      self.postMessage({ type: 'result', result, requestType: type, requestId, meta }, [result.data.buffer]);
    }
  } catch (err) {
    const meta = finalizeMeta(stages, gpu ? 'gpu' : 'cpu', data.imageData, queuedAt, startedAt);
    self.postMessage({ type: 'error', error: String(err), requestType: type, requestId, meta });
  }
}

let queue = Promise.resolve();

self.onmessage = (e: MessageEvent<WorkerMessage>) => {
  const queuedAt = performance.now();
  queue = queue.then(() => handleMessage(e.data, queuedAt)).catch((err) => {
    self.postMessage({ type: 'error', error: String(err) });
  });
};

export {};
