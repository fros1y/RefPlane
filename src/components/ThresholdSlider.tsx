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
      // Clamp between neighbors to preserve ordering without re-sorting,
      // which would cause handles to jump and break pointer capture.
      const lowerBound = index > 0 ? thresholds[index - 1] : 0;
      const upperBound = index < thresholds.length - 1 ? thresholds[index + 1] : 1;
      updated[index] = Math.max(lowerBound, Math.min(upperBound, newVal));
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
        class="threshold-track"
      >
        {thresholds.map((t, i) => (
          <div
            key={i}
            class="threshold-handle"
            style={{ left: `${t * 100}%` }}
            onPointerDown={(e) => handlePointerDown(i, e as unknown as PointerEvent)}
          />
        ))}
      </div>
    </div>
  );
}
