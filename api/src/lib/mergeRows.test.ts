import { describe, it, expect } from 'vitest';
import { mergeRows } from './mergeRows.js';
import type { BloodTestRow } from '../schemas/bloodTests.js';

function row(over: Partial<BloodTestRow>): BloodTestRow {
  return {
    marker: 'creatinine', datetime: '2026-05-18T14:00:00', value: 1073,
    unit: 'umol/L', ref_low: 64, ref_high: 104, timing: 'pre', note: '',
    source: 'imperial-pkb', lab_id: 'abc123', phase: 'home-hd',
    created_at: '2026-05-22T10:00:00', qualitative: false, ...over,
  };
}

describe('mergeRows', () => {
  it('returns static rows when Firestore rows is empty', () => {
    const result = mergeRows([row({ lab_id: 'a' })], []);
    expect(result).toHaveLength(1);
    expect(result[0].lab_id).toBe('a');
  });

  it('returns Firestore rows when static rows is empty', () => {
    const result = mergeRows([], [row({ lab_id: 'b' })]);
    expect(result).toHaveLength(1);
    expect(result[0].lab_id).toBe('b');
  });

  it('combines rows from both sources with no overlap', () => {
    const result = mergeRows([row({ lab_id: 'a' })], [row({ lab_id: 'b' })]);
    expect(result).toHaveLength(2);
  });

  it('Firestore row wins on (lab_id, marker) collision', () => {
    const staticRow = row({ lab_id: 'x', marker: 'creatinine', value: 100, created_at: '2026-05-01T00:00:00' });
    const fsRow    = row({ lab_id: 'x', marker: 'creatinine', value: 999, created_at: '2026-05-27T00:00:00' });
    const result = mergeRows([staticRow], [fsRow]);
    expect(result).toHaveLength(1);
    expect(result[0].value).toBe(999);
  });

  it('keeps separate rows for different markers sharing the same lab_id', () => {
    const r1 = row({ lab_id: 'x', marker: 'creatinine' });
    const r2 = row({ lab_id: 'x', marker: 'urea' });
    const result = mergeRows([r1, r2], []);
    expect(result).toHaveLength(2);
  });

  it('returns empty array when both inputs are empty', () => {
    expect(mergeRows([], [])).toHaveLength(0);
  });
});
