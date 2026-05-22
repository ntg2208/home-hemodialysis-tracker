import { describe, expect, it } from 'vitest';
import { nextSessionId } from './sessionId';

describe('nextSessionId', () => {
  it('returns YYYY-MM-DD when no existing ids for that date', () => {
    expect(nextSessionId('2026-05-10', [])).toBe('2026-05-10');
    expect(nextSessionId('2026-05-10', ['2026-05-09'])).toBe('2026-05-10');
  });

  it('appends -2 when one session already exists for the date', () => {
    expect(nextSessionId('2026-05-10', ['2026-05-10'])).toBe('2026-05-10-2');
  });

  it('appends -3 when -2 already exists', () => {
    expect(nextSessionId('2026-05-10', ['2026-05-10', '2026-05-10-2'])).toBe('2026-05-10-3');
  });

  it('handles non-contiguous suffixes (uses max + 1)', () => {
    expect(nextSessionId('2026-05-10', ['2026-05-10', '2026-05-10-5'])).toBe('2026-05-10-6');
  });

  it('ignores ids for other dates', () => {
    expect(nextSessionId('2026-05-10', ['2026-05-09', '2026-05-09-2', '2026-05-11'])).toBe('2026-05-10');
  });
});
