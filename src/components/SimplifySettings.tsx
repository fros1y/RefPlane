import type { SimplifyConfig, SimplifyMethod } from '../types';
import { strengthToMethodParams } from '../processing/simplify/params';
import { useState } from 'preact/hooks';

interface Props {
  config: SimplifyConfig;
  onChange: (cfg: Partial<SimplifyConfig>) => void;
}

const methodLabels: Record<SimplifyMethod, string> = {
  'none': 'None',
  'bilateral': 'Bilateral',
  'kuwahara': 'Kuwahara',
  'mean-shift': 'Mean-Shift',
  'anisotropic': 'Anisotropic',
  'painterly': 'Painterly',
  'slic': 'SLIC Planes',
};

export function SimplifySettings({ config, onChange }: Props) {
  const [showAdvanced, setShowAdvanced] = useState(false);

  const handleMethodChange = (method: SimplifyMethod) => {
    const params = strengthToMethodParams(method, config.strength);
    const update: Partial<SimplifyConfig> = { method };
    switch (method) {
      case 'bilateral':
        update.bilateral = { sigmaS: params.sigmaS, sigmaR: params.sigmaR };
        break;
      case 'kuwahara':
        update.kuwahara = { kernelSize: params.kernelSize, passes: params.passes, sharpness: params.sharpness, sectors: params.sectors as 4 | 8 };
        break;
      case 'mean-shift':
        update.meanShift = { spatialRadius: params.spatialRadius, colorRadius: params.colorRadius };
        break;
      case 'anisotropic':
        update.anisotropic = { iterations: params.iterations, kappa: params.kappa };
        break;
      case 'painterly':
        update.painterly = params as SimplifyConfig['painterly'];
        break;
      case 'slic':
        update.slic = { detail: params.detail, compactness: params.compactness };
        break;
    }
    onChange(update);
  };

  const handleStrengthChange = (strength: number) => {
    const params = strengthToMethodParams(config.method, strength);
    const update: Partial<SimplifyConfig> = { strength };
    switch (config.method) {
      case 'bilateral':
        update.bilateral = { sigmaS: params.sigmaS, sigmaR: params.sigmaR };
        break;
      case 'kuwahara':
        update.kuwahara = { ...config.kuwahara, kernelSize: params.kernelSize };
        break;
      case 'mean-shift':
        update.meanShift = { spatialRadius: params.spatialRadius, colorRadius: params.colorRadius };
        break;
      case 'anisotropic':
        update.anisotropic = { iterations: params.iterations, kappa: params.kappa };
        break;
      case 'painterly':
        update.painterly = params as SimplifyConfig['painterly'];
        break;
      case 'slic':
        update.slic = { detail: params.detail, compactness: params.compactness };
        break;
    }
    onChange(update);
  };

  return (
    <div class="settings-group">
      <div class="settings-row" title="Image simplification algorithm">
        <label>Method</label>
        <select
          value={config.method}
          onChange={e => handleMethodChange((e.target as HTMLSelectElement).value as SimplifyMethod)}
        >
          {Object.entries(methodLabels).map(([value, label]) => (
            <option key={value} value={value}>{label}</option>
          ))}
        </select>
      </div>

      {config.method !== 'none' && config.method !== 'slic' && (
        <>
          <div class="settings-row" title="Overall simplification intensity">
            <label>Strength</label>
            <input
              type="range" min="0" max="1" step="0.05" value={config.strength}
              onInput={e => handleStrengthChange(Number((e.target as HTMLInputElement).value))}
              style="flex:1"
            />
          </div>

          <div class="settings-row settings-row-split" title="Merge dark shadow areas into flatter value groups while keeping mids and lights more detailed">
            <label>Band Merge</label>
            <div class="settings-toggle-group">
              <label class="settings-check">
                <input
                  type="checkbox"
                  checked={Boolean(config.shadowMerge)}
                  onChange={e => onChange({ shadowMerge: (e.target as HTMLInputElement).checked })}
                />
                {' '}Shadow Merge
              </label>
            </div>
          </div>

          <div class="settings-row settings-actions">
            <button
              class="btn-ghost"
              style={{ fontSize: '11px', padding: '4px 12px', borderRadius: '999px' }}
              onClick={() => setShowAdvanced(!showAdvanced)}
            >
              {showAdvanced ? '▼ Advanced' : '▶ Advanced'}
            </button>
          </div>

          {showAdvanced && config.method === 'bilateral' && (
            <>
              <div class="settings-row" title="Spatial spread of the filter kernel">
                <label>Sigma S</label>
                <input
                  type="range" min="1" max="30" step="0.5" value={config.bilateral.sigmaS}
                  onInput={e => onChange({ bilateral: { ...config.bilateral, sigmaS: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.bilateral.sigmaS.toFixed(1)}</span>
              </div>
              <div class="settings-row" title="Range tolerance — how similar values must be to be smoothed together">
                <label>Sigma R</label>
                <input
                  type="range" min="0.01" max="0.5" step="0.01" value={config.bilateral.sigmaR}
                  onInput={e => onChange({ bilateral: { ...config.bilateral, sigmaR: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.bilateral.sigmaR.toFixed(2)}</span>
              </div>
            </>
          )}

          {showAdvanced && config.method === 'kuwahara' && (
            <>
              <div class="settings-row" title="Size of the sampling regions">
                <label>Kernel</label>
                <input
                  type="range" min="3" max="15" step="2" value={config.kuwahara.kernelSize}
                  onInput={e => onChange({ kuwahara: { ...config.kuwahara, kernelSize: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.kuwahara.kernelSize}</span>
              </div>
              <div class="settings-row" title="Classic 4 rectangular quadrants or generalized 8 overlapping circular sectors (smoother, fewer artifacts)">
                <label>Sectors</label>
                <select
                  value={config.kuwahara.sectors}
                  onChange={e => onChange({ kuwahara: { ...config.kuwahara, sectors: Number((e.target as HTMLSelectElement).value) as 4 | 8 } })}
                >
                  <option value={4}>4 (Classic)</option>
                  <option value={8}>8 (Generalized)</option>
                </select>
              </div>
              <div class="settings-row" title="Number of filter passes — more passes produce a stronger painterly effect">
                <label>Passes</label>
                <input
                  type="range" min="1" max="5" step="1" value={config.kuwahara.passes}
                  onInput={e => onChange({ kuwahara: { ...config.kuwahara, passes: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.kuwahara.passes}</span>
              </div>
              <div class="settings-row" title="Sector blending — low values blend softly across regions, high values select the single smoothest sector">
                <label>Sharpness</label>
                <input
                  type="range" min="1" max="20" step="1" value={config.kuwahara.sharpness}
                  onInput={e => onChange({ kuwahara: { ...config.kuwahara, sharpness: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.kuwahara.sharpness}</span>
              </div>
            </>
          )}

          {showAdvanced && config.method === 'mean-shift' && (
            <>
              <div class="settings-row" title="Pixel neighborhood radius">
                <label>Spatial R</label>
                <input
                  type="range" min="2" max="40" step="1" value={config.meanShift.spatialRadius}
                  onInput={e => onChange({ meanShift: { ...config.meanShift, spatialRadius: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.meanShift.spatialRadius}</span>
              </div>
              <div class="settings-row" title="Color similarity threshold">
                <label>Color R</label>
                <input
                  type="range" min="5" max="60" step="1" value={config.meanShift.colorRadius}
                  onInput={e => onChange({ meanShift: { ...config.meanShift, colorRadius: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.meanShift.colorRadius}</span>
              </div>
            </>
          )}

          {showAdvanced && config.method === 'anisotropic' && (
            <>
              <div class="settings-row" title="Number of diffusion passes">
                <label>Iterations</label>
                <input
                  type="range" min="1" max="30" step="1" value={config.anisotropic.iterations}
                  onInput={e => onChange({ anisotropic: { ...config.anisotropic, iterations: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.anisotropic.iterations}</span>
              </div>
              <div class="settings-row" title="Edge sensitivity — lower values preserve more edges">
                <label>Kappa</label>
                <input
                  type="range" min="5" max="40" step="1" value={config.anisotropic.kappa}
                  onInput={e => onChange({ anisotropic: { ...config.anisotropic, kappa: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.anisotropic.kappa}</span>
              </div>
            </>
          )}

          {showAdvanced && config.method === 'painterly' && (
            <>
              <div class="settings-row" title="Filter kernel radius — larger = more abstraction">
                <label>Radius</label>
                <input
                  type="range" min="3" max="15" step="1" value={config.painterly.radius}
                  onInput={e => onChange({ painterly: { ...config.painterly, radius: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.painterly.radius}</span>
              </div>
              <div class="settings-row" title="Edge sharpening intensity">
                <label>Sharpen</label>
                <input
                  type="range" min="0" max="1" step="0.05" value={config.painterly.sharpenAmount}
                  onInput={e => onChange({ painterly: { ...config.painterly, sharpenAmount: Number((e.target as HTMLInputElement).value) } })}
                  style="flex:1"
                />
                <span class="settings-value">{config.painterly.sharpenAmount.toFixed(2)}</span>
              </div>
            </>
          )}
        </>
      )}

      {config.method === 'slic' && (
        <>
          <div class="settings-row" title="Number of planes: Bold (few large planes) to Fine (many small planes)">
            <label>Detail</label>
            <span class="settings-endpoint">Bold</span>
            <input
              type="range" min="0" max="1" step="0.05" value={config.slic.detail}
              onInput={e => onChange({ slic: { ...config.slic, detail: Number((e.target as HTMLInputElement).value) } })}
              style="flex:1"
            />
            <span class="settings-endpoint">Fine</span>
          </div>
          <div class="settings-row" title="Shape of planes: Organic (follows edges closely) to Regular (grid-like)">
            <label>Compactness</label>
            <span class="settings-endpoint">Organic</span>
            <input
              type="range" min="0" max="1" step="0.05" value={config.slic.compactness}
              onInput={e => onChange({ slic: { ...config.slic, compactness: Number((e.target as HTMLInputElement).value) } })}
              style="flex:1"
            />
            <span class="settings-endpoint">Regular</span>
          </div>
        </>
      )}
    </div>
  );
}
