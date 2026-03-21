import type { ColorConfig } from '../types';
import { getDefaultThresholds } from '../processing/quantize';

interface Props {
  config: ColorConfig;
  onChange: (cfg: Partial<ColorConfig>) => void;
}

export function ColorSettings({ config, onChange }: Props) {
  const handleBandsChange = (bands: number) => {
    onChange({ bands, thresholds: getDefaultThresholds(bands) });
  };

  return (
    <div class="settings-group">
      <div class="settings-row">
        <label>Value Bands</label>
        <input
          type="range" min="2" max="6" step="1" value={config.bands}
          onInput={e => handleBandsChange(Number((e.target as HTMLInputElement).value))}
          style="flex:1"
        />
        <span style="min-width:16px;text-align:right">{config.bands}</span>
      </div>

      <div class="settings-row">
        <label>Colors/Band</label>
        <input
          type="range" min="1" max="4" step="1" value={config.colorsPerBand}
          onInput={e => onChange({ colorsPerBand: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
        <span style="min-width:16px;text-align:right">{config.colorsPerBand}</span>
      </div>

      <div class="settings-row">
        <label>Smoothing</label>
        <input
          type="range" min="0" max="1" step="0.05" value={config.strength}
          onInput={e => onChange({ strength: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
      </div>

      <div class="settings-row">
        <label>Warm/Cool</label>
        <input
          type="range" min="0" max="1" step="0.05" value={config.warmCoolEmphasis}
          onInput={e => onChange({ warmCoolEmphasis: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
      </div>

      <div class="settings-row">
        <label>Min Region</label>
        <select value={config.minRegionSize} onChange={e => onChange({ minRegionSize: (e.target as HTMLSelectElement).value as ColorConfig['minRegionSize'] })}>
          <option value="off">Off</option>
          <option value="small">Small</option>
          <option value="medium">Medium</option>
          <option value="large">Large</option>
        </select>
      </div>
    </div>
  );
}
