import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { getDb } from '../firestore.js';
import { filterRows, type QueryParams } from '../queryFilter.js';
import { mergeRows } from '../mergeRows.js';
import { BloodTestRowSchema, type BloodTestRow } from '../../schemas/bloodTests.js';

const here = dirname(fileURLToPath(import.meta.url));
const staticRows: BloodTestRow[] = JSON.parse(
  readFileSync(resolve(here, '../../data/blood_tests.json'), 'utf8'),
);

/** Pure: rows whose numeric value falls outside a present reference bound. */
export function selectOutOfRange(rows: BloodTestRow[]): BloodTestRow[] {
  return rows.filter((r) => {
    if (r.qualitative) return false;
    if (r.ref_low != null && r.value < r.ref_low) return true;
    if (r.ref_high != null && r.value > r.ref_high) return true;
    return false;
  });
}

/** I/O: Firestore blood_tests merged over the static seed set. */
export async function fetchBloodRows(): Promise<BloodTestRow[]> {
  const snap = await getDb().collection('blood_tests').get();
  const firestoreRows: BloodTestRow[] = snap.docs
    .map((d) => BloodTestRowSchema.safeParse(d.data()))
    .filter((r): r is { success: true; data: BloodTestRow } => r.success)
    .map((r) => r.data);
  return mergeRows(staticRows, firestoreRows);
}

export async function getBloodMarkers(p: QueryParams): Promise<BloodTestRow[]> {
  return filterRows(await fetchBloodRows(), p);
}

export async function getOutOfRangeMarkers(p: QueryParams): Promise<BloodTestRow[]> {
  return selectOutOfRange(filterRows(await fetchBloodRows(), p));
}
