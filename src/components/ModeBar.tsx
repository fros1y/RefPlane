import type { Mode } from '../types';

interface Props {
  activeMode: Mode;
  onModeChange: (mode: Mode) => void;
}

const MODES: { id: Mode; label: string; hint: string }[] = [
  { id: 'original', label: 'Original', hint: 'Reference the untouched source.' },
  { id: 'grayscale', label: 'Grayscale', hint: 'Reduce the image to tonal structure.' },
  { id: 'value', label: 'Value Study', hint: 'Shape the scene into clear light groups.' },
  { id: 'color', label: 'Color Regions', hint: 'Organize palette clusters and temperature.' },
  { id: 'planes', label: 'Planes', hint: 'Decompose into spatially coherent color/value planes.' },
];

export function ModeBar({ activeMode, onModeChange }: Props) {
  return (
    <div class="mode-bar">
      {MODES.map(m => (
        <button
          key={m.id}
          class={`mode-tab ${activeMode === m.id ? 'active' : ''}`}
          onClick={() => onModeChange(m.id)}
          title={m.hint}
        >
          <span class="mode-tab-content">
            <span class="mode-tab-label">{m.label}</span>
            <span class="mode-tab-hint">{m.hint}</span>
          </span>
        </button>
      ))}
    </div>
  );
}
