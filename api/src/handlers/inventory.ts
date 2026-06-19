import { Hono } from 'hono';
import { FieldValue } from '@google-cloud/firestore';
import { getDb } from '../lib/firestore.js';
import { getInventory } from '../lib/reads/inventoryReads.js';
import {
  EventBodySchema,
  ConfirmOrderBodySchema,
  ApplyDeliveryBodySchema,
  SetPakInstallBodySchema,
  UpdateCycleDatesBodySchema,
  StockEditBodySchema,
  OrderEditBodySchema,
} from '../schemas/inventory.js';

export const inventory = new Hono()

  .get('/', async (c) => c.json(await getInventory()))

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

    // Idempotency guard: if a session event for this session_id already
    // exists, skip the write — the client may be retrying after a timeout.
    if (type === 'session' && note) {
      const existingSnap = await db.collection('inventory_events')
        .where('type', '==', 'session')
        .where('note', '==', note)
        .limit(1)
        .get();
      if (!existingSnap.empty) return c.json({ ok: true, deduped: true });
    }

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

  // Reverse the inventory deduction for a specific session. Called when a
  // treatment session is deleted. Finds the session event by its session_id
  // stored in the note field, reverses the deltas, and removes the event.
  .delete('/session/:sessionId', async (c) => {
    const sessionId = c.req.param('sessionId');
    const db = getDb();

    // Query by note only to avoid needing a composite index.
    const snap = await db.collection('inventory_events')
      .where('note', '==', sessionId)
      .get();

    const sessionEvents = snap.docs.filter(d => d.data().type === 'session');
    if (sessionEvents.length === 0) return c.json({ ok: true, reversed: false });

    const now = new Date().toISOString();
    const batch = db.batch();
    for (const doc of sessionEvents) {
      const deltas = (doc.data() as { deltas: Record<string, number> }).deltas;
      for (const [code, delta] of Object.entries(deltas)) {
        const ref = db.collection('inventory_stock').doc(code);
        batch.set(ref, { qty: FieldValue.increment(-delta), updated_at: now }, { merge: true });
      }
      batch.delete(doc.ref);
    }
    await batch.commit();
    return c.json({ ok: true, reversed: true });
  })

  .post('/confirm-order', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }
    const parsed = ConfirmOrderBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);

    const { call_date, delivery_date: customDeliveryDate, order } = parsed.data;
    const deliveryDate = customDeliveryDate ?? addDays(call_date, 7);
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

  .put('/stock', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }
    const parsed = StockEditBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);

    const { items } = parsed.data;
    const now = new Date().toISOString();
    const db = getDb();

    const batch = db.batch();
    for (const [code, qty] of Object.entries(items)) {
      batch.set(db.collection('inventory_stock').doc(code), { qty, updated_at: now });
    }
    await batch.commit();

    await db.collection('inventory_events').add({
      type: 'stock_count',
      deltas: items,
      note: 'api edit',
      timestamp: now,
    });

    return c.json({ ok: true, updated: Object.keys(items).length });
  })

  .patch('/order', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }
    const parsed = OrderEditBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);

    const db = getDb();
    const cycleDoc = await db.collection('inventory_config').doc('cycle').get();
    if (!cycleDoc.exists) return c.json({ error: 'no active cycle' }, 404);

    await db.collection('inventory_config').doc('cycle').set(
      { order: parsed.data.order },
      { merge: true },
    );

    return c.json({ ok: true });
  })

  .post('/update-cycle-dates', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }
    const parsed = UpdateCycleDatesBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);

    const { call_date, delivery_date } = parsed.data;
    await getDb().collection('inventory_config').doc('cycle').set(
      { call_date, delivery_date },
      { merge: true },
    );

    return c.json({ ok: true });
  })

  .post('/set-pak-install', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }
    const parsed = SetPakInstallBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);

    const db = getDb();
    const newInstalledAt = parsed.data.installed_at;
    const pakRef = db.collection('inventory_config').doc('pak');
    const pakDoc = await pakRef.get();
    const prev = pakDoc.exists ? (pakDoc.data() as { installed_at?: string }) : null;

    // Archive the outgoing PAK's lifespan so future averages include it.
    if (prev?.installed_at && prev.installed_at !== newInstalledAt) {
      const sessionsSnap = await db.collection('treatment_sessions')
        .where('date', '>=', prev.installed_at)
        .where('date', '<', newInstalledAt)
        .get();
      await db.collection('pak_history').add({
        installed_at: prev.installed_at,
        replaced_at: newInstalledAt,
        sessions: sessionsSnap.docs.length,
      });
    }

    await pakRef.set({ installed_at: newInstalledAt });

    return c.json({ ok: true });
  });

function addDays(dateStr: string, days: number): string {
  const d = new Date(dateStr);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
