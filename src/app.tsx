import { signal } from '@preact/signals';
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

const MAX_WORKING_SIZE = 1600;

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

const sourceImageData = signal<ImageData | null>(null);
const activeMode = signal<Mode>('original');
const processedImage = signal<ImageData | null>(null);
const edgeDataSignal = signal<ImageData | null>(null);
const gridConfig = signal<GridConfig>(defaultGridConfig);
const edgeConfig = signal<EdgeConfig>(defaultEdgeConfig);
const valueConfig = signal<ValueConfig>(defaultValueConfig);
const colorConfig = signal<ColorConfig>(defaultColorConfig);
const isProcessing = signal(false);
const paletteColors = signal<string[]>([]);
const showCompare = signal(false);
const showCropOverlay = signal(false);
const isolatedBand = signal<number | null>(null);
const showTemperatureMap = signal(false);
const showInstallBanner = signal(false);

export function App() {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const displayCanvasRef = useRef<HTMLCanvasElement>(null);
  const workerRef = useRef<Worker | null>(null);

  useEffect(() => {
    initInstallPrompt(() => { showInstallBanner.value = true; });
  }, []);

  useEffect(() => {
    const worker = new Worker(new URL('./processing/worker.ts', import.meta.url), { type: 'module' });
    workerRef.current = worker;

    worker.onmessage = (e) => {
      const { type, result, palette, requestType, error } = e.data;
      if (type === 'error') {
        console.error('Worker error:', error);
        isProcessing.value = false;
        return;
      }
      if (type === 'result') {
        if (requestType === 'edges') {
          edgeDataSignal.value = result;
        } else {
          processedImage.value = result;
          if (palette) paletteColors.value = palette;
        }
        isProcessing.value = false;
      }
    };

    return () => worker.terminate();
  }, []);

  const triggerProcessing = useCallback(() => {
    const src = sourceImageData.value;
    if (!src) return;
    const mode = activeMode.value;
    const worker = workerRef.current;
    if (!worker) return;

    if (mode === 'grayscale') {
      isProcessing.value = true;
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      worker.postMessage({ type: 'grayscale', imageData: imgCopy }, [imgCopy.data.buffer]);
    } else if (mode === 'value') {
      isProcessing.value = true;
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      worker.postMessage({ type: 'value-study', imageData: imgCopy, config: valueConfig.value }, [imgCopy.data.buffer]);
    } else if (mode === 'color') {
      isProcessing.value = true;
      const imgCopy = new ImageData(new Uint8ClampedArray(src.data), src.width, src.height);
      worker.postMessage({ type: 'color-regions', imageData: imgCopy, config: colorConfig.value }, [imgCopy.data.buffer]);
    } else {
      processedImage.value = null;
      paletteColors.value = [];
    }

    if (edgeConfig.value.enabled) {
      const displaySrc = mode === 'original' ? src : (processedImage.value ?? src);
      const imgCopy2 = new ImageData(new Uint8ClampedArray(displaySrc.data), displaySrc.width, displaySrc.height);
      worker.postMessage({ type: 'edges', imageData: imgCopy2, config: edgeConfig.value }, [imgCopy2.data.buffer]);
    } else {
      edgeDataSignal.value = null;
    }
  }, []);

  useEffect(() => {
    triggerProcessing();
  }, [activeMode.value, valueConfig.value, colorConfig.value]);

  useEffect(() => {
    if (edgeConfig.value.enabled) {
      const src = sourceImageData.value;
      if (!src || !workerRef.current) return;
      const displaySrc = activeMode.value === 'original' ? src : (processedImage.value ?? src);
      const imgCopy = new ImageData(new Uint8ClampedArray(displaySrc.data), displaySrc.width, displaySrc.height);
      workerRef.current.postMessage({ type: 'edges', imageData: imgCopy, config: edgeConfig.value }, [imgCopy.data.buffer]);
    } else {
      edgeDataSignal.value = null;
    }
  }, [edgeConfig.value]);

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
    const canvas = new OffscreenCanvas(targetW, targetH);
    const ctx = canvas.getContext('2d')!;
    ctx.drawImage(bitmap, 0, 0, targetW, targetH);
    const imgData = ctx.getImageData(0, 0, targetW, targetH);
    sourceImageData.value = imgData;
    processedImage.value = null;
    paletteColors.value = [];
    edgeDataSignal.value = null;
    isolatedBand.value = null;
    triggerProcessing();
  };

  const handleExport = async () => {
    const canvas = displayCanvasRef.current;
    if (!canvas) return;
    const modeSlug = activeMode.value === 'original' ? 'original' : activeMode.value;
    await exportImage(canvas, modeSlug);
  };

  const handleCropConfirm = (crop: { x: number; y: number; width: number; height: number }) => {
    const src = sourceImageData.value;
    if (!src) return;
    const croppedCanvas = new OffscreenCanvas(crop.width, crop.height);
    const ctx = croppedCanvas.getContext('2d')!;
    const tmpCanvas = new OffscreenCanvas(src.width, src.height);
    const tmpCtx = tmpCanvas.getContext('2d')!;
    tmpCtx.putImageData(src, 0, 0);
    ctx.drawImage(tmpCanvas, crop.x, crop.y, crop.width, crop.height, 0, 0, crop.width, crop.height);
    const newImgData = ctx.getImageData(0, 0, crop.width, crop.height);
    sourceImageData.value = newImgData;
    processedImage.value = null;
    paletteColors.value = [];
    edgeDataSignal.value = null;
    isolatedBand.value = null;
    showCropOverlay.value = false;
    triggerProcessing();
  };

  const compositeOptions = {
    showTemperatureMap: showTemperatureMap.value,
    tempIntensity: 1.0,
    isolatedBand: isolatedBand.value,
    isolationThresholds: activeMode.value === 'value' ? valueConfig.value.thresholds : colorConfig.value.thresholds,
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

        {showCropOverlay.value && sourceImageData.value && (
          <CropOverlay
            imageWidth={sourceImageData.value.width}
            imageHeight={sourceImageData.value.height}
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
