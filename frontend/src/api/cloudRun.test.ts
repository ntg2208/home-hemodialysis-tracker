import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { cloudGet, isRetryableError, CloudRunError } from './cloudRun';
import type { AuthSettings } from '../auth/storage';

const auth = { mainKey: 'test-key' } as AuthSettings;

describe('isRetryableError', () => {
  it('retries network errors', () => {
    expect(isRetryableError(new CloudRunError('network', 'x'))).toBe(true);
  });
  it('does not retry unauthorized / server / bad_data', () => {
    expect(isRetryableError(new CloudRunError('unauthorized', 'x'))).toBe(false);
    expect(isRetryableError(new CloudRunError('server', 'x'))).toBe(false);
    expect(isRetryableError(new CloudRunError('bad_data', 'x'))).toBe(false);
  });
  it('does not retry non-CloudRunError values', () => {
    expect(isRetryableError(new Error('plain'))).toBe(false);
  });
});

describe('cloudGet retry', () => {
  beforeEach(() => {
    vi.stubGlobal('window', { location: { origin: 'https://example.test' } });
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('retries a transient network failure then resolves', async () => {
    const fetchMock = vi.fn()
      .mockRejectedValueOnce(new TypeError('Failed to fetch'))
      .mockResolvedValueOnce(new Response(JSON.stringify({ ok: 1 }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const p = cloudGet<{ ok: number }>(auth, '/api/blood-tests');
    await vi.runAllTimersAsync();
    await expect(p).resolves.toEqual({ ok: 1 });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('does not retry a 401', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValue(new Response('nope', { status: 401 }));
    vi.stubGlobal('fetch', fetchMock);

    const p = cloudGet(auth, '/api/blood-tests');
    await vi.runAllTimersAsync();
    await expect(p).rejects.toMatchObject({ code: 'unauthorized' });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('throws network after exhausting retries', async () => {
    const fetchMock = vi.fn().mockRejectedValue(new TypeError('Failed to fetch'));
    vi.stubGlobal('fetch', fetchMock);

    const p = cloudGet(auth, '/api/blood-tests');
    await vi.runAllTimersAsync();
    await expect(p).rejects.toMatchObject({ code: 'network' });
    expect(fetchMock).toHaveBeenCalledTimes(3); // 1 + 2 retries
  });
});
