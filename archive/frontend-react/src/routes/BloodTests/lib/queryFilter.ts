import type { BloodTestRow } from '../schemas';

export type QueryParams = {
  marker?: string[];
  phase?: string[];
  from?: string; // YYYY-MM or YYYY-MM-DD
  to?: string;
};

const BOUND_RE = /^\d{4}-\d{2}(-\d{2})?$/;

export function isValidBound(s: string): boolean {
  return BOUND_RE.test(s);
}

// Compare a row's datetime against a bound at the bound's own granularity.
// e.g. to='2026-04' compares the row's 'YYYY-MM' prefix, so all of April matches.
export function matchesFrom(datetime: string, from: string): boolean {
  return datetime.slice(0, from.length) >= from;
}

export function matchesTo(datetime: string, to: string): boolean {
  return datetime.slice(0, to.length) <= to;
}

export function filterRows(rows: BloodTestRow[], p: QueryParams): BloodTestRow[] {
  return rows.filter((r) => {
    if (p.marker?.length && !p.marker.includes(r.marker)) return false;
    if (p.phase?.length && !p.phase.includes(r.phase)) return false;
    if (p.from && !matchesFrom(r.datetime, p.from)) return false;
    if (p.to && !matchesTo(r.datetime, p.to)) return false;
    return true;
  });
}
