import { signal } from '@preact/signals';
import { useEffect, useRef } from 'preact/hooks';
import { ModeBar } from './components/ModeBar';
import { OverlayToggles } from './components/OverlayToggles';
import { ImageCanvas } from './components/ImageCanvas';
import { ValueSettings } from './components/ValueSettings';
import { ColorSettings } from './components/ColorSettings';
import { PlanesSettings } from './components/PlanesSettings';
import { PaletteStrip } from './components/PaletteStrip';
import { ActionBar } from './components/ActionBar';
import { CompareView } from './components/CompareView';
import { CropOverlay } from './components/CropOverlay';
import { SimplifySettings } from './components/SimplifySettings';
import { ErrorToast, showError } from './components/ErrorToast';
import { exportImage } from './export/export';
import { initInstallPrompt, triggerInstall } from './pwa/install-prompt';
import { getDefaultThresholds } from './processing/quantize';
import { useProcessingPipeline } from './hooks/useProcessingPipeline';
import type { Mode, GridConfig, EdgeConfig, ValueConfig, ColorConfig, SimplifyConfig, PlanesConfig } from './types';
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

function loadImageFromFile(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve(img);
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('Failed to decode image file'));
    };
    img.src = url;
  });
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
  lineWeight: 2,
  lineKnockoutColor: 'black',
  lineKnockoutCustomColor: '#000000',
  useOriginal: false,
};

const defaultValueConfig: ValueConfig = {
  levels: 3,
  thresholds: getDefaultThresholds(3),
  minRegionSize: 'small',
};

const defaultColorConfig: ColorConfig = {
  bands: 3,
  colorsPerBand: 2,
  warmCoolEmphasis: 0,
  thresholds: getDefaultThresholds(3),
  minRegionSize: 'small',
};

const defaultSimplifyConfig: SimplifyConfig = {
  method: 'none',
  strength: 0.5,
  shadowMerge: false,
  bilateral: { sigmaS: 10, sigmaR: 0.15 },
  kuwahara: { kernelSize: 7, passes: 1, sharpness: 8, sectors: 8 },
  meanShift: { spatialRadius: 15, colorRadius: 25 },
  anisotropic: { iterations: 10, kappa: 20 },
  painterly: {
    radius: 8, q: 8, alpha: 1.0, zeta: 1.0,
    tensorSigma: 2.0,
    sharpenAmount: 0.35, edgeThresholdLow: 0.03, edgeThresholdHigh: 0.12,
    detailSigma: 1.5,
  },
  slic: { detail: 0.55, compactness: 0.15 },
  superResolution: { scale: 4, sharpenAmount: 0.3 },
  ultrasharp: { downscale: 4 },
  planeGuidance: { preserveBoundaries: false },
};

const defaultPlanesConfig: PlanesConfig = {
  planeCount: 8,
  depthSmooth: 3,
  depthScale: 20,
  lightAzimuth: 225,
  lightElevation: 45,
  minRegionSize: 'small',
  colorMode: 'shading',
  colorStrategy: 'average',
};

const simplifyConfig = signal<SimplifyConfig>(defaultSimplifyConfig);

// originalImageData is never overwritten by crop — non-destructive crop derives sourceImageData from it.
const originalImageData = signal<ImageData | null>(null);
const sourceImageData = signal<ImageData | null>(null);
const activeMode = signal<Mode>('original');
const gridConfig = signal<GridConfig>(defaultGridConfig);
const edgeConfig = signal<EdgeConfig>(defaultEdgeConfig);
const valueConfig = signal<ValueConfig>(defaultValueConfig);
const colorConfig = signal<ColorConfig>(defaultColorConfig);
const showCompare = signal(false);
const showCropOverlay = signal(false);
const isolatedBand = signal<number | null>(null);
const showTemperatureMap = signal(false);
const planesConfig = signal<PlanesConfig>(defaultPlanesConfig);
const tempUseOriginal = signal(false);
const showInstallBanner = signal(false);

export function App() {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const displayCanvasRef = useRef<HTMLCanvasElement>(null);

  const {
    simplifiedImageData,
    processedImage,
    edgeData,
    isProcessing,
    processingProgress,
    paletteColors,
    swatchBands,
    resetProcessingState,
  } = useProcessingPipeline({
    sourceImageData,
    activeMode,
    simplifyConfig,
    valueConfig,
    colorConfig,
    edgeConfig,
    planesConfig,
    onError: showError,
  });

  useEffect(() => {
    initInstallPrompt(() => { showInstallBanner.value = true; });
  }, []);

  const handleFileChange = async (e: Event) => {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;

    let source: ImageBitmap | HTMLImageElement;
    try {
      source = await createImageBitmap(file);
    } catch {
      try {
        source = await loadImageFromFile(file);
      } catch {
        showError('Could not decode image file');
        return;
      }
    }

    let targetW = source.width;
    let targetH = source.height;
    if (Math.max(targetW, targetH) > MAX_WORKING_SIZE) {
      const scale = MAX_WORKING_SIZE / Math.max(targetW, targetH);
      targetW = Math.round(targetW * scale);
      targetH = Math.round(targetH * scale);
    }
    const canvas = makeCanvas(targetW, targetH);
    const ctx = canvas.getContext('2d') as CanvasRenderingContext2D;
    ctx.drawImage(source, 0, 0, targetW, targetH);
    if (typeof ImageBitmap !== 'undefined' && source instanceof ImageBitmap) {
      source.close();
    }
    const imgData = ctx.getImageData(0, 0, targetW, targetH);
    originalImageData.value = imgData;
    sourceImageData.value = imgData;
    resetProcessingState();
    isolatedBand.value = null;
  };

  const handleExport = async () => {
    const canvas = displayCanvasRef.current;
    if (!canvas) return;
    const modeSlug = activeMode.value === 'original' ? 'original' : activeMode.value;
    try {
      await exportImage(canvas, modeSlug);
    } catch (err) {
      showError('Export failed: ' + (err instanceof Error ? err.message : String(err)));
    }
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
    resetProcessingState();
    isolatedBand.value = null;
    showCropOverlay.value = false;
  };

  const compositeOptions = {
    showTemperatureMap: showTemperatureMap.value,
    tempIntensity: 1.0,
    originalSource: (tempUseOriginal.value ? sourceImageData.value : (simplifiedImageData.value ?? sourceImageData.value)) ?? undefined,
    isolatedBand: activeMode.value === 'color' ? isolatedBand.value : null,
    isolationThresholds: colorConfig.value.thresholds,
  };

  const displayBaseImage = simplifiedImageData.value ?? sourceImageData.value;

  const currentImageData = activeMode.value === 'original'
    ? displayBaseImage
    : (processedImage.value ?? displayBaseImage);
  const activeModeLabel = {
    original: 'Source',
    grayscale: 'Tonal',
    value: 'Value',
    color: 'Color',
    planes: 'Planes',
  }[activeMode.value];
  return (
    <div id="app-root" class="app-shell">
      <ErrorToast />
      {showInstallBanner.value && (
        <div class="install-banner">
          <div class="install-banner-copy">
            <span class="install-banner-kicker">Install</span>
            <strong>Add RefPlane to your home screen</strong>
            <span>Keep the studio one tap away for quick visual studies.</span>
          </div>
          <div class="install-banner-actions">
            <button
              class="btn-primary"
              onClick={async () => { await triggerInstall(); showInstallBanner.value = false; }}
            >
              Install
            </button>
            <button
              aria-label="Close install banner"
              class="btn-ghost"
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

      <div class="app-workspace">
        <div class="workspace-stage">
          <ImageCanvas
            sourceImageData={displayBaseImage}
            processedImageData={processedImage.value}
            activeMode={activeMode.value}
            gridConfig={gridConfig.value}
            edgeConfig={edgeConfig.value}
            edgeData={edgeData.value}
            isProcessing={isProcessing.value}
            onOpenImage={() => fileInputRef.current?.click()}
            externalRef={displayCanvasRef}
            compositeOptions={compositeOptions}
            processingProgress={processingProgress.value}
          />

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

        <aside class="control-panel">
          <div class="panel-header">
            <span class="panel-brand">RefPlane</span>
            <span class="panel-title-tag">{activeModeLabel}</span>
          </div>

          <div class="panel-body scrollable">
            <div class="bottom-sheet">
              <section class="panel-card">
                <div class="panel-card-header">
                  <div class="panel-card-title">
                    <strong>Simplify</strong>
                  </div>
                </div>
                <SimplifySettings
                  config={simplifyConfig.value}
                  onChange={(cfg) => { simplifyConfig.value = { ...simplifyConfig.value, ...cfg }; }}
                />
              </section>

              <section class="panel-card">
                <div class="panel-card-header">
                  <div class="panel-card-title">
                    <strong>Modes</strong>
                  </div>
                </div>
                <ModeBar
                  activeMode={activeMode.value}
                  onModeChange={(mode) => { activeMode.value = mode; }}
                />
              </section>

              {(activeMode.value === 'value' || activeMode.value === 'color' || activeMode.value === 'planes') && (
                <section class="panel-card">
                  <div class="panel-card-header">
                    <div class="panel-card-title">
                      <strong>Adjustments</strong>
                    </div>
                  </div>
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
                  {activeMode.value === 'planes' && (
                    <PlanesSettings
                      config={planesConfig.value}
                      onChange={(cfg) => { planesConfig.value = { ...planesConfig.value, ...cfg }; }}
                    />
                  )}
                </section>
              )}

              {activeMode.value === 'color' && paletteColors.value.length > 0 && (
                <section class="panel-card">
                  <div class="panel-card-header">
                    <div class="panel-card-title">
                      <strong>Palette</strong>
                    </div>
                    <span class="panel-chip">{paletteColors.value.length} tones</span>
                  </div>
                  <PaletteStrip
                    colors={paletteColors.value}
                    bands={swatchBands.value}
                    isolatedBand={isolatedBand.value}
                    onIsolate={(band) => { isolatedBand.value = band; }}
                  />
                </section>
              )}

              <section class="panel-card">
                <div class="panel-card-header">
                  <div class="panel-card-title">
                    <strong>Overlays</strong>
                  </div>
                </div>
                <OverlayToggles
                  gridConfig={gridConfig.value}
                  edgeConfig={edgeConfig.value}
                  showTemperatureMap={showTemperatureMap.value}
                  tempUseOriginal={tempUseOriginal.value}
                  onGridChange={(cfg) => { gridConfig.value = { ...gridConfig.value, ...cfg }; }}
                  onEdgeChange={(cfg) => { edgeConfig.value = { ...edgeConfig.value, ...cfg }; }}
                  onTemperatureMapChange={(enabled) => { showTemperatureMap.value = enabled; }}
                  onTempUseOriginalChange={(useOriginal) => { tempUseOriginal.value = useOriginal; }}
                />
              </section>

            </div>
          </div>
          <div class="panel-footer">
            <ActionBar
              hasImage={sourceImageData.value !== null}
              showCrop={showCropOverlay.value}
              showCompare={showCompare.value}
              onOpenImage={() => fileInputRef.current?.click()}
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
        </aside>
      </div>
    </div>
  );
}
