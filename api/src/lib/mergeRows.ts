import type { BloodTestRow } from '../schemas/bloodTests.js';

export function mergeRows(staticRows: BloodTestRow[], firestoreRows: BloodTestRow[]): BloodTestRow[] {
  const map = new Map<string, BloodTestRow>();
  for (const r of staticRows) map.set(`${r.lab_id}_${r.marker}`, r);
  for (const r of firestoreRows) map.set(`${r.lab_id}_${r.marker}`, r);
  return Array.from(map.values());
}
