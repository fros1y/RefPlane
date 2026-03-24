import {
  createWorkerRequestMessage,
  type WorkerRequest,
  type WorkerRequestResult,
  type WorkerOutboundMessage,
  type WorkerProgressMessage,
  type WorkerRequestType,
} from './worker-protocol';

type ProgressCallback = (event: WorkerProgressMessage) => void;

interface PendingRequest {
  requestType: WorkerRequestType;
  resolve: (value: WorkerRequestResult<WorkerRequestType>) => void;
  reject: (reason?: unknown) => void;
  onProgress?: ProgressCallback;
}

export interface WorkerRequestOptions {
  requestId?: number;
  transfer?: Transferable[];
  onProgress?: ProgressCallback;
}

export interface WorkerRequestHandle<T extends WorkerRequestType> {
  requestId: number;
  promise: Promise<WorkerRequestResult<T>>;
}

export class WorkerRequestError extends Error {
  requestId: number;
  requestType: WorkerRequestType;
  workerMeta?: WorkerRequestResult<WorkerRequestType>['meta'];

  constructor(requestId: number, requestType: WorkerRequestType, error: string, meta?: WorkerRequestResult<WorkerRequestType>['meta']) {
    super(error);
    this.name = 'WorkerRequestError';
    this.requestId = requestId;
    this.requestType = requestType;
    this.workerMeta = meta;
  }
}

export class WorkerClient {
  private worker: Worker;
  private nextRequestId = 0;
  private pending = new Map<number, PendingRequest>();
  private onMessageBound: (event: MessageEvent<WorkerOutboundMessage>) => void;

  constructor(worker: Worker) {
    this.worker = worker;
    this.onMessageBound = this.onMessage.bind(this);
    this.worker.addEventListener('message', this.onMessageBound as EventListener);
  }

  request<T extends WorkerRequest>(request: T, options: WorkerRequestOptions = {}): WorkerRequestHandle<T['type']> {
    const requestId = options.requestId ?? this.nextRequestId + 1;
    this.nextRequestId = Math.max(this.nextRequestId, requestId);

    const promise = new Promise<WorkerRequestResult<T['type']>>((resolve, reject) => {
      this.pending.set(requestId, {
        requestType: request.type,
        resolve: resolve as PendingRequest['resolve'],
        reject,
        onProgress: options.onProgress,
      });

      const envelope = {
        kind: 'request' as const,
        requestId,
        request,
      };
      if (options.transfer && options.transfer.length > 0) {
        this.worker.postMessage(envelope, options.transfer);
      } else {
        this.worker.postMessage(envelope);
      }
    });

    return { requestId, promise };
  }

  dispose() {
    this.worker.removeEventListener('message', this.onMessageBound as EventListener);
    this.rejectAllPending('Worker client disposed');
  }

  terminate() {
    this.dispose();
    this.worker.terminate();
  }

  private rejectAllPending(reason: string) {
    for (const [, pending] of this.pending) {
      pending.reject(new Error(reason));
    }
    this.pending.clear();
  }

  private onMessage(event: MessageEvent<WorkerOutboundMessage>) {
    const message = event.data;
    const pending = this.pending.get(message.requestId);
    if (!pending) return;

    if (message.kind === 'progress') {
      pending.onProgress?.(message);
      return;
    }

    this.pending.delete(message.requestId);
    if (message.ok) {
      pending.resolve({
        requestId: message.requestId,
        requestType: message.requestType,
        meta: message.meta,
        payload: message.payload,
      });
      return;
    }

    pending.reject(new WorkerRequestError(message.requestId, message.requestType, message.error, message.meta));
  }
}