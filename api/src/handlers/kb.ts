import { Hono } from 'hono';
export const kb = new Hono().get('/', (c) => c.json({ ok: true, note: 'coming soon' }));
