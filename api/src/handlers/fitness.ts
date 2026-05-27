import { Hono } from 'hono';
import { setCookie, getCookie, deleteCookie } from 'hono/cookie';
import { randomBytes } from 'node:crypto';
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
    const state = randomBytes(16).toString('hex');
    setCookie(c, 'oauth_state', state, {
      httpOnly: true,
      secure: true,
      sameSite: 'Lax',
      path: '/',
      maxAge: 600, // 10 minutes — enough time to complete the consent flow
    });
    return c.redirect(buildOAuthUrl({ clientId, redirectUri, state }));
  })
  .get('/oauth/callback', async (c) => {
    try {
      const error = c.req.query('error');
      if (error) return c.text(`OAuth error: ${error}`, 400);

      const code = c.req.query('code');
      if (!code) return c.text('Missing code param', 400);

      const stateParam = c.req.query('state');
      const stateCookie = getCookie(c, 'oauth_state');
      if (!stateParam || !stateCookie || stateParam !== stateCookie) {
        return c.text('State mismatch — possible CSRF. Please try again from /oauth/start.', 400);
      }
      deleteCookie(c, 'oauth_state', { path: '/' });

      const { clientId, clientSecret, redirectUri } = getOAuthConfig();
      const { refreshToken } = await exchangeCode({ code, clientId, clientSecret, redirectUri });
      await setRefreshToken(refreshToken);
      return c.text('Fitness account authorised. You can close this tab.');
    } catch (err) {
      console.error('OAuth callback error:', err instanceof Error ? err.message : String(err));
      return c.text('Authorization failed. Please try /api/fitness/oauth/start again.', 500);
    }
  });

// Sync endpoint — mounted under bearer auth in index.ts
export const fitness = new Hono()
  .get('/', (c) => c.json({ ok: true, types: SYNC_TYPES }))
  .post('/sync', async (c) => {
    // Implemented in Task 6
    return c.json({ ok: false, note: 'not yet implemented' }, 501);
  });
