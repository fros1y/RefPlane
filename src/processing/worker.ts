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

async function handleMessage(data: WorkerMessage) {
  const { type, requestId } = data;
  const gpu = await getWebGpuProcessor();

  try {
    if (type === 'value-study') {
      const result = gpu
        ? await gpu.processValueStudy(data.imageData, data.config)
        : processValueStudy(data.imageData, data.config);
      self.postMessage({ type: 'result', result, requestType: type, requestId }, [result.data.buffer]);
    } else if (type === 'color-regions') {
      const result = await processColorRegions(data.imageData, data.config, gpu ?? undefined);
      self.postMessage({
        type: 'result',
        result: result.imageData,
        palette: result.palette,
        paletteBands: result.paletteBands,
        requestType: type,
        requestId,
      }, [result.imageData.data.buffer]);
    } else if (type === 'edges') {
      const gray = toGrayscale(data.imageData);
      const cfg = data.config;
      let edgeData: ImageData;
      if (cfg.method === 'simplified') {
        // Simplified: bilateral-smooth the grayscale image first to reduce noise,
        // then run Canny — produces cleaner, more structured contours.
        const { sigmaS, sigmaR } = strengthToParams(0.5);
        const smoothed = gpu
          ? await gpu.bilateralGrayscale(data.imageData, sigmaS, sigmaR)
          : bilateralFilter(gray, sigmaS, sigmaR);
        edgeData = cannyEdges(smoothed, cfg.detail);
      } else if (cfg.method === 'canny') {
        edgeData = cannyEdges(gray, cfg.detail);
      } else {
        edgeData = sobelEdges(gray, cfg.sensitivity);
      }
      self.postMessage({ type: 'result', result: edgeData, requestType: type, requestId }, [edgeData.data.buffer]);
    } else if (type === 'grayscale') {
      const result = gpu ? await gpu.toGrayscale(data.imageData) : toGrayscale(data.imageData);
      self.postMessage({ type: 'result', result, requestType: type, requestId }, [result.data.buffer]);
    }
  } catch (err) {
    self.postMessage({ type: 'error', error: String(err), requestType: type, requestId });
  }
}

let queue = Promise.resolve();

self.onmessage = (e: MessageEvent<WorkerMessage>) => {
  queue = queue.then(() => handleMessage(e.data)).catch((err) => {
    self.postMessage({ type: 'error', error: String(err) });
  });
};

export {};
