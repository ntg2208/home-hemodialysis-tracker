import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import { bearerAuth } from './lib/auth.js';
import { kb } from './handlers/kb.js';
import { inventory } from './handlers/inventory.js';
import { fitness } from './handlers/fitness.js';
import { chat } from './handlers/chat.js';

const app = new Hono();

app.get('/api/health', (c) => c.json({ ok: true }));
app.use('/api/*', bearerAuth(() => process.env.MAIN_API_KEY));

app.route('/api/kb', kb);
app.route('/api/inventory', inventory);
app.route('/api/fitness', fitness);
app.route('/api/chat', chat);

app.notFound((c) => c.json({ error: 'not_found' }, 404));
app.onError((err, c) => c.json({ error: 'server_error', message: String(err) }, 500));

serve({ fetch: app.fetch, port: Number(process.env.PORT ?? 8080) });
