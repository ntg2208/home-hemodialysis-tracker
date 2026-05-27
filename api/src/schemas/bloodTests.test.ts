import { describe, it, expect } from 'vitest';
import { PostBodySchema } from './bloodTests.js';

const validRow = {
  marker: 'creatinine',
  datetime: '2026-06-15T14:00:00',
  value: 980,
  unit: 'umol/L',
  ref_low: 64,
  ref_high: 104,
  timing: 'pre' as const,
  note: '',
  source: 'imperial-pkb',
  lab_id: '99261234567',
  phase: 'home-hd' as const,
  qualitative: false,
};

describe('PostBodySchema', () => {
  it('accepts a valid rows array', () => {
    expect(PostBodySchema.safeParse({ rows: [validRow] }).success).toBe(true);
  });

  it('rejects an empty rows array', () => {
    expect(PostBodySchema.safeParse({ rows: [] }).success).toBe(false);
  });

  it('rejects rows with an invalid phase', () => {
    expect(PostBodySchema.safeParse({ rows: [{ ...validRow, phase: 'icu' }] }).success).toBe(false);
  });

  it('rejects rows with an invalid timing', () => {
    expect(PostBodySchema.safeParse({ rows: [{ ...validRow, timing: 'during' }] }).success).toBe(false);
  });

  it('rejects rows missing required fields', () => {
    const { marker: _m, ...noMarker } = validRow;
    const result = PostBodySchema.safeParse({ rows: [noMarker] });
    expect(result.success).toBe(false);
  });

  it('does not require created_at on input rows', () => {
    const result = PostBodySchema.safeParse({ rows: [validRow] });
    expect(result.success).toBe(true);
    if (result.success) {
      expect('created_at' in result.data.rows[0]).toBe(false);
    }
  });

  it('accepts multiple rows', () => {
    const result = PostBodySchema.safeParse({ rows: [validRow, { ...validRow, lab_id: 'other' }] });
    expect(result.success).toBe(true);
    if (result.success) expect(result.data.rows).toHaveLength(2);
  });
});
