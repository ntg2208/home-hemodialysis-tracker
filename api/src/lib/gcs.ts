import { Storage } from '@google-cloud/storage';

const BUCKET = process.env.FITNESS_BUCKET ?? 'homehd-fitness';

let _storage: Storage | null = null;
function getStorage(): Storage {
  if (!_storage) _storage = new Storage();
  return _storage;
}

// Pure path helpers — testable without GCP
export function dataTypePath(type: string, date: string): string {
  return `raw/${type}/${date}.json`;
}

export function syncStatePath(): string {
  return 'sync_state.json';
}

export function dateRange(from: string, to: string): string[] {
  const dates: string[] = [];
  const cur = new Date(from);
  const end = new Date(to);
  while (cur <= end) {
    dates.push(cur.toISOString().slice(0, 10));
    cur.setUTCDate(cur.getUTCDate() + 1);
  }
  return dates;
}

// GCS I/O
export async function uploadJson(path: string, data: unknown): Promise<void> {
  await getStorage()
    .bucket(BUCKET)
    .file(path)
    .save(JSON.stringify(data), { contentType: 'application/json' });
}

export async function readJson(path: string): Promise<unknown | null> {
  try {
    const [contents] = await getStorage().bucket(BUCKET).file(path).download();
    return JSON.parse(contents.toString('utf8'));
  } catch (err: unknown) {
    if (err instanceof Error && 'code' in err && (err as { code?: number }).code === 404) {
      return null;
    }
    throw err;
  }
}

export type SyncState = Record<string, string>; // { steps: 'YYYY-MM-DD', ... }

export async function readSyncState(): Promise<SyncState> {
  const raw = await readJson(syncStatePath());
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
  return raw as SyncState;
}

export async function writeSyncState(state: SyncState): Promise<void> {
  await uploadJson(syncStatePath(), state);
}
