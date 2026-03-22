function isMobileDevice(): boolean {
  return /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) ||
    (navigator.maxTouchPoints > 1 && /Mobi|Tablet/i.test(navigator.userAgent));
}

function buildFilename(mode: string): string {
  const now = new Date();
  const pad = (n: number, d = 2) => String(n).padStart(d, '0');
  const datePart = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}`;
  const timePart = `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  const slug = mode.replace(/[^a-z0-9]/gi, '-').toLowerCase();
  return `refplane_${slug}_${datePart}-${timePart}.png`;
}

function canvasToBlob(canvas: HTMLCanvasElement): Promise<Blob> {
  return new Promise<Blob>((resolve, reject) => {
    canvas.toBlob((b) => {
      if (b) resolve(b);
      else reject(new Error('Failed to create blob'));
    }, 'image/png');
  });
}

function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => {
    URL.revokeObjectURL(url);
    a.remove();
  }, 0);
}

export async function exportImage(canvas: HTMLCanvasElement, mode: string = 'export'): Promise<void> {
  const filename = buildFilename(mode);
  const blob = await canvasToBlob(canvas);

  // On mobile, prefer the native share sheet; on desktop, download directly
  if (isMobileDevice() && navigator.share && navigator.canShare?.({ files: [new File([blob], filename, { type: 'image/png' })] })) {
    const file = new File([blob], filename, { type: 'image/png' });
    await navigator.share({ files: [file], title: 'RefPlane Export' });
  } else {
    downloadBlob(blob, filename);
  }
}
