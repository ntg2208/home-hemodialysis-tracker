import { describe, it, expect } from 'vitest';
import { filterRows, isValidBound, type QueryParams } from './queryFilter';
import type { BloodTestRow } from '../schemas';

function row(over: Partial<BloodTestRow>): BloodTestRow {
  return {
    marker: 'urea', datetime: '2026-03-15T12:00:00', value: 5, unit: 'mmol/L',
    ref_low: 2.5, ref_high: 7.8, timing: '', note: '', source: 'imperial-pkb',
    lab_id: '1', phase: 'home-hd', created_at: '', qualitative: false, ...over,
  };
}

const rows: BloodTestRow[] = [
  row({ marker: 'urea', datetime: '2026-01-10T09:00:00', phase: 'home-hd' }),
  row({ marker: 'urea', datetime: '2026-04-15T09:00:00', phase: 'home-hd' }),
  row({ marker: 'creatinine', datetime: '2026-04-20T09:00:00', phase: 'home-hd' }),
  row({ marker: 'urea', datetime: '2025-06-01T09:00:00', phase: 'in-center-hd' }),
];

describe('isValidBound', () => {
  it('accepts YYYY-MM and YYYY-MM-DD', () => {
    expect(isValidBound('2026-04')).toBe(true);
    expect(isValidBound('2026-04-15')).toBe(true);
  });
  it('rejects malformed bounds', () => {
    expect(isValidBound('2026')).toBe(false);
    expect(isValidBound('April')).toBe(false);
  });
});

describe('filterRows', () => {
  it('filters by marker', () => {
    expect(filterRows(rows, { marker: ['creatinine'] })).toHaveLength(1);
  });
  it('filters by phase', () => {
    expect(filterRows(rows, { phase: ['in-center-hd'] })).toHaveLength(1);
  });
  it('month-granularity `to` keeps the whole month', () => {
    const r = filterRows(rows, { to: '2026-04' });
    expect(r.map((x) => x.datetime).sort()).toEqual([
      '2025-06-01T09:00:00', '2026-01-10T09:00:00', '2026-04-15T09:00:00', '2026-04-20T09:00:00',
    ]);
  });
  it('month range from/to is inclusive on both ends', () => {
    const r = filterRows(rows, { from: '2026-01', to: '2026-04' });
    expect(r).toHaveLength(3);
  });
  it('day-granularity bounds work', () => {
    const r = filterRows(rows, { from: '2026-04-16', to: '2026-04-20' });
    expect(r.map((x) => x.marker)).toEqual(['creatinine']);
  });
  it('combines marker + phase + range', () => {
    const r = filterRows(rows, { marker: ['urea'], phase: ['home-hd'], from: '2026-02' });
    expect(r.map((x) => x.datetime)).toEqual(['2026-04-15T09:00:00']);
  });
  it('empty params returns everything', () => {
    expect(filterRows(rows, {})).toHaveLength(4);
  });
});
