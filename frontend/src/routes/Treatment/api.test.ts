import { describe, it, expect, vi, beforeEach } from 'vitest';

const { mockSetDoc, mockUpdateDoc, mockGetDocs, mockDoc, mockCollection } = vi.hoisted(() => ({
  mockSetDoc: vi.fn().mockResolvedValue(undefined),
  mockUpdateDoc: vi.fn().mockResolvedValue(undefined),
  mockGetDocs: vi.fn(),
  mockDoc: vi.fn((_db: unknown, path: string, id: string) => ({ _path: `${path}/${id}` })),
  mockCollection: vi.fn((_db: unknown, path: string) => ({ _path: path })),
}));

vi.mock('firebase/firestore', () => ({
  setDoc: mockSetDoc,
  updateDoc: mockUpdateDoc,
  getDocs: mockGetDocs,
  doc: mockDoc,
  collection: mockCollection,
}));

vi.mock('../../lib/firebaseClient', () => ({ db: { _mock: true } }));

import { saveSession, saveReading, updateSession, getAll, ApiError } from './api';
import type { Session, Reading } from './schemas';

const session: Session = {
  session_id: '2026-05-31',
  date: '2026-05-31',
  pre_weight: 61.2,
  pre_bp_sys: 135,
  pre_bp_dia: 82,
  pre_pulse: 72,
  created_at: '2026-05-31T18:00:00.000Z',
};

const reading: Reading = {
  reading_id: '2026-05-31-r1',
  session_id: '2026-05-31',
  seq: 1,
  time: '19:15',
  bp_sys: 128,
  bp_dia: 78,
};

beforeEach(() => vi.clearAllMocks());

describe('saveSession', () => {
  it('calls setDoc on treatment_sessions/{session_id}', async () => {
    await saveSession(session);
    expect(mockSetDoc).toHaveBeenCalledWith(
      expect.objectContaining({ _path: 'treatment_sessions/2026-05-31' }),
      session,
    );
  });

  it('stores numeric fields as numbers (not strings)', async () => {
    await saveSession(session);
    const written = mockSetDoc.mock.calls[0][1] as Session;
    expect(typeof written.pre_weight).toBe('number');
    expect(typeof written.pre_bp_sys).toBe('number');
  });

  it('throws ApiError on Firestore error', async () => {
    mockSetDoc.mockRejectedValueOnce(new Error('network'));
    await expect(saveSession(session)).rejects.toThrow(ApiError);
  });
});

describe('saveReading', () => {
  it('calls setDoc on treatment_readings/{reading_id}', async () => {
    await saveReading(reading);
    expect(mockSetDoc).toHaveBeenCalledWith(
      expect.objectContaining({ _path: 'treatment_readings/2026-05-31-r1' }),
      reading,
    );
  });
});

describe('updateSession', () => {
  it('calls updateDoc with only the patched fields (not session_id)', async () => {
    await updateSession({ session_id: '2026-05-31', post_weight: 59.0, post_bp_sys: 122 });
    expect(mockUpdateDoc).toHaveBeenCalledWith(
      expect.objectContaining({ _path: 'treatment_sessions/2026-05-31' }),
      { post_weight: 59.0, post_bp_sys: 122 },
    );
  });
});

describe('getAll', () => {
  it('returns sessions and readings from both collections', async () => {
    mockGetDocs
      .mockResolvedValueOnce({ docs: [{ data: () => session }] })
      .mockResolvedValueOnce({ docs: [{ data: () => reading }] });

    const result = await getAll();
    expect(result.ok).toBe(true);
    expect(result.sessions).toHaveLength(1);
    expect(result.readings).toHaveLength(1);
    expect(result.sessions[0].session_id).toBe('2026-05-31');
    expect(result.readings[0].reading_id).toBe('2026-05-31-r1');
  });

  it('throws ApiError with code "unauthorized" on permission-denied', async () => {
    mockGetDocs.mockRejectedValueOnce(new Error('Missing or insufficient permissions'));
    await expect(getAll()).rejects.toThrow(expect.objectContaining({ code: 'unauthorized' }));
  });
});
