interface Props {
  colors: string[];
}

export function PaletteStrip({ colors }: Props) {
  if (colors.length === 0) return null;

  const copyColor = (hex: string) => {
    navigator.clipboard?.writeText(hex).catch(() => {});
  };

  return (
    <div class="palette-strip">
      {colors.map((color, i) => (
        <div
          key={i}
          class="palette-swatch"
          style={{ backgroundColor: color }}
          title={color}
          onClick={() => copyColor(color)}
        />
      ))}
    </div>
  );
}
