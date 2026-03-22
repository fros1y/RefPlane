import { fireEvent, render, screen } from '@testing-library/preact';
import { describe, expect, it, vi } from 'vitest';
import { CropOverlay } from '../../src/components/CropOverlay';
import type { CropState } from '../../src/types';

function renderCropOverlay({
  imageWidth,
  imageHeight,
  initialCrop,
}: {
  imageWidth: number;
  imageHeight: number;
  initialCrop: CropState;
}) {
  const onCropChange = vi.fn();
  const onConfirm = vi.fn();
  const onCancel = vi.fn();

  render(
    <CropOverlay
      imageWidth={imageWidth}
      imageHeight={imageHeight}
      initialCrop={initialCrop}
      onCropChange={onCropChange}
      onConfirm={onConfirm}
      onCancel={onCancel}
    />
  );

  fireEvent.click(screen.getByRole('button', { name: 'Apply Crop' }));

  return { onCropChange, onConfirm };
}

describe('CropOverlay', () => {
  it('converts normalized crop to pixels for landscape images', () => {
    const { onCropChange, onConfirm } = renderCropOverlay({
      imageWidth: 400,
      imageHeight: 200,
      initialCrop: { x: 0.125, y: 0.25, width: 0.5, height: 0.5 },
    });

    expect(onCropChange).toHaveBeenCalledWith({ x: 50, y: 50, width: 200, height: 100 });
    expect(onConfirm).toHaveBeenCalledOnce();
  });

  it('converts normalized crop to pixels for portrait images with rounding', () => {
    const { onCropChange } = renderCropOverlay({
      imageWidth: 123,
      imageHeight: 987,
      initialCrop: { x: 0.333, y: 0.111, width: 0.25, height: 0.5 },
    });

    expect(onCropChange).toHaveBeenCalledWith({ x: 41, y: 110, width: 31, height: 494 });
  });

  it('clamps a partially out-of-bounds crop box to image bounds', () => {
    const { onCropChange } = renderCropOverlay({
      imageWidth: 100,
      imageHeight: 80,
      initialCrop: { x: 0.8, y: 0.75, width: 0.5, height: 0.5 },
    });

    expect(onCropChange).toHaveBeenCalledWith({ x: 80, y: 60, width: 20, height: 20 });
  });

  it('clamps an oversized crop box to the full image', () => {
    const { onCropChange } = renderCropOverlay({
      imageWidth: 96,
      imageHeight: 64,
      initialCrop: { x: 0, y: 0, width: 2, height: 1.5 },
    });

    expect(onCropChange).toHaveBeenCalledWith({ x: 0, y: 0, width: 96, height: 64 });
  });
});
