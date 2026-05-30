import type { AuthSettings } from '../auth/storage';
import { withRetry } from './withRetry';

export class CloudRunError extends Error {
  constructor(
    public code: 'unauthorized' | 'network' | 'bad_data' | 'server',
    message: string,
  ) {
    super(message);
    this.name = 'CloudRunError';
  }
}

// GET requests are idempotent, so they're safe to retry. A cold-start scale-from-zero
// drops the connection before any response arrives, surfacing as a `network` error —
// exactly the transient case worth retrying. Never retry auth/server/bad-data: those
// are real responses, and POSTs (inventory writes) are not retried at all (no
// idempotency key → double-write risk).
export function isRetryableError(error: unknown): boolean {
  return error instanceof CloudRunError && error.code === 'network';
}

const REQUEST_TIMEOUT_MS = 35_000; // above the Cloud Run service's 30s timeout
const RETRY_DELAYS_MS = [1_000, 3_000];

async function cloudGetOnce<T>(auth: AuthSettings, url: string): Promise<T> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  let res: Response;
  try {
    res = await fetch(url, {
      headers: { Authorization: `Bearer ${auth.mainKey}` },
      signal: controller.signal,
    });
  } catch {
    throw new CloudRunError('network', 'Could not reach the server.');
  } finally {
    clearTimeout(timer);
  }
  if (res.status === 401) {
    throw new CloudRunError('unauthorized', 'Access key rejected.');
  }
  if (!res.ok) {
    throw new CloudRunError('server', `Server error (${res.status}).`);
  }
  let body: unknown;
  try { body = await res.json(); } catch {
    throw new CloudRunError('bad_data', 'Server returned invalid JSON.');
  }
  return body as T;
}

export async function cloudGet<T>(
  auth: AuthSettings,
  path: string,
  params?: Record<string, string>,
): Promise<T> {
  const url = new URL(path, window.location.origin);
  if (params) {
    Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  }
  const target = url.toString();
  return withRetry(() => cloudGetOnce<T>(auth, target), {
    retries: RETRY_DELAYS_MS.length,
    delays: RETRY_DELAYS_MS,
    shouldRetry: isRetryableError,
  });
}

export async function cloudPost<T>(
  auth: AuthSettings,
  path: string,
  body: unknown,
): Promise<T> {
  const url = new URL(path, window.location.origin).toString();
  let res: Response;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${auth.mainKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
  } catch {
    throw new CloudRunError('network', 'Could not reach the server.');
  }
  if (res.status === 401) throw new CloudRunError('unauthorized', 'Access key rejected.');
  if (!res.ok) throw new CloudRunError('server', `Server error (${res.status}).`);
  let responseBody: unknown;
  try { responseBody = await res.json(); } catch {
    throw new CloudRunError('bad_data', 'Server returned invalid JSON.');
  }
  return responseBody as T;
}
