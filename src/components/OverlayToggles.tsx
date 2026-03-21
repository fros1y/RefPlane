import { useState } from 'preact/hooks';
import type { GridConfig, EdgeConfig } from '../types';
import { GridSettings } from './GridSettings';
import { EdgeSettings } from './EdgeSettings';

interface Props {
  gridConfig: GridConfig;
  edgeConfig: EdgeConfig;
  onGridChange: (cfg: Partial<GridConfig>) => void;
  onEdgeChange: (cfg: Partial<EdgeConfig>) => void;
}

export function OverlayToggles({ gridConfig, edgeConfig, onGridChange, onEdgeChange }: Props) {
  const [showGridSettings, setShowGridSettings] = useState(false);
  const [showEdgeSettings, setShowEdgeSettings] = useState(false);

  return (
    <div class="overlay-bar" style="position:relative">
      <div style="position:relative">
        <button
          class={`overlay-btn ${gridConfig.enabled ? 'active' : ''}`}
          onClick={() => onGridChange({ enabled: !gridConfig.enabled })}
        >
          <svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
            <path d="M3 3h18v18H3zM3 9h18M3 15h18M9 3v18M15 3v18" />
          </svg>
          Grid
        </button>
        <button
          class="btn-ghost"
          style="min-width:24px;min-height:24px;padding:2px;margin-left:2px"
          onClick={() => { setShowGridSettings(!showGridSettings); setShowEdgeSettings(false); }}
          title="Grid settings"
        >
          <svg width="14" height="14" fill="currentColor" viewBox="0 0 24 24">
            <path d="M12 15a3 3 0 100-6 3 3 0 000 6z"/>
            <path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-2 2 2 2 0 01-2-2v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83 0 2 2 0 010-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 01-2-2 2 2 0 012-2h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 010-2.83 2 2 0 012.83 0l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 012-2 2 2 0 012 2v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 0 2 2 0 010 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 012 2 2 2 0 01-2 2h-.09a1.65 1.65 0 00-1.51 1z"/>
          </svg>
        </button>
        {showGridSettings && (
          <div class="popover">
            <GridSettings config={gridConfig} onChange={onGridChange} />
          </div>
        )}
      </div>

      <div style="position:relative">
        <button
          class={`overlay-btn ${edgeConfig.enabled ? 'active' : ''}`}
          onClick={() => onEdgeChange({ enabled: !edgeConfig.enabled })}
        >
          <svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
            <path d="M4 4l16 16M4 20L20 4" />
          </svg>
          Edges
        </button>
        <button
          class="btn-ghost"
          style="min-width:24px;min-height:24px;padding:2px;margin-left:2px"
          onClick={() => { setShowEdgeSettings(!showEdgeSettings); setShowGridSettings(false); }}
          title="Edge settings"
        >
          <svg width="14" height="14" fill="currentColor" viewBox="0 0 24 24">
            <path d="M12 15a3 3 0 100-6 3 3 0 000 6z"/>
            <path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-2 2 2 2 0 01-2-2v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83 0 2 2 0 010-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 01-2-2 2 2 0 012-2h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 010-2.83 2 2 0 012.83 0l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 012-2 2 2 0 012 2v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 0 2 2 0 010 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 012 2 2 2 0 01-2 2h-.09a1.65 1.65 0 00-1.51 1z"/>
          </svg>
        </button>
        {showEdgeSettings && (
          <div class="popover">
            <EdgeSettings config={edgeConfig} onChange={onEdgeChange} />
          </div>
        )}
      </div>
    </div>
  );
}
