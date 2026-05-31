import { describe, it, expect, vi } from 'vitest';
import { extractLatest, countOf, isStale, parseDataFileName, buildSummary, type SummaryDeps } from './fitnessSummary.js';

// Wrap dataPoints the way ingest stores list-type files: { count, data: [...] }.
const listFile = (count: number, data: unknown[]) => ({ count, data });

describe('extractLatest — daily-resting-heart-rate', () => {
  it('returns the max-date reading (arrays are not time-sorted)', () => {
    const file = listFile(2, [
      { dailyRestingHeartRate: { date: { year: 2026, month: 5, day: 28 }, beatsPerMinute: '81' } },
      { dailyRestingHeartRate: { date: { year: 2026, month: 5, day: 30 }, beatsPerMinute: '83' } },
      { dailyRestingHeartRate: { date: { year: 2026, month: 5, day: 29 }, beatsPerMinute: '84' } },
    ]);
    expect(extractLatest('daily-resting-heart-rate', file)).toEqual({
      label: 'Resting HR', value: '83', unit: 'bpm', at: '2026-05-30',
    });
  });
});

describe('extractLatest — steps (dailyRollUp shape)', () => {
  it('reads rollupDataPoints and picks the latest civilStartTime', () => {
    const file = {
      data: {
        rollupDataPoints: [
          { civilStartTime: { date: { year: 2026, month: 5, day: 29 } }, steps: { countSum: '1029' } },
          { civilStartTime: { date: { year: 2026, month: 5, day: 30 } }, steps: { countSum: '2539' } },
        ],
      },
    };
    expect(extractLatest('steps', file)).toEqual({
      label: 'Steps', value: '2539', unit: '', at: '2026-05-30',
    });
  });
});

describe('extractLatest — oxygen-saturation (unsorted samples)', () => {
  it('finds the max sampleTime even when it is not last in the array', () => {
    const file = listFile(3, [
      { oxygenSaturation: { sampleTime: { civilTime: { date: { year: 2026, month: 5, day: 30 } } }, percentage: 96.4 } },
      { oxygenSaturation: { sampleTime: { civilTime: { date: { year: 2026, month: 5, day: 28 } } }, percentage: 90.1 } },
    ]);
    const r = extractLatest('oxygen-saturation', file);
    expect(r?.at).toBe('2026-05-30');
    expect(r?.value).toBe('96');
    expect(r?.unit).toBe('%');
  });
});

describe('extractLatest — sleep', () => {
  it('reports duration and deep minutes from the latest session', () => {
    const file = listFile(1, [
      {
        sleep: {
          interval: { endTime: '2026-05-30T09:03:00Z' },
          summary: {
            minutesAsleep: '474',
            stagesSummary: [
              { type: 'DEEP', minutes: '90' },
              { type: 'REM', minutes: '106' },
            ],
          },
        },
      },
    ]);
    const r = extractLatest('sleep', file);
    expect(r?.label).toBe('Sleep');
    expect(r?.value).toBe('7h 54m');
    expect(r?.unit).toBe('DEEP 90m');
    expect(r?.at).toBe('2026-05-30');
  });
});

describe('extractLatest — skin temp with "NaN" baseline', () => {
  it('shows nightly temp absolute and does not crash on the NaN-string baseline', () => {
    const file = listFile(1, [
      {
        dailySleepTemperatureDerivations: {
          date: { year: 2026, month: 5, day: 27 },
          nightlyTemperatureCelsius: 34.067368,
          baselineTemperatureCelsius: 'NaN',
          relativeNightlyStddev30dCelsius: 'NaN',
        },
      },
    ]);
    const r = extractLatest('daily-sleep-temperature-derivations', file);
    expect(r?.value).toBe('34.1');
    expect(r?.unit).toBe('°C');
    expect(r?.at).toBe('2026-05-27');
  });
});

describe('extractLatest — daily HRV', () => {
  it('returns averageHeartRateVariabilityMilliseconds as RMSSD', () => {
    const file = listFile(1, [
      { dailyHeartRateVariability: { date: { year: 2026, month: 5, day: 27 }, averageHeartRateVariabilityMilliseconds: 13.5 } },
    ]);
    expect(extractLatest('daily-heart-rate-variability', file)).toEqual({
      label: 'HRV (RMSSD)', value: '14', unit: 'ms', at: '2026-05-27',
    });
  });
});

describe('extractLatest — respiratory rate', () => {
  it('returns deep-sleep breaths/min from the latest session', () => {
    const file = listFile(1, [
      {
        respiratoryRateSleepSummary: {
          sampleTime: { civilTime: { date: { year: 2026, month: 5, day: 27 } } },
          deepSleepStats: { breathsPerMinute: 14.8 },
        },
      },
    ]);
    expect(extractLatest('respiratory-rate-sleep-summary', file)).toEqual({
      label: 'Resp. rate', value: '14.8', unit: '/min', at: '2026-05-27',
    });
  });
});

describe('extractLatest — status-only types', () => {
  it('returns null for heart-rate', () => {
    expect(extractLatest('heart-rate', listFile(0, []))).toBeNull();
  });
  it('returns null for raw heart-rate-variability', () => {
    expect(extractLatest('heart-rate-variability', listFile(0, []))).toBeNull();
  });
});

describe('extractLatest — empty / missing data', () => {
  it('returns null when there are no points', () => {
    expect(extractLatest('daily-resting-heart-rate', listFile(0, []))).toBeNull();
  });
});

describe('countOf', () => {
  it('uses the count field for list-type files', () => {
    expect(countOf('oxygen-saturation', listFile(1484, []))).toBe(1484);
  });
  it('falls back to data length when count is absent', () => {
    expect(countOf('daily-resting-heart-rate', { data: [{}, {}, {}] })).toBe(3);
  });
  it('counts rollupDataPoints for steps', () => {
    expect(countOf('steps', { data: { rollupDataPoints: [{}, {}] } })).toBe(2);
  });
});

describe('isStale', () => {
  it('is stale when never synced', () => {
    expect(isStale(null, '2026-06-01')).toBe(true);
  });
  it('is not stale at exactly 2 days old (job runs each morning)', () => {
    expect(isStale('2026-05-30', '2026-06-01')).toBe(false);
  });
  it('is stale beyond 2 days', () => {
    expect(isStale('2026-05-29', '2026-06-01')).toBe(true);
  });
});

describe('parseDataFileName', () => {
  it('extracts the start/end range from a raw data path', () => {
    expect(parseDataFileName('raw/steps/2026-05-01_to_2026-05-30.json'))
      .toEqual({ start: '2026-05-01', end: '2026-05-30' });
  });
  it('returns null for non-conforming names', () => {
    expect(parseDataFileName('raw/sync_state.json')).toBeNull();
  });
});

describe('buildSummary', () => {
  function deps(over: Partial<SummaryDeps> = {}): SummaryDeps {
    return {
      readSyncState: vi.fn().mockResolvedValue({}),
      listFiles: vi.fn().mockResolvedValue([]),
      readJson: vi.fn().mockResolvedValue({ data: [] }),
      readCount: vi.fn().mockResolvedValue(0),
      ...over,
    };
  }

  it('aggregates counts and date range across multiple files, latest from the newest', async () => {
    const d = deps({
      readSyncState: vi.fn().mockResolvedValue({ 'daily-resting-heart-rate': '2026-05-30' }),
      listFiles: vi.fn(async (prefix: string) =>
        prefix.includes('daily-resting-heart-rate')
          ? [
              { name: 'raw/daily-resting-heart-rate/2026-05-01_to_2026-05-15.json', size: 100 },
              { name: 'raw/daily-resting-heart-rate/2026-05-16_to_2026-05-30.json', size: 200 },
            ]
          : []),
      readJson: vi.fn(async (name: string) =>
        name.endsWith('2026-05-16_to_2026-05-30.json')
          ? { count: 15, data: [{ dailyRestingHeartRate: { date: { year: 2026, month: 5, day: 30 }, beatsPerMinute: '83' } }] }
          : { count: 15, data: [] }),
    });
    const out = await buildSummary(d, { types: ['daily-resting-heart-rate'], today: '2026-06-01' });
    const t = out.types[0];
    expect(t.count).toBe(30);                  // 15 + 15
    expect(t.first_date).toBe('2026-05-01');
    expect(t.last_date).toBe('2026-05-30');
    expect(t.stale).toBe(false);
    expect(t.latest).toEqual({ label: 'Resting HR', value: '83', unit: 'bpm', at: '2026-05-30' });
    expect(out.totals).toMatchObject({ types: 1, stale: 0, bytes: 300 });
  });

  it('uses range-read (not full parse) for heart-rate and emits no latest', async () => {
    const readJson = vi.fn().mockResolvedValue({ data: [] });
    const d = deps({
      listFiles: vi.fn(async () => [{ name: 'raw/heart-rate/2026-05-01_to_2026-05-30.json', size: 43000000 }]),
      readCount: vi.fn().mockResolvedValue(147725),
      readJson,
    });
    const out = await buildSummary(d, { types: ['heart-rate'], today: '2026-06-01' });
    expect(out.types[0].count).toBe(147725);
    expect(out.types[0].latest).toBeNull();
    expect(readJson).not.toHaveBeenCalled(); // never downloaded the 43MB blob
  });

  it('marks a type with no files as stale with zero count', async () => {
    const out = await buildSummary(deps(), { types: ['sleep'], today: '2026-06-01' });
    expect(out.types[0]).toMatchObject({ type: 'sleep', count: 0, stale: true, latest: null });
    expect(out.totals.stale).toBe(1);
  });

  it('isolates a failing type as { error } without aborting the rest', async () => {
    const d = deps({
      readSyncState: vi.fn().mockResolvedValue({ steps: '2026-05-30', sleep: '2026-05-30' }),
      listFiles: vi.fn(async (prefix: string) => {
        if (prefix.includes('steps')) throw new Error('gcs boom');
        return [{ name: 'raw/sleep/2026-05-30_to_2026-05-30.json', size: 10 }];
      }),
      readJson: vi.fn().mockResolvedValue({ count: 1, data: [] }),
    });
    const out = await buildSummary(d, { types: ['steps', 'sleep'], today: '2026-06-01' });
    expect(out.types.find((t) => t.type === 'steps')).toMatchObject({ error: expect.stringContaining('gcs boom') });
    expect(out.types.find((t) => t.type === 'sleep')).toMatchObject({ type: 'sleep', count: 1 });
  });
});
