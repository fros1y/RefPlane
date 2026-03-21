interface Props {
  hasImage: boolean;
  showCrop: boolean;
  showCompare: boolean;
  onOpenImage: () => void;
  onCrop: () => void;
  onCompare: () => void;
  onExport: () => void;
}

export function ActionBar({ hasImage, showCrop, showCompare, onOpenImage, onCrop, onCompare, onExport }: Props) {
  return (
    <div class="action-bar">
      <button
        class="btn-ghost action-button"
        onClick={onOpenImage}
        title="Open a new image"
      >
        <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <rect x="3" y="3" width="18" height="18" rx="2" />
          <circle cx="8.5" cy="8.5" r="1.5" />
          <path d="M21 15l-5-5L5 21" />
        </svg>
        <span style="margin-left:4px">Open</span>
      </button>
      <button
        class={`btn-ghost action-button ${showCrop ? 'active' : ''}`}
        onClick={onCrop}
        disabled={!hasImage}
        title="Crop the image to a region of interest"
      >
        <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <path d="M6.13 1L6 16a2 2 0 002 2h15M1 6.13l15-.13a2 2 0 012 2V23"/>
        </svg>
        <span style="margin-left:4px">Crop</span>
      </button>
      <button
        class={`btn-ghost action-button ${showCompare ? 'active' : ''}`}
        onClick={onCompare}
        disabled={!hasImage}
        title="Side-by-side comparison of original and processed image"
      >
        <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <path d="M9 3H5a2 2 0 00-2 2v4m6-6h10a2 2 0 012 2v4M9 3v18m0 0h10a2 2 0 002-2V9M9 21H5a2 2 0 01-2-2V9m0 0h18"/>
        </svg>
        <span style="margin-left:4px">Compare</span>
      </button>
      <button
        class="btn-primary action-button action-button-primary"
        onClick={onExport}
        disabled={!hasImage}
        title="Export the current canvas view as an image"
      >
        <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/>
        </svg>
        <span style="margin-left:4px">Export</span>
      </button>
    </div>
  );
}
