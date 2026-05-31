// One-time migration: reads sessions + readings from Apps Script, writes to Firestore.
// Run: cd api && HD_SECRET='...' npx tsx scripts/backfill-treatment.ts
// Uses Application Default Credentials (gcloud auth login already done).

import { Firestore } from '@google-cloud/firestore';

const HD_URL = 'https://script.google.com/macros/s/AKfycbyBSvXWCNajqgJ1UPIS6cL-BfIy2aXslvlS2FkN9V126gWUWeA5A6wxsz6YMsa2Az21oQ/exec';
const HD_SECRET = process.env.HD_SECRET;

if (!HD_SECRET) {
  console.error('Missing HD_SECRET env var');
  process.exit(1);
}

// Fields that must stay as strings (not coerced to numbers)
const STRING_FIELDS = new Set([
  'session_id', 'reading_id', 'date', 'time', 'note', 'created_at',
]);

// Coerce a value: if it's a non-empty string that parses as a finite number
// and the field name is not in STRING_FIELDS, return the number. Otherwise return as-is.
function coerce(key: string, value: unknown): unknown {
  if (typeof value !== 'string' || STRING_FIELDS.has(key)) return value;
  if (value === '') return undefined; // drop empty strings
  const n = Number(value);
  return Number.isFinite(n) ? n : value;
}

function toFirestoreDoc(obj: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj)) {
    const coerced = coerce(k, v);
    if (coerced !== undefined) result[k] = coerced;
  }
  return result;
}

interface AppsScriptResponse {
  ok: boolean;
  sessions?: Record<string, unknown>[];
  readings?: Record<string, unknown>[];
  error?: string;
}

async function fetchFromAppsScript(): Promise<{ sessions: Record<string, unknown>[]; readings: Record<string, unknown>[] }> {
  const url = `${HD_URL}?secret=${encodeURIComponent(HD_SECRET!)}`;
  console.log('Fetching from Apps Script...');
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const body = await res.json() as AppsScriptResponse;
  if (!body.ok) throw new Error(`Apps Script error: ${body.error ?? JSON.stringify(body)}`);
  return { sessions: body.sessions ?? [], readings: body.readings ?? [] };
}

async function batchWrite(
  db: Firestore,
  collectionName: string,
  docs: Array<{ id: string; data: Record<string, unknown> }>,
  skipExisting: boolean,
): Promise<{ written: number; skipped: number }> {
  let written = 0;
  let skipped = 0;

  // Firestore batch max = 500 operations
  for (let i = 0; i < docs.length; i += 490) {
    const chunk = docs.slice(i, i + 490);
    const batch = db.batch();
    for (const { id, data } of chunk) {
      if (skipExisting) {
        const snap = await db.collection(collectionName).doc(id).get();
        if (snap.exists) { skipped++; continue; }
      }
      batch.set(db.collection(collectionName).doc(id), data);
      written++;
    }
    await batch.commit();
  }
  return { written, skipped };
}

async function main() {
  const { sessions, readings } = await fetchFromAppsScript();
  console.log(`  Found: ${sessions.length} sessions, ${readings.length} readings`);

  const db = new Firestore({ projectId: 'homehd-personal' });
  const skipExisting = !process.argv.includes('--overwrite');

  console.log(`Writing sessions to Firestore (skipExisting=${skipExisting})...`);
  const sr = await batchWrite(db, 'treatment_sessions',
    sessions
      .filter(s => s['session_id'])
      .map(s => ({ id: String(s['session_id']), data: toFirestoreDoc(s) })),
    skipExisting,
  );
  console.log(`  Sessions: ${sr.written} written, ${sr.skipped} skipped`);

  console.log('Writing readings to Firestore...');
  const rr = await batchWrite(db, 'treatment_readings',
    readings
      .filter(r => r['reading_id'])
      .map(r => ({ id: String(r['reading_id']), data: toFirestoreDoc(r) })),
    skipExisting,
  );
  console.log(`  Readings: ${rr.written} written, ${rr.skipped} skipped`);

  console.log('Done.');
}

main().catch(e => { console.error(e); process.exit(1); });
