import { useState, useRef, useCallback } from 'preact/hooks';
import { Fragment } from 'preact';
import type { CropState } from '../types';

interface AspectPreset {
  label: string;
  ratio: number | null; // null = free
}

const PRESETS: AspectPreset[] = [
  { label: 'Free', ratio: null },
  { label: '1:1', ratio: 1 },
  { label: '4:3', ratio: 4 / 3 },
  { label: '3:2', ratio: 3 / 2 },
  { label: '16:9', ratio: 16 / 9 },
  { label: '5:4', ratio: 5 / 4 },
  { label: 'φ', ratio: (1 + Math.sqrt(5)) / 2 },
];

interface Props {
  imageWidth: number;
  imageHeight: number;
  initialCrop: CropState | null;
  onCropChange: (crop: CropState) => void;
  onConfirm: () => void;
  onCancel: () => void;
}

export function CropOverlay({ imageWidth, imageHeight, initialCrop, onCropChange, onConfirm, onCancel }: Props) {
  const [crop, setCrop] = useState<CropState>(
    initialCrop ?? { x: 0.1, y: 0.1, width: 0.8, height: 0.8 }
  );
  const [activePreset, setActivePreset] = useState<number>(0);
  const [landscape, setLandscape] = useState(true);
  const containerRef = useRef<HTMLDivElement>(null);
  const dragStateRef = useRef<{ type: string; startX: number; startY: number; startCrop: CropState } | null>(null);

  const getRelPos = (clientX: number, clientY: number) => {
    const el = containerRef.current;
    if (!el) return { rx: 0, ry: 0 };
    const rect = el.getBoundingClientRect();
    return {
      rx: (clientX - rect.left) / rect.width,
      ry: (clientY - rect.top) / rect.height,
    };
  };

  const applyAspect = useCallback((c: CropState, ratio: number | null, isLandscape: boolean): CropState => {
    if (ratio === null) return c;
    const effectiveRatio = isLandscape ? ratio : 1 / ratio;
    const cx = c.x + c.width / 2;
    const cy = c.y + c.height / 2;
    let w = c.width;
    let h = w / effectiveRatio;
    if (h > 0.95) { h = 0.95; w = h * effectiveRatio; }
    if (w > 0.95) { w = 0.95; h = w / effectiveRatio; }
    return {
      x: Math.max(0, Math.min(1 - w, cx - w / 2)),
      y: Math.max(0, Math.min(1 - h, cy - h / 2)),
      width: w,
      height: h,
    };
  }, []);

  const handlePresetClick = (idx: number) => {
    const preset = PRESETS[idx];
    setActivePreset(idx);
    const newCrop = applyAspect(crop, preset.ratio, landscape);
    setCrop(newCrop);
  };

  const toggleOrientation = () => {
    const newLandscape = !landscape;
    setLandscape(newLandscape);
    const preset = PRESETS[activePreset];
    if (preset.ratio !== null) {
      const newCrop = applyAspect(crop, preset.ratio, newLandscape);
      setCrop(newCrop);
    }
  };

  const handleRectPointerDown = (type: string, e: PointerEvent) => {
    e.stopPropagation();
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    const { rx, ry } = getRelPos(e.clientX, e.clientY);
    dragStateRef.current = { type, startX: rx, startY: ry, startCrop: { ...crop } };
  };

  const handlePointerMove = (e: PointerEvent) => {
    const ds = dragStateRef.current;
    if (!ds) return;
    const { rx, ry } = getRelPos(e.clientX, e.clientY);
    const dx = rx - ds.startX;
    const dy = ry - ds.startY;
    const sc = ds.startCrop;
    const preset = PRESETS[activePreset];

    let newCrop: CropState = { ...sc };

    if (ds.type === 'move') {
      newCrop.x = Math.max(0, Math.min(1 - sc.width, sc.x + dx));
      newCrop.y = Math.max(0, Math.min(1 - sc.height, sc.y + dy));
    } else {
      // Handle corner/edge resizing
      if (ds.type.includes('e')) newCrop.width = Math.max(0.05, Math.min(1 - sc.x, sc.width + dx));
      if (ds.type.includes('w')) {
        const newW = Math.max(0.05, sc.width - dx);
        newCrop.x = sc.x + sc.width - newW;
        newCrop.width = newW;
      }
      if (ds.type.includes('s')) newCrop.height = Math.max(0.05, Math.min(1 - sc.y, sc.height + dy));
      if (ds.type.includes('n')) {
        const newH = Math.max(0.05, sc.height - dy);
        newCrop.y = sc.y + sc.height - newH;
        newCrop.height = newH;
      }
      if (preset.ratio !== null) {
        newCrop = applyAspect(newCrop, preset.ratio, landscape);
      }
    }

    setCrop(newCrop);
  };

  const handlePointerUp = () => {
    dragStateRef.current = null;
  };

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
    <div
      ref={containerRef}
      class="crop-shell"
      onPointerMove={handlePointerMove as any}
      onPointerUp={handlePointerUp}
      onPointerCancel={handlePointerUp}
    >
      <div class="crop-mask" />

      <div
        class="crop-rect"
        style={{
          left: `${crop.x * 100}%`,
          top: `${crop.y * 100}%`,
          width: `${crop.width * 100}%`,
          height: `${crop.height * 100}%`,
        }}
        onPointerDown={(e) => handleRectPointerDown('move', e as unknown as PointerEvent)}
      >
        {[1/3, 2/3].map((t) => (
          <Fragment key={t}>
            <div class="crop-guide" style={{ left: 0, right: 0, top: `${t * 100}%`, height: '1px' }} />
            <div class="crop-guide" style={{ top: 0, bottom: 0, left: `${t * 100}%`, width: '1px' }} />
          </Fragment>
        ))}

        {(['nw','ne','sw','se'] as const).map((corner) => (
          <div
            key={corner}
            class="crop-handle"
            style={{
              left: corner.includes('e') ? '100%' : '0%',
              top: corner.includes('s') ? '100%' : '0%',
              cursor: (corner === 'nw' || corner === 'se') ? 'nwse-resize' : 'nesw-resize',
            }}
            onPointerDown={(e) => handleRectPointerDown(corner, e as unknown as PointerEvent)}
          />
        ))}
      </div>

      <div class="crop-toolbar">
        {PRESETS.map((p, i) => (
          <button
            key={i}
            class={`crop-preset ${activePreset === i ? 'active' : ''}`}
            onClick={() => handlePresetClick(i)}
          >
            {p.label}
          </button>
        ))}
        {activePreset > 0 && (
          <button
            class="crop-preset"
            onClick={toggleOrientation}
            aria-label={landscape ? 'Switch to portrait' : 'Switch to landscape'}
            title="Toggle landscape/portrait"
          >
            {landscape ? '⇔' : '⇕'}
          </button>
        )}
      </div>

      <div class="crop-actions">
        <button class="crop-secondary" onClick={onCancel}>Cancel</button>
        <button class="btn-primary" onClick={handleCropConfirm}>Apply Crop</button>
      </div>
    </div>
  );
}
