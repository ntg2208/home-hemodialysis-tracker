// Pure aggregation/extraction helpers for the fitness summary endpoint.
// No GCP, no network — unit-tested against the live file shapes verified 2026-05-31.

export interface LatestReading {
  label: string;
  value: string;
  unit: string;
  at: string; // YYYY-MM-DD
}

type CivilDate = { year: number; month: number; day: number };

function fmtCivil(d: CivilDate | undefined): string {
  if (!d) return '';
  return `${d.year}-${String(d.month).padStart(2, '0')}-${String(d.day).padStart(2, '0')}`;
}

// Parse a possibly-stringy number ("83", 13.5, "NaN"). Returns null for non-finite.
function num(v: unknown): number | null {
  const n = typeof v === 'string' ? Number(v) : typeof v === 'number' ? v : NaN;
  return Number.isFinite(n) ? n : null;
}

function fmtSleepDuration(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return `${h}h ${String(m).padStart(2, '0')}m`;
}

// Per-list-type config: where the payload lives, how to read its date, how to render its value.
// `null` config = status-only (no card value).
interface TypeConfig {
  key: string;
  getDate: (p: Record<string, unknown>) => string;
  getValue: (p: Record<string, unknown>) => Omit<LatestReading, 'at'> | null;
}

const G = (...path: string[]) => (p: Record<string, unknown>): unknown =>
  path.reduce<unknown>((acc, k) => (acc && typeof acc === 'object' ? (acc as Record<string, unknown>)[k] : undefined), p);

const LIST_CONFIG: Record<string, TypeConfig | null> = {
  'daily-resting-heart-rate': {
    key: 'dailyRestingHeartRate',
    getDate: (p) => fmtCivil(G('date')(p) as CivilDate),
    getValue: (p) => {
      const v = num(G('beatsPerMinute')(p));
      return v == null ? null : { label: 'Resting HR', value: String(v), unit: 'bpm' };
    },
  },
  'daily-heart-rate-variability': {
    key: 'dailyHeartRateVariability',
    getDate: (p) => fmtCivil(G('date')(p) as CivilDate),
    getValue: (p) => {
      const v = num(G('averageHeartRateVariabilityMilliseconds')(p));
      return v == null ? null : { label: 'HRV (RMSSD)', value: String(Math.round(v)), unit: 'ms' };
    },
  },
  'daily-sleep-temperature-derivations': {
    key: 'dailySleepTemperatureDerivations',
    getDate: (p) => fmtCivil(G('date')(p) as CivilDate),
    getValue: (p) => {
      const v = num(G('nightlyTemperatureCelsius')(p));
      return v == null ? null : { label: 'Skin temp', value: v.toFixed(1), unit: '°C' };
    },
  },
  'oxygen-saturation': {
    key: 'oxygenSaturation',
    getDate: (p) => fmtCivil(G('sampleTime', 'civilTime', 'date')(p) as CivilDate),
    getValue: (p) => {
      const v = num(G('percentage')(p));
      return v == null ? null : { label: 'SpO2', value: String(Math.round(v)), unit: '%' };
    },
  },
  'respiratory-rate-sleep-summary': {
    key: 'respiratoryRateSleepSummary',
    getDate: (p) => fmtCivil(G('sampleTime', 'civilTime', 'date')(p) as CivilDate),
    getValue: (p) => {
      const v = num(G('deepSleepStats', 'breathsPerMinute')(p));
      return v == null ? null : { label: 'Resp. rate', value: String(v), unit: '/min' };
    },
  },
  'sleep': {
    key: 'sleep',
    getDate: (p) => String(G('interval', 'endTime')(p) ?? '').slice(0, 10),
    getValue: (p) => {
      const mins = num(G('summary', 'minutesAsleep')(p));
      if (mins == null) return null;
      const stages = (G('summary', 'stagesSummary')(p) as Array<Record<string, unknown>>) ?? [];
      const deep = stages.find((s) => s['type'] === 'DEEP');
      const deepMin = deep ? num(deep['minutes']) : null;
      return { label: 'Sleep', value: fmtSleepDuration(mins), unit: deepMin != null ? `DEEP ${deepMin}m` : '' };
    },
  },
  // status-only: no card value
  'heart-rate': null,
  'heart-rate-variability': null,
};

// dailyRollUp shape (steps): { data: { rollupDataPoints: [...] } }
function stepsLatest(file: Record<string, unknown>): LatestReading | null {
  const pts = (G('data', 'rollupDataPoints')(file) as Array<Record<string, unknown>>) ?? [];
  let best: { at: string; value: string } | null = null;
  for (const pt of pts) {
    const at = fmtCivil(G('civilStartTime', 'date')(pt) as CivilDate);
    const count = G('steps', 'countSum')(pt);
    if (at && (!best || at > best.at)) best = { at, value: String(count ?? '') };
  }
  return best ? { label: 'Steps', value: best.value, unit: '', at: best.at } : null;
}

function dataArray(file: unknown): Array<Record<string, unknown>> {
  const d = (file as Record<string, unknown>)?.['data'];
  return Array.isArray(d) ? (d as Array<Record<string, unknown>>) : [];
}

export function extractLatest(type: string, file: unknown): LatestReading | null {
  if (type === 'steps') return stepsLatest(file as Record<string, unknown>);
  const cfg = LIST_CONFIG[type];
  if (!cfg) return null; // status-only or unknown
  let best: LatestReading | null = null;
  for (const dp of dataArray(file)) {
    const payload = dp[cfg.key] as Record<string, unknown> | undefined;
    if (!payload) continue;
    const at = cfg.getDate(payload);
    if (!at) continue;
    if (best && at <= best.at) continue;
    const v = cfg.getValue(payload);
    if (v) best = { ...v, at };
  }
  return best;
}

export function countOf(type: string, file: unknown): number {
  if (type === 'steps') {
    const pts = (file as Record<string, unknown>)?.['data'] as Record<string, unknown> | undefined;
    const rdp = pts?.['rollupDataPoints'];
    return Array.isArray(rdp) ? rdp.length : 0;
  }
  const f = file as Record<string, unknown>;
  if (typeof f?.['count'] === 'number') return f['count'] as number;
  return dataArray(file).length;
}

// raw/{type}/{start}_to_{end}.json → { start, end }
export function parseDataFileName(name: string): { start: string; end: string } | null {
  const m = name.match(/(\d{4}-\d{2}-\d{2})_to_(\d{4}-\d{2}-\d{2})\.json$/);
  return m ? { start: m[1], end: m[2] } : null;
}

export interface TypeSummary {
  type: string;
  last_synced?: string | null;
  count?: number;
  first_date?: string | null;
  last_date?: string | null;
  stale?: boolean;
  latest?: LatestReading | null;
  bytes?: number;
  error?: string;
}

export interface SummaryResponse {
  ok: true;
  generated_at: string;
  types: TypeSummary[];
  totals: { types: number; healthy: number; stale: number; bytes: number };
}

export interface SummaryDeps {
  readSyncState: () => Promise<Record<string, string>>;
  listFiles: (prefix: string) => Promise<Array<{ name: string; size: number }>>;
  readJson: (name: string) => Promise<unknown>;
  readCount: (name: string) => Promise<number>;
}

export interface SummaryOptions {
  types: readonly string[];
  today: string; // YYYY-MM-DD (UTC)
  rangeReadTypes?: readonly string[]; // never fully downloaded — count via readCount
}

// Build the per-type summary. Each type is isolated: one failure becomes { type, error }
// rather than aborting the whole response (same philosophy as runSync).
export async function buildSummary(deps: SummaryDeps, opts: SummaryOptions): Promise<SummaryResponse> {
  const rangeRead = new Set(opts.rangeReadTypes ?? ['heart-rate']);
  const syncState = await deps.readSyncState();
  const out: TypeSummary[] = [];

  for (const type of opts.types) {
    try {
      const files = await deps.listFiles(`raw/${type}/`);
      const lastSynced = syncState[type] ?? null;
      const stale = isStale(lastSynced, opts.today);

      if (files.length === 0) {
        out.push({ type, last_synced: lastSynced, count: 0, first_date: null, last_date: null, stale, latest: null, bytes: 0 });
        continue;
      }

      const ranged = files
        .map((f) => ({ f, r: parseDataFileName(f.name) }))
        .filter((x): x is { f: { name: string; size: number }; r: { start: string; end: string } } => x.r !== null);

      const first_date = ranged.reduce<string | null>((min, x) => (min === null || x.r.start < min ? x.r.start : min), null);
      const last_date = ranged.reduce<string | null>((max, x) => (max === null || x.r.end > max ? x.r.end : max), null);
      const newest = ranged.reduce((best, x) => (x.r.end > best.r.end ? x : best), ranged[0]);
      const bytes = files.reduce((sum, f) => sum + (f.size || 0), 0);

      let count = 0;
      let latest: LatestReading | null = null;

      if (rangeRead.has(type)) {
        for (const f of files) count += await deps.readCount(f.name);
      } else {
        let newestJson: unknown = null;
        for (const { f } of ranged) {
          const json = await deps.readJson(f.name);
          count += countOf(type, json);
          if (f.name === newest.f.name) newestJson = json;
        }
        latest = extractLatest(type, newestJson);
      }

      out.push({ type, last_synced: lastSynced, count, first_date, last_date, stale, latest, bytes });
    } catch (err) {
      out.push({ type, error: err instanceof Error ? err.message : String(err) });
    }
  }

  const stale = out.filter((t) => t.error == null && t.stale).length;
  const healthy = out.filter((t) => t.error == null && !t.stale).length;
  const bytes = out.reduce((sum, t) => sum + (t.bytes ?? 0), 0);
  return { ok: true, generated_at: new Date().toISOString(), types: out, totals: { types: out.length, healthy, stale, bytes } };
}

// Stale if never synced, or the last-synced data date is older than `maxAgeDays` before today.
// Default 2: the daily 09:00 job keeps last_synced at yesterday, so a 2-day-old value is the
// normal pre-run state, not a fault.
export function isStale(lastSynced: string | null, today: string, maxAgeDays = 2): boolean {
  if (!lastSynced) return true;
  const cutoff = new Date(today);
  cutoff.setUTCDate(cutoff.getUTCDate() - maxAgeDays);
  return lastSynced < cutoff.toISOString().slice(0, 10);
}
