import { describe, it, expect } from 'vitest';
import { buildOAuthUrl } from './googleHealth.js';

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
});
