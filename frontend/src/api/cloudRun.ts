import type { AuthSettings } from '../auth/storage';

export class CloudRunError extends Error {
  constructor(
    public code: 'unauthorized' | 'network' | 'bad_data' | 'server',
    message: string,
  ) {
    super(message);
    this.name = 'CloudRunError';
  }
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
  let res: Response;
  try {
    res = await fetch(url.toString(), {
      headers: { Authorization: `Bearer ${auth.mainKey}` },
    });
  } catch {
    throw new CloudRunError('network', 'Could not reach the server.');
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
