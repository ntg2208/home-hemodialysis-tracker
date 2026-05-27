import { describe, it, expect } from 'vitest';
import { Hono } from 'hono';
import { bearerAuth } from './auth';

function makeApp(key: string | undefined) {
  const app = new Hono();
  app.use('/protected/*', bearerAuth(() => key));
  app.get('/protected/data', (c) => c.json({ ok: true }));
  app.get('/api/health', (c) => c.json({ ok: true }));
  return app;
}

async function req(app: Hono, path: string, authHeader?: string) {
  const headers: Record<string, string> = {};
  if (authHeader) headers['Authorization'] = authHeader;
  return app.request(path, { headers });
}

describe('bearerAuth middleware', () => {
  it('returns 401 when Authorization header is missing', async () => {
    const res = await req(makeApp('secret'), '/protected/data');
    expect(res.status).toBe(401);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('unauthorized');
  });

  it('returns 401 when the key is wrong', async () => {
    const res = await req(makeApp('secret'), '/protected/data', 'Bearer wrong');
    expect(res.status).toBe(401);
  });

  it('passes through with the correct key', async () => {
    const res = await req(makeApp('secret'), '/protected/data', 'Bearer secret');
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean };
    expect(body.ok).toBe(true);
  });

  it('returns 500 when the env key is not set', async () => {
    const res = await req(makeApp(undefined), '/protected/data', 'Bearer anything');
    expect(res.status).toBe(500);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('server_misconfigured');
  });

  it('does not protect routes outside the middleware path', async () => {
    const res = await req(makeApp('secret'), '/api/health');
    expect(res.status).toBe(200);
  });
});
