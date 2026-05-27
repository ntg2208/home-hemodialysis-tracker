import { Hono } from 'hono';
import { buildOAuthUrl, exchangeCode, SYNC_TYPES } from '../lib/googleHealth.js';
import { setRefreshToken } from '../lib/secretManager.js';

function getOAuthConfig() {
  const clientId = process.env.HEALTH_OAUTH_CLIENT_ID;
  const clientSecret = process.env.HEALTH_OAUTH_CLIENT_SECRET;
  const redirectUri = `${process.env.APP_ORIGIN ?? 'https://homehd.web.app'}/api/fitness/oauth/callback`;
  if (!clientId || !clientSecret) throw new Error('HEALTH_OAUTH_CLIENT_ID / HEALTH_OAUTH_CLIENT_SECRET not set');
  return { clientId, clientSecret, redirectUri };
}

// Routes registered pre-auth on `app` in index.ts — no bearer token needed
export const fitnessOAuth = new Hono()
  .get('/oauth/start', (c) => {
    const { clientId, redirectUri } = getOAuthConfig();
    return c.redirect(buildOAuthUrl({ clientId, redirectUri }));
  })
  .get('/oauth/callback', async (c) => {
    const code = c.req.query('code');
    const error = c.req.query('error');
    if (error) return c.text(`OAuth error: ${error}`, 400);
    if (!code) return c.text('Missing code param', 400);

    const { clientId, clientSecret, redirectUri } = getOAuthConfig();
    const { refreshToken } = await exchangeCode({ code, clientId, clientSecret, redirectUri });
    await setRefreshToken(refreshToken);
    return c.text('Fitness account authorised. You can close this tab.');
  });

// Sync endpoint — mounted under bearer auth in index.ts
export const fitness = new Hono()
  .get('/', (c) => c.json({ ok: true, types: SYNC_TYPES }))
  .post('/sync', async (c) => {
    // Implemented in Task 6
    return c.json({ ok: false, note: 'not yet implemented' }, 501);
  });
