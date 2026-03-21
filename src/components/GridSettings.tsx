import type { GridConfig, CellAspect, LineStyle } from '../types';

interface Props {
  config: GridConfig;
  onChange: (cfg: Partial<GridConfig>) => void;
}

export function GridSettings({ config, onChange }: Props) {
  return (
    <div class="settings-group">
      <div class="settings-row">
        <label>Divisions</label>
        <input
          type="range" min="2" max="20" value={config.divisions}
          onInput={e => onChange({ divisions: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
        <span style="min-width:20px;text-align:right">{config.divisions}</span>
      </div>

      <div class="settings-row">
        <label>Cell Shape</label>
        <select value={config.cellAspect} onChange={e => onChange({ cellAspect: (e.target as HTMLSelectElement).value as CellAspect })}>
          <option value="square">Square</option>
          <option value="match-image">Match Image</option>
        </select>
      </div>

      <div class="settings-row">
        <label>Line Style</label>
        <select value={config.lineStyle} onChange={e => onChange({ lineStyle: (e.target as HTMLSelectElement).value as LineStyle })}>
          <option value="auto-contrast">Auto Contrast</option>
          <option value="black">Black</option>
          <option value="white">White</option>
          <option value="custom">Custom</option>
        </select>
        {config.lineStyle === 'custom' && (
          <input type="color" value={config.customColor} onInput={e => onChange({ customColor: (e.target as HTMLInputElement).value })} />
        )}
      </div>

      <div class="settings-row">
        <label>Opacity</label>
        <input
          type="range" min="0.1" max="1" step="0.05" value={config.opacity}
          onInput={e => onChange({ opacity: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
      </div>

      <div class="settings-row">
        <label>
          <input type="checkbox" checked={config.showDiagonals} onChange={e => onChange({ showDiagonals: (e.target as HTMLInputElement).checked })} />
          {' '}Diagonals
        </label>
        <label>
          <input type="checkbox" checked={config.showCenterLines} onChange={e => onChange({ showCenterLines: (e.target as HTMLInputElement).checked })} />
          {' '}Center Lines
        </label>
      </div>
    </div>
  );
}
