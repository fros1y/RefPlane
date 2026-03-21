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
      ref={containerRef}
      style={{
        position: 'absolute', inset: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: '#0d0d0d', overflow: 'hidden', userSelect: 'none',
      }}
      onPointerMove={handlePointerMove}
    >
      <div style={{ position: 'relative', maxWidth: '100%', maxHeight: '100%' }}>
        <canvas ref={beforeRef} style={{ maxWidth: '100%', maxHeight: '100%', display: 'block' }} />
        <div style={{
          position: 'absolute', inset: 0, overflow: 'hidden',
          clipPath: `inset(0 ${Math.round((1 - split) * 100)}% 0 0)`,
        }}>
          <canvas ref={afterRef} style={{ maxWidth: '100%', maxHeight: '100%', display: 'block' }} />
        </div>
        <div style={{
          position: 'absolute', top: 0, bottom: 0,
          left: `${split * 100}%`, width: '2px',
          background: 'white', transform: 'translateX(-1px)',
          boxShadow: '0 0 4px rgba(0,0,0,0.5)',
        }}>
          <div style={{
            position: 'absolute', top: '50%', left: '50%',
            transform: 'translate(-50%,-50%)',
            width: '32px', height: '32px',
            background: 'white', borderRadius: '50%',
            boxShadow: '0 2px 8px rgba(0,0,0,0.3)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="16" height="16" fill="#333" viewBox="0 0 24 24">
              <path d="M18 8l4 4-4 4M6 8l-4 4 4 4M14 4l-4 16"/>
            </svg>
          </div>
        </div>
      </div>
      <button
        style={{
          position: 'absolute', top: '16px', right: '16px',
          background: 'rgba(0,0,0,0.5)', color: 'white',
          borderRadius: '50%', width: '40px', height: '40px',
          fontSize: '20px', minWidth: '40px',
        }}
        onClick={onClose}
      >
        ×
      </button>
    </div>
  );
}
