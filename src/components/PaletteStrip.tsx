interface Props {
  colors: string[];
  isolatedBand?: number | null;
  onIsolate?: (band: number | null) => void;
}

export function PaletteStrip({ colors, isolatedBand, onIsolate }: Props) {
  if (colors.length === 0) return null;

  const copyColor = (hex: string) => {
    navigator.clipboard?.writeText(hex).catch(() => {});
  };

  const handleClick = (i: number) => {
    copyColor(colors[i]);
    if (onIsolate) {
      onIsolate(isolatedBand === i ? null : i);
    }
  };

  return (
    <div class="palette-strip">
      {colors.map((color, i) => (
        <div
          key={i}
          class="palette-swatch"
          style={{
            backgroundColor: color,
            outline: isolatedBand === i ? '2px solid #5b8def' : 'none',
            outlineOffset: '-2px',
            opacity: (isolatedBand != null && isolatedBand !== i) ? 0.45 : 1,
            transition: 'opacity 0.15s, outline 0.15s',
          }}
          title={color}
          onClick={() => handleClick(i)}
        />
      ))}
    </div>
  );
}
