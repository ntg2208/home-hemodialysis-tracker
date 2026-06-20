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
import type { SyncType, FetchStrategy } from '../lib/googleHealth.js';
import {
  readSyncState,
  writeSyncState,
  uploadJson,
  dataTypePath,
  dateRange,
  listFiles,
  readJson,
  readCount,
  type SyncState,
} from '../lib/gcs.js';
import { buildSummary } from '../lib/fitnessSummary.js';
import { buildSeries } from '../lib/fitnessSeries.js';
import { buildSleep } from '../lib/fitnessSleep.js';

/** Resolve the sync end date: a valid YYYY-MM-DD `to` param on/before
 * yesterday, else yesterday. Lets a caller backfill one day at a time
 * (?to=YYYY-MM-DD) instead of pulling the whole cursor→yesterday span. */
export function clampSyncEnd(to: string | undefined, yesterday: string): string {
  if (!to || !/^\d{4}-\d{2}-\d{2}$/.test(to)) return yesterday;
  return to <= yesterday ? to : yesterday;
}

// YYYY-MM-DD for `n` days before today (UTC).
function daysAgoDate(n: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

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

function nextDay(date: string): string {
  const d = new Date(date);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}

function subtractDays(date: string, n: number): string {
  const d = new Date(date);
  d.setUTCDate(d.getUTCDate() - n);
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

// === Core sync loop (dependency-injected so it's unit-testable without GCP/network) ===

export interface SyncDeps {
  readSyncState: () => Promise<SyncState>;
  writeSyncState: (s: SyncState) => Promise<void>;
  uploadJson: (path: string, data: unknown) => Promise<void>;
  fetchRollUp: (args: { dataType: string; startDate: string; endDate: string }) => Promise<unknown>;
  fetchList: (args: {
    dataType: string;
    filterField: string;
    filterDateField: Extract<FetchStrategy, { method: 'list' }>['filterDateField'];
    startDate: string;
    endDate: string;
  }) => Promise<unknown[]>;
}

export interface SyncOptions {
  backfillDays: number;
  lastInclusiveDate: string; // usually yesterday (UTC)
  onlyType?: SyncType;       // sync a single type instead of all
}

export type TypeResult =
  | { from: string; to: string; days_covered: number; status: 'ok' }
  | { status: 'error'; error: string };

export type SyncSummary = Record<string, TypeResult>;

// Sync each type independently: one type's failure is isolated (recorded, not thrown)
// and sync_state is persisted after every successful type so partial progress survives
// a timeout, an OOM, or a single bad data type.
export async function runSync(deps: SyncDeps, opts: SyncOptions): Promise<SyncSummary> {
  const { backfillDays, lastInclusiveDate, onlyType } = opts;
  const syncState = await deps.readSyncState();
  const summary: SyncSummary = {};
  const types: readonly SyncType[] = onlyType ? [onlyType] : SYNC_TYPES;

  for (const type of types) {
    try {
      const lastSynced = syncState[type];
      const startDate = lastSynced ? nextDay(lastSynced) : subtractDays(lastInclusiveDate, backfillDays - 1);

      if (startDate > lastInclusiveDate) {
        summary[type] = { from: startDate, to: lastInclusiveDate, days_covered: 0, status: 'ok' };
        continue;
      }

      const strategy = SYNC_TYPE_STRATEGY[type];
      let totalDays = 0;

      if (strategy.method === 'dailyRollUp') {
        const chunks = chunkDateRange(startDate, lastInclusiveDate, 90);
        for (const [chunkStart, chunkEnd] of chunks) {
          const raw = await deps.fetchRollUp({
            dataType: type,
            startDate: chunkStart,
            endDate: nextDay(chunkEnd), // API end is exclusive
          });
          await deps.uploadJson(dataTypePath(type, `${chunkStart}_to_${chunkEnd}`), {
            fetched_at: new Date().toISOString(),
            start: chunkStart,
            end: chunkEnd,
            data: raw,
          });
          totalDays += dateRange(chunkStart, chunkEnd).length;
        }
      } else {
        const points = await deps.fetchList({
          dataType: type,
          filterField: strategy.filterField,
          filterDateField: strategy.filterDateField,
          startDate,
          endDate: lastInclusiveDate,
        });
        await deps.uploadJson(dataTypePath(type, `${startDate}_to_${lastInclusiveDate}`), {
          fetched_at: new Date().toISOString(),
          start: startDate,
          end: lastInclusiveDate,
          count: points.length,
          data: points,
        });
        totalDays = dateRange(startDate, lastInclusiveDate).length;
      }

      // Advance + persist this type's cursor immediately, before moving to the next type.
      syncState[type] = lastInclusiveDate;
      await deps.writeSyncState(syncState);
      summary[type] = { from: startDate, to: lastInclusiveDate, days_covered: totalDays, status: 'ok' };
    } catch (err) {
      summary[type] = { status: 'error', error: err instanceof Error ? err.message : String(err) };
    }
  }

  return summary;
}

// Sync endpoint — mounted under bearer auth in index.ts
export const fitness = new Hono()
  .get('/', (c) => c.json({ ok: true, types: SYNC_TYPES }))
  .get('/summary', async (c) => {
    try {
      const today = new Date().toISOString().slice(0, 10);
      const summary = await buildSummary(
        { readSyncState, listFiles, readJson, readCount },
        { types: SYNC_TYPES, today }
      );
      return c.json(summary);
    } catch (err) {
      console.error('Summary error:', err instanceof Error ? err.message : String(err));
      return c.json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  })
  .get('/series', async (c) => {
    const type = c.req.query('type');
    if (!type || !SYNC_TYPES.includes(type as SyncType)) {
      return c.json({ ok: false, error: `unknown or missing type: ${type ?? ''}` }, 400);
    }
    const today = new Date().toISOString().slice(0, 10);
    const from = c.req.query('from') ?? daysAgoDate(30);
    const to = c.req.query('to') ?? today;
    try {
      const series = await buildSeries({ listFiles, readJson }, { type, from, to });
      return c.json(series);
    } catch (err) {
      console.error('Series error:', err instanceof Error ? err.message : String(err));
      return c.json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  })
  .get('/sleep', async (c) => {
    const today = new Date().toISOString().slice(0, 10);
    const from = c.req.query('from') ?? daysAgoDate(30);
    const to = c.req.query('to') ?? today;
    try {
      const sleep = await buildSleep({ listFiles, readJson }, { from, to });
      return c.json(sleep);
    } catch (err) {
      console.error('Sleep error:', err instanceof Error ? err.message : String(err));
      return c.json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  })
  .post('/sync', async (c) => {
    try {
      const backfillDays = Math.max(1, Math.min(Number(c.req.query('days') ?? '365'), 3650));

      const typeParam = c.req.query('type');
      if (typeParam && !SYNC_TYPES.includes(typeParam as SyncType)) {
        return c.json({ ok: false, error: `unknown type: ${typeParam}` }, 400);
      }
      const onlyType = typeParam as SyncType | undefined;

      const { clientId, clientSecret } = getOAuthConfig();
      const refreshToken = await getRefreshToken();
      const accessToken = await refreshAccessToken({ refreshToken, clientId, clientSecret });

      const summary = await runSync(
        {
          readSyncState,
          writeSyncState,
          uploadJson,
          fetchRollUp: ({ dataType, startDate, endDate }) =>
            fetchDailyRollUp({ accessToken, dataType, startDate, endDate }),
          fetchList: ({ dataType, filterField, filterDateField, startDate, endDate }) =>
            fetchListAll({ accessToken, dataType, filterField, filterDateField, startDate, endDate }),
        },
        { backfillDays, lastInclusiveDate: clampSyncEnd(c.req.query('to'), yesterday()), onlyType }
      );

      const anyError = Object.values(summary).some((r) => r.status === 'error');
      return c.json({ ok: !anyError, synced: summary });
    } catch (err) {
      console.error('Sync error:', err instanceof Error ? err.message : String(err));
      return c.json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  });
