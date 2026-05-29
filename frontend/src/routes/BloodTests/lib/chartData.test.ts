import { describe, it, expect } from 'vitest';
import { toNivoSeries, getReferenceRange, getPointColor } from './chartData';
import type { BloodTestRow } from '../schemas';

function row(overrides: Partial<BloodTestRow> = {}): BloodTestRow {
  return {
    marker: 'haemoglobin',
    datetime: '2024-01-15T09:00:00',
    value: 130,
    unit: 'g/L',
    ref_low: 130,
    ref_high: 170,
    timing: '',
    note: '',
    source: '',
    lab_id: '',
    phase: 'home-hd',
    created_at: '2024-01-15T09:00:00',
    qualitative: false,
    ...overrides,
  };
}

describe('getReferenceRange', () => {
  it('returns null when no rows have ref values', () => {
    const rows = [row({ ref_low: null, ref_high: null })];
    expect(getReferenceRange(rows)).toBeNull();
  });

  it('returns low/high/unit from the most recent row with ref values', () => {
    const rows = [
      row({ datetime: '2024-01-01T00:00:00', ref_low: 120, ref_high: 160, unit: 'g/L' }),
      row({ datetime: '2024-06-01T00:00:00', ref_low: 130, ref_high: 170, unit: 'g/L' }),
      row({ datetime: '2024-03-01T00:00:00', ref_low: 125, ref_high: 165, unit: 'g/L' }),
    ];
    expect(getReferenceRange(rows)).toEqual({ low: 130, high: 170, unit: 'g/L' });
  });

  it('ignores rows where only one ref value is set', () => {
    const rows = [
      row({ ref_low: 130, ref_high: null }),
      row({ datetime: '2023-01-01T00:00:00', ref_low: 120, ref_high: 160 }),
    ];
    expect(getReferenceRange(rows)).toEqual({ low: 120, high: 160, unit: 'g/L' });
  });
});

describe('getPointColor', () => {
  it('returns red for out-of-range points', () => {
    expect(getPointColor({ inRange: false, timing: '' })).toBe('#f87171');
  });

  it('returns red for out-of-range even if timing is pre', () => {
    expect(getPointColor({ inRange: false, timing: 'pre' })).toBe('#f87171');
  });

  it('returns cyan for pre-dialysis in-range', () => {
    expect(getPointColor({ inRange: true, timing: 'pre' })).toBe('#22d3ee');
  });

  it('returns amber for post-dialysis in-range', () => {
    expect(getPointColor({ inRange: true, timing: 'post' })).toBe('#f59e0b');
  });

  it('returns indigo for plain in-range', () => {
    expect(getPointColor({ inRange: true, timing: '' })).toBe('#818cf8');
  });

  it('returns indigo for plain when inRange is null (no ref data)', () => {
    expect(getPointColor({ inRange: null, timing: '' })).toBe('#818cf8');
  });

  it('returns cyan for pre when inRange is null', () => {
    expect(getPointColor({ inRange: null, timing: 'pre' })).toBe('#22d3ee');
  });
});

describe('toNivoSeries', () => {
  it('filters out qualitative rows', () => {
    const rows = [
      row({ qualitative: false, value: 130 }),
      row({ datetime: '2024-02-01T00:00:00', qualitative: true, value: 999 }),
    ];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data).toHaveLength(1);
    expect(series.data[0].y).toBe(130);
  });

  it('sorts rows by datetime ascending', () => {
    const rows = [
      row({ datetime: '2024-03-01T00:00:00', value: 140 }),
      row({ datetime: '2024-01-01T00:00:00', value: 120 }),
      row({ datetime: '2024-02-01T00:00:00', value: 130 }),
    ];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data.map(d => d.y)).toEqual([120, 130, 140]);
  });

  it('sets x as a Date object', () => {
    const rows = [row({ datetime: '2024-01-15T09:00:00' })];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data[0].x).toBeInstanceOf(Date);
  });

  it('marks a point inRange=false when value is below ref_low', () => {
    const rows = [row({ value: 110, ref_low: 130, ref_high: 170 })];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data[0].inRange).toBe(false);
  });

  it('marks a point inRange=true when value is within range', () => {
    const rows = [row({ value: 150, ref_low: 130, ref_high: 170 })];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data[0].inRange).toBe(true);
  });

  it('sets inRange=null when ref values are missing', () => {
    const rows = [row({ value: 150, ref_low: null, ref_high: null })];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data[0].inRange).toBeNull();
  });

  it('preserves timing, unit, refLow, refHigh on each datum', () => {
    const rows = [row({ timing: 'pre', unit: 'g/L', ref_low: 130, ref_high: 170 })];
    const series = toNivoSeries('haemoglobin', rows);
    const d = series.data[0];
    expect(d.timing).toBe('pre');
    expect(d.unit).toBe('g/L');
    expect(d.refLow).toBe(130);
    expect(d.refHigh).toBe(170);
  });

  it('deduplicates same-day readings, keeping pre over post', () => {
    const rows = [
      row({ datetime: '2024-01-15T08:00:00', timing: 'pre', value: 115 }),
      row({ datetime: '2024-01-15T14:00:00', timing: 'post', value: 120 }),
    ];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data).toHaveLength(1);
    expect(series.data[0].timing).toBe('pre');
    expect(series.data[0].y).toBe(115);
  });

  it('deduplicates same-day readings, keeping post over plain', () => {
    const rows = [
      row({ datetime: '2024-01-15T08:00:00', timing: '', value: 115 }),
      row({ datetime: '2024-01-15T14:00:00', timing: 'post', value: 120 }),
    ];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data).toHaveLength(1);
    expect(series.data[0].timing).toBe('post');
  });

  it('keeps separate points for different calendar dates', () => {
    const rows = [
      row({ datetime: '2024-01-15T08:00:00', timing: 'pre', value: 115 }),
      row({ datetime: '2024-02-15T08:00:00', timing: 'pre', value: 118 }),
    ];
    const series = toNivoSeries('haemoglobin', rows);
    expect(series.data).toHaveLength(2);
  });
});
