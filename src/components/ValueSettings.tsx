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
    onChange({ levels: 2, thresholds: [0.5] });
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

      <div class="settings-row" title="Number of distinct value groups to create">
        <label>Levels</label>
        <input
          type="range" min="2" max="8" step="1" value={config.levels}
          onInput={e => handleLevelsChange(Number((e.target as HTMLInputElement).value))}
          style="flex:1"
        />
        <span class="settings-value">{config.levels}</span>
      </div>

      <div class="settings-row settings-row-split" title="Drag handles to adjust where value bands split">
        <label>Thresholds</label>
        <div style={{ width: '100%' }}>
          <ThresholdSlider
            thresholds={config.thresholds}
            onChange={(thresholds) => onChange({ thresholds })}
          />
        </div>
      </div>

      <div class="settings-row" title="Merge small isolated patches into neighboring regions">
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
