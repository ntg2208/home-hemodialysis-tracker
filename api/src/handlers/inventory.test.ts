import { describe, it, expect, vi, beforeEach } from 'vitest';
import { Hono } from 'hono';
import { bearerAuth } from '../lib/auth.js';

const mocks = vi.hoisted(() => ({
  batchSet: vi.fn(),
  batchCommit: vi.fn().mockResolvedValue(undefined),
  docGet: vi.fn().mockResolvedValue({ exists: false, data: () => undefined }),
  docSet: vi.fn().mockResolvedValue(undefined),
  colGet: vi.fn().mockResolvedValue({ docs: [] }),
  colAdd: vi.fn().mockResolvedValue({ id: 'event-id' }),
}));

vi.mock('../lib/firestore.js', () => ({
  getDb: () => ({
    collection: () => ({
      get: mocks.colGet,
      add: mocks.colAdd,
      doc: () => ({
        get: mocks.docGet,
        set: mocks.docSet,
      }),
    }),
    batch: () => ({
      set: mocks.batchSet,
      commit: mocks.batchCommit,
    }),
  }),
}));

import { inventory } from './inventory.js';

function makeApp() {
  const app = new Hono();
  app.use('/api/*', bearerAuth(() => 'test-key'));
  app.route('/api/inventory', inventory);
  return app;
}

function get(app: Hono, path: string) {
  return app.request(path, { headers: { Authorization: 'Bearer test-key' } });
}

describe('GET /api/inventory', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.colGet.mockResolvedValue({ docs: [] });
    mocks.docGet.mockResolvedValue({ exists: false, data: () => undefined });
  });

  it('returns stock map and null cycle when Firestore is empty', async () => {
    const res = await get(makeApp(), '/api/inventory');
    expect(res.status).toBe(200);
    const body = await res.json() as { stock: Record<string, number>; cycle: null };
    expect(body.stock).toEqual({});
    expect(body.cycle).toBeNull();
  });

  it('returns cycle when inventory_config/cycle exists', async () => {
    const cycleData = {
      call_date: '2026-06-23',
      delivery_date: '2026-06-30',
      order: {},
      order_placed_at: null,
      delivery_applied_at: null,
    };
    mocks.docGet.mockResolvedValue({ exists: true, data: () => cycleData });
    const res = await get(makeApp(), '/api/inventory');
    expect(res.status).toBe(200);
    const body = await res.json() as { cycle: typeof cycleData };
    expect(body.cycle?.call_date).toBe('2026-06-23');
  });

  it('returns stock quantities from inventory_stock collection', async () => {
    mocks.colGet.mockResolvedValue({
      docs: [
        { id: 'SAK-303', data: () => ({ qty: 12, updated_at: '2026-05-28T10:00:00Z' }) },
        { id: 'CAR-172-C', data: () => ({ qty: 6, updated_at: '2026-05-28T10:00:00Z' }) },
      ],
    });
    const res = await get(makeApp(), '/api/inventory');
    const body = await res.json() as { stock: Record<string, number> };
    expect(body.stock['SAK-303']).toBe(12);
    expect(body.stock['CAR-172-C']).toBe(6);
  });

  it('returns 401 without auth', async () => {
    const res = await makeApp().request('/api/inventory');
    expect(res.status).toBe(401);
  });
});
