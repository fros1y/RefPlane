/// <reference lib="webworker" />

import { superResolutionFilter } from './simplify/super-resolution';

export interface SrWorkerRequest {
  kind: 'sr';
  requestId: number;
  imageData: ImageData;
  scale: number;
  sharpenAmount: number;
}

export interface SrWorkerProgress {
  kind: 'progress';
  requestId: number;
  stage: string;
  percent: number;
}

export interface SrWorkerResult {
  kind: 'result';
  requestId: number;
  imageData: ImageData;
}

export interface SrWorkerError {
  kind: 'error';
  requestId: number;
  error: string;
}

export type SrWorkerOutbound = SrWorkerProgress | SrWorkerResult | SrWorkerError;

// Serialise progress updates at most once every 80 ms to avoid flooding
// the main thread with messages.
function makeThrottledProgress(requestId: number, minIntervalMs = 80) {
  let lastSent = 0;
  let pending: { stage: string; percent: number } | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;

  const send = (stage: string, percent: number) => {
    const msg: SrWorkerProgress = { kind: 'progress', requestId, stage, percent };
    self.postMessage(msg);
    lastSent = performance.now();
    pending = null;
    timer = null;
  };

  return (percent: number) => {
    const stage = 'Super-Res';
    const now = performance.now();
    if (now - lastSent >= minIntervalMs) {
      if (timer !== null) clearTimeout(timer);
      send(stage, percent);
    } else {
      pending = { stage, percent };
      if (timer === null) {
        timer = setTimeout(() => {
          if (pending) send(pending.stage, pending.percent);
        }, minIntervalMs - (now - lastSent));
      }
    }
  };
}

let currentController: AbortController | null = null;

self.onmessage = async (e: MessageEvent<SrWorkerRequest>) => {
  const { requestId, imageData, scale, sharpenAmount } = e.data;

  // Cancel any in-flight request
  if (currentController) {
    currentController.abort();
  }
  const controller = new AbortController();
  currentController = controller;

  const onProgress = makeThrottledProgress(requestId);

  try {
    const result = await superResolutionFilter(
      imageData,
      scale,
      sharpenAmount,
      onProgress,
      controller.signal,
    );

    if (controller.signal.aborted) return;

    const msg: SrWorkerResult = { kind: 'result', requestId, imageData: result };
    self.postMessage(msg, [result.data.buffer]);
  } catch (err) {
    if (controller.signal.aborted) return;
    const errorMsg: SrWorkerError = {
      kind: 'error',
      requestId,
      error: err instanceof Error ? err.message : String(err),
    };
    self.postMessage(errorMsg);
  } finally {
    if (currentController === controller) {
      currentController = null;
    }
  }
};

export {};
