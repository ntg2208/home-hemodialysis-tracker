// Pure helpers for the per-night sleep endpoint.
// Reads sleep stage breakdown + hypnogram from the raw `sleep` files.

import { G, num, dataArray } from './fitnessExtract.js';
import { parseDataFileName } from './fitnessSummary.js';

export interface SleepStage {
  type: string; // AWAKE | LIGHT | DEEP | REM
  minutes: number;
}

export interface HypnogramSegment {
  type: string;
  start: string;
  end: string;
}

export interface SleepNight {
  date: string; // YYYY-MM-DD (interval end)
  minutesAsleep: number | null;
  minutesAwake: number | null;
  hasStages: boolean;
  stages: SleepStage[];
  hypnogram: HypnogramSegment[];
}

export interface SleepResponse {
  nights: SleepNight[];
}

export interface SleepDeps {
  listFiles: (prefix: string) => Promise<Array<{ name: string; size: number }>>;
  readJson: (name: string) => Promise<unknown>;
}

/** Parse one night from a raw sleep file. Null if no sleep payload.
 * Classic (non-STAGES) nights degrade to total-only (empty stages/hypnogram). */
export function parseSleepNight(file: unknown): SleepNight | null {
  const dp = dataArray(file).find((d) => d['sleep']);
  if (!dp) return null;
  const sleep = dp['sleep'] as Record<string, unknown>;

  const date = String(G('interval', 'endTime')(sleep) ?? '').slice(0, 10);
  const minutesAsleep = num(G('summary', 'minutesAsleep')(sleep));
  const minutesAwake = num(G('summary', 'minutesAwake')(sleep));

  const rawStages = (G('stages')(sleep) as Array<Record<string, unknown>>) ?? [];
  const rawSummary = (G('summary', 'stagesSummary')(sleep) as Array<Record<string, unknown>>) ?? [];
  const hasStages = sleep['type'] === 'STAGES' && rawStages.length > 0;

  const stages: SleepStage[] = hasStages
    ? rawSummary
        .map((s) => ({ type: String(s['type'] ?? ''), minutes: num(s['minutes']) }))
        .filter((s): s is SleepStage => s.minutes != null)
    : [];

  const hypnogram: HypnogramSegment[] = hasStages
    ? rawStages.map((s) => ({
        type: String(s['type'] ?? ''),
        start: String(s['startTime'] ?? ''),
        end: String(s['endTime'] ?? ''),
      }))
    : [];

  return { date, minutesAsleep, minutesAwake, hasStages, stages, hypnogram };
}

/** Nights within [from, to] (inclusive), newest first. Duplicate dates: last
 * file read wins. */
export async function buildSleep(
  deps: SleepDeps,
  opts: { from: string; to: string },
): Promise<SleepResponse> {
  const { from, to } = opts;
  const files = await deps.listFiles('raw/sleep/');
  const byDate = new Map<string, SleepNight>();

  for (const f of files) {
    const r = parseDataFileName(f.name);
    if (r && (r.end < from || r.start > to)) continue;
    const night = parseSleepNight(await deps.readJson(f.name));
    if (!night || !night.date) continue;
    if (night.date < from || night.date > to) continue;
    byDate.set(night.date, night);
  }

  const nights = [...byDate.values()].sort((a, b) => b.date.localeCompare(a.date));
  return { nights };
}
