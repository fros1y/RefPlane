export async function exportImage(canvas: HTMLCanvasElement, mode: string = 'export'): Promise<void> {
  const now = new Date();
  const pad = (n: number, d = 2) => String(n).padStart(d, '0');
  const datePart = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}`;
  const timePart = `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  const slug = mode.replace(/[^a-z0-9]/gi, '-').toLowerCase();
  const filename = `refplane_${slug}_${datePart}-${timePart}.png`;

  const blob = await new Promise<Blob>((resolve, reject) => {
    canvas.toBlob((b) => {
      if (b) resolve(b);
      else reject(new Error('Failed to create blob'));
    }, 'image/png');
  });

  if (navigator.share && navigator.canShare?.({ files: [new File([blob], filename, { type: 'image/png' })] })) {
    const file = new File([blob], filename, { type: 'image/png' });
    await navigator.share({ files: [file], title: 'RefPlane Export' });
  } else {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  }
}
