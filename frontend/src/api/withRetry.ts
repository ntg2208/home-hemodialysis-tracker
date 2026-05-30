export interface RetryOptions {
  /** Number of retries after the initial attempt. */
  retries?: number;
  /** Delay (ms) before each retry; index 0 is the first retry. Falls back to the last entry. */
  delays?: number[];
  /** Return true to retry on a given error. Default: never retry. */
  shouldRetry?: (error: unknown) => boolean;
  /** Injectable sleep, for tests. */
  sleep?: (ms: number) => Promise<void>;
}

const realSleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export async function withRetry<T>(
  fn: () => Promise<T>,
  opts: RetryOptions = {},
): Promise<T> {
  const retries = opts.retries ?? 0;
  const delays = opts.delays ?? [];
  const shouldRetry = opts.shouldRetry ?? (() => false);
  const sleep = opts.sleep ?? realSleep;

  let lastError: unknown;
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      if (attempt === retries || !shouldRetry(error)) throw error;
      const delay = delays[attempt] ?? delays[delays.length - 1] ?? 0;
      await sleep(delay);
    }
  }
  throw lastError;
}
