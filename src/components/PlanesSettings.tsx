import type { PlanesConfig } from '../types';

interface Props {
  config: PlanesConfig;
  onChange: (cfg: Partial<PlanesConfig>) => void;
}

export function PlanesSettings({ config, onChange }: Props) {
  return (
    <div class="settings-group">
      <div class="settings-row" title="Number of distinct plane groups to detect">
        <label>Planes</label>
        <input
          type="range" min="3" max="30" step="1" value={config.planeCount}
          onInput={e => onChange({ planeCount: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
        <span class="settings-value">{config.planeCount}</span>
      </div>

      <div class="settings-row" title="Amplify depth differences to reveal more surface detail">
        <label>Depth Scale</label>
        <input
          type="range" min="1" max="100" step="1" value={config.depthScale}
          onInput={e => onChange({ depthScale: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
        <span class="settings-value">{config.depthScale}</span>
      </div>

      <div class="settings-row" title="Compass direction the light comes from (225° = top-left)">
        <label>Light Azimuth</label>
        <input
          type="range" min="0" max="360" step="5" value={config.lightAzimuth}
          onInput={e => onChange({ lightAzimuth: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
        <span class="settings-value">{config.lightAzimuth}°</span>
      </div>

      <div class="settings-row" title="Height of the light source (90° = directly above)">
        <label>Light Elevation</label>
        <input
          type="range" min="10" max="90" step="5" value={config.lightElevation}
          onInput={e => onChange({ lightElevation: Number((e.target as HTMLInputElement).value) })}
          style="flex:1"
        />
        <span class="settings-value">{config.lightElevation}°</span>
      </div>

      <div class="settings-row" title="Merge small isolated plane fragments into neighbors">
        <label>Cleanup</label>
        <select
          value={config.minRegionSize}
          onChange={e => onChange({ minRegionSize: (e.target as HTMLSelectElement).value as PlanesConfig['minRegionSize'] })}
        >
          <option value="off">Off</option>
          <option value="small">Small</option>
          <option value="medium">Medium</option>
          <option value="large">Large</option>
        </select>
      </div>
    </div>
  );
}
