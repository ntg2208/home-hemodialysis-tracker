import { Hono } from 'hono';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { Firestore } from '@google-cloud/firestore';
import { google } from 'googleapis';

if (getApps().length === 0) initializeApp();

const SESSION_COLS = [
  'session_id', 'date',
  'pre_weight', 'uf_goal', 'uf_rate', 'pre_bp_sys', 'pre_bp_dia', 'pre_pulse',
  'post_weight', 'post_bp_sys', 'post_bp_dia', 'post_pulse',
  'duration_min', 'dialysate_volume', 'total_uf', 'blood_processed',
  'created_at',
] as const;

const READING_COLS = [
  'reading_id', 'session_id', 'seq', 'time',
  'bp_sys', 'bp_dia', 'pulse', 'blood_flow',
  'venous_pressure', 'arterial_pressure', 'note', 'created_at',
] as const;

type SessionDoc = Record<string, unknown>;
type ReadingDoc = Record<string, unknown>;

function formatDuration(min: number): string {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

function buildLegacyRows(sessions: SessionDoc[], readingsBySession: Map<string, ReadingDoc[]>): unknown[][] {
  const header = [
    'Date', 'Weight', 'UF Goal', 'UF rate', 'Blood Pressure', 'Pulse',
    'Time', 'Blood Pressure', 'Pulse', 'Bloodflow', 'Venous Pressure', 'Arterial Pressure', 'Note',
    'Weight', 'Blood Pressure', 'Pulse', 'Treatment Time', 'Dialysate volume', 'Total UF', 'Blood Processed',
  ];
  const rows: unknown[][] = [header];
  for (const s of sessions) {
    const rs = readingsBySession.get(String(s['session_id'])) ?? [];
    const n = Math.max(rs.length, 1);
    for (let i = 0; i < n; i++) {
      const r: ReadingDoc = rs[i] ?? {};
      const isFirst = i === 0;
      const isLast = i === n - 1;
      rows.push([
        isLast ? s['date'] : '',
        isFirst ? (s['pre_weight'] ?? '') : '',
        isFirst ? (s['uf_goal'] ?? '') : '',
        isFirst ? (s['uf_rate'] ?? '') : '',
        isFirst && s['pre_bp_sys'] && s['pre_bp_dia'] ? `${s['pre_bp_sys']}/${s['pre_bp_dia']}` : '',
        isFirst ? (s['pre_pulse'] ?? '') : '',
        r['time'] ?? '',
        r['bp_sys'] && r['bp_dia'] ? `${r['bp_sys']}/${r['bp_dia']}` : '',
        r['pulse'] ?? '',
        r['blood_flow'] ?? '',
        r['venous_pressure'] ?? '',
        r['arterial_pressure'] ?? '',
        r['note'] ?? '',
        isLast ? (s['post_weight'] ?? '') : '',
        isLast && s['post_bp_sys'] && s['post_bp_dia'] ? `${s['post_bp_sys']}/${s['post_bp_dia']}` : '',
        isLast ? (s['post_pulse'] ?? '') : '',
        isLast && typeof s['duration_min'] === 'number' ? formatDuration(s['duration_min']) : '',
        isLast ? (s['dialysate_volume'] ?? '') : '',
        isLast ? (s['total_uf'] ?? '') : '',
        isLast ? (s['blood_processed'] ?? '') : '',
      ]);
    }
  }
  return rows;
}

export const treatment = new Hono()
  .get('/token', async (c) => {
    try {
      const token = await getAuth().createCustomToken('homehd-treatment');
      const expires_at = Date.now() + 55 * 60 * 1000;
      return c.json({ ok: true, token, expires_at });
    } catch (err) {
      console.error('Token mint error:', err instanceof Error ? err.message : String(err));
      return c.json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  })
  .post('/sync-to-sheet', async (c) => {
    const sheetId = process.env.TREATMENT_SHEET_ID;
    if (!sheetId) return c.json({ ok: false, error: 'TREATMENT_SHEET_ID not set' }, 500);
    try {
      const db = new Firestore();
      const sessSnap = await db.collection('treatment_sessions').orderBy('date').get();
      const sessions: SessionDoc[] = sessSnap.docs.map(d => d.data());
      // Composite index on (session_id ASC, seq ASC) required in production.
      // Deploy via firestore.indexes.json or Firestore console before first use.
      const readSnap = await db.collection('treatment_readings').orderBy('session_id').orderBy('seq').get();
      const readings: ReadingDoc[] = readSnap.docs.map(d => d.data());

      const readingsBySession = new Map<string, ReadingDoc[]>();
      for (const r of readings) {
        const sid = String(r['session_id']);
        if (!readingsBySession.has(sid)) readingsBySession.set(sid, []);
        readingsBySession.get(sid)!.push(r);
      }

      const sessionRows = [[...SESSION_COLS], ...sessions.map(s => SESSION_COLS.map(col => s[col] ?? ''))];
      const readingRows = [[...READING_COLS], ...readings.map(r => READING_COLS.map(col => r[col] ?? ''))];
      const legacyRows = buildLegacyRows(sessions, readingsBySession);

      const auth = new google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/spreadsheets'] });
      // googleapis types don't align perfectly with google-auth-library — cast needed
      const sheets = google.sheets({ version: 'v4', auth: await auth.getClient() as never });

      async function writeTab(tabName: string, values: unknown[][]): Promise<void> {
        await sheets.spreadsheets.values.clear({ spreadsheetId: sheetId, range: tabName });
        await sheets.spreadsheets.values.update({
          spreadsheetId: sheetId,
          range: `${tabName}!A1`,
          valueInputOption: 'RAW',
          requestBody: { values },
        });
      }

      await writeTab('legacy_view', legacyRows);
      await writeTab('sessions', sessionRows);
      await writeTab('readings', readingRows);

      return c.json({ ok: true, sessions_written: sessions.length, readings_written: readings.length, synced_at: new Date().toISOString() });
    } catch (err) {
      console.error('Sync-to-sheet error:', err instanceof Error ? err.message : String(err));
      return c.json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  });
