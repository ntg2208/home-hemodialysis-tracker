import { Hono } from 'hono';
export const fitness = new Hono().get('/', (c) => c.json({ ok: true, note: 'coming soon' }));
