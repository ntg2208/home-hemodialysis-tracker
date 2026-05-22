import { describe, it, expect } from 'vitest';
import { BloodTestRowSchema, ApiResponseSchema } from './schemas';

const validRow = {
  marker: 'creatinine', datetime: '2026-05-18T14:18:00', value: 1073,
  unit: 'umol/L', ref_low: 64, ref_high: 104, timing: 'pre',
  note: '', source: 'imperial-pkb', lab_id: '99261284417',
  phase: 'home-hd', created_at: '2026-05-22T10:00:00', qualitative: false,
};

describe('BloodTestRowSchema', () => {
  it('accepts a valid row', () => {
    expect(BloodTestRowSchema.parse(validRow).marker).toBe('creatinine');
  });
  it('accepts null reference bounds', () => {
    expect(BloodTestRowSchema.parse({ ...validRow, ref_low: null, ref_high: null }).ref_low).toBeNull();
  });
  it('rejects an unknown phase', () => {
    expect(BloodTestRowSchema.safeParse({ ...validRow, phase: 'outpatient' }).success).toBe(false);
  });
});

describe('ApiResponseSchema', () => {
  it('accepts a response with count and rows', () => {
    expect(ApiResponseSchema.parse({ count: 1, rows: [validRow] }).count).toBe(1);
  });
});
