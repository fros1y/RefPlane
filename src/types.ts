export type Mode = "original" | "grayscale" | "value" | "color" | "planes";
export type EdgeMethod = "canny" | "sobel";
export type EdgeCompositeMode = "lines-over" | "edges-only" | "multiply" | "knockout";
export type LineStyle = "auto-contrast" | "black" | "white" | "custom";
export type CellAspect = "square" | "match-image";

export interface CropState {
  x: number; y: number; width: number; height: number;
}

export interface GridConfig {
  enabled: boolean;
  divisions: number;
  cellAspect: CellAspect;
  showDiagonals: boolean;
  showCenterLines: boolean;
  lineStyle: LineStyle;
  customColor: string;
  opacity: number;
}

export interface EdgeConfig {
  enabled: boolean;
  method: EdgeMethod;
  detail: number;
  sensitivity: number;
  compositeMode: EdgeCompositeMode;
  lineColor: "black" | "white" | "custom";
  lineCustomColor: string;
  lineOpacity: number;
  edgesOnlyPolarity: "dark-on-light" | "light-on-dark";
  lineWeight: number;
  lineKnockoutColor: "black" | "dark-gray" | "custom";
  lineKnockoutCustomColor: string;
  useOriginal: boolean;
}

export interface ValueConfig {
  levels: number;
  thresholds: number[];
  minRegionSize: "off" | "small" | "medium" | "large";
}

export interface ColorConfig {
  bands: number;
  colorsPerBand: number;
  warmCoolEmphasis: number;
  thresholds: number[];
  minRegionSize: "off" | "small" | "medium" | "large";
}

export type PlanesColorMode = 'shading' | 'flat-color';

export type PlanesConfig = {
  planeCount: number;        // 3–30, default 8
  depthSmooth: number;       // 0–10, bilateral smoothing passes on depth map (0 = off)
  depthScale: number;        // 1–100, amplifies depth differences for normal computation
  lightAzimuth: number;      // 0–360 degrees, default 225 (top-left)
  lightElevation: number;    // 10–90 degrees, default 45
  minRegionSize: "off" | "small" | "medium" | "large";
  colorMode: PlanesColorMode;       // 'shading' (directional light) or 'flat-color' (representative color per plane)
  colorStrategy: PlaneColorStrategy; // used when colorMode === 'flat-color'
}

export type PlaneColorStrategy = 'average' | 'median' | 'dominant';

export interface PlaneGuidance {
  width: number;
  height: number;
  labels: Uint8Array;
  planeCount: number;
}

export type SimplifyMethod = "none" | "bilateral" | "kuwahara" | "mean-shift" | "anisotropic" | "painterly" | "slic" | "super-resolution";

export interface SimplifyConfig {
  method: SimplifyMethod;
  strength: number;
  shadowMerge?: boolean;
  bilateral: { sigmaS: number; sigmaR: number };
  kuwahara: { kernelSize: number; passes: number; sharpness: number; sectors: 4 | 8 };
  meanShift: { spatialRadius: number; colorRadius: number };
  anisotropic: { iterations: number; kappa: number };
  painterly: {
    radius: number; q: number; alpha: number; zeta: number;
    tensorSigma: number;
    sharpenAmount: number; edgeThresholdLow: number; edgeThresholdHigh: number;
    detailSigma: number;
  };
  slic: { detail: number; compactness: number };
  superResolution: { scale: number; sharpenAmount: number };
  planeGuidance: { preserveBoundaries: boolean };
}

export interface AppState {
  sourceImage: ImageBitmap | null;
  crop: CropState | null;
  workingImageData: ImageData | null;
  activeMode: Mode;
  processedImage: ImageData | null;
  gridConfig: GridConfig;
  edgeConfig: EdgeConfig;
  valueConfig: ValueConfig;
  colorConfig: ColorConfig;
  isProcessing: boolean;
  paletteColors: string[];
  showCrop: boolean;
  showCompare: boolean;
  isolatedBand: number | null;
  showTemperatureMap: boolean;
}
