interface Props {
  colors: string[];
  /** Maps each swatch index to its value band index (0..bands-1).
   *  When omitted, the swatch index is used as the band index. */
  bands?: number[];
  isolatedBand?: number | null;
  onIsolate?: (band: number | null) => void;
}

export function PaletteStrip({ colors, bands, isolatedBand, onIsolate }: Props) {
  if (colors.length === 0) return null;

  const copyColor = (hex: string) => {
    navigator.clipboard?.writeText(hex).catch(() => {});
  };

  const getBandForIndex = (i: number): number =>
    (bands && bands.length === colors.length && i >= 0 && i < bands.length) ? bands[i] : i;

  const handleClick = (i: number) => {
    copyColor(colors[i]);
    if (onIsolate) {
      const band = getBandForIndex(i);
      onIsolate(isolatedBand === band ? null : band);
    }
  };

  return (
    <div class="palette-strip">
      {colors.map((color, i) => {
        const band = getBandForIndex(i);
        const isIsolated = isolatedBand === band;
        const isDimmed = isolatedBand != null && !isIsolated;
        return (
          <div
            key={i}
            class="palette-swatch"
            style={{
              backgroundColor: color,
              outline: isIsolated ? '2px solid #5b8def' : 'none',
              outlineOffset: '-2px',
              opacity: isDimmed ? 0.45 : 1,
              transition: 'opacity 0.15s, outline 0.15s',
            }}
            title={color}
            onClick={() => handleClick(i)}
          />
        );
      })}
    </div>
  );
}
