import { fireEvent, render, screen } from '@testing-library/preact';
import { describe, expect, it, vi } from 'vitest';
import { OverlayToggles } from '../../src/components/OverlayToggles';

describe('OverlayToggles', () => {
  it('toggles edge and temperature overlays and opens edge settings', () => {
    const onGridChange = vi.fn();
    const onEdgeChange = vi.fn();
    const onTemperatureMapChange = vi.fn();
    const onTempUseOriginalChange = vi.fn();

    render(
      <OverlayToggles
        gridConfig={{
          enabled: false,
          divisions: 4,
          cellAspect: 'square',
          showDiagonals: false,
          showCenterLines: false,
          lineStyle: 'auto-contrast',
          customColor: '#ffffff',
          opacity: 0.7,
        }}
        edgeConfig={{
          enabled: false,
          method: 'canny',
          detail: 0.5,
          sensitivity: 0.5,
          compositeMode: 'lines-over',
          lineColor: 'black',
          lineCustomColor: '#000000',
          lineOpacity: 0.8,
          edgesOnlyPolarity: 'dark-on-light',
          lineWeight: 2,
          lineKnockoutColor: 'black',
          lineKnockoutCustomColor: '#000000',
          useOriginal: false,
        }}
        showTemperatureMap={false}
        tempUseOriginal={false}
        onGridChange={onGridChange}
        onEdgeChange={onEdgeChange}
        onTemperatureMapChange={onTemperatureMapChange}
        onTempUseOriginalChange={onTempUseOriginalChange}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: /^Edges$/i }));
    fireEvent.click(screen.getByRole('button', { name: /^Temp$/i }));
    fireEvent.click(screen.getByTitle('Edge settings'));

    expect(onEdgeChange).toHaveBeenCalledWith({ enabled: true });
    expect(onTemperatureMapChange).toHaveBeenCalledWith(true);
    expect(screen.getByText('Line Weight')).toBeInTheDocument();
  });
});
