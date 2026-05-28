import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Hono } from 'hono';
import { filterRows, isValidBound, type QueryParams } from '../lib/queryFilter.js';
import { mergeRows } from '../lib/mergeRows.js';
import { getDb } from '../lib/firestore.js';
import {
  PHASES,
  BloodTestRowSchema,
  PostBodySchema,
  type BloodTestRow,
} from '../schemas/bloodTests.js';

const here = dirname(fileURLToPath(import.meta.url));
const staticRows: BloodTestRow[] = JSON.parse(
  readFileSync(resolve(here, '../data/blood_tests.json'), 'utf8'),
);

export const bloodTests = new Hono()
  .get('/', async (c) => {
    const params = c.req.query();
    const p: QueryParams = {};

    const marker = params['marker'];
    if (marker) p.marker = marker.split(',').map((s) => s.trim()).filter(Boolean);

    const phase = params['phase'];
    if (phase) {
      p.phase = phase.split(',').map((s) => s.trim()).filter(Boolean);
      if (p.phase.some((x) => !(PHASES as readonly string[]).includes(x))) {
        return c.json({ error: 'invalid phase param' }, 400);
      }
    }

    const from = params['from'];
    if (from) {
      if (!isValidBound(from)) return c.json({ error: 'invalid from param' }, 400);
      p.from = from;
    }

    const to = params['to'];
    if (to) {
      if (!isValidBound(to)) return c.json({ error: 'invalid to param' }, 400);
      p.to = to;
    }

    const snap = await getDb().collection('blood_tests').get();
    const firestoreRows: BloodTestRow[] = snap.docs
      .map((d) => BloodTestRowSchema.safeParse(d.data()))
      .filter((r): r is { success: true; data: BloodTestRow } => {
        if (!r.success) console.warn('bloodTests GET: Firestore doc failed validation', r.error.issues);
        return r.success;
      })
      .map((r) => r.data);

    const merged = mergeRows(staticRows, firestoreRows);
    const result = filterRows(merged, p);
    return c.json({ count: result.length, rows: result });
  })
  .post('/', async (c) => {
    let body: unknown;
    try {
      body = await c.req.json();
    } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }

    const parsed = PostBodySchema.safeParse(body);
    if (!parsed.success) {
      return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);
    }

    const now = new Date().toISOString();
    const db = getDb();
    const col = db.collection('blood_tests');
    const batch = db.batch();
    for (const row of parsed.data.rows) {
      batch.set(col.doc(`${row.lab_id}_${row.marker}`), { ...row, created_at: now });
    }
    await batch.commit();

    return c.json({ ok: true, count: parsed.data.rows.length });
  });
