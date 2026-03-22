import { useState, useEffect, useRef } from 'preact/hooks';
import type { GridConfig, EdgeConfig } from '../types';
import { GridSettings } from './GridSettings';
import { EdgeSettings } from './EdgeSettings';

interface Props {
  gridConfig: GridConfig;
  edgeConfig: EdgeConfig;
  showTemperatureMap: boolean;
  tempUseOriginal: boolean;
  onGridChange: (cfg: Partial<GridConfig>) => void;
  onEdgeChange: (cfg: Partial<EdgeConfig>) => void;
  onTemperatureMapChange: (enabled: boolean) => void;
  onTempUseOriginalChange: (useOriginal: boolean) => void;
}

export function OverlayToggles({ gridConfig, edgeConfig, showTemperatureMap, tempUseOriginal, onGridChange, onEdgeChange, onTemperatureMapChange, onTempUseOriginalChange }: Props) {
  const [showGridSettings, setShowGridSettings] = useState(false);
  const [showEdgeSettings, setShowEdgeSettings] = useState(false);
  const [showTempSettings, setShowTempSettings] = useState(false);
  const gridItemRef = useRef<HTMLDivElement>(null);
  const edgeItemRef = useRef<HTMLDivElement>(null);
  const tempItemRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!showGridSettings && !showEdgeSettings && !showTempSettings) return;
    const handleClickOutside = (e: MouseEvent) => {
      const target = e.target as Node;
      if (showGridSettings && gridItemRef.current && !gridItemRef.current.contains(target)) {
        setShowGridSettings(false);
      }
      if (showEdgeSettings && edgeItemRef.current && !edgeItemRef.current.contains(target)) {
        setShowEdgeSettings(false);
      }
      if (showTempSettings && tempItemRef.current && !tempItemRef.current.contains(target)) {
        setShowTempSettings(false);
      }
    };
    document.addEventListener('pointerdown', handleClickOutside);
    return () => document.removeEventListener('pointerdown', handleClickOutside);
  }, [showGridSettings, showEdgeSettings, showTempSettings]);

  return (
    <div class="overlay-bar">
      <div class="overlay-item" ref={gridItemRef}>
        <button
          class={`overlay-btn ${gridConfig.enabled ? 'active' : ''}`}
          onClick={() => onGridChange({ enabled: !gridConfig.enabled })}
          title="Toggle compositional grid overlay"
        >
          <svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
            <path d="M3 3h18v18H3zM3 9h18M3 15h18M9 3v18M15 3v18" />
          </svg>
          Grid
        </button>
        <button
          class={`overlay-settings-btn ${showGridSettings ? 'active' : ''}`}
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

      <div class="overlay-item" ref={edgeItemRef}>
        <button
          class={`overlay-btn ${edgeConfig.enabled ? 'active' : ''}`}
          onClick={() => onEdgeChange({ enabled: !edgeConfig.enabled })}
          title="Toggle edge detection overlay"
        >
          <svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
            <path d="M4 4l16 16M4 20L20 4" />
          </svg>
          Edges
        </button>
        <button
          class={`overlay-settings-btn ${showEdgeSettings ? 'active' : ''}`}
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

      <div class="overlay-item" ref={tempItemRef}>
        <button
          class={`overlay-btn ${showTemperatureMap ? 'active' : ''}`}
          onClick={() => onTemperatureMapChange(!showTemperatureMap)}
          title="Toggle warm/cool temperature map overlay"
        >
          <svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
            <path d="M14 14.76V3.5a2.5 2.5 0 00-5 0v11.26a4.5 4.5 0 105 0z"/>
          </svg>
          Temp
        </button>
        <button
          class={`overlay-settings-btn ${showTempSettings ? 'active' : ''}`}
          onClick={() => { setShowTempSettings(!showTempSettings); setShowGridSettings(false); setShowEdgeSettings(false); }}
          title="Temperature settings"
        >
          <svg width="14" height="14" fill="currentColor" viewBox="0 0 24 24">
            <path d="M12 15a3 3 0 100-6 3 3 0 000 6z"/>
            <path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-2 2 2 2 0 01-2-2v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83 0 2 2 0 010-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 01-2-2 2 2 0 012-2h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 010-2.83 2 2 0 012.83 0l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 012-2 2 2 0 012 2v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 0 2 2 0 010 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 012 2 2 2 0 01-2 2h-.09a1.65 1.65 0 00-1.51 1z"/>
          </svg>
        </button>
        {showTempSettings && (
          <div class="popover">
            <div class="settings-group">
              <div class="settings-row" title="Classify temperature from the original image instead of the simplified version">
                <label>Source</label>
                <select value={tempUseOriginal ? 'original' : 'simplified'} onChange={e => onTempUseOriginalChange((e.target as HTMLSelectElement).value === 'original')}>
                  <option value="simplified">Simplified</option>
                  <option value="original">Original</option>
                </select>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
