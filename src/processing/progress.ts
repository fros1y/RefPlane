export type ProgressCallback = (stage: string, percent: number) => void;

export function createProgressReporter(requestId: number): ProgressCallback {
  return (stage: string, percent: number) => {
    self.postMessage({ type: 'progress', stage, percent, requestId });
  };
}
