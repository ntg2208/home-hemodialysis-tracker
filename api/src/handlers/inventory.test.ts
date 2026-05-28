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

function post(app: Hono, path: string, body: unknown) {
  return app.request(`/api/inventory${path}`, {
    method: 'POST',
    headers: { Authorization: 'Bearer test-key', 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('POST /api/inventory/event', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.batchCommit.mockResolvedValue(undefined);
    mocks.batchSet.mockReturnValue(undefined);
    mocks.colAdd.mockResolvedValue({ id: 'event-id' });
    mocks.colGet.mockResolvedValue({ docs: [] });
    mocks.docGet.mockResolvedValue({ exists: false, data: () => undefined });
  });

  it('returns ok:true on valid session event', async () => {
    const res = await post(makeApp(), '/event', {
      type: 'session',
      deltas: { 'SAK-303': -1, 'CAR-172-C': -1 },
    });
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean };
    expect(body.ok).toBe(true);
  });

  it('commits a batch set for each item in deltas', async () => {
    await post(makeApp(), '/event', {
      type: 'manual',
      deltas: { 'SAK-303': -1 },
    });
    expect(mocks.batchSet).toHaveBeenCalledTimes(1);
    expect(mocks.batchCommit).toHaveBeenCalledTimes(1);
  });

  it('logs the event to inventory_events', async () => {
    await post(makeApp(), '/event', {
      type: 'session',
      deltas: { 'SAK-303': -1 },
    });
    expect(mocks.colAdd).toHaveBeenCalledWith(expect.objectContaining({ type: 'session' }));
  });

  it('returns 400 for invalid event type', async () => {
    const res = await post(makeApp(), '/event', { type: 'bad', deltas: {} });
    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid JSON', async () => {
    const res = await makeApp().request('/api/inventory/event', {
      method: 'POST',
      headers: { Authorization: 'Bearer test-key', 'Content-Type': 'application/json' },
      body: 'not-json',
    });
    expect(res.status).toBe(400);
  });
});

describe('POST /api/inventory/confirm-order', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.docSet.mockResolvedValue(undefined);
    mocks.docGet.mockResolvedValue({ exists: false, data: () => undefined });
    mocks.colGet.mockResolvedValue({ docs: [] });
  });

  it('returns ok:true on valid input', async () => {
    const res = await post(makeApp(), '/confirm-order', {
      call_date: '2026-06-23',
      order: { 'SAK-303': 16 },
    });
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean };
    expect(body.ok).toBe(true);
  });

  it('writes cycle doc with delivery_date = call_date + 7 days', async () => {
    await post(makeApp(), '/confirm-order', {
      call_date: '2026-06-23',
      order: { 'SAK-303': 16 },
    });
    expect(mocks.docSet).toHaveBeenCalledWith(
      expect.objectContaining({
        call_date: '2026-06-23',
        delivery_date: '2026-06-30',
      }),
    );
  });

  it('sets order_placed_at when order is non-empty', async () => {
    await post(makeApp(), '/confirm-order', { call_date: '2026-06-23', order: { 'SAK-303': 16 } });
    expect(mocks.docSet).toHaveBeenCalledWith(
      expect.objectContaining({ order_placed_at: expect.any(String) }),
    );
  });

  it('leaves order_placed_at null when order is empty (initial setup)', async () => {
    await post(makeApp(), '/confirm-order', { call_date: '2026-06-23', order: {} });
    expect(mocks.docSet).toHaveBeenCalledWith(
      expect.objectContaining({ order_placed_at: null }),
    );
  });

  it('returns 400 for malformed call_date', async () => {
    const res = await post(makeApp(), '/confirm-order', { call_date: '23/06/2026', order: {} });
    expect(res.status).toBe(400);
  });
});

describe('POST /api/inventory/apply-delivery', () => {
  const existingCycle = {
    call_date: '2026-05-26',
    delivery_date: '2026-06-02',
    order: { 'SAK-303': 16, 'CAR-172-C': 18 },
    order_placed_at: '2026-05-26T10:00:00Z',
    delivery_applied_at: null,
  };

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.batchCommit.mockResolvedValue(undefined);
    mocks.batchSet.mockReturnValue(undefined);
    mocks.docGet.mockResolvedValue({ exists: true, data: () => existingCycle });
    mocks.docSet.mockResolvedValue(undefined);
    mocks.colAdd.mockResolvedValue({ id: 'event-id' });
    mocks.colGet.mockResolvedValue({ docs: [] });
  });

  it('returns ok:true', async () => {
    const res = await post(makeApp(), '/apply-delivery', {});
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean };
    expect(body.ok).toBe(true);
  });

  it('applies order quantities as positive deltas to stock', async () => {
    await post(makeApp(), '/apply-delivery', {});
    // batchSet called for each item in order (SAK-303 and CAR-172-C)
    expect(mocks.batchSet).toHaveBeenCalledTimes(2);
    expect(mocks.batchCommit).toHaveBeenCalled();
  });

  it('applies adjustments that override the stored order', async () => {
    await post(makeApp(), '/apply-delivery', { adjustments: { 'SAK-303': 14 } });
    // SAK-303 should use 14 (adjustment), CAR-172-C should use 18 (from order)
    expect(mocks.batchSet).toHaveBeenCalledTimes(2);
  });

  it('advances cycle call_date by 28 days', async () => {
    await post(makeApp(), '/apply-delivery', {});
    expect(mocks.docSet).toHaveBeenCalledWith(
      expect.objectContaining({ call_date: '2026-06-23' }),
    );
  });

  it('returns 404 when no cycle exists', async () => {
    mocks.docGet.mockResolvedValue({ exists: false, data: () => undefined });
    const res = await post(makeApp(), '/apply-delivery', {});
    expect(res.status).toBe(404);
  });
});
