import { Hono } from 'hono';
import { FieldValue } from '@google-cloud/firestore';
import { getDb } from '../lib/firestore.js';
import {
  EventBodySchema,
  ConfirmOrderBodySchema,
  ApplyDeliveryBodySchema,
} from '../schemas/inventory.js';

export const inventory = new Hono()

  .get('/', async (c) => {
    const db = getDb();

    const [stockSnap, cycleDoc] = await Promise.all([
      db.collection('inventory_stock').get(),
      db.collection('inventory_config').doc('cycle').get(),
    ]);

    const stock: Record<string, number> = {};
    for (const doc of stockSnap.docs) {
      const d = doc.data() as { qty: number };
      if (typeof d.qty === 'number') stock[doc.id] = d.qty;
    }

    const cycle = cycleDoc.exists ? (cycleDoc.data() ?? null) : null;

    return c.json({ stock, cycle });
  })

  .post('/event', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }

    const parsed = EventBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);

    const { type, deltas, note } = parsed.data;
    const now = new Date().toISOString();
    const db = getDb();

    // Update stock quantities (batch)
    const batch = db.batch();
    for (const [code, delta] of Object.entries(deltas)) {
      const ref = db.collection('inventory_stock').doc(code);
      if (type === 'stock_count') {
        // Absolute set
        batch.set(ref, { qty: delta, updated_at: now }, { merge: false });
      } else {
        // Relative increment
        batch.set(ref, { qty: FieldValue.increment(delta), updated_at: now }, { merge: true });
      }
    }
    await batch.commit();

    // Log event
    await db.collection('inventory_events').add({ type, deltas, note: note ?? '', timestamp: now });

    return c.json({ ok: true });
  });
