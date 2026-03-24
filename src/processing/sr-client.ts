import type { SrWorkerRequest, SrWorkerOutbound } from './sr-worker';

export type SrProgressCallback = (stage: string, percent: number) => void;

export class SrClient {
  private worker: Worker;
  private pending = new Map<number, {
    resolve: (result: ImageData) => void;
    reject: (err: Error) => void;
  }>();
  private nextId = 0;
  private onProgress?: SrProgressCallback;

  constructor(onProgress?: SrProgressCallback) {
    this.onProgress = onProgress;
    this.worker = new Worker(
      new URL('./sr-worker.ts', import.meta.url),
      { type: 'module' },
    );
    this.worker.addEventListener('message', this.handleMessage);
  }

  request(
    imageData: ImageData,
    scale: number,
    sharpenAmount: number,
  ): { requestId: number; promise: Promise<ImageData> } {
    const requestId = ++this.nextId;
    const imgCopy = new ImageData(
      new Uint8ClampedArray(imageData.data),
      imageData.width,
      imageData.height,
    );

    const promise = new Promise<ImageData>((resolve, reject) => {
      this.pending.set(requestId, { resolve, reject });

      const msg: SrWorkerRequest = {
        kind: 'sr',
        requestId,
        imageData: imgCopy,
        scale,
        sharpenAmount,
      };
      this.worker.postMessage(msg, [imgCopy.data.buffer]);
    });

    return { requestId, promise };
  }

  terminate() {
    this.worker.removeEventListener('message', this.handleMessage);
    for (const [, p] of this.pending) {
      p.reject(new Error('SrClient terminated'));
    }
    this.pending.clear();
    this.worker.terminate();
  }

  private handleMessage = (e: MessageEvent<SrWorkerOutbound>) => {
    const msg = e.data;

    if (msg.kind === 'progress') {
      this.onProgress?.(msg.stage, msg.percent);
      return;
    }

    if (msg.kind === 'error') {
      const p = this.pending.get(msg.requestId);
      if (p) {
        this.pending.delete(msg.requestId);
        p.reject(new Error(msg.error));
      }
      return;
    }

    if (msg.kind === 'result') {
      const p = this.pending.get(msg.requestId);
      if (p) {
        this.pending.delete(msg.requestId);
        p.resolve(msg.imageData);
      }
    }
  };
}
