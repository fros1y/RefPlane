import { useRef, useEffect, useState } from 'preact/hooks';

interface Props {
  beforeData: ImageData | null;
  afterData: ImageData | null;
  onClose: () => void;
}

export function CompareView({ beforeData, afterData, onClose }: Props) {
  const beforeRef = useRef<HTMLCanvasElement>(null);
  const afterRef = useRef<HTMLCanvasElement>(null);
  const [split, setSplit] = useState(0.5);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (beforeRef.current && beforeData) {
      beforeRef.current.width = beforeData.width;
      beforeRef.current.height = beforeData.height;
      beforeRef.current.getContext('2d')!.putImageData(beforeData, 0, 0);
    }
    if (afterRef.current && afterData) {
      afterRef.current.width = afterData.width;
      afterRef.current.height = afterData.height;
      afterRef.current.getContext('2d')!.putImageData(afterData, 0, 0);
    }
  }, [beforeData, afterData]);

  const handlePointerMove = (e: PointerEvent) => {
    const rect = containerRef.current?.getBoundingClientRect();
    if (!rect) return;
    setSplit(Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width)));
  };

  if (!beforeData && !afterData) return null;

  return (
    <div
      class="compare-view"
      ref={containerRef}
      onPointerMove={handlePointerMove}
    >
      <div class="compare-stage">
        <canvas ref={beforeRef} class="compare-canvas" />
        <div
          class="compare-slice"
          style={{ clipPath: `inset(0 ${Math.round((1 - split) * 100)}% 0 0)` }}
        >
          <canvas ref={afterRef} class="compare-canvas" />
        </div>
        <div class="compare-badge compare-badge-left">Before</div>
        <div class="compare-badge compare-badge-right">After</div>
        <div class="compare-divider" style={{ left: `${split * 100}%` }}>
          <div class="compare-handle">
            <svg width="16" height="16" fill="#44372d" viewBox="0 0 24 24">
              <path d="M18 8l4 4-4 4M6 8l-4 4 4 4M14 4l-4 16"/>
            </svg>
          </div>
        </div>
      </div>
      <button
        class="compare-close"
        onClick={onClose}
      >
        ×
      </button>
    </div>
  );
}
