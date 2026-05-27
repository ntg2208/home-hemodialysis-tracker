import { Hono } from 'hono';
export const chat = new Hono().get('/', (c) => c.json({ ok: true, note: 'coming soon' }));
