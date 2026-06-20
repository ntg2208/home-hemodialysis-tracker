// Shared per-type extraction config for fitness data files.
// Used by fitnessSummary (latest value per type) and fitnessSeries (full series).
// No GCP, no network — pure functions over parsed JSON file shapes.

export interface LatestReading {
  label: string;
  value: string;
  unit: string;
  at: string; // YYYY-MM-DD
}

export type CivilDate = { year: number; month: number; day: number };

export function fmtCivil(d: CivilDate | undefined): string {
  if (!d) return '';
  return `${d.year}-${String(d.month).padStart(2, '0')}-${String(d.day).padStart(2, '0')}`;
}

// Parse a possibly-stringy number ("83", 13.5, "NaN"). Returns null for non-finite.
export function num(v: unknown): number | null {
  const n = typeof v === 'string' ? Number(v) : typeof v === 'number' ? v : NaN;
  return Number.isFinite(n) ? n : null;
}

export function fmtSleepDuration(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return `${h}h ${String(m).padStart(2, '0')}m`;
}

// Per-list-type config: where the payload lives, how to read its date, how to render its value.
// `null` config = status-only (no card value).
export interface TypeConfig {
  key: string;
  getDate: (p: Record<string, unknown>) => string;
  getValue: (p: Record<string, unknown>) => Omit<LatestReading, 'at'> | null;
}

export const G = (...path: string[]) => (p: Record<string, unknown>): unknown =>
  path.reduce<unknown>((acc, k) => (acc && typeof acc === 'object' ? (acc as Record<string, unknown>)[k] : undefined), p);

export const LIST_CONFIG: Record<string, TypeConfig | null> = {
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

export function dataArray(file: unknown): Array<Record<string, unknown>> {
  const d = (file as Record<string, unknown>)?.['data'];
  return Array.isArray(d) ? (d as Array<Record<string, unknown>>) : [];
}
