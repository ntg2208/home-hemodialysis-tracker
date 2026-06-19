import { describe, it, expect, vi, beforeEach } from 'vitest';

const { mockSheetsUpdate, mockSheetsClear, mockLimit } = vi.hoisted(() => ({
  mockSheetsUpdate: vi.fn().mockResolvedValue({ data: {} }),
  mockSheetsClear: vi.fn().mockResolvedValue({ data: {} }),
  mockLimit: vi.fn(),
}));

vi.mock('googleapis', () => ({
  google: {
    auth: {
      GoogleAuth: vi.fn().mockImplementation(() => ({
        getClient: vi.fn().mockResolvedValue({}),
      })),
    },
    sheets: vi.fn().mockReturnValue({
      spreadsheets: {
        values: {
          clear: mockSheetsClear,
          update: mockSheetsUpdate,
        },
      },
    }),
  },
}));

vi.mock('@google-cloud/firestore', () => {
  const mockSessionData = {
    session_id: '2026-05-31',
    date: '2026-05-31',
    pre_weight: 61.2,
    uf_goal: 2.2,
    uf_rate: 550,
    pre_bp_sys: 135,
    pre_bp_dia: 82,
    pre_pulse: 72,
    created_at: '2026-05-31T18:00:00.000Z',
  };
  const mockReadingData = {
    reading_id: '2026-05-31-r1',
    session_id: '2026-05-31',
    seq: 1,
    time: '19:15',
    bp_sys: 128,
    bp_dia: 78,
    pulse: 70,
    blood_flow: 350,
    venous_pressure: 150,
    arterial_pressure: -120,
    created_at: '2026-05-31T19:15:00.000Z',
  };
  return {
    Firestore: vi.fn().mockImplementation(() => ({
      collection: vi.fn().mockReturnValue({
        orderBy: vi.fn().mockReturnThis(),
        limit: mockLimit.mockReturnThis(),
        get: vi.fn()
          .mockResolvedValueOnce({ docs: [{ data: () => mockSessionData }] })
          .mockResolvedValueOnce({ docs: [{ data: () => mockReadingData }] }),
      }),
    })),
  };
});

vi.mock('firebase-admin/auth', () => ({
  getAuth: vi.fn().mockReturnValue({
    createCustomToken: vi.fn().mockResolvedValue('mock-firebase-token'),
  }),
}));

vi.mock('firebase-admin/app', () => ({
  initializeApp: vi.fn(),
  getApps: vi.fn().mockReturnValue([]),
}));

import { Hono } from 'hono';
import { treatment } from './treatment.js';

function makeApp() {
  const app = new Hono();
  app.route('/api/treatment', treatment);
  return app;
}

describe('GET /api/treatment/token', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns a firebase token and expires_at', async () => {
    const res = await makeApp().request('/api/treatment/token');
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(body.ok).toBe(true);
    expect(body.token).toBe('mock-firebase-token');
    expect(typeof body.expires_at).toBe('number');
    expect(body.expires_at as number).toBeGreaterThan(Date.now() + 54 * 60 * 1000);
  });

  it('returns 500 when firebase-admin throws', async () => {
    const { getAuth } = await import('firebase-admin/auth');
    vi.mocked(getAuth).mockReturnValue({
      createCustomToken: vi.fn().mockRejectedValue(new Error('iam error')),
    } as ReturnType<typeof getAuth>);

    const res = await makeApp().request('/api/treatment/token');
    expect(res.status).toBe(500);
    const body = await res.json() as Record<string, unknown>;
    expect(body.ok).toBe(false);
  });
});

describe('POST /api/treatment/sync-to-sheet', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    process.env.TREATMENT_SHEET_ID = 'test-sheet-id';
  });

  it('writes sessions and readings to Sheet and returns counts', async () => {
    const res = await makeApp().request('/api/treatment/sync-to-sheet', { method: 'POST' });
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(body.ok).toBe(true);
    expect(body.sessions_written).toBe(1);
    expect(body.readings_written).toBe(1);
    expect(mockSheetsUpdate).toHaveBeenCalled();

    // Verify legacy_view content
    const legacyCalls = mockSheetsUpdate.mock.calls.filter(
      (call: unknown[]) => {
        const args = call[0] as Record<string, unknown>;
        return args['range'] === 'legacy_view!A1';
      }
    );
    expect(legacyCalls).toHaveLength(1);
    const legacyValues = (legacyCalls[0][0] as Record<string, unknown>)['requestBody'] as Record<string, unknown>;
    const rows = legacyValues['values'] as unknown[][];
    // Header row
    expect(rows[0][0]).toBe('Date');
    // Data row: with 1 reading, row 1 is both first and last
    const dataRow = rows[1];
    expect(dataRow[0]).toBe('2026-05-31');        // date on last row
    expect(dataRow[4]).toBe('135/82');             // pre BP as "sys/dia"
    expect(dataRow[6]).toBe('19:15');             // reading time
    expect(dataRow[7]).toBe('128/78');            // reading BP
  });

  it('caps the sync at the 32 most recent sessions', async () => {
    await makeApp().request('/api/treatment/sync-to-sheet', { method: 'POST' });
    expect(mockLimit).toHaveBeenCalledWith(32);
  });

  it('returns 500 when TREATMENT_SHEET_ID is missing', async () => {
    delete process.env.TREATMENT_SHEET_ID;
    const res = await makeApp().request('/api/treatment/sync-to-sheet', { method: 'POST' });
    expect(res.status).toBe(500);
    const body = await res.json() as Record<string, unknown>;
    expect(body.ok).toBe(false);
  });
});
