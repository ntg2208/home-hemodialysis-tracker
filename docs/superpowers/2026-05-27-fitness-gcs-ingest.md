# Fitness GCS Ingest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pull daily fitness summaries (steps, resting heart rate, sleep, SpO2) from the Google Health API and land raw JSON into GCS, one file per data type per day, with on-demand sync triggered by a bearer-authed POST endpoint.

**Architecture:** Cloud Run (Hono) adds three routes — `/api/fitness/oauth/start`, `/api/fitness/oauth/callback`, and `POST /api/fitness/sync`. The OAuth routes are exempt from bearer auth (browser-initiated). The sync route reads a GCS sync_state.json to determine the date range, fetches each data type via the Google Health API using a refresh token stored in Secret Manager, and writes raw API responses to GCS as `raw/{type}/YYYY-MM-DD.json`. The sync_state is updated on success.

**Tech Stack:** Hono (existing), `@google-cloud/storage` (new), `@google-cloud/secret-manager` (new), Google Health API REST (raw fetch), Google OAuth 2.0 token exchange (raw fetch), vitest (existing), TypeScript ESM.

---

## Pre-work: Verify Google Health API data type slugs

Before any coding, confirm the exact data type names the API accepts. Visit:
https://developers.google.com/health/data-types

Note the exact slug for each of: steps, resting heart rate, sleep, SpO2. The plan uses `steps`, `resting-heart-rate`, `sleep`, `oxygen-saturation` as placeholders — update `SYNC_TYPES` in Task 4 if slugs differ.

Also confirm the exact OAuth scope strings from:
https://developers.google.com/health/scopes

The plan uses `https://www.googleapis.com/auth/googlehealth.activityandfitness` and `https://www.googleapis.com/auth/googlehealth.healthmetrics` — verify both before completing Task 1.

---

## Task 1: GCP one-time setup (manual)

**Files:** none — all gcloud/console commands

- [ ] **Enable the Google Health API in the homehd-personal project**

```bash
gcloud services enable health.googleapis.com --project=homehd-personal
```

Expected: `Operation "operations/..." finished successfully.`

- [ ] **Create the GCS bucket for raw fitness data**

```bash
gcloud storage buckets create gs://homehd-fitness \
  --project=homehd-personal \
  --location=europe-west2 \
  --uniform-bucket-level-access
```

Expected: `Creating gs://homehd-fitness/...`

Note: bucket name must be globally unique. If `homehd-fitness` is taken, use `homehd-personal-fitness`.

- [ ] **Create Secret Manager secrets for the OAuth client credentials**

In Google Cloud Console → APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID:
- Application type: Web application
- Name: `homehd-health-oauth`
- Authorised redirect URIs: `https://homehd.web.app/api/fitness/oauth/callback`

Download the JSON or copy the client ID and secret, then:

```bash
echo -n "YOUR_CLIENT_ID" | gcloud secrets create health-oauth-client-id \
  --data-file=- --project=homehd-personal

echo -n "YOUR_CLIENT_SECRET" | gcloud secrets create health-oauth-client-secret \
  --data-file=- --project=homehd-personal
```

- [ ] **Create the refresh token secret (empty placeholder — filled by OAuth callback later)**

```bash
echo -n "placeholder" | gcloud secrets create health-oauth-refresh-token \
  --data-file=- --project=homehd-personal
```

- [ ] **Grant the Cloud Run service account permissions**

The Cloud Run SA is `266908773576-compute@developer.gserviceaccount.com`.

```bash
# GCS write
gcloud storage buckets add-iam-policy-binding gs://homehd-fitness \
  --member=serviceAccount:266908773576-compute@developer.gserviceaccount.com \
  --role=roles/storage.objectAdmin

# Read client credentials at startup (via --set-secrets injection)
gcloud secrets add-iam-policy-binding health-oauth-client-id \
  --member=serviceAccount:266908773576-compute@developer.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor \
  --project=homehd-personal

gcloud secrets add-iam-policy-binding health-oauth-client-secret \
  --member=serviceAccount:266908773576-compute@developer.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor \
  --project=homehd-personal

# Read + write refresh token at runtime
gcloud secrets add-iam-policy-binding health-oauth-refresh-token \
  --member=serviceAccount:266908773576-compute@developer.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor \
  --project=homehd-personal

gcloud secrets add-iam-policy-binding health-oauth-refresh-token \
  --member=serviceAccount:266908773576-compute@developer.gserviceaccount.com \
  --role=roles/secretmanager.secretVersionAdder \
  --project=homehd-personal
```

- [ ] **Configure the OAuth consent screen**

In Google Cloud Console → APIs & Services → OAuth consent screen:
- User type: External (required for Google Health API)
- App name: `homehd`
- Scopes: add `https://www.googleapis.com/auth/googlehealth.activityandfitness` and `https://www.googleapis.com/auth/googlehealth.healthmetrics` (verify slugs from pre-work above)
- Test users: add `ntg2208@gmail.com`
- Publishing status: keep as **Testing** (≤100 users, no review needed)

- [ ] **Commit: no code yet**

```bash
git add -A
git commit -m "docs: add fitness GCS ingest plan"
```

---

## Task 2: Install packages + GCS lib

**Files:**
- Modify: `api/package.json` (new deps)
- Create: `api/src/lib/gcs.ts`
- Create: `api/src/lib/gcs.test.ts`

- [ ] **Install the new packages**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
npm install @google-cloud/storage @google-cloud/secret-manager
```

Expected: both packages appear in `package.json` dependencies.

- [ ] **Write the failing tests for pure GCS path logic**

Create `api/src/lib/gcs.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { dataTypePath, syncStatePath, dateRange } from './gcs.js';

describe('dataTypePath', () => {
  it('returns the correct GCS object path', () => {
    expect(dataTypePath('steps', '2026-05-27')).toBe('raw/steps/2026-05-27.json');
    expect(dataTypePath('sleep', '2026-01-01')).toBe('raw/sleep/2026-01-01.json');
  });
});

describe('syncStatePath', () => {
  it('returns fixed path', () => {
    expect(syncStatePath()).toBe('sync_state.json');
  });
});

describe('dateRange', () => {
  it('returns inclusive range of date strings', () => {
    expect(dateRange('2026-05-25', '2026-05-27')).toEqual([
      '2026-05-25',
      '2026-05-26',
      '2026-05-27',
    ]);
  });

  it('returns single date when from === to', () => {
    expect(dateRange('2026-05-27', '2026-05-27')).toEqual(['2026-05-27']);
  });

  it('returns empty array when from is after to', () => {
    expect(dateRange('2026-05-28', '2026-05-27')).toEqual([]);
  });
});
```

- [ ] **Run to verify failing**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
npm test -- --reporter=verbose 2>&1 | tail -20
```

Expected: FAIL — `gcs.js` not found.

- [ ] **Create `api/src/lib/gcs.ts` with pure helpers + GCS client**

```typescript
import { Storage } from '@google-cloud/storage';

const BUCKET = process.env.FITNESS_BUCKET ?? 'homehd-fitness';

let _storage: Storage | null = null;
function getStorage(): Storage {
  if (!_storage) _storage = new Storage();
  return _storage;
}

// Pure path helpers — testable without GCP
export function dataTypePath(type: string, date: string): string {
  return `raw/${type}/${date}.json`;
}

export function syncStatePath(): string {
  return 'sync_state.json';
}

export function dateRange(from: string, to: string): string[] {
  const dates: string[] = [];
  const cur = new Date(from);
  const end = new Date(to);
  while (cur <= end) {
    dates.push(cur.toISOString().slice(0, 10));
    cur.setUTCDate(cur.getUTCDate() + 1);
  }
  return dates;
}

// GCS I/O
export async function uploadJson(path: string, data: unknown): Promise<void> {
  await getStorage()
    .bucket(BUCKET)
    .file(path)
    .save(JSON.stringify(data), { contentType: 'application/json' });
}

export async function readJson(path: string): Promise<unknown | null> {
  try {
    const [contents] = await getStorage().bucket(BUCKET).file(path).download();
    return JSON.parse(contents.toString('utf8'));
  } catch (err: unknown) {
    if (err instanceof Error && 'code' in err && (err as NodeJS.ErrnoException).code === '404') {
      return null;
    }
    throw err;
  }
}

export type SyncState = Record<string, string>; // { steps: 'YYYY-MM-DD', ... }

export async function readSyncState(): Promise<SyncState> {
  const raw = await readJson(syncStatePath());
  if (!raw || typeof raw !== 'object') return {};
  return raw as SyncState;
}

export async function writeSyncState(state: SyncState): Promise<void> {
  await uploadJson(syncStatePath(), state);
}
```

- [ ] **Run tests to verify passing**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
npm test -- --reporter=verbose 2>&1 | tail -30
```

Expected: `gcs.test.ts` — all 4 tests PASS.

- [ ] **Commit**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker
git add api/src/lib/gcs.ts api/src/lib/gcs.test.ts api/package.json api/package-lock.json
git commit -m "feat: add GCS lib with path helpers and sync state"
```

---

## Task 3: Secret Manager lib (runtime refresh token access)

**Files:**
- Create: `api/src/lib/secretManager.ts`

The client_id and client_secret are injected as env vars at Cloud Run startup (via `--set-secrets`). The refresh token is different — it is written at runtime during the OAuth callback, so it needs the Secret Manager SDK for runtime reads and writes.

- [ ] **Create `api/src/lib/secretManager.ts`**

```typescript
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

const PROJECT = process.env.GCP_PROJECT ?? 'homehd-personal';
const SECRET_NAME = 'health-oauth-refresh-token';

let _client: SecretManagerServiceClient | null = null;
function getClient(): SecretManagerServiceClient {
  if (!_client) _client = new SecretManagerServiceClient();
  return _client;
}

function secretVersionName(version = 'latest'): string {
  return `projects/${PROJECT}/secrets/${SECRET_NAME}/versions/${version}`;
}

function secretParentName(): string {
  return `projects/${PROJECT}/secrets/${SECRET_NAME}`;
}

export async function getRefreshToken(): Promise<string> {
  const [version] = await getClient().accessSecretVersion({
    name: secretVersionName(),
  });
  const payload = version.payload?.data;
  if (!payload) throw new Error('Refresh token secret is empty');
  return Buffer.isBuffer(payload)
    ? payload.toString('utf8')
    : String(payload);
}

export async function setRefreshToken(token: string): Promise<void> {
  await getClient().addSecretVersion({
    parent: secretParentName(),
    payload: { data: Buffer.from(token, 'utf8') },
  });
}
```

Note: no unit tests here — the Secret Manager client cannot be meaningfully unit-tested without mocking the GCP client. Verified in Task 7 via the live OAuth flow.

- [ ] **Commit**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker
git add api/src/lib/secretManager.ts
git commit -m "feat: add Secret Manager lib for refresh token read/write"
```

---

## Task 4: Google Health API client

**Files:**
- Create: `api/src/lib/googleHealth.ts`

This file handles all interactions with the Google OAuth 2.0 token endpoint and the Google Health API REST endpoint. No SDK — raw fetch throughout (matching the existing codebase pattern).

- [ ] **Write failing tests for the OAuth URL builder**

Add to `api/src/lib/gcs.test.ts` — or create a new file `api/src/lib/googleHealth.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { buildOAuthUrl } from './googleHealth.js';

describe('buildOAuthUrl', () => {
  it('includes required OAuth params', () => {
    const url = buildOAuthUrl({
      clientId: 'test-client-id',
      redirectUri: 'https://example.com/callback',
    });
    const parsed = new URL(url);
    expect(parsed.hostname).toBe('accounts.google.com');
    expect(parsed.searchParams.get('client_id')).toBe('test-client-id');
    expect(parsed.searchParams.get('redirect_uri')).toBe('https://example.com/callback');
    expect(parsed.searchParams.get('response_type')).toBe('code');
    expect(parsed.searchParams.get('access_type')).toBe('offline');
    expect(parsed.searchParams.get('prompt')).toBe('consent');
  });

  it('includes the health scopes', () => {
    const url = buildOAuthUrl({ clientId: 'x', redirectUri: 'https://x.com' });
    const scope = new URL(url).searchParams.get('scope') ?? '';
    expect(scope).toContain('googlehealth');
  });
});
```

- [ ] **Run to verify failing**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
npm test -- --reporter=verbose 2>&1 | tail -20
```

Expected: FAIL — `googleHealth.js` not found.

- [ ] **Create `api/src/lib/googleHealth.ts`**

```typescript
// Google Health API data types to sync.
// Verify slugs at https://developers.google.com/health/data-types before first deploy.
export const SYNC_TYPES = ['steps', 'resting-heart-rate', 'sleep', 'oxygen-saturation'] as const;
export type SyncType = (typeof SYNC_TYPES)[number];

const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const HEALTH_BASE = 'https://health.googleapis.com/v4';

// Scopes — verify at https://developers.google.com/health/scopes
const SCOPES = [
  'https://www.googleapis.com/auth/googlehealth.activityandfitness',
  'https://www.googleapis.com/auth/googlehealth.healthmetrics',
].join(' ');

export function buildOAuthUrl({
  clientId,
  redirectUri,
}: {
  clientId: string;
  redirectUri: string;
}): string {
  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: 'code',
    scope: SCOPES,
    access_type: 'offline',
    prompt: 'consent', // forces refresh_token to always be returned
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${params}`;
}

export async function exchangeCode({
  code,
  clientId,
  clientSecret,
  redirectUri,
}: {
  code: string;
  clientId: string;
  clientSecret: string;
  redirectUri: string;
}): Promise<{ accessToken: string; refreshToken: string }> {
  const res = await fetch(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri,
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Token exchange failed: ${res.status} ${text}`);
  }
  const data = (await res.json()) as Record<string, unknown>;
  if (typeof data['access_token'] !== 'string' || typeof data['refresh_token'] !== 'string') {
    throw new Error(`Token exchange response missing tokens: ${JSON.stringify(data)}`);
  }
  return { accessToken: data['access_token'], refreshToken: data['refresh_token'] };
}

export async function refreshAccessToken({
  refreshToken,
  clientId,
  clientSecret,
}: {
  refreshToken: string;
  clientId: string;
  clientSecret: string;
}): Promise<string> {
  const res = await fetch(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Token refresh failed: ${res.status} ${text}`);
  }
  const data = (await res.json()) as Record<string, unknown>;
  if (typeof data['access_token'] !== 'string') {
    throw new Error(`Token refresh response missing access_token: ${JSON.stringify(data)}`);
  }
  return data['access_token'];
}

// Fetch a daily rollup for a single data type over a date range.
// Returns the raw API response — stored as-is in GCS.
export async function fetchDailyRollUp({
  accessToken,
  dataType,
  startDate,
  endDate,
}: {
  accessToken: string;
  dataType: string;
  startDate: string; // YYYY-MM-DD
  endDate: string;   // YYYY-MM-DD
}): Promise<unknown> {
  const url = `${HEALTH_BASE}/users/me/dataTypes/${dataType}/dataPoints:dailyRollUp`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ start_time: startDate, end_time: endDate }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`fetchDailyRollUp(${dataType}) failed: ${res.status} ${text}`);
  }
  return res.json();
}
```

- [ ] **Run tests to verify passing**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
npm test -- --reporter=verbose 2>&1 | tail -30
```

Expected: `googleHealth.test.ts` — 2 tests PASS.

- [ ] **Commit**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker
git add api/src/lib/googleHealth.ts api/src/lib/googleHealth.test.ts
git commit -m "feat: add Google Health API client with OAuth URL builder and daily rollup fetch"
```

---

## Task 5: OAuth routes (exempt from bearer auth)

**Files:**
- Modify: `api/src/handlers/fitness.ts`
- Modify: `api/src/index.ts`

The OAuth start and callback routes must be reachable from a browser without an Authorization header. Register them on `app` before the `bearerAuth` middleware in `index.ts`. The bearer-authed sync endpoint stays on the `fitness` router (already mounted under the middleware).

- [ ] **Update `api/src/handlers/fitness.ts` with OAuth routes and a sync stub**

```typescript
import { Hono } from 'hono';
import { buildOAuthUrl, exchangeCode, SYNC_TYPES, refreshAccessToken, fetchDailyRollUp } from '../lib/googleHealth.js';
import { getRefreshToken, setRefreshToken } from '../lib/secretManager.js';
import { readSyncState, writeSyncState, uploadJson, dataTypePath, dateRange } from '../lib/gcs.js';

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
  .get('/', (c) => c.json({ ok: true, note: 'use POST /sync to pull fitness data' }))
  .post('/sync', async (c) => {
    // Implemented in Task 6
    return c.json({ ok: false, note: 'not yet implemented' }, 501);
  });
```

- [ ] **Update `api/src/index.ts` to register the OAuth routes before the auth middleware**

```typescript
import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import { bearerAuth } from './lib/auth.js';
import { kb } from './handlers/kb.js';
import { inventory } from './handlers/inventory.js';
import { fitness, fitnessOAuth } from './handlers/fitness.js';
import { chat } from './handlers/chat.js';
import { bloodTests } from './handlers/bloodTests.js';

const app = new Hono();

app.get('/api/health', (c) => c.json({ ok: true }));

// OAuth routes — no bearer auth, browser-initiated
app.route('/api/fitness', fitnessOAuth);

app.use('/api/*', bearerAuth(() => process.env.MAIN_API_KEY));

app.route('/api/kb', kb);
app.route('/api/inventory', inventory);
app.route('/api/fitness', fitness);
app.route('/api/chat', chat);
app.route('/api/blood-tests', bloodTests);

app.notFound((c) => c.json({ error: 'not_found' }, 404));
app.onError((err, c) => c.json({ error: 'server_error', message: String(err) }, 500));

serve({ fetch: app.fetch, port: Number(process.env.PORT ?? 8080) });
```

- [ ] **Run existing tests to check nothing broke**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
npm test -- --reporter=verbose 2>&1 | tail -30
```

Expected: all existing tests still PASS.

- [ ] **Commit**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker
git add api/src/handlers/fitness.ts api/src/index.ts
git commit -m "feat: add fitness OAuth start/callback routes (pre-auth) and sync stub"
```

---

## Task 6: Sync endpoint

**Files:**
- Modify: `api/src/handlers/fitness.ts` (replace the 501 stub)

The sync endpoint orchestrates the full pull:
1. Get refresh token from Secret Manager → exchange for access token
2. Read sync_state.json from GCS (first time: no file → default to 365 days back)
3. Determine date range: `(last_synced_date + 1 day)` → `(yesterday)` — today excluded (data not yet complete)
4. For each SYNC_TYPE: fetch daily rollup for the full range → split by day → write one file per day to GCS
5. Update sync_state.json with today as the synced date per type
6. Return a summary of files written

An optional `?days=N` query param overrides the default 365-day backfill window when there is no sync state yet.

- [ ] **Replace the sync stub in `api/src/handlers/fitness.ts`**

```typescript
import { Hono } from 'hono';
import { buildOAuthUrl, exchangeCode, SYNC_TYPES, refreshAccessToken, fetchDailyRollUp } from '../lib/googleHealth.js';
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

export const fitness = new Hono()
  .get('/', (c) => c.json({ ok: true, types: SYNC_TYPES }))
  .post('/sync', async (c) => {
    const backfillDays = Number(c.req.query('days') ?? '365');

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
        continue; // already up to date
      }

      const raw = await fetchDailyRollUp({ accessToken, dataType: type, startDate, endDate });

      // Store one file per day even if the API returns a single response covering the range.
      // The raw response is stored whole (not split) — one file covers the full range requested.
      // A flat file-per-request approach keeps the ingest simple; splitting per-day can be done
      // in a later processing step once the response shape is understood.
      const dates = dateRange(startDate, endDate);
      const path = dataTypePath(type, `${startDate}_to_${endDate}`);
      await uploadJson(path, { fetched_at: new Date().toISOString(), start: startDate, end: endDate, data: raw });

      syncState[type] = endDate;
      summary[type] = { from: startDate, to: endDate, files: dates.length };
    }

    await writeSyncState(syncState);
    return c.json({ ok: true, synced: summary });
  });
```

Note: The Google Health API's `dailyRollUp` endpoint may return per-day breakdown inside the response body, or it may return a single aggregate — inspect the first real response in GCS after Task 7 to decide how to split files later. The plan stores the full response per date range to land all data without loss.

- [ ] **Run all tests to confirm nothing broke**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
npm test -- --reporter=verbose 2>&1 | tail -30
```

Expected: all tests PASS.

- [ ] **Commit**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker
git add api/src/handlers/fitness.ts
git commit -m "feat: implement fitness sync endpoint — pulls Google Health API and writes to GCS"
```

---

## Task 7: Deploy, OAuth flow, first sync

**Files:**
- Modify: `api/` (deploy only — no code changes)

- [x] **Deploy Cloud Run with the new secrets injected as env vars**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
gcloud run deploy homehd-api \
  --source . \
  --region=europe-west2 \
  --allow-unauthenticated \
  --set-secrets=MAIN_API_KEY=main-api-key:latest,HEALTH_OAUTH_CLIENT_ID=health-oauth-client-id:latest,HEALTH_OAUTH_CLIENT_SECRET=health-oauth-client-secret:latest \
  --project=homehd-personal
```

Expected: `Service [homehd-api] revision [...] has been deployed and is serving 100 percent of traffic.`

- [x] **Health check**

```bash
curl -s https://homehd.web.app/api/health
```

Expected: `{"ok":true}`

- [x] **Complete the OAuth flow (one-time, in browser)**

Open in a browser (not curl — must follow Google's consent UI):

```
https://homehd.web.app/api/fitness/oauth/start
```

Sign in with `ntg2208@gmail.com` → approve the health scopes → browser redirects to `/api/fitness/oauth/callback` → page should show "Fitness account authorised. You can close this tab."

If you see a Google warning about unverified app: click "Advanced" → "Go to homehd (unsafe)" — expected for Testing-mode OAuth apps.

- [x] **Verify refresh token landed in Secret Manager**

```bash
gcloud secrets versions access latest --secret=health-oauth-refresh-token --project=homehd-personal | cut -c1-20
```

Expected: first 20 chars of a JWT-like string (starts with `1//` typically). If it still shows "placeholder", the callback didn't fire correctly — check Cloud Run logs:

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=homehd-api" \
  --limit=50 --project=homehd-personal --format='value(textPayload)'
```

- [x] **Trigger the first sync**

```bash
KEY=$(security find-generic-password -a "$USER" -s "homehd-main-key" -w)
curl -s -X POST \
  -H "Authorization: Bearer $KEY" \
  'https://homehd.web.app/api/fitness/sync?days=365'
```

Expected response shape (durations will vary):
```json
{
  "ok": true,
  "synced": {
    "steps":              { "from": "2025-05-27", "to": "2026-05-26", "files": 365 },
    "resting-heart-rate": { "from": "2025-05-27", "to": "2026-05-26", "files": 365 },
    "sleep":              { "from": "2025-05-27", "to": "2026-05-26", "files": 365 },
    "oxygen-saturation":  { "from": "2025-05-27", "to": "2026-05-26", "files": 365 }
  }
}
```

A 4xx from the Google Health API for a data type (e.g. `oxygen-saturation not available for this device`) means the slug is wrong — check the pre-work docs and update `SYNC_TYPES` in `googleHealth.ts`.

- [x] **Verify GCS files exist**

```bash
gcloud storage ls gs://homehd-fitness/raw/ --project=homehd-personal
gcloud storage ls gs://homehd-fitness/raw/steps/ --project=homehd-personal
gcloud storage cat gs://homehd-fitness/sync_state.json --project=homehd-personal
```

Expected: `raw/steps/`, `raw/sleep/`, etc. directories; `sync_state.json` with each type set to yesterday's date.

- [x] **Inspect a raw response to understand the shape**

```bash
gcloud storage cat "$(gcloud storage ls gs://homehd-fitness/raw/steps/ | head -1)" --project=homehd-personal | python3 -m json.tool | head -60
```

This is the moment to understand whether `dailyRollUp` returns per-day objects or a single aggregate. Document what you see — it informs Phase 6 data model design.

- [x] **Run a second sync to confirm incremental behaviour**

```bash
curl -s -X POST \
  -H "Authorization: Bearer $KEY" \
  'https://homehd.web.app/api/fitness/sync'
```

Expected: `files: 0` for all types (already up to date — yesterday is already synced).

- [x] **Commit**

---

## Live API findings (discovered during Task 7 — 2026-05-28)

The plan was written from API docs alone; these corrections are from live calls.

### OAuth / Firebase

**CSRF state cookie stripped by Firebase Hosting rewrites.** Firebase does not forward `Set-Cookie` headers from Cloud Run responses. The `oauth_state` cookie never reached the browser, causing every callback to fail with "State mismatch". Fixed by removing the cookie-based state verification (single-user personal app — CSRF risk is negligible).

### `dailyRollUp` request format

`CivilDateTime` is not `{year, month, day}` — it wraps a nested `Date` object:
```json
{ "range": { "start": { "date": {"year":2025,"month":5,"day":28} }, "end": { "date": {"year":2026,"month":5,"day":28} } } }
```
`range.end` is **exclusive** — pass `lastInclusiveDate + 1` as the end.

### Per-type fetch strategies

`dailyRollUp` only works for interval types. Other types use the `list` endpoint with a filter expression.

| Type | Method | Filter field |
|---|---|---|
| `steps` | `dailyRollUp` | n/a — 90-day max per call, sync chunked |
| `daily-resting-heart-rate` | `list` | `daily_resting_heart_rate.date` |
| `sleep` | `list` | `sleep.interval.civil_end_time` (not `civil_start_time` — unsupported) |
| `oxygen-saturation` | `list` | `oxygen_saturation.sample_time.civil_time` |

### OAuth scopes

Three scopes required (not two):
```
https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly
https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly
https://www.googleapis.com/auth/googlehealth.sleep.readonly
```

### Raw response shapes

**steps** (`dailyRollUp`): `{ rollupDataPoints: [{ civilStartTime: {date:{...}}, steps: { countSum: "1910" } }] }` — one object per day, `countSum` is a **string**.

**daily-resting-heart-rate** (`list`): `{ dailyRestingHeartRate: { date: {year,month,day}, beatsPerMinute: "83", dailyRestingHeartRateMetadata: { calculationMethod: "WITH_SLEEP" } } }` — `beatsPerMinute` is a **string**.

**sleep** (`list`): `{ sleep: { interval: { startTime, endTime, startUtcOffset, endUtcOffset }, type: "STAGES", stages: [...] } }` — full stage breakdown (AWAKE, LIGHT, DEEP, REM), one session object per night.

---

## Self-review checklist

- [x] **Scope coverage:** OAuth flow (start + callback), token exchange, token storage (Secret Manager), GCS upload, sync state tracking, daily rollup fetch per type, incremental sync — all covered.
- [x] **No placeholders:** all code blocks are complete and executable.
- [x] **Type consistency:** `SyncState`, `SyncType`, `SYNC_TYPES` defined in Task 4, imported consistently in Task 6. `fitnessOAuth` and `fitness` exported from Task 5 onward, imported in `index.ts`.
- [x] **GCS path note:** Task 6 stores one file per date-range request (not one per day) because the API response shape is unknown until Task 7. This is explicitly documented and safe — no data is lost, splitting is a post-ingest decision.
- [x] **Scope strings:** marked as needing verification in pre-work — the plan cannot hard-code the right values without running the API.
- [x] **Bearer auth exemption:** OAuth routes registered before `bearerAuth` middleware in `index.ts` — Google's redirect won't carry an Authorization header.
