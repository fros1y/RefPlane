import type { ValueConfig } from '../types';
import { getDefaultThresholds } from '../processing/quantize';
import { ThresholdSlider } from './ThresholdSlider';

interface Props {
  config: ValueConfig;
  onChange: (cfg: Partial<ValueConfig>) => void;
}

export function ValueSettings({ config, onChange }: Props) {
  const handleLevelsChange = (levels: number) => {
    onChange({ levels, thresholds: getDefaultThresholds(levels) });
  };

  const applyNotan = () => {
    onChange({ levels: 2, strength: 0.8, thresholds: [0.5] });
  };

  return (
    <div class="settings-group">
      <div class="settings-row settings-actions">
        <button
          class="btn-ghost"
          style={{ fontSize: '11px', padding: '4px 12px', borderRadius: '999px' }}
          onClick={applyNotan}
          title="Set 2-tone Notan preset"
        >
          Notan
        </button>
      </div>

      <div class="settings-row">
        <label>Levels</label>
        <input
          type="range" min="2" max="8" step="1" value={config.levels}
          onInput={e => handleLevelsChange(Number((e.target as HTMLInputElement).value))}
          style="flex:1"
        />
        <span class="settings-value">{config.levels}</span>
      </div>

      <div class="settings-row settings-row-split">
        <label>Thresholds</label>
        <div style={{ width: '100%' }}>
          <ThresholdSlider
            thresholds={config.thresholds}
            onChange={(thresholds) => onChange({ thresholds })}
          />
        </div>
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
        <label>Min Region</label>
        <select value={config.minRegionSize} onChange={e => onChange({ minRegionSize: (e.target as HTMLSelectElement).value as ValueConfig['minRegionSize'] })}>
          <option value="off">Off</option>
          <option value="small">Small</option>
          <option value="medium">Medium</option>
          <option value="large">Large</option>
        </select>
      </div>
    </div>
  );
}
