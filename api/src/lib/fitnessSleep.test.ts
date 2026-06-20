import { describe, it, expect } from 'vitest';
import { parseSleepNight, buildSleep, type SleepDeps } from './fitnessSleep.js';

const stagesNight = (date: string) => ({
  data: [
    {
      sleep: {
        type: 'STAGES',
        interval: { startTime: `${date}T00:09:00Z`, endTime: `${date}T08:09:00Z` },
        stages: [
          { startTime: `${date}T00:09:00Z`, endTime: `${date}T00:18:00Z`, type: 'AWAKE' },
          { startTime: `${date}T00:18:00Z`, endTime: `${date}T02:00:00Z`, type: 'LIGHT' },
        ],
        summary: {
          minutesAsleep: '462',
          minutesAwake: '18',
          stagesSummary: [
            { type: 'AWAKE', minutes: '18' },
            { type: 'DEEP', minutes: '70' },
            { type: 'LIGHT', minutes: '300' },
            { type: 'REM', minutes: '92' },
          ],
        },
      },
    },
  ],
});

const classicNight = (date: string) => ({
  data: [
    {
      sleep: {
        type: 'classic',
        interval: { startTime: `${date}T01:00:00Z`, endTime: `${date}T07:00:00Z` },
        summary: { minutesAsleep: '360', minutesAwake: '0' },
      },
    },
  ],
});

describe('parseSleepNight', () => {
  it('parses a staged night with hypnogram + stage breakdown', () => {
    expect(parseSleepNight(stagesNight('2026-06-03'))).toEqual({
      date: '2026-06-03',
      minutesAsleep: 462,
      minutesAwake: 18,
      hasStages: true,
      stages: [
        { type: 'AWAKE', minutes: 18 },
        { type: 'DEEP', minutes: 70 },
        { type: 'LIGHT', minutes: 300 },
        { type: 'REM', minutes: 92 },
      ],
      hypnogram: [
        { type: 'AWAKE', start: '2026-06-03T00:09:00Z', end: '2026-06-03T00:18:00Z' },
        { type: 'LIGHT', start: '2026-06-03T00:18:00Z', end: '2026-06-03T02:00:00Z' },
      ],
    });
  });

  it('degrades gracefully for a classic night (total only)', () => {
    expect(parseSleepNight(classicNight('2026-06-04'))).toEqual({
      date: '2026-06-04',
      minutesAsleep: 360,
      minutesAwake: 0,
      hasStages: false,
      stages: [],
      hypnogram: [],
    });
  });

  it('returns null when there is no sleep payload', () => {
    expect(parseSleepNight({ data: [] })).toBeNull();
  });
});

describe('buildSleep', () => {
  const deps = (files: Record<string, unknown>): SleepDeps => ({
    listFiles: async () => Object.keys(files).map((name) => ({ name, size: 1 })),
    readJson: async (name) => files[name],
  });

  it('windows by date and returns nights newest first', async () => {
    const files = {
      'raw/sleep/2026-06-02_to_2026-06-02.json': stagesNight('2026-06-02'),
      'raw/sleep/2026-06-03_to_2026-06-03.json': stagesNight('2026-06-03'),
      'raw/sleep/2026-06-01_to_2026-06-01.json': classicNight('2026-06-01'),
    };
    const out = await buildSleep(deps(files), { from: '2026-06-02', to: '2026-06-03' });
    expect(out.nights.map((n) => n.date)).toEqual(['2026-06-03', '2026-06-02']);
  });
});
