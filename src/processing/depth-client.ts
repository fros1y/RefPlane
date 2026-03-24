import type {
  DepthWorkerRequest,
  DepthWorkerOutbound,
} from './depth-worker';

export type DepthProgressCallback = (stage: string, percent: number) => void;

export class DepthClient {
  private worker: Worker;
  private pending = new Map<number, {
    resolve: (result: { depthData: Float32Array; depthWidth: number; depthHeight: number }) => void;
    reject: (err: Error) => void;
  }>();
  private nextId = 0;
  private onProgress?: DepthProgressCallback;

  constructor(onProgress?: DepthProgressCallback) {
    this.onProgress = onProgress;
    this.worker = new Worker(
      new URL('./depth-worker.ts', import.meta.url),
      { type: 'module' },
    );
    this.worker.addEventListener('message', this.handleMessage);
  }

  requestDepth(imageData: ImageData, modelSize?: 'small' | 'base' | 'large' | 'depth-pro'): { requestId: number; promise: Promise<{ depthData: Float32Array; depthWidth: number; depthHeight: number }> } {
    const requestId = ++this.nextId;
    const imgCopy = new ImageData(new Uint8ClampedArray(imageData.data), imageData.width, imageData.height);

    const promise = new Promise<{ depthData: Float32Array; depthWidth: number; depthHeight: number }>((resolve, reject) => {
      this.pending.set(requestId, { resolve, reject });

      const msg: DepthWorkerRequest = { kind: 'estimate', requestId, imageData: imgCopy, modelSize };
      this.worker.postMessage(msg, [imgCopy.data.buffer]);
    });

    return { requestId, promise };
  }

  terminate() {
    this.worker.removeEventListener('message', this.handleMessage);
    for (const [, p] of this.pending) {
      p.reject(new Error('DepthClient terminated'));
    }
    this.pending.clear();
    this.worker.terminate();
  }

  private handleMessage = (e: MessageEvent<DepthWorkerOutbound>) => {
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
        p.resolve({
          depthData: msg.depthData,
          depthWidth: msg.depthWidth,
          depthHeight: msg.depthHeight,
        });
      }
    }
  };
}
