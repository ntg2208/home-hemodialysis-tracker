import { openDB, type IDBPDatabase } from 'idb';
import type { PendingReading, Session, Settings } from './schemas';

// Auto-resume an unfinished session for up to 24h; older state is dropped on
// read so a long-abandoned session doesn't keep ambushing the user on launch.
const ACTIVE_TTL_MS = 24 * 60 * 60 * 1000;

export interface ActiveState {
  screen: 'pre' | 'active' | 'post';
  session?: Session;
  existingIds?: string[];
  readings?: PendingReading[];
  savedAt: number;
}

const DB_NAME = 'hd-tracker';
const DB_VERSION = 1;
const STORE_KV = 'kv';

let dbPromise: Promise<IDBPDatabase> | null = null;

function db(): Promise<IDBPDatabase> {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(d) {
        if (!d.objectStoreNames.contains(STORE_KV)) {
          d.createObjectStore(STORE_KV);
        }
      },
    }).catch(err => {
      dbPromise = null;
      throw err;
    });
  }
  return dbPromise;
}

async function get<T>(key: string): Promise<T | undefined> {
  return (await db()).get(STORE_KV, key) as Promise<T | undefined>;
}

async function set<T>(key: string, value: T): Promise<void> {
  await (await db()).put(STORE_KV, value, key);
}

async function del(key: string): Promise<void> {
  await (await db()).delete(STORE_KV, key);
}

export async function getSettings(): Promise<Settings | undefined> {
  return get<Settings>('settings');
}

export async function saveSettings(s: Settings): Promise<void> {
  await set('settings', s);
}

export async function clearSettings(): Promise<void> {
  await del('settings');
}

export async function getLastSession(): Promise<Session | undefined> {
  return get<Session>('last_session');
}

export async function saveLastSession(s: Session): Promise<void> {
  await set('last_session', s);
}

// Cached sessions list for instant Home render. The Apps Script backend can
// take several seconds on a cold start; rendering from cache first hides that
// latency and the background refresh updates the list when it lands.
export async function getCachedSessions(): Promise<Session[] | undefined> {
  return get<Session[]>('sessions_cache');
}

export async function saveCachedSessions(sessions: Session[]): Promise<void> {
  await set('sessions_cache', sessions);
}

// Dried (target) weight in kg. Used to derive the pre-dialysis UF goal as
// pre_weight - dried_weight. Defaults to 59 if the user hasn't set one.
const DRIED_WEIGHT_DEFAULT = 59;

export async function getDriedWeight(): Promise<number> {
  const v = await get<number>('dried_weight');
  return typeof v === 'number' && Number.isFinite(v) ? v : DRIED_WEIGHT_DEFAULT;
}

export async function saveDriedWeight(kg: number): Promise<void> {
  await set('dried_weight', kg);
}

// Active state uses localStorage, not IndexedDB, because iOS Safari/PWA can
// kill the JS process during an in-flight IDB transaction (auto-commit at
// next event-loop tick), which silently drops the write. localStorage
// flushes before the setter returns — there's no commit phase to lose.
const ACTIVE_KEY = 'active_state';

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
  } catch {
    return undefined;
  }
}

export function saveActiveState(s: Omit<ActiveState, 'savedAt'>): void {
  try {
    localStorage.setItem(ACTIVE_KEY, JSON.stringify({ ...s, savedAt: Date.now() }));
  } catch {
    // Quota / private mode — best-effort persistence; don't crash the app.
  }
}

export function clearActiveState(): void {
  try { localStorage.removeItem(ACTIVE_KEY); } catch {}
}
