import { fireEvent, render, screen } from '@testing-library/preact';
import { describe, expect, it, vi } from 'vitest';
import { ModeBar } from '../../src/components/ModeBar';

describe('ModeBar', () => {
  it('renders all study modes and dispatches selection changes', () => {
    const onModeChange = vi.fn();
    render(<ModeBar activeMode="original" onModeChange={onModeChange} />);

    fireEvent.click(screen.getByRole('button', { name: /Value Study/i }));

    expect(screen.getByRole('button', { name: /Color Regions/i })).toBeInTheDocument();
    expect(onModeChange).toHaveBeenCalledWith('value');
  });
});
