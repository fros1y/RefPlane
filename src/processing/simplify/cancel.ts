export function createAbortError(): Error {
  const error = new Error('Simplify job cancelled');
  error.name = 'AbortError';
  return error;
}

export function throwIfAborted(signal?: AbortSignal): void {
  if (signal?.aborted) {
    throw createAbortError();
  }
}

export async function yieldToEventLoop(): Promise<void> {
  await new Promise<void>((resolve) => {
    setTimeout(resolve, 0);
  });
}
