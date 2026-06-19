import { Hono } from 'hono';
import { isValidBound, type QueryParams } from '../lib/queryFilter.js';
import { getDb } from '../lib/firestore.js';
import { getBloodMarkers } from '../lib/reads/bloodTestReads.js';
import { PHASES, PostBodySchema } from '../schemas/bloodTests.js';

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

    const result = await getBloodMarkers(p);
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
  })
  .delete('/:labId/:marker', async (c) => {
    const labId = c.req.param('labId');
    const marker = c.req.param('marker');
    const ref = getDb().collection('blood_tests').doc(`${labId}_${marker}`);
    const snap = await ref.get();
    if (!snap.exists) return c.json({ error: 'not_found' }, 404);
    await ref.delete();
    return c.json({ ok: true });
  });
