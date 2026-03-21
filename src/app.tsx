import { signal, computed } from '@preact/signals';
import { useEffect, useRef, useCallback } from 'preact/hooks';
import { ModeBar } from './components/ModeBar';
import { OverlayToggles } from './components/OverlayToggles';
import { ImageCanvas } from './components/ImageCanvas';
import { ValueSettings } from './components/ValueSettings';
import { ColorSettings } from './components/ColorSettings';
import { PaletteStrip } from './components/PaletteStrip';
import { ActionBar } from './components/ActionBar';
import { CompareView } from './components/CompareView';
import { CropOverlay } from './components/CropOverlay';
import { exportImage } from './export/export';
import { initInstallPrompt, triggerInstall } from './pwa/install-prompt';
import { getDefaultThresholds } from './processing/quantize';
import type { Mode, GridConfig, EdgeConfig, ValueConfig, ColorConfig } from './types';
import './styles/global.css';

// 1600px keeps memory and processing time reasonable on mobile devices
const MAX_WORKING_SIZE = 1600;

/** Create a canvas, falling back to HTMLCanvasElement on platforms where OffscreenCanvas is unavailable (e.g. some iOS Safari versions). */
function makeCanvas(w: number, h: number): OffscreenCanvas | HTMLCanvasElement {
  if (typeof OffscreenCanvas !== 'undefined') {
    return new OffscreenCanvas(w, h);
  }
  const el = document.createElement('canvas');
  el.width = w;
  el.height = h;
  return el;
}

const defaultGridConfig: GridConfig = {
  enabled: false,
  divisions: 4,
  cellAspect: 'square',
  showDiagonals: false,
  showCenterLines: false,
  lineStyle: 'auto-contrast',
  customColor: '#ffffff',
  opacity: 0.7,
};

const defaultEdgeConfig: EdgeConfig = {
  enabled: false,
  method: 'canny',
  detail: 0.5,
  sensitivity: 0.5,
  compositeMode: 'lines-over',
  lineColor: 'black',
  lineCustomColor: '#000000',
  lineOpacity: 0.8,
  edgesOnlyPolarity: 'dark-on-light',
  lineWeight: 1,
  lineKnockoutColor: 'black',
  lineKnockoutCustomColor: '#000000',
};

const defaultValueConfig: ValueConfig = {
  levels: 3,
  strength: 0.5,
  thresholds: getDefaultThresholds(3),
  minRegionSize: 'small',
};

const defaultColorConfig: ColorConfig = {
  bands: 3,
  colorsPerBand: 2,
  strength: 0.5,
  warmCoolEmphasis: 0,
  thresholds: getDefaultThresholds(3),
  minRegionSize: 'small',
};

// originalImageData is never overwritten by crop — non-destructive crop derives sourceImageData from it.
const originalImageData = signal<ImageData | null>(null);
const sourceImageData = signal<ImageData | null>(null);
const activeMode = signal<Mode>('original');
const processedImage = signal<ImageData | null>(null);
const edgeDataSignal = signal<ImageData | null>(null);
const gridConfig = signal<GridConfig>(defaultGridConfig);
const edgeConfig = signal<EdgeConfig>(defaultEdgeConfig);
const valueConfig = signal<ValueConfig>(defaultValueConfig);
const colorConfig = signal<ColorConfig>(defaultColorConfig);
// Track number of outstanding worker requests; spinner shows while any are pending.
const processingCount = signal(0);
const isProcessing = computed(() => processingCount.value > 0);
const paletteColors = signal<string[]>([]);
// Maps each palette swatch index to its value-band index for correct band isolation.
const swatchBands = signal<number[]>([]);
const showCompare = signal(false);
const showCropOverlay = signal(false);
const isolatedBand = signal<number | null>(null);
const showTemperatureMap = signal(false);
const showInstallBanner = signal(false);

export function App() {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const displayCanvasRef = useRef<HTMLCanvasElement>(null);
  const workerRef = useRef<Worker | null>(null);
  const processingTimerRef = useRef<number | null>(null);
  const edgeTimerRef = useRef<number | null>(null);
  const requestSeqRef = useRef(0);
  const latestMainRequestIdRef = useRef(0);
  const latestEdgeRequestIdRef = useRef(0);
  const requestTimingsRef = useRef(new Map<number, { sentAt: number; requestType: string }>());

  useEffect(() => {
    initInstallPrompt(() => { showInstallBanner.value = true; });
  }, []);

  useEffect(() => {
    console.log('[Perf] RefPlane timing logs enabled');
  }, []);

  useEffect(() => {
    const worker = new Worker(new URL('./processing/worker.ts', import.meta.url), { type: 'module' });
    workerRef.current = worker;

    worker.onmessage = (e) => {
      const { type, result, palette, paletteBands, requestType, error, requestId, meta } = e.data;
      const isEdgeRequest = requestType === 'edges';
      const latestRequestId = isEdgeRequest ? latestEdgeRequestIdRef.current : latestMainRequestIdRef.current;
      const requestTiming = requestTimingsRef.current.get(requestId);
      const roundTripMs = requestTiming ? performance.now() - requestTiming.sentAt : undefined;
      requestTimingsRef.current.delete(requestId);
      if (type === 'error') {
        logProcessingTiming(requestType, requestId, meta, roundTripMs, true, error);
        console.error('Worker error:', error);
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
        if (requestType === 'edges') {
          edgeDataSignal.value = result;
        } else {
          processedImage.value = result;
          if (palette) {
            paletteColors.value = palette;
            swatchBands.value = paletteBands ?? [];
          }
          // Post edges using the freshly-computed result, not a stale processedImage value.
          if (edgeConfig.value.enabled && sourceImageData.value) {
            const src = sourceImageData.value;
            const displaySrc = activeMode.value === 'original' ? src : result;
            postEdgeRequest(displaySrc, 0);
          }
        }
      }
    };

    return () => {
      if (processingTimerRef.current !== null) window.clearTimeout(processingTimerRef.current);
      if (edgeTimerRef.current !== null) window.clearTimeout(edgeTimerRef.current);
      requestTimingsRef.current.clear();
      worker.terminate();
    };
  }, []);

  const nextRequestId = useCallback(() => {
    requestSeqRef.current += 1;
    return requestSeqRef.current;
  }, []);

  const postMainRequest = useCallback((src: ImageData) => {
    const worker = workerRef.current;
    if (!worker) return;
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
  }, [nextRequestId]);

  const postEdgeRequest = useCallback((src: ImageData, delay = 80) => {
    const worker = workerRef.current;
    if (!worker) return;
    if (edgeTimerRef.current !== null) {
      window.clearTimeout(edgeTimerRef.current);
    }
    edgeTimerRef.current = window.setTimeout(() => {
      edgeTimerRef.current = null;
      if (!edgeConfig.value.enabled) {
        edgeDataSignal.value = null;
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
  }, [nextRequestId]);

  const runProcessing = useCallback(() => {
    const src = sourceImageData.value;
    if (!src) return;
    const mode = activeMode.value;

    postMainRequest(src);

    // For non-original modes, edges are posted in the onmessage handler after the main result
    // arrives so they're always computed from the correct (freshly-processed) image.
    // For original mode there is no main processing, so post edges immediately.
    if (mode === 'original') {
      if (edgeConfig.value.enabled) {
        postEdgeRequest(src, 0);
      } else {
        latestEdgeRequestIdRef.current = nextRequestId();
        edgeDataSignal.value = null;
      }
    }
  }, [nextRequestId, postEdgeRequest, postMainRequest]);

  const triggerProcessing = useCallback((delay = 120) => {
    if (processingTimerRef.current !== null) {
      window.clearTimeout(processingTimerRef.current);
    }
    processingTimerRef.current = window.setTimeout(() => {
      processingTimerRef.current = null;
      runProcessing();
    }, delay);
  }, [runProcessing]);

  useEffect(() => {
    triggerProcessing(120);
  }, [activeMode.value, valueConfig.value, colorConfig.value]);

  useEffect(() => {
    if (edgeConfig.value.enabled) {
      const src = sourceImageData.value;
      if (!src || !workerRef.current) return;
      // Use the latest available processed image as the edge base. If main processing
      // is still in-flight, processedImage.value may lag behind the current config; the
      // in-flight result will post fresh edges via the onmessage handler once it arrives.
      const displaySrc = activeMode.value === 'original' ? src : (processedImage.value ?? src);
      postEdgeRequest(displaySrc, 80);
    } else {
      latestEdgeRequestIdRef.current = nextRequestId();
      edgeDataSignal.value = null;
    }
  }, [edgeConfig.value, nextRequestId, postEdgeRequest]);

  const handleFileChange = async (e: Event) => {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;

    const bitmap = await createImageBitmap(file);
    let targetW = bitmap.width;
    let targetH = bitmap.height;
    if (Math.max(targetW, targetH) > MAX_WORKING_SIZE) {
      const scale = MAX_WORKING_SIZE / Math.max(targetW, targetH);
      targetW = Math.round(targetW * scale);
      targetH = Math.round(targetH * scale);
    }
    const canvas = makeCanvas(targetW, targetH);
    const ctx = canvas.getContext('2d') as CanvasRenderingContext2D;
    ctx.drawImage(bitmap, 0, 0, targetW, targetH);
    const imgData = ctx.getImageData(0, 0, targetW, targetH);
    originalImageData.value = imgData;
    sourceImageData.value = imgData;
    processedImage.value = null;
    paletteColors.value = [];
    swatchBands.value = [];
    edgeDataSignal.value = null;
    isolatedBand.value = null;
    runProcessing();
  };

  const handleExport = async () => {
    const canvas = displayCanvasRef.current;
    if (!canvas) return;
    const modeSlug = activeMode.value === 'original' ? 'original' : activeMode.value;
    await exportImage(canvas, modeSlug);
  };

  const handleCropConfirm = (crop: { x: number; y: number; width: number; height: number }) => {
    // Always crop from the original image to support non-destructive re-cropping.
    const original = originalImageData.value;
    if (!original) return;
    const croppedCanvas = makeCanvas(crop.width, crop.height);
    const croppedCtx = croppedCanvas.getContext('2d') as CanvasRenderingContext2D;
    const tmpCanvas = makeCanvas(original.width, original.height);
    const tmpCtx = tmpCanvas.getContext('2d') as CanvasRenderingContext2D;
    tmpCtx.putImageData(original, 0, 0);
    croppedCtx.drawImage(tmpCanvas, crop.x, crop.y, crop.width, crop.height, 0, 0, crop.width, crop.height);
    const newImgData = croppedCtx.getImageData(0, 0, crop.width, crop.height);
    sourceImageData.value = newImgData;
    processedImage.value = null;
    paletteColors.value = [];
    swatchBands.value = [];
    edgeDataSignal.value = null;
    isolatedBand.value = null;
    showCropOverlay.value = false;
    runProcessing();
  };

  const compositeOptions = {
    showTemperatureMap: showTemperatureMap.value,
    tempIntensity: 1.0,
    // Only apply band isolation in 'color' mode; switching modes would otherwise
    // continue to dim the image even after the palette strip is hidden.
    isolatedBand: activeMode.value === 'color' ? isolatedBand.value : null,
    isolationThresholds: colorConfig.value.thresholds,
  };

  const currentImageData = activeMode.value === 'original'
    ? sourceImageData.value
    : (processedImage.value ?? sourceImageData.value);

  return (
    <div id="app-root" style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {showInstallBanner.value && (
        <div style={{
          background: '#1a2744',
          color: 'white',
          padding: '10px 16px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          fontSize: '14px',
          flexShrink: 0,
        }}>
          <span>📲 Add RefPlane to home screen</span>
          <div style={{ display: 'flex', gap: '8px' }}>
            <button
              style={{ background: '#5b8def', color: 'white', borderRadius: '8px', padding: '6px 14px', fontSize: '13px', fontWeight: 600 }}
              onClick={async () => { await triggerInstall(); showInstallBanner.value = false; }}
            >
              Install
            </button>
            <button
              aria-label="Close install banner"
              style={{ background: 'transparent', color: 'rgba(255,255,255,0.6)', border: 'none', padding: '6px', fontSize: '16px' }}
              onClick={() => { showInstallBanner.value = false; }}
            >
              ✕
            </button>
          </div>
        </div>
      )}

      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        style={{ display: 'none' }}
        onChange={handleFileChange}
      />

      <div style={{ flex: 1, position: 'relative', overflow: 'hidden', background: '#0d0d0d' }}>
        <ImageCanvas
          sourceImageData={sourceImageData.value}
          processedImageData={processedImage.value}
          activeMode={activeMode.value}
          gridConfig={gridConfig.value}
          edgeConfig={edgeConfig.value}
          edgeData={edgeDataSignal.value}
          isProcessing={isProcessing.value}
          externalRef={displayCanvasRef}
          compositeOptions={compositeOptions}
        />

        {!sourceImageData.value && (
          <button
            style={{
              position: 'absolute', bottom: '24px', left: '50%',
              transform: 'translateX(-50%)',
              background: '#5b8def', color: 'white',
              padding: '12px 32px', borderRadius: '24px',
              fontWeight: 600, fontSize: '16px',
              boxShadow: '0 4px 16px rgba(91,141,239,0.4)',
              minHeight: '48px',
            }}
            onClick={() => fileInputRef.current?.click()}
          >
            Open Image
          </button>
        )}

        {showCropOverlay.value && originalImageData.value && (
          <CropOverlay
            imageWidth={originalImageData.value.width}
            imageHeight={originalImageData.value.height}
            initialCrop={null}
            onCropChange={handleCropConfirm}
            onConfirm={() => {}}
            onCancel={() => { showCropOverlay.value = false; }}
          />
        )}

        {showCompare.value && (
          <CompareView
            beforeData={sourceImageData.value}
            afterData={currentImageData}
            onClose={() => { showCompare.value = false; }}
          />
        )}
      </div>

      <div class="bottom-sheet">
        <ModeBar
          activeMode={activeMode.value}
          onModeChange={(mode) => { activeMode.value = mode; }}
        />

        <OverlayToggles
          gridConfig={gridConfig.value}
          edgeConfig={edgeConfig.value}
          showTemperatureMap={showTemperatureMap.value}
          onGridChange={(cfg) => { gridConfig.value = { ...gridConfig.value, ...cfg }; }}
          onEdgeChange={(cfg) => { edgeConfig.value = { ...edgeConfig.value, ...cfg }; }}
          onTemperatureMapChange={(enabled) => { showTemperatureMap.value = enabled; }}
        />

        <div class="scrollable" style={{ flex: 1 }}>
          {activeMode.value === 'value' && (
            <ValueSettings
              config={valueConfig.value}
              onChange={(cfg) => { valueConfig.value = { ...valueConfig.value, ...cfg }; }}
            />
          )}
          {activeMode.value === 'color' && (
            <ColorSettings
              config={colorConfig.value}
              onChange={(cfg) => { colorConfig.value = { ...colorConfig.value, ...cfg }; }}
            />
          )}
        </div>

        {paletteColors.value.length > 0 && (
          <PaletteStrip
            colors={paletteColors.value}
            bands={swatchBands.value}
            isolatedBand={isolatedBand.value}
            onIsolate={(band) => { isolatedBand.value = band; }}
          />
        )}

        <ActionBar
          hasImage={sourceImageData.value !== null}
          showCrop={showCropOverlay.value}
          showCompare={showCompare.value}
          onCrop={() => {
            if (sourceImageData.value) {
              showCropOverlay.value = !showCropOverlay.value;
              showCompare.value = false;
            } else {
              fileInputRef.current?.click();
            }
          }}
          onCompare={() => { showCompare.value = !showCompare.value; showCropOverlay.value = false; }}
          onExport={handleExport}
        />
      </div>
    </div>
  );
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
