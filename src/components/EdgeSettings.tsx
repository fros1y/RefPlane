import type { EdgeConfig, EdgeMethod, EdgeCompositeMode } from '../types';

interface Props {
  config: EdgeConfig;
  onChange: (cfg: Partial<EdgeConfig>) => void;
}

export function EdgeSettings({ config, onChange }: Props) {
  return (
    <div class="settings-group">
      <div class="settings-row">
        <label>Method</label>
        <select value={config.method} onChange={e => onChange({ method: (e.target as HTMLSelectElement).value as EdgeMethod })}>
          <option value="canny">Canny</option>
          <option value="sobel">Sobel</option>
          <option value="simplified">Simplified</option>
        </select>
      </div>

      {(config.method === 'canny' || config.method === 'simplified') && (
        <div class="settings-row">
          <label>Detail</label>
          <input
            type="range" min="0" max="1" step="0.05" value={config.detail}
            onInput={e => onChange({ detail: Number((e.target as HTMLInputElement).value) })}
            style="flex:1"
          />
        </div>
      )}

      {config.method === 'sobel' && (
        <div class="settings-row">
          <label>Sensitivity</label>
          <input
            type="range" min="0" max="1" step="0.05" value={config.sensitivity}
            onInput={e => onChange({ sensitivity: Number((e.target as HTMLInputElement).value) })}
            style="flex:1"
          />
        </div>
      )}

      <div class="settings-row">
        <label>Mode</label>
        <select value={config.compositeMode} onChange={e => onChange({ compositeMode: (e.target as HTMLSelectElement).value as EdgeCompositeMode })}>
          <option value="lines-over">Lines Over</option>
          <option value="edges-only">Edges Only</option>
          <option value="multiply">Multiply</option>
          <option value="knockout">Knockout</option>
        </select>
      </div>

      <div class="settings-row">
        <label>Opacity</label>
        <input
          type="range" min="0.1" max="1" step="0.05" value={config.lineOpacity}
          onInput={e => onChange({ lineOpacity: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
      </div>
    </div>
  );
}
