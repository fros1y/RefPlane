import type { SimplifyConfig } from '../types';

interface Props {
  config: SimplifyConfig;
  onChange: (cfg: Partial<SimplifyConfig>) => void;
}

export function SimplifySettings({ config, onChange }: Props) {
  return (
    <div class="settings-group">
      <div class="settings-row" title="Downscale factor before the 4× AI upscale — higher values produce a more abstracted result (2×–8×)">
        <label>Downscale</label>
        <input
          type="range" min="2" max="8" step="1" value={config.ultrasharp.downscale}
          onInput={e => onChange({ ultrasharp: { downscale: Number((e.target as HTMLInputElement).value) } })}
          style="flex:1"
        />
        <span class="settings-value">{config.ultrasharp.downscale}×</span>
      </div>
    </div>
  );
}
