import { signal, computed, type Signal, type ReadonlySignal } from '@preact/signals';
import { useEffect, useRef, useCallback, useMemo } from 'preact/hooks';
import type { Mode, EdgeConfig, ValueConfig, ColorConfig, SimplifyConfig } from '../types';

export interface ProcessingPipelineInputs {
  sourceImageData: Signal<ImageData | null>;
  activeMode: Signal<Mode>;
  simplifyConfig: Signal<SimplifyConfig>;
  valueConfig: Signal<ValueConfig>;
  colorConfig: Signal<ColorConfig>;
  edgeConfig: Signal<EdgeConfig>;
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

  // ── Internal refs ─────────────────────────────────────────────────────
  const workerRef = useRef<Worker | null>(null);
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

  const postMainRequest = useCallback(() => {
    const worker = workerRef.current;
    const src = simplifiedImageData.value;
    if (!worker || !src) return;
    const mode = activeMode.value;
    if (mode === 'grayscale') {
      const requestId = nextRequestId();
      latestMainRequestIdRef.current = requestId;
      processingCount.value++;
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      requestTimingsRef.current.set(requestId, { sentAt: performance.now(), requestType: 'grayscale' });
      console.log(`[Perf] dispatch grayscale#${requestId} | size=${src.width}x${src.height}`);
      worker.postMessage({ type: 'grayscale', imageData: imgCopy, requestId }, [imgCopy.data.buffer]);
    } else if (mode === 'value') {
      const requestId = nextRequestId();
      latestMainRequestIdRef.current = requestId;
      processingCount.value++;
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      requestTimingsRef.current.set(requestId, { sentAt: performance.now(), requestType: 'value-study' });
      console.log(`[Perf] dispatch value-study#${requestId} | size=${src.width}x${src.height}`);
      worker.postMessage({ type: 'value-study', imageData: imgCopy, config: valueConfig.value, requestId }, [imgCopy.data.buffer]);
    } else if (mode === 'color') {
      const requestId = nextRequestId();
      latestMainRequestIdRef.current = requestId;
      processingCount.value++;
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      requestTimingsRef.current.set(requestId, { sentAt: performance.now(), requestType: 'color-regions' });
      console.log(`[Perf] dispatch color-regions#${requestId} | size=${src.width}x${src.height}`);
      worker.postMessage({ type: 'color-regions', imageData: imgCopy, config: colorConfig.value, requestId }, [imgCopy.data.buffer]);
    } else {
      latestMainRequestIdRef.current = nextRequestId();
      processedImage.value = null;
      paletteColors.value = [];
      swatchBands.value = [];
    }
  }, [nextRequestId, simplifiedImageData, activeMode, valueConfig, colorConfig, processedImage, paletteColors, swatchBands, processingCount]);

  const postEdgeRequest = useCallback((src: ImageData, delay = 80) => {
    const worker = workerRef.current;
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
      const requestId = nextRequestId();
      latestEdgeRequestIdRef.current = requestId;
      processingCount.value++;
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      requestTimingsRef.current.set(requestId, { sentAt: performance.now(), requestType: 'edges' });
      console.log(`[Perf] dispatch edges#${requestId} | size=${src.width}x${src.height}`);
      worker.postMessage({ type: 'edges', imageData: imgCopy, config: edgeConfig.value, requestId }, [imgCopy.data.buffer]);
    }, delay);
  }, [nextRequestId, edgeConfig, edgeData, processingCount]);

  const postSimplifyRequest = useCallback((src: ImageData) => {
    const worker = workerRef.current;
    if (!worker) return;
    const requestId = nextRequestId();
    latestSimplifyRequestIdRef.current = requestId;
    processingCount.value++;
    const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
    requestTimingsRef.current.set(requestId, { sentAt: performance.now(), requestType: 'simplify' });
    console.log(`[Perf] dispatch simplify#${requestId} | method=${simplifyConfig.value.method} | size=${src.width}x${src.height}`);
    worker.postMessage({ type: 'simplify', imageData: imgCopy, config: simplifyConfig.value, requestId }, [imgCopy.data.buffer]);
  }, [nextRequestId, simplifyConfig, processingCount]);

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
      postSimplifyRequest(src);
    }, delay);
  }, [postSimplifyRequest, sourceImageData, simplifyConfig, simplifiedImageData]);

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

  // ── Worker lifecycle ──────────────────────────────────────────────────
  useEffect(() => {
    console.log('[Perf] RefPlane timing logs enabled');
  }, []);

  useEffect(() => {
    const worker = new Worker(new URL('../processing/worker.ts', import.meta.url), { type: 'module' });
    workerRef.current = worker;

    worker.onmessage = (e) => {
      const { type, result, palette, paletteBands, requestType, error, requestId, meta } = e.data;
      if (type === 'progress') {
        if (requestId === latestSimplifyRequestIdRef.current) {
          processingProgress.value = { stage: e.data.stage, percent: e.data.percent };
        }
        return;
      }
      const isEdgeRequest = requestType === 'edges';
      const latestRequestId = isEdgeRequest
        ? latestEdgeRequestIdRef.current
        : requestType === 'simplify'
          ? latestSimplifyRequestIdRef.current
          : latestMainRequestIdRef.current;
      const requestTiming = requestTimingsRef.current.get(requestId);
      const roundTripMs = requestTiming ? performance.now() - requestTiming.sentAt : undefined;
      requestTimingsRef.current.delete(requestId);
      if (type === 'error') {
        const isAbort = error === 'AbortError';
        logProcessingTiming(requestType, requestId, meta, roundTripMs, true, error);
        if (!isAbort) {
          console.error('Worker error:', error);
          onError?.(typeof error === 'string' ? error : 'Processing failed');
        }
        processingCount.value = Math.max(0, processingCount.value - 1);
        return;
      }
      if (type === 'result') {
        processingCount.value = Math.max(0, processingCount.value - 1);
        const isStale = requestId !== latestRequestId;
        logProcessingTiming(requestType, requestId, meta, roundTripMs, isStale);
        if (requestId !== latestRequestId) {
          return;
        }
        if (requestType === 'simplify') {
          processingProgress.value = null;
          simplifiedImageData.value = result;
          // Trigger downstream analysis
          triggerProcessing(0);
          return;
        }
        if (requestType !== 'simplify') {
          processingProgress.value = null;
        }
        if (requestType === 'edges') {
          edgeData.value = result;
        } else {
          processedImage.value = result;
          if (palette) {
            paletteColors.value = palette;
            swatchBands.value = paletteBands ?? [];
          }
          // Post edges using the freshly-computed result, not a stale processedImage value.
          if (edgeConfig.value.enabled && sourceImageData.value) {
            const edgeSrc = edgeConfig.value.useOriginal
              ? sourceImageData.value
              : (activeMode.value === 'original' ? sourceImageData.value : result);
            postEdgeRequest(edgeSrc, 0);
          }
        }
      }
    };

    return () => {
      if (processingTimerRef.current !== null) window.clearTimeout(processingTimerRef.current);
      if (edgeTimerRef.current !== null) window.clearTimeout(edgeTimerRef.current);
      if (simplifyTimerRef.current !== null) window.clearTimeout(simplifyTimerRef.current);
      requestTimingsRef.current.clear();
      worker.terminate();
    };
  }, []);

  // ── Reactive processing triggers ──────────────────────────────────────

  // Stage 1: source or simplify config changes → re-simplify
  useEffect(() => {
    if (!sourceImageData.value) return;
    triggerSimplify();
  }, [sourceImageData.value, simplifyConfig.value]);

  // Stage 2: analysis config changes → re-analyze from cached simplified image.
  // Note: simplifiedImageData is intentionally NOT in the dep array — the worker
  // onmessage handler calls triggerProcessing(0) directly when a new simplified
  // result arrives, so adding it here would cause double-firing.
  useEffect(() => {
    if (!simplifiedImageData.value) return;
    triggerProcessing(120);
  }, [activeMode.value, valueConfig.value, colorConfig.value]);

  useEffect(() => {
    if (edgeConfig.value.enabled) {
      const simplified = simplifiedImageData.value ?? sourceImageData.value;
      if (!simplified || !workerRef.current) return;
      const edgeSrc = edgeConfig.value.useOriginal
        ? (sourceImageData.value ?? simplified)
        : (activeMode.value === 'original' ? simplified : (processedImage.value ?? simplified));
      postEdgeRequest(edgeSrc, 80);
    } else {
      latestEdgeRequestIdRef.current = nextRequestId();
      edgeData.value = null;
    }
  }, [edgeConfig.value, nextRequestId, postEdgeRequest]);

  // ── Public API ────────────────────────────────────────────────────────
  const resetProcessingState = useCallback(() => {
    simplifiedImageData.value = null;
    processedImage.value = null;
    paletteColors.value = [];
    swatchBands.value = [];
    edgeData.value = null;
  }, [simplifiedImageData, processedImage, paletteColors, swatchBands, edgeData]);

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
