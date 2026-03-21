import { useRef, useEffect, useCallback } from 'preact/hooks';
import type { RefObject } from 'preact';
import type { GridConfig, EdgeConfig, Mode } from '../types';
import { composite } from '../compositing/compositor';
import type { CompositeOptions } from '../compositing/compositor';

interface Props {
  sourceImageData: ImageData | null;
  processedImageData: ImageData | null;
  activeMode: Mode;
  gridConfig: GridConfig;
  edgeConfig: EdgeConfig;
  edgeData: ImageData | null;
  isProcessing: boolean;
  onOpenImage?: () => void;
  externalRef?: RefObject<HTMLCanvasElement>;
  compositeOptions?: CompositeOptions;
}

export function ImageCanvas({
  sourceImageData,
  processedImageData,
  activeMode,
  gridConfig,
  edgeConfig,
  edgeData,
  isProcessing,
  onOpenImage,
  externalRef,
  compositeOptions,
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const wrapperRef = useRef<HTMLDivElement>(null);

  // Zoom/pan state
  const zoomRef = useRef({ scale: 1, tx: 0, ty: 0 });
  const pointersRef = useRef<Map<number, { x: number; y: number }>>(new Map());
  const lastPinchDistRef = useRef<number | null>(null);
  const lastTapRef = useRef<number>(0);

  // Assign both internal and external refs
  const setCanvasRef = useCallback((el: HTMLCanvasElement | null) => {
    (canvasRef as any).current = el;
    if (externalRef) (externalRef as any).current = el;
  }, [externalRef]);

  const displaySource = activeMode === 'original' ? sourceImageData : (processedImageData ?? sourceImageData);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !displaySource) return;
    composite(canvas, displaySource, gridConfig, edgeConfig, edgeData, compositeOptions);
  }, [displaySource, gridConfig, edgeConfig, edgeData, compositeOptions]);

  const applyTransform = useCallback(() => {
    const wrapper = wrapperRef.current;
    if (!wrapper) return;
    const { scale, tx, ty } = zoomRef.current;
    wrapper.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`;
  }, []);

  const resetZoom = useCallback(() => {
    zoomRef.current = { scale: 1, tx: 0, ty: 0 };
    applyTransform();
  }, [applyTransform]);

  const handlePointerDown = useCallback((e: PointerEvent) => {
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    pointersRef.current.set(e.pointerId, { x: e.clientX, y: e.clientY });

    // Double-tap to reset
    if (pointersRef.current.size === 1) {
      const now = Date.now();
      if (now - lastTapRef.current < 300) {
        resetZoom();
      }
      lastTapRef.current = now;
    }
    lastPinchDistRef.current = null;
  }, [resetZoom]);

  const handlePointerMove = useCallback((e: PointerEvent) => {
    if (!pointersRef.current.has(e.pointerId)) return;
    const prev = pointersRef.current.get(e.pointerId)!;
    pointersRef.current.set(e.pointerId, { x: e.clientX, y: e.clientY });

    const pointers = Array.from(pointersRef.current.values());

    if (pointers.length === 2) {
      // Pinch to zoom
      const [p1, p2] = pointers;
      const dist = Math.hypot(p2.x - p1.x, p2.y - p1.y);
      if (lastPinchDistRef.current !== null) {
        const delta = dist / lastPinchDistRef.current;
        const newScale = Math.max(0.5, Math.min(8, zoomRef.current.scale * delta));
        zoomRef.current.scale = newScale;
        applyTransform();
      }
      lastPinchDistRef.current = dist;
    } else if (pointers.length === 1) {
      // Pan
      const dx = e.clientX - prev.x;
      const dy = e.clientY - prev.y;
      zoomRef.current.tx += dx;
      zoomRef.current.ty += dy;
      applyTransform();
    }
  }, [applyTransform]);

  const handlePointerUp = useCallback((e: PointerEvent) => {
    pointersRef.current.delete(e.pointerId);
    if (pointersRef.current.size < 2) lastPinchDistRef.current = null;
  }, []);

  const containerStyle = {
    width: '100%',
    height: '100%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    position: 'relative' as const,
    overflow: 'hidden',
    background: '#0d0d0d',
  };

  const wrapperStyle: preact.JSX.CSSProperties = {
    transformOrigin: 'center center',
    willChange: 'transform',
    transition: 'none',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    maxWidth: '100%',
    maxHeight: '100%',
  };

  const canvasStyle: preact.JSX.CSSProperties = {
    maxWidth: '100%',
    maxHeight: '100%',
    objectFit: 'contain',
    imageRendering: 'pixelated',
    touchAction: 'none',
  };

  return (
    <div
      ref={containerRef}
      style={containerStyle}
      onPointerDown={displaySource ? handlePointerDown as any : undefined}
      onPointerMove={displaySource ? handlePointerMove as any : undefined}
      onPointerUp={displaySource ? handlePointerUp as any : undefined}
      onPointerCancel={displaySource ? handlePointerUp as any : undefined}
    >
      {displaySource ? (
        <div ref={wrapperRef} style={wrapperStyle}>
          <canvas ref={setCanvasRef} style={canvasStyle} />
        </div>
      ) : (
        <UploadPrompt onOpenImage={onOpenImage} />
      )}
      {isProcessing && (
        <div class="processing-overlay">
          <div class="spinner" />
        </div>
      )}
    </div>
  );
}

function UploadPrompt({ onOpenImage }: { onOpenImage?: () => void }) {
  return (
    <div
      class="upload-prompt"
      onPointerDown={(e) => e.stopPropagation()}
      onClick={(e) => e.stopPropagation()}
    >
      <svg width="80" height="80" fill="none" stroke="currentColor" stroke-width="1" viewBox="0 0 24 24">
        <rect x="3" y="3" width="18" height="18" rx="2" />
        <circle cx="8.5" cy="8.5" r="1.5" />
        <path d="M21 15l-5-5L5 21" />
      </svg>
      <h2>Open an Image</h2>
      <div class="upload-prompt-actions">
        <button class="btn-primary" type="button" onClick={onOpenImage}>
          Open Image
        </button>
      </div>
    </div>
  );
}
