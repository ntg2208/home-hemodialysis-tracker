import type { BloodTestRow } from '../schemas';

export type MarkerSummary = {
  marker: string;
  latest: BloodTestRow | null;
  previous: BloodTestRow | null;
  delta: number | null;
  direction: 'up' | 'down' | 'flat' | null;
  status: 'in' | 'out' | 'unknown';
};

export function summarize(marker: string, rows: BloodTestRow[]): MarkerSummary {
  const numeric = rows
    .filter((r) => !r.qualitative)
    .sort((a, b) => a.datetime.localeCompare(b.datetime));

  const latest = numeric[numeric.length - 1] ?? null;
  const previous = numeric[numeric.length - 2] ?? null;

  let delta: number | null = null;
  let direction: MarkerSummary['direction'] = null;
  if (latest && previous) {
    delta = Number((latest.value - previous.value).toFixed(4));
    direction = delta > 0 ? 'up' : delta < 0 ? 'down' : 'flat';
  }

  let status: MarkerSummary['status'] = 'unknown';
  if (latest && latest.ref_low != null && latest.ref_high != null) {
    status = latest.value >= latest.ref_low && latest.value <= latest.ref_high ? 'in' : 'out';
  }

  return { marker, latest, previous, delta, direction, status };
}
