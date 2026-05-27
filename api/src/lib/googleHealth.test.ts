import { describe, it, expect, vi, afterEach } from 'vitest';
import { buildOAuthUrl, exchangeCode, refreshAccessToken, fetchDailyRollUp } from './googleHealth.js';

afterEach(() => vi.restoreAllMocks());

describe('buildOAuthUrl', () => {
  it('includes required OAuth params', () => {
    const url = buildOAuthUrl({
      clientId: 'test-client-id',
      redirectUri: 'https://example.com/callback',
    });
    const parsed = new URL(url);
    expect(parsed.hostname).toBe('accounts.google.com');
    expect(parsed.searchParams.get('client_id')).toBe('test-client-id');
    expect(parsed.searchParams.get('redirect_uri')).toBe('https://example.com/callback');
    expect(parsed.searchParams.get('response_type')).toBe('code');
    expect(parsed.searchParams.get('access_type')).toBe('offline');
    expect(parsed.searchParams.get('prompt')).toBe('consent');
  });

  it('includes the health scopes', () => {
    const url = buildOAuthUrl({ clientId: 'x', redirectUri: 'https://x.com' });
    const scope = new URL(url).searchParams.get('scope') ?? '';
    expect(scope).toContain('googlehealth');
  });

  it('includes state param when provided', () => {
    const url = buildOAuthUrl({ clientId: 'x', redirectUri: 'https://x.com', state: 'test-state' });
    expect(new URL(url).searchParams.get('state')).toBe('test-state');
  });
});

describe('exchangeCode', () => {
  it('returns tokens on 200', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ access_token: 'at', refresh_token: 'rt' }),
    }));
    const result = await exchangeCode({ code: 'c', clientId: 'id', clientSecret: 'sec', redirectUri: 'https://x.com' });
    expect(result).toEqual({ accessToken: 'at', refreshToken: 'rt' });
  });

  it('throws on HTTP error', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false, status: 400, text: () => Promise.resolve('bad_request'),
    }));
    await expect(exchangeCode({ code: 'c', clientId: 'id', clientSecret: 'sec', redirectUri: 'https://x.com' }))
      .rejects.toThrow('Token exchange failed: 400');
  });

  it('throws when tokens missing from response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ access_token: 'at' }), // no refresh_token
    }));
    await expect(exchangeCode({ code: 'c', clientId: 'id', clientSecret: 'sec', redirectUri: 'https://x.com' }))
      .rejects.toThrow('Token exchange response missing tokens');
  });
});

describe('refreshAccessToken', () => {
  it('returns access token on 200', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ access_token: 'new-at' }),
    }));
    const token = await refreshAccessToken({ refreshToken: 'rt', clientId: 'id', clientSecret: 'sec' });
    expect(token).toBe('new-at');
  });

  it('throws on HTTP error', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false, status: 401, text: () => Promise.resolve('invalid_grant'),
    }));
    await expect(refreshAccessToken({ refreshToken: 'rt', clientId: 'id', clientSecret: 'sec' }))
      .rejects.toThrow('Token refresh failed: 401');
  });

  it('throws when access_token missing from response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({}),
    }));
    await expect(refreshAccessToken({ refreshToken: 'rt', clientId: 'id', clientSecret: 'sec' }))
      .rejects.toThrow('Token refresh response missing access_token');
  });
});

describe('fetchDailyRollUp', () => {
  it('returns parsed JSON on 200', async () => {
    const mockData = { data: [{ date: '2026-05-27', value: 8000 }] };
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(mockData),
    }));
    const result = await fetchDailyRollUp({ accessToken: 'at', dataType: 'steps', startDate: '2026-05-01', endDate: '2026-05-27' });
    expect(result).toEqual(mockData);
  });

  it('throws on HTTP error', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false, status: 403, text: () => Promise.resolve('forbidden'),
    }));
    await expect(fetchDailyRollUp({ accessToken: 'at', dataType: 'steps', startDate: '2026-05-01', endDate: '2026-05-27' }))
      .rejects.toThrow('fetchDailyRollUp(steps) failed: 403');
  });
});
