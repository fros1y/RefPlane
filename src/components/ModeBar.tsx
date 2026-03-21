import type { Mode } from '../types';

interface Props {
  activeMode: Mode;
  onModeChange: (mode: Mode) => void;
}

const MODES: { id: Mode; label: string }[] = [
  { id: 'original', label: 'Original' },
  { id: 'grayscale', label: 'Grayscale' },
  { id: 'value', label: 'Value Study' },
  { id: 'color', label: 'Color Regions' },
];

export function ModeBar({ activeMode, onModeChange }: Props) {
  return (
    <div class="mode-bar">
      {MODES.map(m => (
        <button
          key={m.id}
          class={`mode-tab ${activeMode === m.id ? 'active' : ''}`}
          onClick={() => onModeChange(m.id)}
        >
          {m.label}
        </button>
      ))}
    </div>
  );
}
