import { useState } from 'preact/hooks';
import type { CropState } from '../types';

interface Props {
  imageWidth: number;
  imageHeight: number;
  initialCrop: CropState | null;
  onCropChange: (crop: CropState) => void;
  onConfirm: () => void;
  onCancel: () => void;
}

export function CropOverlay({ imageWidth, imageHeight, initialCrop, onCropChange, onConfirm, onCancel }: Props) {
  const [crop] = useState<CropState>(
    initialCrop ?? { x: 0.1, y: 0.1, width: 0.8, height: 0.8 }
  );

  const handleCropConfirm = () => {
    const pixelCrop: CropState = {
      x: Math.round(crop.x * imageWidth),
      y: Math.round(crop.y * imageHeight),
      width: Math.round(crop.width * imageWidth),
      height: Math.round(crop.height * imageHeight),
    };
    onCropChange(pixelCrop);
    onConfirm();
  };

  return (
    <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.6)' }}>
      <div style={{
        position: 'absolute',
        left: `${crop.x * 100}%`,
        top: `${crop.y * 100}%`,
        width: `${crop.width * 100}%`,
        height: `${crop.height * 100}%`,
        border: '2px solid white',
        boxShadow: '0 0 0 9999px rgba(0,0,0,0.5)',
        pointerEvents: 'none',
      }} />
      <div style={{
        position: 'absolute', bottom: '16px', left: '50%', transform: 'translateX(-50%)',
        display: 'flex', gap: '12px',
      }}>
        <button style={{ background: 'rgba(0,0,0,0.7)', color: 'white', borderRadius: '8px', padding: '10px 20px' }} onClick={onCancel}>Cancel</button>
        <button style={{ background: '#5b8def', color: 'white', borderRadius: '8px', padding: '10px 20px', fontWeight: 600 }} onClick={handleCropConfirm}>Apply Crop</button>
      </div>
    </div>
  );
}
