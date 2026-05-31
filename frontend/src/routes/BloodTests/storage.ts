import { openDB, type IDBPDatabase } from 'idb';
import type { BloodTestRow } from './schemas';

// Reuse the Treatment app's IndexedDB. Same DB name on purpose — one store per
// concern. Bumped to v2 to add the blood-test cache store alongside the existing
// `kv` store; the v1 upgrade is replayed for fresh installs.
const DB_NAME = 'hd-tracker';
const DB_VERSION = 2;
const STORE_KV = 'kv';
const STORE_BT = 'blood_tests';

const ROWS_KEY = 'rows';
const COVERED_FROM_KEY = 'covered_from';
const LAST_SYNCED_KEY = 'last_synced';

let dbPromise: Promise<IDBPDatabase> | null = null;

function db(): Promise<IDBPDatabase> {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(d) {
        if (!d.objectStoreNames.contains(STORE_KV)) d.createObjectStore(STORE_KV);
        if (!d.objectStoreNames.contains(STORE_BT)) d.createObjectStore(STORE_BT);
      },
    }).catch((err) => { dbPromise = null; throw err; });
  }
  return dbPromise;
}

async function get<T>(key: string): Promise<T | undefined> {
  return (await db()).get(STORE_BT, key) as Promise<T | undefined>;
}
async function set<T>(key: string, value: T): Promise<void> {
  await (await db()).put(STORE_BT, value, key);
}

export interface CacheState {
  rows: BloodTestRow[];
  coveredFrom: string | null; // earliest cached month (YYYY-MM), '' = all time, null = empty
  lastSynced: number | null;
}

export async function readCache(): Promise<CacheState> {
  try {
    const [rows, coveredFrom, lastSynced] = await Promise.all([
      get<BloodTestRow[]>(ROWS_KEY),
      get<string>(COVERED_FROM_KEY),
      get<number>(LAST_SYNCED_KEY),
    ]);
    return {
      rows: rows ?? [],
      coveredFrom: coveredFrom ?? null,
      lastSynced: lastSynced ?? null,
    };
  } catch {
    return { rows: [], coveredFrom: null, lastSynced: null };
  }
}

export async function writeCache(
  rows: BloodTestRow[],
  coveredFrom: string,
  lastSynced: number,
): Promise<void> {
  try {
    await Promise.all([
      set(ROWS_KEY, rows),
      set(COVERED_FROM_KEY, coveredFrom),
      set(LAST_SYNCED_KEY, lastSynced),
    ]);
  } catch {
    // Cache write failure is a UX nicety, not fatal — the rows are already in memory.
  }
}
