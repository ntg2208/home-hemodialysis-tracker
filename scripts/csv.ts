import { parse } from 'csv-parse/sync';

export interface BloodTestRow {
  marker: string;
  datetime: string;
  value: number;
  unit: string;
  ref_low: number | null;
  ref_high: number | null;
  timing: '' | 'pre' | 'post';
  note: string;
  source: string;
  lab_id: string;
  phase: string;
  created_at: string;
  qualitative: boolean;
}

function num(v: string | undefined): number | null {
  const t = (v ?? '').trim();
  if (t === '') return null;
  const n = Number(t.replace(/,/g, ''));
  return Number.isFinite(n) ? n : null;
}

export function csvToRows(csvText: string): BloodTestRow[] {
  const records = parse(csvText, {
    columns: true,
    skip_empty_lines: true,
    relax_column_count: true,
  }) as Record<string, string>[];

  const rows: BloodTestRow[] = [];
  for (const r of records) {
    const marker = (r.marker ?? '').trim();
    const datetime = (r.datetime ?? '').trim();
    if (!marker || !datetime) continue;
    const value = num(r.value) ?? 0;
    const timing = (r.timing ?? '').trim();
    rows.push({
      marker, datetime, value,
      unit: (r.unit ?? '').trim(),
      ref_low: num(r.ref_low),
      ref_high: num(r.ref_high),
      timing: timing === 'pre' || timing === 'post' ? timing : '',
      note: (r.note ?? '').trim(),
      source: (r.source ?? '').trim(),
      lab_id: (r.lab_id ?? '').trim(),
      phase: (r.phase ?? '').trim(),
      created_at: (r.created_at ?? '').trim(),
      qualitative: value === 0,
    });
  }
  rows.sort((a, b) => a.datetime.localeCompare(b.datetime));
  return rows;
}
