import { Hono } from 'hono';
export const inventory = new Hono().get('/', (c) => c.json({ ok: true, note: 'coming soon' }));
