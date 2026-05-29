import { openDB, type IDBPDatabase } from 'idb';
import type { PendingReading, Session } from './schemas';

const ACTIVE_TTL_MS = 24 * 60 * 60 * 1000;

export interface SessionConsumed {
  needles: number;
  onOffPacks: number;
  heparinUsed: boolean;
  durationMin?: number;
}

export interface ActiveState {
  screen: 'pre' | 'active' | 'post';
  session?: Session;
  existingIds?: string[];
  readings?: PendingReading[];
  heparinUsed?: boolean;    // carried from pre → active
  consumed?: SessionConsumed;  // carried from active → post
  countdownStartedAt?: number;
  targetMin?: number;
  savedAt: number;
}

// Keep DB_NAME as 'hd-tracker' — changing it would orphan the existing
// install's last_session cache and dried_weight on the user's phone.
const DB_NAME = 'hd-tracker';
const DB_VERSION = 1;
const STORE_KV = 'kv';

let dbPromise: Promise<IDBPDatabase> | null = null;

function db(): Promise<IDBPDatabase> {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(d) {
        if (!d.objectStoreNames.contains(STORE_KV)) d.createObjectStore(STORE_KV);
      },
    }).catch(err => { dbPromise = null; throw err; });
  }
  return dbPromise;
}

async function get<T>(key: string): Promise<T | undefined> {
  return (await db()).get(STORE_KV, key) as Promise<T | undefined>;
}
async function set<T>(key: string, value: T): Promise<void> {
  await (await db()).put(STORE_KV, value, key);
}

export async function getLastSession(): Promise<Session | undefined> {
  return get<Session>('last_session');
}
export async function saveLastSession(s: Session): Promise<void> {
  await set('last_session', s);
}
export async function getCachedSessions(): Promise<Session[] | undefined> {
  return get<Session[]>('sessions_cache');
}
export async function saveCachedSessions(sessions: Session[]): Promise<void> {
  await set('sessions_cache', sessions);
}

const DRIED_WEIGHT_DEFAULT = 59;
export async function getDriedWeight(): Promise<number> {
  const v = await get<number>('dried_weight');
  return typeof v === 'number' && Number.isFinite(v) ? v : DRIED_WEIGHT_DEFAULT;
}
export async function saveDriedWeight(kg: number): Promise<void> {
  await set('dried_weight', kg);
}

// Active state in localStorage: iOS kills IDB mid-transaction; localStorage
// writes flush synchronously before setItem returns.
const ACTIVE_KEY = 'treatment_active_state';

export function getActiveState(): ActiveState | undefined {
  try {
    const raw = localStorage.getItem(ACTIVE_KEY);
    if (!raw) return undefined;
    const s = JSON.parse(raw) as ActiveState;
    if (Date.now() - s.savedAt > ACTIVE_TTL_MS) {
      localStorage.removeItem(ACTIVE_KEY);
      return undefined;
    }
    return s;
  } catch { return undefined; }
}
export function saveActiveState(s: Omit<ActiveState, 'savedAt'>): void {
  try {
    localStorage.setItem(ACTIVE_KEY, JSON.stringify({ ...s, savedAt: Date.now() }));
  } catch {}
}
export function clearActiveState(): void {
  try { localStorage.removeItem(ACTIVE_KEY); } catch {}
}
