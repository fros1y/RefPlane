import type { PlanesConfig } from '../types';

interface Props {
  config: PlanesConfig;
  onChange: (cfg: Partial<PlanesConfig>) => void;
}

export function PlanesSettings({ config, onChange }: Props) {
  return (
    <div class="settings-group">
      <div class="settings-row" title="Number of planes: Bold (few large planes) to Fine (many small planes)">
        <label>Detail</label>
        <span class="settings-endpoint">Bold</span>
        <input
          type="range" min="0" max="1" step="0.05" value={config.detail}
          onInput={e => onChange({ detail: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
        <span class="settings-endpoint">Fine</span>
      </div>

      <div class="settings-row" title="Shape of planes: Organic (follows edges closely) to Regular (grid-like)">
        <label>Compactness</label>
        <span class="settings-endpoint">Organic</span>
        <input
          type="range" min="0" max="1" step="0.05" value={config.compactness}
          onInput={e => onChange({ compactness: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
        <span class="settings-endpoint">Regular</span>
      </div>
    </div>
  );
}
