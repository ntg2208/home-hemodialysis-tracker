// Pure helpers for the fitness time-series endpoint.
// Builds a daily {date, value} series per list-type, sharing the per-type
// extraction config with the summary endpoint (fitnessExtract.ts).

import { LIST_CONFIG, dataArray, num } from './fitnessExtract.js';
import { parseDataFileName } from './fitnessSummary.js';

export interface SeriesPoint {
  date: string; // YYYY-MM-DD
  value: number;
}

export interface SeriesResponse {
  type: string;
  points: SeriesPoint[];
}

export interface SeriesDeps {
  listFiles: (prefix: string) => Promise<Array<{ name: string; size: number }>>;
  readJson: (name: string) => Promise<unknown>;
}

/** Every datapoint in a file as {date, value}, using the shared per-type
 * config. Status-only/unknown types and non-finite values yield nothing. */
export function extractSeries(type: string, file: unknown): SeriesPoint[] {
  const cfg = LIST_CONFIG[type];
  if (!cfg) return [];
  const out: SeriesPoint[] = [];
  for (const dp of dataArray(file)) {
    const payload = dp[cfg.key] as Record<string, unknown> | undefined;
    if (!payload) continue;
    const date = cfg.getDate(payload);
    if (!date) continue;
    const v = cfg.getValue(payload);
    if (!v) continue;
    const value = num(v.value);
    if (value == null) continue;
    out.push({ date, value });
  }
  return out;
}

/** Daily series for `type` within [from, to] (inclusive, YYYY-MM-DD),
 * ascending by date. Duplicate dates: last file read wins. */
export async function buildSeries(
  deps: SeriesDeps,
  opts: { type: string; from: string; to: string },
): Promise<SeriesResponse> {
  const { type, from, to } = opts;
  const files = await deps.listFiles(`raw/${type}/`);
  const byDate = new Map<string, number>();

  for (const f of files) {
    const r = parseDataFileName(f.name);
    if (r && (r.end < from || r.start > to)) continue; // file outside window
    const json = await deps.readJson(f.name);
    for (const pt of extractSeries(type, json)) {
      if (pt.date < from || pt.date > to) continue;
      byDate.set(pt.date, pt.value);
    }
  }

  const points = [...byDate.entries()]
    .map(([date, value]) => ({ date, value }))
    .sort((a, b) => a.date.localeCompare(b.date));
  return { type, points };
}
