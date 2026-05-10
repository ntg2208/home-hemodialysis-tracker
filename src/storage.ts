import { openDB, type IDBPDatabase } from 'idb';
import type { Session, Settings } from './schemas';

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
