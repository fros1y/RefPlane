export async function exportImage(canvas: HTMLCanvasElement, filename: string = 'refplane-export.png'): Promise<void> {
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
