import { Hono } from 'hono';
import { FieldValue } from '@google-cloud/firestore';
import { getDb } from '../lib/firestore.js';
import {
  EventBodySchema,
  ConfirmOrderBodySchema,
  ApplyDeliveryBodySchema,
  SetPakInstallBodySchema,
} from '../schemas/inventory.js';

export const inventory = new Hono()

  .get('/', async (c) => {
    const db = getDb();

    const [stockSnap, cycleDoc, pakDoc] = await Promise.all([
      db.collection('inventory_stock').get(),
      db.collection('inventory_config').doc('cycle').get(),
      db.collection('inventory_config').doc('pak').get(),
    ]);

    const stock: Record<string, number> = {};
    for (const doc of stockSnap.docs) {
      const d = doc.data() as { qty: number };
      if (typeof d.qty === 'number') stock[doc.id] = d.qty;
    }

    const cycle = cycleDoc.exists ? (cycleDoc.data() ?? null) : null;

    const pakData = pakDoc.exists ? (pakDoc.data() as { installed_at?: string }) : null;
    const pak_installed_at = pakData?.installed_at ?? null;

    let pak_sessions = 0;
    if (pak_installed_at) {
      const eventsSnap = await db.collection('inventory_events')
        .where('type', '==', 'session')
        .get();
      pak_sessions = eventsSnap.docs.filter(d => {
        const ts = (d.data() as { timestamp: string }).timestamp;
        return typeof ts === 'string' && ts >= pak_installed_at;
      }).length;
    }

    return c.json({ stock, cycle, pak_installed_at, pak_sessions });
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
  })

  .post('/confirm-order', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }
    const parsed = ConfirmOrderBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);

    const { call_date, order } = parsed.data;
    const deliveryDate = addDays(call_date, 7);
    const now = new Date().toISOString();
    const hasOrder = Object.keys(order).length > 0;

    await getDb().collection('inventory_config').doc('cycle').set({
      call_date,
      delivery_date: deliveryDate,
      order,
      order_placed_at: hasOrder ? now : null,
      delivery_applied_at: null,
    });

    return c.json({ ok: true });
  })

  .post('/apply-delivery', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }
    const parsed = ApplyDeliveryBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);

    const db = getDb();
    const cycleDoc = await db.collection('inventory_config').doc('cycle').get();
    if (!cycleDoc.exists) return c.json({ error: 'no active cycle' }, 404);

    const cycle = cycleDoc.data() as {
      call_date: string;
      order?: Record<string, number>;
      order_placed_at: string | null;
    };

    const baseOrder = cycle.order ?? {};
    const adjustments = parsed.data.adjustments ?? {};
    const finalDelivery: Record<string, number> = { ...baseOrder, ...adjustments };

    const now = new Date().toISOString();
    const batch = db.batch();
    for (const [code, qty] of Object.entries(finalDelivery)) {
      const ref = db.collection('inventory_stock').doc(code);
      batch.set(ref, { qty: FieldValue.increment(qty), updated_at: now }, { merge: true });
    }
    await batch.commit();

    await db.collection('inventory_events').add({
      type: 'delivery',
      deltas: finalDelivery,
      note: 'delivery applied',
      timestamp: now,
    });

    const nextCallDate = addDays(cycle.call_date, 28);
    const nextDeliveryDate = addDays(nextCallDate, 7);
    await db.collection('inventory_config').doc('cycle').set({
      call_date: nextCallDate,
      delivery_date: nextDeliveryDate,
      order: {},
      order_placed_at: null,
      delivery_applied_at: now,
    });

    return c.json({ ok: true });
  })

  .get('/deliveries', async (c) => {
    const snap = await getDb().collection('inventory_events')
      .where('type', '==', 'delivery')
      .get();
    const deliveries = snap.docs
      .map(d => d.data() as { timestamp: string; deltas: Record<string, number>; note?: string })
      .sort((a, b) => b.timestamp.localeCompare(a.timestamp));
    return c.json({ deliveries });
  })

  .post('/set-pak-install', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }
    const parsed = SetPakInstallBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);

    await getDb().collection('inventory_config').doc('pak').set({
      installed_at: parsed.data.installed_at,
    });

    return c.json({ ok: true });
  });

function addDays(dateStr: string, days: number): string {
  const d = new Date(dateStr);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
