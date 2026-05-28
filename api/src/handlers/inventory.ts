import { Hono } from 'hono';
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
  });
