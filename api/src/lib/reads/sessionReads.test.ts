import { describe, it, expect } from 'vitest';
import { joinSessions } from './sessionReads.js';

const sessions = [
  { session_id: 's1', date: '2026-05-01' },
  { session_id: 's2', date: '2026-05-03' },
  { session_id: 's3', date: '2026-05-05' },
];
const readings = [
  { reading_id: 'r1', session_id: 's2', seq: 2, bp_sys: 120 },
  { reading_id: 'r2', session_id: 's2', seq: 1, bp_sys: 130 },
];

describe('joinSessions', () => {
  it('attaches readings sorted by seq, newest sessions first', () => {
    const out = joinSessions(sessions, readings, {});
    expect(out.map((s) => s.session_id)).toEqual(['s3', 's2', 's1']);
    const s2 = out.find((s) => s.session_id === 's2')!;
    expect(s2.readings.map((r) => r.seq)).toEqual([1, 2]);
  });

  it('filters by from/to (date prefix) and applies limit', () => {
    const out = joinSessions(sessions, readings, { from: '2026-05-03', limit: 1 });
    expect(out.map((s) => s.session_id)).toEqual(['s3']); // s1 excluded, newest first, limit 1
  });
});
