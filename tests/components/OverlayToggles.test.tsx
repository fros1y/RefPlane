import { fireEvent, render, screen } from '@testing-library/preact';
import { describe, expect, it, vi } from 'vitest';
import { OverlayToggles } from '../../src/components/OverlayToggles';

describe('OverlayToggles', () => {
  it('toggles the grid overlay and opens grid settings', () => {
    const onGridChange = vi.fn();

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
        onGridChange={onGridChange}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: /^Grid$/i }));
    fireEvent.click(screen.getByTitle('Grid settings'));

    expect(onGridChange).toHaveBeenCalledWith({ enabled: true });
    expect(screen.getByText('Divisions')).toBeInTheDocument();
  });
});
