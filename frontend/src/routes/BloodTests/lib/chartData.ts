import type { BloodTestRow } from '../schemas';

export type ChartDatum = {
  x: Date;
  y: number;
  timing: string;
  inRange: boolean | null;
  unit: string;
  datetime: string;
  refLow: number | null;
  refHigh: number | null;
};

export type ChartSeries = {
  id: string;
  data: ChartDatum[];
};

export type RefRange = {
  low: number;
  high: number;
  unit: string;
};

export function getReferenceRange(rows: BloodTestRow[]): RefRange | null {
  const withRange = rows
    .filter(r => r.ref_low != null && r.ref_high != null)
    .sort((a, b) => b.datetime.localeCompare(a.datetime));
  const latest = withRange[0];
  if (!latest || latest.ref_low == null || latest.ref_high == null) return null;
  return { low: latest.ref_low, high: latest.ref_high, unit: latest.unit };
}

export function getPointColor(datum: Pick<ChartDatum, 'timing'>): string {
  if (datum.timing === 'pre')  return '#22d3ee';  // pre-dialysis — cyan
  if (datum.timing === 'post') return '#f59e0b';  // post-dialysis — amber
  return '#818cf8';                               // plain / unknown timing — indigo
}

// Priority for same-day deduplication: pre beats post beats plain.
// This prevents pre+post readings on the same day creating a zigzag
// that looks like two separate lines.
const TIMING_RANK: Record<string, number> = { pre: 0, post: 1, '': 2 };

export function toNivoSeries(marker: string, rows: BloodTestRow[]): ChartSeries {
  // One representative reading per calendar date.
  const byDate = new Map<string, BloodTestRow>();
  for (const r of rows.filter(r => !r.qualitative)) {
    const dateKey = r.datetime.slice(0, 10);
    const existing = byDate.get(dateKey);
    const rank = TIMING_RANK[r.timing] ?? 2;
    if (!existing || rank < (TIMING_RANK[existing.timing] ?? 2)) {
      byDate.set(dateKey, r);
    }
  }

  const data: ChartDatum[] = Array.from(byDate.values())
    .sort((a, b) => a.datetime.localeCompare(b.datetime))
    .map(r => {
      const inRange =
        r.ref_low != null && r.ref_high != null
          ? r.value >= r.ref_low && r.value <= r.ref_high
          : null;
      return {
        x: new Date(r.datetime),
        y: r.value,
        timing: r.timing,
        inRange,
        unit: r.unit,
        datetime: r.datetime,
        refLow: r.ref_low,
        refHigh: r.ref_high,
      };
    });
  return { id: marker, data };
}
