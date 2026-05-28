import { Hono } from 'hono';
import {
  buildOAuthUrl,
  exchangeCode,
  SYNC_TYPES,
  SYNC_TYPE_STRATEGY,
  refreshAccessToken,
  fetchDailyRollUp,
  fetchListAll,
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

// Split an inclusive date range into chunks of at most `chunkDays` days each.
function chunkDateRange(startInclusive: string, endInclusive: string, chunkDays: number): Array<[string, string]> {
  const chunks: Array<[string, string]> = [];
  let cursor = startInclusive;
  while (cursor <= endInclusive) {
    const chunkEnd = new Date(cursor);
    chunkEnd.setUTCDate(chunkEnd.getUTCDate() + chunkDays - 1);
    const chunkEndStr = chunkEnd.toISOString().slice(0, 10);
    chunks.push([cursor, chunkEndStr < endInclusive ? chunkEndStr : endInclusive]);
    cursor = nextDay(chunks[chunks.length - 1][1]);
  }
  return chunks;
}

// Routes registered pre-auth on `app` in index.ts — no bearer token needed
export const fitnessOAuth = new Hono()
  .get('/oauth/start', (c) => {
    const { clientId, redirectUri } = getOAuthConfig();
    return c.redirect(buildOAuthUrl({ clientId, redirectUri }));
  })
  .get('/oauth/callback', async (c) => {
    try {
      const error = c.req.query('error');
      if (error) return c.text(`OAuth error: ${error}`, 400);

      const code = c.req.query('code');
      if (!code) return c.text('Missing code param', 400);

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
      const lastInclusiveDate = yesterday();

      const summary: Record<string, { from: string; to: string; days_covered: number }> = {};

      for (const type of SYNC_TYPES) {
        const lastSynced = syncState[type];
        const startDate = lastSynced ? nextDay(lastSynced) : daysAgo(backfillDays);

        if (startDate > lastInclusiveDate) {
          summary[type] = { from: startDate, to: lastInclusiveDate, days_covered: 0 };
          continue;
        }

        const strategy = SYNC_TYPE_STRATEGY[type];
        let totalDays = 0;

        if (strategy.method === 'dailyRollUp') {
          const chunks = chunkDateRange(startDate, lastInclusiveDate, 90);
          for (const [chunkStart, chunkEnd] of chunks) {
            const raw = await fetchDailyRollUp({
              accessToken,
              dataType: type,
              startDate: chunkStart,
              endDate: nextDay(chunkEnd), // API end is exclusive
            });
            const path = dataTypePath(type, `${chunkStart}_to_${chunkEnd}`);
            await uploadJson(path, {
              fetched_at: new Date().toISOString(),
              start: chunkStart,
              end: chunkEnd,
              data: raw,
            });
            totalDays += dateRange(chunkStart, chunkEnd).length;
          }
        } else {
          const points = await fetchListAll({
            accessToken,
            dataType: type,
            filterField: strategy.filterField,
            filterDateField: strategy.filterDateField,
            startDate,
            endDate: lastInclusiveDate,
          });
          const path = dataTypePath(type, `${startDate}_to_${lastInclusiveDate}`);
          await uploadJson(path, {
            fetched_at: new Date().toISOString(),
            start: startDate,
            end: lastInclusiveDate,
            count: points.length,
            data: points,
          });
          totalDays = dateRange(startDate, lastInclusiveDate).length;
        }

        syncState[type] = lastInclusiveDate;
        summary[type] = { from: startDate, to: lastInclusiveDate, days_covered: totalDays };
      }

      await writeSyncState(syncState);
      return c.json({ ok: true, synced: summary });
    } catch (err) {
      console.error('Sync error:', err instanceof Error ? err.message : String(err));
      return c.json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  });
