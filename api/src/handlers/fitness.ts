import { Hono } from 'hono';
import { setCookie, getCookie, deleteCookie } from 'hono/cookie';
import { randomBytes } from 'node:crypto';
import {
  buildOAuthUrl,
  exchangeCode,
  SYNC_TYPES,
  refreshAccessToken,
  fetchDailyRollUp,
} from '../lib/googleHealth.js';
import { getRefreshToken, setRefreshToken } from '../lib/secretManager.js';
import {
  readSyncState,
  writeSyncState,
  uploadJson,
  dataTypePath,
  dateRange,
  type SyncState,
} from '../lib/gcs.js';

function getOAuthConfig() {
  const clientId = process.env.HEALTH_OAUTH_CLIENT_ID;
  const clientSecret = process.env.HEALTH_OAUTH_CLIENT_SECRET;
  const redirectUri = `${process.env.APP_ORIGIN ?? 'https://homehd.web.app'}/api/fitness/oauth/callback`;
  if (!clientId || !clientSecret) throw new Error('HEALTH_OAUTH_CLIENT_ID / HEALTH_OAUTH_CLIENT_SECRET not set');
  return { clientId, clientSecret, redirectUri };
}

function yesterday(): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

function daysAgo(n: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

function nextDay(date: string): string {
  const d = new Date(date);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
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
      maxAge: 600,
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
    try {
      const backfillDays = Math.max(1, Math.min(Number(c.req.query('days') ?? '365'), 3650));

      const { clientId, clientSecret } = getOAuthConfig();
      const refreshToken = await getRefreshToken();
      const accessToken = await refreshAccessToken({ refreshToken, clientId, clientSecret });

      const syncState: SyncState = await readSyncState();
      const endDate = yesterday();

      const summary: Record<string, { from: string; to: string; files: number }> = {};

      for (const type of SYNC_TYPES) {
        const lastSynced = syncState[type];
        const startDate = lastSynced ? nextDay(lastSynced) : daysAgo(backfillDays);

        if (startDate > endDate) {
          summary[type] = { from: startDate, to: endDate, files: 0 };
          continue;
        }

        const raw = await fetchDailyRollUp({ accessToken, dataType: type, startDate, endDate });

        // Store one file per date range (not per day) — the dailyRollUp response covers the full
        // range in a single payload. Per-day splitting deferred to a later processing step once
        // the actual response shape is understood from the first live call.
        const path = dataTypePath(type, `${startDate}_to_${endDate}`);
        await uploadJson(path, {
          fetched_at: new Date().toISOString(),
          start: startDate,
          end: endDate,
          data: raw,
        });

        syncState[type] = endDate;
        summary[type] = { from: startDate, to: endDate, files: dateRange(startDate, endDate).length };
      }

      await writeSyncState(syncState);
      return c.json({ ok: true, synced: summary });
    } catch (err) {
      console.error('Sync error:', err instanceof Error ? err.message : String(err));
      return c.json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  });
