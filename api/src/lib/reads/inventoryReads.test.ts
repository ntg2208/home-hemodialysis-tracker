import { describe, it, expect } from 'vitest';
import { averagePakLifespan } from './inventoryReads.js';

const doc = (sessions: number, replaced_at: string) => ({ data: () => ({ sessions, replaced_at }) });

describe('averagePakLifespan', () => {
  it('returns null with no history', () => {
    expect(averagePakLifespan([])).toBeNull();
  });
  it('averages the 6 most recent valid lifespans', () => {
    const docs = [
      doc(10, '2026-01-01'), doc(20, '2026-02-01'), doc(30, '2026-03-01'),
      doc(40, '2026-04-01'), doc(50, '2026-05-01'), doc(60, '2026-06-01'),
      doc(999, '2025-01-01'), // older than the most recent 6 → excluded
    ];
    expect(averagePakLifespan(docs)).toBe(35); // (10+20+30+40+50+60)/6
  });
});
