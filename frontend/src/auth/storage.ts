import { openDB } from 'idb';

export interface AuthSettings {
  mainKey: string;
  treatmentToken?: string;
  treatmentTokenExpiresAt?: number;
}

const DB_NAME = 'homehd-auth';
const DB_VERSION = 1;
const STORE = 'auth';

let dbPromise: ReturnType<typeof openDB> | null = null;

function db() {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(d) {
        if (!d.objectStoreNames.contains(STORE)) d.createObjectStore(STORE);
      },
    }).catch(err => { dbPromise = null; throw err; });
  }
  return dbPromise;
}

export async function getAuth(): Promise<AuthSettings | undefined> {
  return (await db()).get(STORE, 'auth') as Promise<AuthSettings | undefined>;
}

export async function saveAuth(a: AuthSettings): Promise<void> {
  await (await db()).put(STORE, a, 'auth');
}

export async function clearAuth(): Promise<void> {
  await (await db()).delete(STORE, 'auth');
}
