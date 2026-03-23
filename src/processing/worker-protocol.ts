import type { ValueConfig, ColorConfig, EdgeConfig, SimplifyConfig, PlanesConfig } from '../types';

export interface TimingStage {
  label: string;
  ms: number;
}

export interface ProcessingMeta {
  backend: 'cpu' | 'gpu' | 'mixed';
  queueWaitMs: number;
  totalMs: number;
  width: number;
  height: number;
  stages: TimingStage[];
}

export type WorkerRequest =
  | { type: 'simplify'; imageData: ImageData; config: SimplifyConfig }
  | { type: 'value-study'; imageData: ImageData; config: ValueConfig }
  | { type: 'color-regions'; imageData: ImageData; config: ColorConfig }
  | { type: 'edges'; imageData: ImageData; config: EdgeConfig }
  | { type: 'grayscale'; imageData: ImageData }
  | { type: 'planes'; imageData: ImageData; depthMap: Float32Array; depthWidth: number; depthHeight: number; config: PlanesConfig };

export type WorkerRequestType = WorkerRequest['type'];

export type WorkerResponsePayload<T extends WorkerRequestType> =
  T extends 'color-regions'
    ? { result: ImageData; palette: string[]; paletteBands: number[] }
    : { result: ImageData };

export interface WorkerRequestMessage {
  kind: 'request';
  requestId: number;
  request: WorkerRequest;
}

export interface WorkerProgressMessage {
  kind: 'progress';
  requestId: number;
  stage: string;
  percent: number;
}

export interface WorkerSuccessMessage<T extends WorkerRequestType = WorkerRequestType> {
  kind: 'response';
  ok: true;
  requestId: number;
  requestType: T;
  meta: ProcessingMeta;
  payload: WorkerResponsePayload<T>;
}

export interface WorkerErrorMessage<T extends WorkerRequestType = WorkerRequestType> {
  kind: 'response';
  ok: false;
  requestId: number;
  requestType: T;
  error: string;
  meta?: ProcessingMeta;
}

export type WorkerOutboundMessage = WorkerProgressMessage | WorkerSuccessMessage | WorkerErrorMessage;

export type WorkerInboundMessage = WorkerRequestMessage;

export interface WorkerRequestResult<T extends WorkerRequestType> {
  requestId: number;
  requestType: T;
  meta: ProcessingMeta;
  payload: WorkerResponsePayload<T>;
}

export function createWorkerRequestMessage(requestId: number, request: WorkerRequest): WorkerRequestMessage {
  return {
    kind: 'request',
    requestId,
    request,
  };
}

export function createWorkerProgressMessage(
  requestId: number,
  stage: string,
  percent: number,
): WorkerProgressMessage {
  return {
    kind: 'progress',
    requestId,
    stage,
    percent,
  };
}

export function createWorkerSuccessMessage<T extends WorkerRequestType>(
  requestId: number,
  requestType: T,
  meta: ProcessingMeta,
  payload: WorkerResponsePayload<T>,
): WorkerSuccessMessage<T> {
  return {
    kind: 'response',
    ok: true,
    requestId,
    requestType,
    meta,
    payload,
  };
}

export function createWorkerErrorMessage<T extends WorkerRequestType>(
  requestId: number,
  requestType: T,
  error: string,
  meta?: ProcessingMeta,
): WorkerErrorMessage<T> {
  return {
    kind: 'response',
    ok: false,
    requestId,
    requestType,
    error,
    meta,
  };
}