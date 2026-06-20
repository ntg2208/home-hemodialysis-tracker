import { describe, it, expect } from 'vitest';
import { extractSeries, buildSeries, type SeriesDeps } from './fitnessSeries.js';

const rhrFile = (rows: Array<{ d: string; bpm: number }>) => ({
  data: rows.map(({ d, bpm }) => {
    const [year, month, day] = d.split('-').map(Number);
    return { dailyRestingHeartRate: { date: { year, month, day }, beatsPerMinute: bpm } };
  }),
});

describe('extractSeries', () => {
  it('extracts {date, value} per datapoint for a list type', () => {
    const file = rhrFile([{ d: '2026-06-01', bpm: 58 }, { d: '2026-06-02', bpm: 60 }]);
    expect(extractSeries('daily-resting-heart-rate', file)).toEqual([
      { date: '2026-06-01', value: 58 },
      { date: '2026-06-02', value: 60 },
    ]);
  });

  it('skips datapoints with a non-finite value', () => {
    const file = { data: [{ dailyRestingHeartRate: { date: { year: 2026, month: 6, day: 1 }, beatsPerMinute: 'NaN' } }] };
    expect(extractSeries('daily-resting-heart-rate', file)).toEqual([]);
  });

  it('returns [] for status-only / unknown types', () => {
    expect(extractSeries('heart-rate', { data: [] })).toEqual([]);
    expect(extractSeries('mystery', { data: [] })).toEqual([]);
  });
});

describe('buildSeries', () => {
  const deps = (files: Record<string, unknown>): SeriesDeps => ({
    listFiles: async () => Object.keys(files).map((name) => ({ name, size: 1 })),
    readJson: async (name) => files[name],
  });

  it('merges files, windows by date, sorts ascending, dedupes by date', async () => {
    const files = {
      'raw/daily-resting-heart-rate/2026-06-01_to_2026-06-02.json': rhrFile([
        { d: '2026-06-01', bpm: 58 }, { d: '2026-06-02', bpm: 60 },
      ]),
      'raw/daily-resting-heart-rate/2026-06-03_to_2026-06-03.json': rhrFile([{ d: '2026-06-03', bpm: 62 }]),
    };
    const out = await buildSeries(deps(files), {
      type: 'daily-resting-heart-rate', from: '2026-06-02', to: '2026-06-03',
    });
    expect(out).toEqual({
      type: 'daily-resting-heart-rate',
      points: [{ date: '2026-06-02', value: 60 }, { date: '2026-06-03', value: 62 }],
    });
  });

  it('last value wins on duplicate dates', async () => {
    const files = {
      'raw/daily-resting-heart-rate/2026-06-01_to_2026-06-01.json': rhrFile([{ d: '2026-06-01', bpm: 58 }]),
      'raw/daily-resting-heart-rate/2026-06-01_to_2026-06-01_v2.json': rhrFile([{ d: '2026-06-01', bpm: 99 }]),
    };
    const out = await buildSeries(deps(files), {
      type: 'daily-resting-heart-rate', from: '2026-06-01', to: '2026-06-01',
    });
    expect(out.points).toEqual([{ date: '2026-06-01', value: 99 }]);
  });
});
