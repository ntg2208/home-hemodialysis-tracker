import type { BloodTestRow } from '../schemas';

/** Composite key matching the server doc id: `${lab_id}_${marker}`. */
function rowKey(r: BloodTestRow): string {
  return `${r.lab_id}_${r.marker}`;
}

/**
 * Union of existing + incoming rows, keyed by lab_id+marker. Incoming wins on
 * collision so a re-fetch picks up in-place edits (e.g. `timing` corrections).
 */
export function mergeRows(existing: BloodTestRow[], incoming: BloodTestRow[]): BloodTestRow[] {
  const byKey = new Map<string, BloodTestRow>();
  for (const r of existing) byKey.set(rowKey(r), r);
  for (const r of incoming) byKey.set(rowKey(r), r);
  return [...byKey.values()];
}

/** `YYYY-MM` six months before `now`. */
export function sixMonthsAgo(now: Date): string {
  const d = new Date(now.getFullYear(), now.getMonth() - 6, 1);
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  return `${d.getFullYear()}-${mm}`;
}

/**
 * Is month `a` earlier than month `b`? `''` means open-ended (all time), so it is
 * the earliest possible bound.
 */
export function earlierMonth(a: string, b: string): boolean {
  if (a === b) return false;
  if (a === '') return true;   // all-time start is earlier than any real month
  if (b === '') return false;
  return a < b;
}

/**
 * The slice still missing from the cache for a requested `from` bound, given the
 * cache's current earliest covered month (`coveredFrom`, `null` if empty cache).
 * The cache is always a single window `[coveredFrom → now]`, so we only ever
 * extend backward.
 *
 * - empty cache → fetch from the requested bound to now
 * - request already inside coverage → null (no fetch)
 * - request older than coverage → fetch only `[requestedFrom → coveredFrom]`
 */
export function computeFetchRange(
  coveredFrom: string | null,
  requestedFrom: string,
): { from: string; to?: string } | null {
  if (coveredFrom === null) return { from: requestedFrom };
  if (!earlierMonth(requestedFrom, coveredFrom)) return null;
  return { from: requestedFrom, to: coveredFrom };
}
