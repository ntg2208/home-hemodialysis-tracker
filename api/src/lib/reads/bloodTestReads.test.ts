import { describe, it, expect } from 'vitest';
import { selectOutOfRange } from './bloodTestReads.js';
import type { BloodTestRow } from '../../schemas/bloodTests.js';

const row = (over: Partial<BloodTestRow>): BloodTestRow => ({
  marker: 'potassium', datetime: '2026-05-01T09:00:00', value: 5.0, unit: 'mmol/L',
  ref_low: 3.5, ref_high: 5.3, timing: '', note: '', source: 'test',
  lab_id: '1', phase: 'home-hd', created_at: '2026-05-01T09:00:00', qualitative: false,
  ...over,
});

describe('selectOutOfRange', () => {
  it('keeps values below ref_low or above ref_high', () => {
    const rows = [
      row({ lab_id: 'a', value: 5.0 }),               // in range
      row({ lab_id: 'b', value: 6.1 }),               // above
      row({ lab_id: 'c', value: 2.9 }),               // below
    ];
    expect(selectOutOfRange(rows).map(r => r.lab_id)).toEqual(['b', 'c']);
  });

  it('ignores qualitative rows and rows missing a bound', () => {
    const rows = [
      row({ lab_id: 'q', value: 9, qualitative: true }),
      row({ lab_id: 'n', value: 9, ref_high: null }),
    ];
    expect(selectOutOfRange(rows)).toEqual([]);
  });
});
