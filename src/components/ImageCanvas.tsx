import { useRef, useEffect } from 'preact/hooks';
import type { GridConfig, EdgeConfig, Mode } from '../types';
import { composite } from '../compositing/compositor';

interface Props {
  sourceImageData: ImageData | null;
  processedImageData: ImageData | null;
  activeMode: Mode;
  gridConfig: GridConfig;
  edgeConfig: EdgeConfig;
  edgeData: ImageData | null;
  isProcessing: boolean;
}

export function ImageCanvas({
  sourceImageData,
  processedImageData,
  activeMode,
  gridConfig,
  edgeConfig,
  edgeData,
  isProcessing,
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  const displaySource = activeMode === 'original' ? sourceImageData : (processedImageData ?? sourceImageData);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !displaySource) return;
    composite(canvas, displaySource, gridConfig, edgeConfig, edgeData);
  }, [displaySource, gridConfig, edgeConfig, edgeData]);

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

  const canvasStyle: preact.JSX.CSSProperties = {
    maxWidth: '100%',
    maxHeight: '100%',
    objectFit: 'contain',
    imageRendering: 'pixelated',
  };

  return (
    <div ref={containerRef} style={containerStyle}>
      {displaySource ? (
        <canvas ref={canvasRef} style={canvasStyle} />
      ) : (
        <UploadPrompt />
      )}
      {isProcessing && (
        <div class="processing-overlay">
          <div class="spinner" />
        </div>
      )}
    </div>
  );
}

function UploadPrompt() {
  return (
    <div class="upload-prompt">
      <svg width="80" height="80" fill="none" stroke="currentColor" stroke-width="1" viewBox="0 0 24 24">
        <rect x="3" y="3" width="18" height="18" rx="2" />
        <circle cx="8.5" cy="8.5" r="1.5" />
        <path d="M21 15l-5-5L5 21" />
      </svg>
      <h2>Open an Image</h2>
      <p>Tap the button below to choose a photo</p>
    </div>
  );
}
