/// <reference lib="webworker" />

import { processValueStudy } from './value-study';
import { processColorRegions } from './color-regions';
import { cannyEdges, sobelEdges } from './edges';
import { toGrayscale } from './grayscale';
import type { ValueConfig, ColorConfig, EdgeConfig } from '../types';

type WorkerMessage =
  | { type: 'value-study'; imageData: ImageData; config: ValueConfig }
  | { type: 'color-regions'; imageData: ImageData; config: ColorConfig }
  | { type: 'edges'; imageData: ImageData; config: EdgeConfig }
  | { type: 'grayscale'; imageData: ImageData };

self.onmessage = (e: MessageEvent<WorkerMessage>) => {
  const { type } = e.data;

  try {
    if (type === 'value-study') {
      const result = processValueStudy(e.data.imageData, e.data.config);
      self.postMessage({ type: 'result', result, requestType: type }, [result.data.buffer]);
    } else if (type === 'color-regions') {
      const result = processColorRegions(e.data.imageData, e.data.config);
      self.postMessage({
        type: 'result',
        result: result.imageData,
        palette: result.palette,
        requestType: type,
      }, [result.imageData.data.buffer]);
    } else if (type === 'edges') {
      const gray = toGrayscale(e.data.imageData);
      const cfg = e.data.config;
      let edgeData: ImageData;
      if (cfg.method === 'canny' || cfg.method === 'simplified') {
        edgeData = cannyEdges(gray, cfg.detail);
      } else {
        edgeData = sobelEdges(gray, cfg.sensitivity);
      }
      self.postMessage({ type: 'result', result: edgeData, requestType: type }, [edgeData.data.buffer]);
    } else if (type === 'grayscale') {
      const result = toGrayscale(e.data.imageData);
      self.postMessage({ type: 'result', result, requestType: type }, [result.data.buffer]);
    }
  } catch (err) {
    self.postMessage({ type: 'error', error: String(err) });
  }
};

export {};
