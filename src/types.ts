export type Mode = "original" | "grayscale" | "value" | "color";
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

export type SimplifyMethod = "ultrasharp";

export interface SimplifyConfig {
  method: SimplifyMethod;
  ultrasharp: { downscale: number };
}
