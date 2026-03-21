import { useRef, useCallback } from 'preact/hooks';

interface Props {
  thresholds: number[];  // values 0..1
  onChange: (thresholds: number[]) => void;
}

export function ThresholdSlider({ thresholds, onChange }: Props) {
  const barRef = useRef<HTMLDivElement>(null);

  const getRelativeX = (clientX: number): number => {
    const bar = barRef.current;
    if (!bar) return 0;
    const rect = bar.getBoundingClientRect();
    return Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
  };

  const handlePointerDown = useCallback((index: number, e: PointerEvent) => {
    e.preventDefault();
    const target = e.currentTarget as HTMLElement;
    target.setPointerCapture(e.pointerId);

    const handleMove = (me: PointerEvent) => {
      const newVal = getRelativeX(me.clientX);
      const updated = [...thresholds];
      updated[index] = newVal;
      // keep sorted
      updated.sort((a, b) => a - b);
      onChange(updated);
    };

    const handleUp = () => {
      target.removeEventListener('pointermove', handleMove as EventListener);
      target.removeEventListener('pointerup', handleUp);
      target.removeEventListener('pointercancel', handleUp);
    };

    target.addEventListener('pointermove', handleMove as EventListener);
    target.addEventListener('pointerup', handleUp);
    target.addEventListener('pointercancel', handleUp);
  }, [thresholds, onChange]);

  return (
    <div style={{ position: 'relative', margin: '8px 0' }}>
      <div
        ref={barRef}
        style={{
          height: '16px',
          borderRadius: '4px',
          background: 'linear-gradient(to right, #000, #fff)',
          position: 'relative',
        }}
      >
        {thresholds.map((t, i) => (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: `${t * 100}%`,
              top: '50%',
              transform: 'translate(-50%, -50%)',
              width: '16px',
              height: '22px',
              cursor: 'ew-resize',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              touchAction: 'none',
            }}
            onPointerDown={(e) => handlePointerDown(i, e as unknown as PointerEvent)}
          >
            <div style={{
              width: 0, height: 0,
              borderLeft: '6px solid transparent',
              borderRight: '6px solid transparent',
              borderBottom: '10px solid #5b8def',
              filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.5))',
            }} />
          </div>
        ))}
      </div>
    </div>
  );
}
