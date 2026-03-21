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
import { exportImage } from './export/export';
import { getDefaultThresholds } from './processing/quantize';
import type { Mode, GridConfig, EdgeConfig, ValueConfig, ColorConfig } from './types';
import './styles/global.css';

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

export function App() {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const displayCanvasRef = useRef<HTMLCanvasElement>(null);
  const workerRef = useRef<Worker | null>(null);

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
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const ctx = canvas.getContext('2d')!;
    ctx.drawImage(bitmap, 0, 0);
    const imgData = ctx.getImageData(0, 0, bitmap.width, bitmap.height);
    sourceImageData.value = imgData;
    processedImage.value = null;
    paletteColors.value = [];
    edgeDataSignal.value = null;
    triggerProcessing();
  };

  const handleExport = async () => {
    if (!displayCanvasRef.current) return;
    await exportImage(displayCanvasRef.current);
  };

  const currentImageData = activeMode.value === 'original'
    ? sourceImageData.value
    : (processedImage.value ?? sourceImageData.value);

  return (
    <div id="app-root" style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
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
          onGridChange={(cfg) => { gridConfig.value = { ...gridConfig.value, ...cfg }; }}
          onEdgeChange={(cfg) => { edgeConfig.value = { ...edgeConfig.value, ...cfg }; }}
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
          <PaletteStrip colors={paletteColors.value} />
        )}

        <ActionBar
          hasImage={sourceImageData.value !== null}
          showCrop={false}
          showCompare={showCompare.value}
          onCrop={() => fileInputRef.current?.click()}
          onCompare={() => { showCompare.value = !showCompare.value; }}
          onExport={handleExport}
        />
      </div>

      <canvas ref={displayCanvasRef} style={{ display: 'none' }} aria-hidden="true" />
    </div>
  );
}
