import { signal, computed, type Signal, type ReadonlySignal } from '@preact/signals';
import { useEffect, useRef, useCallback, useMemo } from 'preact/hooks';
import type { Mode, EdgeConfig, ValueConfig, ColorConfig, SimplifyConfig, PlanesConfig, PlaneGuidance } from '../types';
import { WorkerClient, WorkerRequestError } from '../processing/worker-client';
import { DepthClient } from '../processing/depth-client';
import { segmentPlanes, resizeDepthMap } from '../processing/planes';
import { buildPlaneGuidance } from '../processing/plane-guidance';
import type { WorkerRequest, WorkerRequestType } from '../processing/worker-protocol';

export interface ProcessingPipelineInputs {
  sourceImageData: Signal<ImageData | null>;
  activeMode: Signal<Mode>;
  simplifyConfig: Signal<SimplifyConfig>;
  valueConfig: Signal<ValueConfig>;
  colorConfig: Signal<ColorConfig>;
  edgeConfig: Signal<EdgeConfig>;
  planesConfig: Signal<PlanesConfig>;
  onError?: (message: string) => void;
}

export interface ProcessingPipelineOutputs {
  simplifiedImageData: Signal<ImageData | null>;
  processedImage: Signal<ImageData | null>;
  edgeData: Signal<ImageData | null>;
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
    edgeConfig,
    planesConfig,
    onError,
  } = inputs;

  // ── Output signals (created once, stable across renders) ──────────────
  const simplifiedImageData = useMemo(() => signal<ImageData | null>(null), []);
  const processedImage = useMemo(() => signal<ImageData | null>(null), []);
  const edgeData = useMemo(() => signal<ImageData | null>(null), []);
  const processingProgress = useMemo(() => signal<{ stage: string; percent: number } | null>(null), []);
  const processingCount = useMemo(() => signal(0), []);
  const isProcessing = useMemo(() => computed(() => processingCount.value > 0), [processingCount]);
  const paletteColors = useMemo(() => signal<string[]>([]), []);
  const swatchBands = useMemo(() => signal<number[]>([]), []);

  // ── Depth estimation & Plane Guidance state ───────────────────────────
  const depthMap = useMemo(() => signal<{ data: Float32Array; width: number; height: number } | null>(null), []);
  const planeGuidance = useMemo(() => signal<PlaneGuidance | null>(null), []);
  const depthSourceRef = useRef<ImageData | null>(null);

  const depthClientRef = useRef<DepthClient | null>(null);
  const latestDepthRequestIdRef = useRef(0);

  // ── Internal refs ─────────────────────────────────────────────────────
  const workerClientRef = useRef<WorkerClient | null>(null);
  const processingTimerRef = useRef<number | null>(null);
  const edgeTimerRef = useRef<number | null>(null);
  const simplifyTimerRef = useRef<number | null>(null);
  const requestSeqRef = useRef(0);
  const latestMainRequestIdRef = useRef(0);
  const latestEdgeRequestIdRef = useRef(0);
  const latestSimplifyRequestIdRef = useRef(0);
  const requestTimingsRef = useRef(new Map<number, { sentAt: number; requestType: string }>());

  // ── Helpers ───────────────────────────────────────────────────────────
  const nextRequestId = useCallback(() => {
    requestSeqRef.current += 1;
    return requestSeqRef.current;
  }, []);

  const requiresPlaneGuidance = useCallback((config: SimplifyConfig) => {
    return config.planeGuidance.preserveBoundaries;
  }, []);

  const dispatchWorkerRequest = useCallback(<T extends WorkerRequest,>(
    request: T,
    channel: 'main' | 'edge' | 'simplify',
    logLabel: string,
    onSuccess: (result: { requestType: T['type']; payload: T['type'] extends 'color-regions' ? { result: ImageData; palette: string[]; paletteBands: number[] } : { result: ImageData } }) => void,
    onProgress?: (stage: string, percent: number, requestId: number) => void,
  ) => {
    const workerClient = workerClientRef.current;
    if (!workerClient) return;

    const requestId = nextRequestId();
    if (channel === 'main') {
      latestMainRequestIdRef.current = requestId;
    } else if (channel === 'edge') {
      latestEdgeRequestIdRef.current = requestId;
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
        const latestRequestId = response.requestType === 'edges'
          ? latestEdgeRequestIdRef.current
          : response.requestType === 'simplify'
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
    } else if (mode === 'planes') {
      const depth = depthMap.value;
      if (!depth) return; // depth not ready yet — will be triggered when depth completes
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      const depthCopy = new Float32Array(depth.data);
      const requestId = nextRequestId();
      latestMainRequestIdRef.current = requestId;
      processingCount.value++;

      const request = {
        type: 'planes' as const,
        imageData: imgCopy,
        depthMap: depthCopy,
        depthWidth: depth.width,
        depthHeight: depth.height,
        config: planesConfig.value,
      };

      const { promise } = workerClientRef.current!.request(request, {
        requestId,
        transfer: [imgCopy.data.buffer, depthCopy.buffer],
      });

      promise
        .then((response) => {
          if (response.requestId !== latestMainRequestIdRef.current) return;
          processingProgress.value = null;
          processedImage.value = response.payload.result;
        })
        .catch((err: unknown) => {
          const msg = err instanceof Error ? err.message : String(err);
          if (msg !== 'AbortError') onError?.(msg);
        })
        .finally(() => {
          processingCount.value = Math.max(0, processingCount.value - 1);
        });
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
    planesConfig,
    depthMap,
    processedImage,
    paletteColors,
    swatchBands,
    dispatchWorkerRequest,
    processingProgress,
    processingCount,
    onError,
  ]);

  const postEdgeRequest = useCallback((src: ImageData, delay = 80) => {
    const worker = workerClientRef.current;
    if (!worker) return;
    if (edgeTimerRef.current !== null) {
      window.clearTimeout(edgeTimerRef.current);
    }
    edgeTimerRef.current = window.setTimeout(() => {
      edgeTimerRef.current = null;
      if (!edgeConfig.value.enabled) {
        edgeData.value = null;
        return;
      }
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      dispatchWorkerRequest(
        { type: 'edges', imageData: imgCopy, config: edgeConfig.value },
        'edge',
        'edges',
        ({ payload }) => {
          processingProgress.value = null;
          edgeData.value = payload.result;
        },
      );
    }, delay);
  }, [edgeConfig, edgeData, dispatchWorkerRequest, processingProgress]);

  const postSimplifyRequest = useCallback((src: ImageData) => {
    const worker = workerClientRef.current;
    if (!worker) return;
    const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
    const guidance = planeGuidance.value;
    const transfer: Transferable[] = [imgCopy.data.buffer];
    let guidanceCopy: PlaneGuidance | undefined;
    if (guidance) {
      const labelsCopy = new Uint8Array(guidance.labels);
      guidanceCopy = { ...guidance, labels: labelsCopy };
      transfer.push(labelsCopy.buffer);
    }
    dispatchWorkerRequest(
      { type: 'simplify', imageData: imgCopy, config: simplifyConfig.value, planeGuidance: guidanceCopy },
      'simplify',
      'simplify',
      ({ payload }) => {
        processingProgress.value = null;
        simplifiedImageData.value = payload.result;
      },
      (stage, percent, requestId) => {
        if (requestId === latestSimplifyRequestIdRef.current) {
          processingProgress.value = { stage, percent };
        }
      },
    );
  }, [dispatchWorkerRequest, simplifyConfig, processingProgress, simplifiedImageData, planeGuidance]);

  const runProcessing = useCallback(() => {
    const src = simplifiedImageData.value;
    if (!src) return;
    const mode = activeMode.value;

    postMainRequest();

    if (mode === 'original') {
      if (edgeConfig.value.enabled) {
        const edgeSrc = edgeConfig.value.useOriginal ? (sourceImageData.value ?? src) : src;
        postEdgeRequest(edgeSrc, 0);
      } else {
        latestEdgeRequestIdRef.current = nextRequestId();
        edgeData.value = null;
      }
    }
  }, [nextRequestId, postEdgeRequest, postMainRequest, simplifiedImageData, activeMode, edgeConfig, sourceImageData, edgeData]);

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
      if (simplifyConfig.value.method === 'none') {
        simplifiedImageData.value = src;
        triggerProcessing(0);
        return;
      }
      if (requiresPlaneGuidance(simplifyConfig.value) && !planeGuidance.value) {
        // Will be triggered when plane guidance completes
        return;
      }
      postSimplifyRequest(src);
    }, delay);
  }, [postSimplifyRequest, sourceImageData, simplifyConfig, simplifiedImageData, planeGuidance, requiresPlaneGuidance, triggerProcessing]);

  // ── Worker lifecycle ──────────────────────────────────────────────────
  useEffect(() => {
    console.log('[Perf] RefPlane timing logs enabled');
  }, []);

  useEffect(() => {
    const worker = new Worker(new URL('../processing/worker.ts', import.meta.url), { type: 'module' });
    workerClientRef.current = new WorkerClient(worker);

    depthClientRef.current = new DepthClient((stage, percent) => {
      processingProgress.value = { stage, percent };
    });

    return () => {
      if (processingTimerRef.current !== null) window.clearTimeout(processingTimerRef.current);
      if (edgeTimerRef.current !== null) window.clearTimeout(edgeTimerRef.current);
      if (simplifyTimerRef.current !== null) window.clearTimeout(simplifyTimerRef.current);
      requestTimingsRef.current.clear();
      workerClientRef.current?.terminate();
      workerClientRef.current = null;
      depthClientRef.current?.terminate();
      depthClientRef.current = null;
    };
  }, []);

  // ── Depth estimation trigger (planes mode or plane-guided simplify) ────
  useEffect(() => {
    const needsDepth = activeMode.value === 'planes' || requiresPlaneGuidance(simplifyConfig.value);
    if (!needsDepth) return;
    const src = sourceImageData.value;
    if (!src || !depthClientRef.current) return;

    // Only re-run depth if source and model haven't changed
    if (depthSourceRef.current === src) {
      // Depth already estimated for this source — but guidance may not have been built yet
      if (requiresPlaneGuidance(simplifyConfig.value) && !planeGuidance.value && depthMap.value) {
        const depth = depthMap.value;
        const resized = resizeDepthMap(depth.data, depth.width, depth.height, src.width, src.height);
        const segmentation = segmentPlanes(resized, src.width, src.height, planesConfig.value);
        planeGuidance.value = buildPlaneGuidance(segmentation);
        triggerSimplify(0);
      }
      return;
    }
    depthSourceRef.current = src;
    depthMap.value = null;
    planeGuidance.value = null;

    const { requestId, promise } = depthClientRef.current.requestDepth(src);
    latestDepthRequestIdRef.current = requestId;
    processingCount.value++;

    promise
      .then((result) => {
        if (requestId !== latestDepthRequestIdRef.current) return; // stale
        depthMap.value = { data: result.depthData, width: result.depthWidth, height: result.depthHeight };

        // Auto-extract plane guidance if needed
        if (requiresPlaneGuidance(simplifyConfig.value)) {
          const imgSrc = sourceImageData.value;
          if (imgSrc) {
            const resized = resizeDepthMap(result.depthData, result.depthWidth, result.depthHeight, imgSrc.width, imgSrc.height);
            const segmentation = segmentPlanes(resized, imgSrc.width, imgSrc.height, planesConfig.value);
            planeGuidance.value = buildPlaneGuidance(segmentation);
          }
          triggerSimplify(0);
        }

        // If planes mode is still active, trigger processing
        if (activeMode.value === 'planes') {
          triggerProcessing(0);
        }
      })
      .catch((err) => {
        if (requestId !== latestDepthRequestIdRef.current) return;
        onError?.('Depth estimation failed: ' + (err instanceof Error ? err.message : String(err)));
      })
      .finally(() => {
        processingCount.value = Math.max(0, processingCount.value - 1);
      });
  }, [sourceImageData.value, activeMode.value, simplifyConfig.value, requiresPlaneGuidance, planesConfig.value, triggerSimplify, triggerProcessing]);

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
  }, [simplifiedImageData.value, activeMode.value, valueConfig.value, colorConfig.value, planesConfig.value, depthMap.value]);

  useEffect(() => {
    if (edgeConfig.value.enabled) {
      const simplified = simplifiedImageData.value ?? sourceImageData.value;
      if (!simplified || !workerClientRef.current) return;
      const edgeSrc = edgeConfig.value.useOriginal
        ? (sourceImageData.value ?? simplified)
        : (activeMode.value === 'original' ? simplified : (processedImage.value ?? simplified));
      postEdgeRequest(edgeSrc, 80);
    } else {
      latestEdgeRequestIdRef.current = nextRequestId();
      edgeData.value = null;
    }
  }, [edgeConfig.value, activeMode.value, processedImage.value, simplifiedImageData.value, sourceImageData.value, nextRequestId, postEdgeRequest]);

  // ── Public API ────────────────────────────────────────────────────────
  const resetProcessingState = useCallback(() => {
    simplifiedImageData.value = null;
    processedImage.value = null;
    paletteColors.value = [];
    swatchBands.value = [];
    edgeData.value = null;
    depthMap.value = null;
    depthSourceRef.current = null;
  }, [simplifiedImageData, processedImage, paletteColors, swatchBands, edgeData, depthMap]);

  return {
    simplifiedImageData,
    processedImage,
    edgeData,
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
