import { describe, it, expect, vi, beforeEach } from 'vitest';
import { Hono } from 'hono';
import { bearerAuth } from '../lib/auth.js';

const { mockCommit, mockSet, mockDoc, mockGet } = vi.hoisted(() => ({
  mockCommit: vi.fn(),
  mockSet: vi.fn(),
  mockDoc: vi.fn(),
  mockGet: vi.fn(),
}));

vi.mock('../lib/firestore.js', () => ({
  getDb: () => ({
    collection: () => ({ get: mockGet, doc: mockDoc }),
    batch: () => ({ set: mockSet, commit: mockCommit }),
  }),
}));

import { bloodTests } from './bloodTests.js';

function makeApp() {
  const app = new Hono();
  app.use('/api/*', bearerAuth(() => 'test-key'));
  app.route('/api/blood-tests', bloodTests);
  return app;
}

function get(app: Hono, path: string) {
  return app.request(path, { headers: { Authorization: 'Bearer test-key' } });
}

function post(app: Hono, body: unknown) {
  return app.request('/api/blood-tests', {
    method: 'POST',
    headers: { Authorization: 'Bearer test-key', 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

const validRow = {
  marker: 'creatinine', datetime: '2026-06-15T14:00:00', value: 980,
  unit: 'umol/L', ref_low: 64, ref_high: 104, timing: 'pre', note: '',
  source: 'imperial-pkb', lab_id: '99261234567', phase: 'home-hd', qualitative: false,
};

describe('GET /api/blood-tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGet.mockResolvedValue({ docs: [] });
  });

  it('returns 200 with count and rows', async () => {
    const res = await get(makeApp(), '/api/blood-tests');
    expect(res.status).toBe(200);
    const body = await res.json() as { count: number; rows: unknown[] };
    expect(typeof body.count).toBe('number');
    expect(Array.isArray(body.rows)).toBe(true);
    expect(body.rows).toHaveLength(body.count);
  });

  it('merges Firestore rows into the response', async () => {
    const fsRow = { ...validRow, lab_id: 'fs-only', created_at: '2026-05-27T00:00:00' };
    mockGet.mockResolvedValue({ docs: [{ data: () => fsRow }] });
    const res = await get(makeApp(), '/api/blood-tests?marker=creatinine&phase=home-hd&from=2026-06&to=2026-06');
    expect(res.status).toBe(200);
    const body = await res.json() as { rows: { lab_id: string }[] };
    expect(body.rows.some((r) => r.lab_id === 'fs-only')).toBe(true);
  });

  it('returns 400 for invalid phase', async () => {
    const res = await get(makeApp(), '/api/blood-tests?phase=bad-phase');
    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid from bound', async () => {
    const res = await get(makeApp(), '/api/blood-tests?from=not-a-date');
    expect(res.status).toBe(400);
  });
});

describe('POST /api/blood-tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockCommit.mockResolvedValue(undefined);
    mockSet.mockReturnValue(undefined);
    mockDoc.mockReturnValue({});
  });

  it('returns ok:true and count on valid input', async () => {
    const res = await post(makeApp(), { rows: [validRow] });
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean; count: number };
    expect(body.ok).toBe(true);
    expect(body.count).toBe(1);
  });

  it('writes to Firestore keyed by lab_id_marker with server-set created_at', async () => {
    await post(makeApp(), { rows: [validRow] });
    expect(mockDoc).toHaveBeenCalledWith('99261234567_creatinine');
    expect(mockSet).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ lab_id: '99261234567', created_at: expect.any(String) }),
    );
  });

  it('accepts multiple rows and returns the correct count', async () => {
    const rows = [validRow, { ...validRow, lab_id: 'other-id' }];
    const res = await post(makeApp(), { rows });
    expect(res.status).toBe(200);
    const body = await res.json() as { count: number };
    expect(body.count).toBe(2);
  });

  it('returns 400 for empty rows array', async () => {
    const res = await post(makeApp(), { rows: [] });
    expect(res.status).toBe(400);
  });

  it('returns 400 for rows with missing required fields', async () => {
    const res = await post(makeApp(), { rows: [{ marker: 'creatinine' }] });
    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid JSON body', async () => {
    const res = await makeApp().request('/api/blood-tests', {
      method: 'POST',
      headers: { Authorization: 'Bearer test-key', 'Content-Type': 'application/json' },
      body: 'not-json',
    });
    expect(res.status).toBe(400);
  });

  it('returns 401 without auth header', async () => {
    const res = await makeApp().request('/api/blood-tests', { method: 'POST' });
    expect(res.status).toBe(401);
  });
});
