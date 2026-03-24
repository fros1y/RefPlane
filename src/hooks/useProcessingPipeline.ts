import { signal, computed, type Signal, type ReadonlySignal } from '@preact/signals';
import { useEffect, useRef, useCallback, useMemo } from 'preact/hooks';
import type { Mode, ValueConfig, ColorConfig, SimplifyConfig } from '../types';
import { WorkerClient, WorkerRequestError } from '../processing/worker-client';
import { UltrasharpClient } from '../processing/ultrasharp-client';
import type { WorkerRequest, WorkerRequestType } from '../processing/worker-protocol';

export interface ProcessingPipelineInputs {
  sourceImageData: Signal<ImageData | null>;
  activeMode: Signal<Mode>;
  simplifyConfig: Signal<SimplifyConfig>;
  valueConfig: Signal<ValueConfig>;
  colorConfig: Signal<ColorConfig>;
  onError?: (message: string) => void;
}

export interface ProcessingPipelineOutputs {
  simplifiedImageData: Signal<ImageData | null>;
  processedImage: Signal<ImageData | null>;
  isProcessing: ReadonlySignal<boolean>;
  processingProgress: Signal<{ stage: string; percent: number } | null>;
  paletteColors: Signal<string[]>;
  swatchBands: Signal<number[]>;
  /** Clear all derived processing state (call when loading a new image or cropping). */
  resetProcessingState: () => void;
}

export function useProcessingPipeline(inputs: ProcessingPipelineInputs): ProcessingPipelineOutputs {
  const {
    sourceImageData,
    activeMode,
    simplifyConfig,
    valueConfig,
    colorConfig,
    onError,
  } = inputs;

  // ── Output signals (created once, stable across renders) ──────────────
  const simplifiedImageData = useMemo(() => signal<ImageData | null>(null), []);
  const processedImage = useMemo(() => signal<ImageData | null>(null), []);
  const processingProgress = useMemo(() => signal<{ stage: string; percent: number } | null>(null), []);
  const processingCount = useMemo(() => signal(0), []);
  const isProcessing = useMemo(() => computed(() => processingCount.value > 0), [processingCount]);
  const paletteColors = useMemo(() => signal<string[]>([]), []);
  const swatchBands = useMemo(() => signal<number[]>([]), []);

  const ultrasharpClientRef = useRef<UltrasharpClient | null>(null);
  const latestUltrasharpRequestIdRef = useRef(0);

  // ── Internal refs ─────────────────────────────────────────────────────
  const workerClientRef = useRef<WorkerClient | null>(null);
  const processingTimerRef = useRef<number | null>(null);
  const simplifyTimerRef = useRef<number | null>(null);
  const requestSeqRef = useRef(0);
  const latestMainRequestIdRef = useRef(0);
  const latestSimplifyRequestIdRef = useRef(0);
  const requestTimingsRef = useRef(new Map<number, { sentAt: number; requestType: string }>());

  // ── Helpers ───────────────────────────────────────────────────────────
  const nextRequestId = useCallback(() => {
    requestSeqRef.current += 1;
    return requestSeqRef.current;
  }, []);

  const dispatchWorkerRequest = useCallback(<T extends WorkerRequest,>(
    request: T,
    channel: 'main' | 'simplify',
    logLabel: string,
    onSuccess: (result: { requestType: T['type']; payload: T['type'] extends 'color-regions' ? { result: ImageData; palette: string[]; paletteBands: number[] } : { result: ImageData } }) => void,
    onProgress?: (stage: string, percent: number, requestId: number) => void,
  ) => {
    const workerClient = workerClientRef.current;
    if (!workerClient) return;

    const requestId = nextRequestId();
    if (channel === 'main') {
      latestMainRequestIdRef.current = requestId;
    } else {
      latestSimplifyRequestIdRef.current = requestId;
    }

    processingCount.value++;
    requestTimingsRef.current.set(requestId, { sentAt: performance.now(), requestType: request.type });
    console.log(`[Perf] dispatch ${logLabel}#${requestId} | size=${request.imageData.width}x${request.imageData.height}`);

    const imgBuffer = request.imageData.data.buffer as Transferable;
    const { promise } = workerClient.request(request, {
      requestId,
      transfer: [imgBuffer],
      onProgress: onProgress
        ? (event) => {
            onProgress(event.stage, event.percent, event.requestId);
          }
        : undefined,
    });

    promise
      .then((response) => {
        const latestRequestId = response.requestType === 'simplify'
          ? latestSimplifyRequestIdRef.current
          : latestMainRequestIdRef.current;
        const requestTiming = requestTimingsRef.current.get(response.requestId);
        const roundTripMs = requestTiming ? performance.now() - requestTiming.sentAt : undefined;
        requestTimingsRef.current.delete(response.requestId);
        const isStale = response.requestId !== latestRequestId;
        logProcessingTiming(response.requestType, response.requestId, response.meta, roundTripMs, isStale);
        if (isStale) {
          return;
        }
        onSuccess({
          requestType: response.requestType as T['type'],
          payload: response.payload as T['type'] extends 'color-regions' ? { result: ImageData; palette: string[]; paletteBands: number[] } : { result: ImageData },
        });
      })
      .catch((err: unknown) => {
        const requestError = err instanceof WorkerRequestError ? err : null;
        const failedRequestId = requestError?.requestId ?? requestId;
        const failedRequestType = (requestError?.requestType ?? request.type) as WorkerRequestType;
        const requestTiming = requestTimingsRef.current.get(failedRequestId);
        const roundTripMs = requestTiming ? performance.now() - requestTiming.sentAt : undefined;
        requestTimingsRef.current.delete(failedRequestId);
        const errorMessage = requestError?.message ?? String(err);
        logProcessingTiming(failedRequestType, failedRequestId, requestError?.workerMeta, roundTripMs, true, errorMessage);

        const isAbort = errorMessage === 'AbortError';
        if (!isAbort) {
          console.error('Worker error:', errorMessage);
          onError?.(typeof errorMessage === 'string' ? errorMessage : 'Processing failed');
        }
      })
      .finally(() => {
        processingCount.value = Math.max(0, processingCount.value - 1);
      });
  }, [nextRequestId, processingCount, onError]);

  const postMainRequest = useCallback(() => {
    const worker = workerClientRef.current;
    const src = simplifiedImageData.value;
    if (!worker || !src) return;
    const mode = activeMode.value;
    if (mode === 'grayscale') {
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      dispatchWorkerRequest(
        { type: 'grayscale', imageData: imgCopy },
        'main',
        'grayscale',
        ({ payload }) => {
          processingProgress.value = null;
          processedImage.value = payload.result;
        },
      );
    } else if (mode === 'value') {
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      dispatchWorkerRequest(
        { type: 'value-study', imageData: imgCopy, config: valueConfig.value },
        'main',
        'value-study',
        ({ payload }) => {
          processingProgress.value = null;
          processedImage.value = payload.result;
        },
      );
    } else if (mode === 'color') {
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      dispatchWorkerRequest(
        { type: 'color-regions', imageData: imgCopy, config: colorConfig.value },
        'main',
        'color-regions',
        ({ payload }) => {
          processingProgress.value = null;
          processedImage.value = payload.result;
          paletteColors.value = payload.palette;
          swatchBands.value = payload.paletteBands ?? [];
        },
      );
    } else {
      latestMainRequestIdRef.current = nextRequestId();
      processedImage.value = null;
      paletteColors.value = [];
      swatchBands.value = [];
    }
  }, [
    nextRequestId,
    simplifiedImageData,
    activeMode,
    valueConfig,
    colorConfig,
    processedImage,
    paletteColors,
    swatchBands,
    dispatchWorkerRequest,
    processingProgress,
  ]);

  const runProcessing = useCallback(() => {
    const src = simplifiedImageData.value;
    if (!src) return;
    postMainRequest();
  }, [postMainRequest, simplifiedImageData]);

  const triggerProcessing = useCallback((delay = 120) => {
    if (processingTimerRef.current !== null) {
      window.clearTimeout(processingTimerRef.current);
    }
    processingTimerRef.current = window.setTimeout(() => {
      processingTimerRef.current = null;
      runProcessing();
    }, delay);
  }, [runProcessing]);

  const triggerSimplify = useCallback((delay = 120) => {
    if (simplifyTimerRef.current !== null) {
      window.clearTimeout(simplifyTimerRef.current);
    }
    simplifyTimerRef.current = window.setTimeout(() => {
      simplifyTimerRef.current = null;
      const src = sourceImageData.value;
      if (!src) return;
      const ultrasharpClient = ultrasharpClientRef.current;
      if (!ultrasharpClient) return;
      const { downscale } = simplifyConfig.value.ultrasharp;
      processingCount.value++;
      const sentAt = performance.now();
      const { requestId, promise } = ultrasharpClient.request(src, downscale);
      latestUltrasharpRequestIdRef.current = requestId;
      console.log(`[Perf] dispatch ultrasharp#${requestId} | size=${src.width}x${src.height}`);
      promise
        .then((result) => {
          if (requestId !== latestUltrasharpRequestIdRef.current) return;
          const roundTrip = performance.now() - sentAt;
          console.log(`[Perf] ultrasharp#${requestId} current | roundTrip=${roundTrip.toFixed(1)}ms`);
          processingProgress.value = null;
          simplifiedImageData.value = result;
          triggerProcessing(0);
        })
        .catch((err: unknown) => {
          const msg = err instanceof Error ? err.message : String(err);
          if (requestId === latestUltrasharpRequestIdRef.current) {
            onError?.(msg);
          }
        })
        .finally(() => {
          processingCount.value = Math.max(0, processingCount.value - 1);
        });
    }, delay);
  }, [sourceImageData, simplifyConfig, simplifiedImageData, triggerProcessing, processingCount, processingProgress, onError]);

  // ── Worker lifecycle ──────────────────────────────────────────────────
  useEffect(() => {
    console.log('[Perf] RefPlane timing logs enabled');
  }, []);

  useEffect(() => {
    const worker = new Worker(new URL('../processing/worker.ts', import.meta.url), { type: 'module' });
    workerClientRef.current = new WorkerClient(worker);

    ultrasharpClientRef.current = new UltrasharpClient((stage, percent, requestId) => {
      if (requestId === latestUltrasharpRequestIdRef.current) {
        processingProgress.value = { stage, percent };
      }
    });

    return () => {
      if (processingTimerRef.current !== null) window.clearTimeout(processingTimerRef.current);
      if (simplifyTimerRef.current !== null) window.clearTimeout(simplifyTimerRef.current);
      requestTimingsRef.current.clear();
      workerClientRef.current?.terminate();
      workerClientRef.current = null;
      ultrasharpClientRef.current?.terminate();
      ultrasharpClientRef.current = null;
    };
  }, []);

  // ── Reactive processing triggers ──────────────────────────────────────

  // Stage 1: source or simplify config changes → re-simplify
  useEffect(() => {
    if (!sourceImageData.value) return;
    triggerSimplify();
  }, [sourceImageData.value, simplifyConfig.value]);

  // Stage 2: analysis config changes or a new simplified image → re-analyze.
  useEffect(() => {
    if (!simplifiedImageData.value) return;
    triggerProcessing(120);
  }, [simplifiedImageData.value, activeMode.value, valueConfig.value, colorConfig.value]);

  // ── Public API ────────────────────────────────────────────────────────
  const resetProcessingState = useCallback(() => {
    simplifiedImageData.value = null;
    processedImage.value = null;
    paletteColors.value = [];
    swatchBands.value = [];
  }, [simplifiedImageData, processedImage, paletteColors, swatchBands]);

  return {
    simplifiedImageData,
    processedImage,
    isProcessing,
    processingProgress,
    paletteColors,
    swatchBands,
    resetProcessingState,
  };
}

function logProcessingTiming(
  requestType: string,
  requestId: number,
  meta: {
    backend?: string;
    queueWaitMs?: number;
    totalMs?: number;
    width?: number;
    height?: number;
    stages?: Array<{ label: string; ms: number }>;
  } | undefined,
  roundTripMs?: number,
  stale?: boolean,
  error?: string,
) {
  const stageSummary = meta?.stages?.map(stage => `${stage.label}=${stage.ms.toFixed(1)}ms`).join(', ');
  const parts = [
    `[Perf] ${requestType}#${requestId}`,
    stale ? 'stale' : 'current',
  ];
  if (meta?.backend) parts.push(`backend=${meta.backend}`);
  if (meta?.queueWaitMs !== undefined) parts.push(`queue=${meta.queueWaitMs.toFixed(1)}ms`);
  if (meta?.totalMs !== undefined) parts.push(`worker=${meta.totalMs.toFixed(1)}ms`);
  if (roundTripMs !== undefined) parts.push(`roundTrip=${roundTripMs.toFixed(1)}ms`);
  if (meta?.width && meta?.height) parts.push(`size=${meta.width}x${meta.height}`);
  if (stageSummary) parts.push(`stages=[${stageSummary}]`);
  if (error) parts.push(`error=${error}`);

  console.log(parts.join(' | '));
}
