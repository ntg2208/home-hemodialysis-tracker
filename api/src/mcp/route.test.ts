import { describe, it, expect, beforeAll } from 'vitest';

beforeAll(() => { process.env.MAIN_API_KEY = 'test-key'; });

import { app } from '../app.js';

describe('/api/mcp auth', () => {
  it('rejects an unauthenticated POST with 401', async () => {
    const res = await app.request('/api/mcp', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
    });
    expect(res.status).toBe(401);
  });
});
