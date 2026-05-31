import { describe, it, expect } from 'vitest';
import { mergeRows, sixMonthsAgo, computeFetchRange, earlierMonth } from './cache';
import type { BloodTestRow } from '../schemas';

function row(over: Partial<BloodTestRow>): BloodTestRow {
  return {
    marker: 'urea', datetime: '2026-03-15T12:00:00', value: 5, unit: 'mmol/L',
    ref_low: 2.5, ref_high: 7.8, timing: '', note: '', source: 'imperial-pkb',
    lab_id: '1', phase: 'home-hd', created_at: '', qualitative: false, ...over,
  };
}

describe('mergeRows', () => {
  it('unions disjoint rows', () => {
    const a = [row({ lab_id: '1', marker: 'urea' })];
    const b = [row({ lab_id: '2', marker: 'creatinine' })];
    expect(mergeRows(a, b)).toHaveLength(2);
  });

  it('incoming overwrites existing with the same lab_id+marker (picks up edits)', () => {
    const existing = [row({ lab_id: '1', marker: 'urea', value: 5, timing: '' })];
    const incoming = [row({ lab_id: '1', marker: 'urea', value: 5, timing: 'pre' })];
    const merged = mergeRows(existing, incoming);
    expect(merged).toHaveLength(1);
    expect(merged[0].timing).toBe('pre');
  });

  it('distinguishes same lab_id across different markers', () => {
    const existing = [row({ lab_id: '1', marker: 'urea' })];
    const incoming = [row({ lab_id: '1', marker: 'creatinine' })];
    expect(mergeRows(existing, incoming)).toHaveLength(2);
  });
});

describe('sixMonthsAgo', () => {
  it('returns YYYY-MM six months before the given date', () => {
    expect(sixMonthsAgo(new Date('2026-05-30'))).toBe('2025-11');
  });
  it('handles year boundary', () => {
    expect(sixMonthsAgo(new Date('2026-02-15'))).toBe('2025-08');
  });
});

describe('earlierMonth', () => {
  it("treats '' as the earliest (all time)", () => {
    expect(earlierMonth('', '2025-11')).toBe(true);
    expect(earlierMonth('2025-11', '')).toBe(false);
  });
  it('compares real months', () => {
    expect(earlierMonth('2025-06', '2025-11')).toBe(true);
    expect(earlierMonth('2026-01', '2025-11')).toBe(false);
    expect(earlierMonth('2025-11', '2025-11')).toBe(false);
  });
});

describe('computeFetchRange', () => {
  it('fetches the requested from when nothing is cached', () => {
    expect(computeFetchRange(null, '2025-11')).toEqual({ from: '2025-11' });
  });
  it('returns null when the cache already covers the requested range', () => {
    expect(computeFetchRange('2025-11', '2026-01')).toBeNull();
    expect(computeFetchRange('2025-11', '2025-11')).toBeNull();
  });
  it('fetches only the uncovered older slice when extending backward', () => {
    expect(computeFetchRange('2025-11', '2025-06')).toEqual({ from: '2025-06', to: '2025-11' });
  });
  it("an 'all time' request ('') fetches everything older than coverage", () => {
    expect(computeFetchRange('2025-11', '')).toEqual({ from: '', to: '2025-11' });
  });
  it("returns null for 'all time' when coverage is already all time", () => {
    expect(computeFetchRange('', '')).toBeNull();
  });
});
