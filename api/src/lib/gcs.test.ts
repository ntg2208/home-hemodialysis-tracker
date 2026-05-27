import { describe, it, expect } from 'vitest';
import { dataTypePath, syncStatePath, dateRange } from './gcs.js';

describe('dataTypePath', () => {
  it('returns the correct GCS object path', () => {
    expect(dataTypePath('steps', '2026-05-27')).toBe('raw/steps/2026-05-27.json');
    expect(dataTypePath('sleep', '2026-01-01')).toBe('raw/sleep/2026-01-01.json');
  });
});

describe('syncStatePath', () => {
  it('returns fixed path', () => {
    expect(syncStatePath()).toBe('sync_state.json');
  });
});

describe('dateRange', () => {
  it('returns inclusive range of date strings', () => {
    expect(dateRange('2026-05-25', '2026-05-27')).toEqual([
      '2026-05-25',
      '2026-05-26',
      '2026-05-27',
    ]);
  });

  it('returns single date when from === to', () => {
    expect(dateRange('2026-05-27', '2026-05-27')).toEqual(['2026-05-27']);
  });

  it('returns empty array when from is after to', () => {
    expect(dateRange('2026-05-28', '2026-05-27')).toEqual([]);
  });
});
