import { Storage } from '@google-cloud/storage';

const BUCKET = process.env.FITNESS_BUCKET ?? 'homehd-fitness';

let _storage: Storage | null = null;
function getStorage(): Storage {
  if (!_storage) _storage = new Storage();
  return _storage;
}

// Pure path helpers — testable without GCP
export function dataTypePath(type: string, segment: string): string {
  return `raw/${type}/${segment}.json`;
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

// List objects under a prefix with their sizes — no content download.
export async function listFiles(prefix: string): Promise<Array<{ name: string; size: number }>> {
  const [files] = await getStorage().bucket(BUCKET).getFiles({ prefix });
  return files.map((f) => ({ name: f.name, size: Number(f.metadata?.size ?? 0) }));
}

// Read just the `count` field from a stored data file via a byte-range request, so dense
// files (heart-rate, ~43MB) aren't downloaded. The ingest wrapper serializes count before
// the `data` array, so it lives in the first bytes. Returns 0 if not found in the window.
export async function readCount(path: string): Promise<number> {
  try {
    const [buf] = await getStorage().bucket(BUCKET).file(path).download({ start: 0, end: 1023 });
    const m = buf.toString('utf8').match(/"count"\s*:\s*(\d+)/);
    return m ? Number(m[1]) : 0;
  } catch {
    return 0;
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
