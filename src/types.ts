export type Mode = "original" | "grayscale" | "value" | "color";
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

export type SimplifyMethod = "none" | "bilateral" | "kuwahara" | "mean-shift" | "anisotropic" | "painterly" | "slic";

export interface SimplifyConfig {
  method: SimplifyMethod;
  strength: number;
  bilateral: { sigmaS: number; sigmaR: number };
  kuwahara: { kernelSize: number };
  meanShift: { spatialRadius: number; colorRadius: number };
  anisotropic: { iterations: number; kappa: number };
  painterly: {
    radius: number; q: number; alpha: number; zeta: number;
    tensorSigma: number;
    sharpenAmount: number; edgeThresholdLow: number; edgeThresholdHigh: number;
    detailSigma: number;
    saturation: number; contrast: number; gamma: number; highlightCompression: number;
  };
  slic: { compactness: number };
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
