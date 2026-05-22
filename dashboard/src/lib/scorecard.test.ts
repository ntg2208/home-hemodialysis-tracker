import { describe, it, expect } from 'vitest';
import { summarize } from './scorecard';
import type { BloodTestRow } from '../schemas';

function row(over: Partial<BloodTestRow>): BloodTestRow {
  return {
    marker: 'urea', datetime: '2026-03-15T12:00:00', value: 5, unit: 'mmol/L',
    ref_low: 2.5, ref_high: 7.8, timing: '', note: '', source: 'imperial-pkb',
    lab_id: '1', phase: 'home-hd', created_at: '', qualitative: false, ...over,
  };
}

describe('summarize', () => {
  it('picks the latest numeric row and computes the delta', () => {
    const s = summarize('urea', [
      row({ datetime: '2026-03-01T09:00:00', value: 6 }),
      row({ datetime: '2026-04-01T09:00:00', value: 8 }),
    ]);
    expect(s.latest?.value).toBe(8);
    expect(s.delta).toBe(2);
    expect(s.direction).toBe('up');
  });

  it('marks an out-of-range latest value', () => {
    const s = summarize('urea', [row({ value: 9, ref_low: 2.5, ref_high: 7.8 })]);
    expect(s.status).toBe('out');
  });

  it('marks an in-range latest value', () => {
    const s = summarize('urea', [row({ value: 5 })]);
    expect(s.status).toBe('in');
  });

  it('returns unknown status when the reference range is missing', () => {
    const s = summarize('mcv', [row({ ref_low: null, ref_high: null })]);
    expect(s.status).toBe('unknown');
  });

  it('ignores qualitative rows when choosing latest', () => {
    const s = summarize('urea', [
      row({ datetime: '2026-04-01T09:00:00', value: 7 }),
      row({ datetime: '2026-05-01T09:00:00', value: 0, qualitative: true }),
    ]);
    expect(s.latest?.value).toBe(7);
  });

  it('has null delta and direction with only one reading', () => {
    const s = summarize('urea', [row({ value: 5 })]);
    expect(s.delta).toBeNull();
    expect(s.direction).toBeNull();
  });

  it('returns an empty summary for no rows', () => {
    const s = summarize('urea', []);
    expect(s.latest).toBeNull();
    expect(s.status).toBe('unknown');
  });
});
