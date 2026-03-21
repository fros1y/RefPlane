export type Mode = "original" | "grayscale" | "value" | "color";
export type EdgeMethod = "canny" | "sobel" | "simplified";
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
  strength: number;
  thresholds: number[];
  minRegionSize: "off" | "small" | "medium" | "large";
}

export interface ColorConfig {
  bands: number;
  colorsPerBand: number;
  strength: number;
  warmCoolEmphasis: number;
  thresholds: number[];
  minRegionSize: "off" | "small" | "medium" | "large";
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
