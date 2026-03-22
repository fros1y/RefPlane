/// <reference lib="webworker" />

import { processValueStudy } from './value-study';
import { processColorRegions } from './color-regions';
import { cannyEdges, sobelEdges } from './edges';
import { toGrayscale } from './grayscale';
import { runSimplify } from './simplify/index';
import { createProgressReporter } from './progress';
import { getWebGpuProcessor } from './webgpu';
import type { ValueConfig, ColorConfig, EdgeConfig, SimplifyConfig } from '../types';

type WorkerMessage =
  | { type: 'simplify'; imageData: ImageData; config: SimplifyConfig; requestId: number }
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
    if (type === 'simplify') {
      const controller = new AbortController();
      currentSimplifyController = controller;
      const reporter = createProgressReporter(requestId);
      const result = await measureStage(stages, 'simplify', () =>
        runSimplify(data.imageData, data.config, (percent) => reporter('Simplifying', percent), controller.signal, gpu)
      );
      const simplifyBackend: ProcessingMeta['backend'] = gpu && data.config.method !== 'none' ? 'gpu' : 'cpu';
      const meta = finalizeMeta(stages, simplifyBackend, data.imageData, queuedAt, startedAt);
      self.postMessage({ type: 'result', result, requestType: type, requestId, meta }, [result.data.buffer]);
      if (currentSimplifyController === controller) {
        currentSimplifyController = null;
      }
    } else if (type === 'value-study') {
      const result = gpu
        ? await measureStage(stages, 'value-study-gpu', () => gpu.processValueStudy(data.imageData, data.config))
        : await measureStage(stages, 'value-study-cpu', () => processValueStudy(data.imageData, data.config));
      const meta = finalizeMeta(stages, gpu ? 'gpu' : 'cpu', data.imageData, queuedAt, startedAt);
      self.postMessage({ type: 'result', result, requestType: type, requestId, meta }, [result.data.buffer]);
    } else if (type === 'color-regions') {
      const stageLabel = gpu ? 'color-regions-mixed' : 'color-regions-cpu';
      const result = await measureStage(stages, stageLabel, () =>
        processColorRegions(data.imageData, data.config, gpu ? gpu.kMeansAssign.bind(gpu) : undefined));
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
      if (cfg.method === 'canny') {
        edgeData = gpu
          ? await measureStage(stages, 'canny-gpu', () => gpu.cannyEdges(gray, cfg.detail))
          : await measureStage(stages, 'canny', () => cannyEdges(gray, cfg.detail));
      } else {
        edgeData = gpu
          ? await measureStage(stages, 'sobel-gpu', () => gpu.sobelEdges(gray, cfg.sensitivity))
          : await measureStage(stages, 'sobel', () => sobelEdges(gray, cfg.sensitivity));
      }
      const meta = finalizeMeta(stages, gpu ? 'gpu' : 'cpu', data.imageData, queuedAt, startedAt);
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
    const isAbort = err instanceof Error && err.name === 'AbortError';
    self.postMessage({ type: 'error', error: isAbort ? 'AbortError' : String(err), requestType: type, requestId, meta });
  } finally {
    if (type === 'simplify') {
      currentSimplifyController = null;
    }
  }
}

let queue = Promise.resolve();
let currentSimplifyController: AbortController | null = null;

self.onmessage = (e: MessageEvent<WorkerMessage>) => {
  if (e.data.type === 'simplify' && currentSimplifyController) {
    currentSimplifyController.abort();
  }
  const queuedAt = performance.now();
  queue = queue.then(() => handleMessage(e.data, queuedAt)).catch((err) => {
    self.postMessage({ type: 'error', error: String(err) });
  });
};

export {};
