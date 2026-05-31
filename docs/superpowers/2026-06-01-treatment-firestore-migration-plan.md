# Treatment Firestore Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate Treatment session/reading storage from Apps Script + Google Sheet (primary) to Firestore (primary), with a weekly Cloud Scheduler job rebuilding the Sheet for the clinical team.

**Architecture:** Client-side Firestore SDK writes from the PWA (bypassing Cloud Run entirely — no cold-start risk). Cloud Run issues short-lived Firebase custom tokens in exchange for the mainKey. A Cloud Scheduler job POSTs to `/api/treatment/sync-to-sheet` every Sunday 08:00 UTC to rebuild the Sheet tabs.

**Tech Stack:** `firebase` (frontend SDK), `firebase-admin` + `googleapis` (api), `@google-cloud/firestore` (already in api), Firestore security rules, Google Sheets API v4.

**Spec:** `docs/superpowers/2026-06-01-treatment-firestore-migration.md`

---

## File map

| File | Action | Purpose |
|---|---|---|
| `api/package.json` | modify | add `firebase-admin`, `googleapis` |
| `api/src/handlers/treatment.ts` | create | token endpoint + sync-to-sheet endpoint |
| `api/src/handlers/treatment.test.ts` | create | unit tests for both endpoints |
| `api/src/index.ts` | modify | wire `/api/treatment` route |
| `api/scripts/backfill-treatment.ts` | create | one-time migration from Sheet → Firestore |
| `firestore.rules` | create | security rules for treatment_sessions + treatment_readings |
| `frontend/package.json` | modify | add `firebase` |
| `frontend/src/lib/firebaseClient.ts` | create | Firebase app + Firestore + Auth singletons |
| `frontend/src/routes/Treatment/api.ts` | replace | Firestore SDK calls (same exported signatures) |
| `frontend/src/routes/Treatment/api.test.ts` | create | unit tests for new api.ts |
| `frontend/src/routes/Treatment/schemas.ts` | modify | remove `Settings` type; `z.coerce.number()` → `z.number()` |
| `frontend/src/auth/storage.ts` | modify | drop Apps Script fields; add token fields |
| `frontend/src/auth/SetupWizard.tsx` | replace | remove Apps Script inputs; add token fetch |
| `frontend/src/routes/Treatment/index.tsx` | modify | remove settings state; add `ensureFirebaseAuth` |
| `frontend/src/routes/Treatment/screens/Home.tsx` | modify | remove `settings` prop |
| `frontend/src/routes/Treatment/screens/PreTreatment.tsx` | modify | remove `settings` prop |
| `frontend/src/routes/Treatment/screens/ActiveSession.tsx` | modify | remove `settings` prop |
| `frontend/src/routes/Treatment/screens/PostTreatment.tsx` | modify | remove `settings` prop |

---

## Phase 1 — GCP manual setup

### Task 1: GCP permissions + Sheet sharing

**Files:** none (infrastructure)

- [ ] **Step 1: Grant token-minting IAM role**

```bash
gcloud projects add-iam-policy-binding homehd-personal \
  --member="serviceAccount:266908773576-compute@developer.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator"
```

Expected: `Updated IAM policy for project [homehd-personal]`

- [ ] **Step 2: Enable Google Sheets API**

```bash
gcloud services enable sheets.googleapis.com --project=homehd-personal
```

Expected: `Operation ... finished successfully.`

- [ ] **Step 3: Share the Google Sheet with the service account**

Open the Google Sheet in your browser → Share → add `266908773576-compute@developer.gserviceaccount.com` as **Editor**. (This is the same Sheet the Apps Script writes to — the one whose URL contains the sheet ID you'll use for `TREATMENT_SHEET_ID`.)

- [ ] **Step 4: Record the spreadsheet ID**

The spreadsheet ID is the part of the Sheet URL between `/d/` and `/edit`:
```
https://docs.google.com/spreadsheets/d/SPREADSHEET_ID_HERE/edit
```

Save it — you'll pass it as `TREATMENT_SHEET_ID` at deploy time.

---

## Phase 2 — Backend: token + sync-to-sheet endpoints

### Task 2: Add api dependencies

**Files:**
- Modify: `api/package.json`

- [ ] **Step 1: Install firebase-admin and googleapis**

```bash
cd api && npm install firebase-admin googleapis
```

- [ ] **Step 2: Verify installation**

```bash
node -e "import('firebase-admin/auth').then(() => console.log('ok'))"
```

Expected: `ok`

---

### Task 3: Token endpoint (TDD)

**Files:**
- Create: `api/src/handlers/treatment.ts`
- Create: `api/src/handlers/treatment.test.ts`

- [ ] **Step 1: Write the failing test**

Create `api/src/handlers/treatment.test.ts`:

```ts
import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock firebase-admin/auth before importing the handler
vi.mock('firebase-admin/auth', () => ({
  getAuth: vi.fn().mockReturnValue({
    createCustomToken: vi.fn().mockResolvedValue('mock-firebase-token'),
  }),
}));

vi.mock('firebase-admin/app', () => ({
  initializeApp: vi.fn(),
  getApps: vi.fn().mockReturnValue([]),
  cert: vi.fn(),
}));

import { Hono } from 'hono';
import { treatment } from './treatment.js';

function makeApp() {
  const app = new Hono();
  app.route('/api/treatment', treatment);
  return app;
}

describe('GET /api/treatment/token', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns a firebase token and expires_at', async () => {
    const res = await makeApp().request('/api/treatment/token');
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(body.ok).toBe(true);
    expect(body.token).toBe('mock-firebase-token');
    expect(typeof body.expires_at).toBe('number');
    // expires_at should be ~55 minutes in the future
    expect(body.expires_at as number).toBeGreaterThan(Date.now() + 54 * 60 * 1000);
  });

  it('returns 500 when firebase-admin throws', async () => {
    const { getAuth } = await import('firebase-admin/auth');
    vi.mocked(getAuth).mockReturnValue({
      createCustomToken: vi.fn().mockRejectedValue(new Error('iam error')),
    } as ReturnType<typeof getAuth>);

    const res = await makeApp().request('/api/treatment/token');
    expect(res.status).toBe(500);
    const body = await res.json() as Record<string, unknown>;
    expect(body.ok).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to confirm RED**

```bash
cd api && npx vitest run src/handlers/treatment.test.ts 2>&1 | tail -10
```

Expected: `FAIL` — `treatment.js` does not exist yet.

- [ ] **Step 3: Implement the token endpoint**

Create `api/src/handlers/treatment.ts`:

```ts
import { Hono } from 'hono';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

// Init Firebase Admin once (ADC used automatically on Cloud Run)
if (getApps().length === 0) initializeApp();

export const treatment = new Hono()
  .get('/token', async (c) => {
    try {
      const token = await getAuth().createCustomToken('homehd-treatment');
      const expires_at = Date.now() + 55 * 60 * 1000; // 55 min (custom tokens expire at 60)
      return c.json({ ok: true, token, expires_at });
    } catch (err) {
      console.error('Token mint error:', err instanceof Error ? err.message : String(err));
      return c.json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  });
```

- [ ] **Step 4: Run test to confirm GREEN**

```bash
cd api && npx vitest run src/handlers/treatment.test.ts 2>&1 | grep -E "Tests |Test Files"
```

Expected: `Tests  2 passed (2)`

---

### Task 4: Sync-to-sheet endpoint (TDD)

**Files:**
- Modify: `api/src/handlers/treatment.ts`
- Modify: `api/src/handlers/treatment.test.ts`

- [ ] **Step 1: Write the failing tests — add to treatment.test.ts**

Add these mocks at the top of `api/src/handlers/treatment.test.ts`, BEFORE the existing mocks:

```ts
vi.mock('@google-cloud/firestore', () => {
  const mockSession = {
    session_id: '2026-05-31',
    date: '2026-05-31',
    pre_weight: 61.2,
    uf_goal: 2.2,
    uf_rate: 550,
    pre_bp_sys: 135,
    pre_bp_dia: 82,
    pre_pulse: 72,
    created_at: '2026-05-31T18:00:00.000Z',
  };
  const mockReading = {
    reading_id: '2026-05-31-r1',
    session_id: '2026-05-31',
    seq: 1,
    time: '19:15',
    bp_sys: 128,
    bp_dia: 78,
    pulse: 70,
    blood_flow: 350,
    venous_pressure: 150,
    arterial_pressure: -120,
    created_at: '2026-05-31T19:15:00.000Z',
  };
  return {
    Firestore: vi.fn().mockImplementation(() => ({
      collection: vi.fn().mockReturnValue({
        orderBy: vi.fn().mockReturnThis(),
        get: vi.fn().mockResolvedValue({
          docs: [{ data: () => mockSession }, { data: () => mockReading }],
        }),
      }),
    })),
  };
});

const mockSheetsUpdate = vi.fn().mockResolvedValue({ data: {} });
vi.mock('googleapis', () => ({
  google: {
    auth: {
      GoogleAuth: vi.fn().mockImplementation(() => ({
        getClient: vi.fn().mockResolvedValue({}),
      })),
    },
    sheets: vi.fn().mockReturnValue({
      spreadsheets: {
        values: {
          clear: vi.fn().mockResolvedValue({}),
          update: mockSheetsUpdate,
        },
      },
    }),
  },
}));
```

Then add this test block after the token tests:

```ts
describe('POST /api/treatment/sync-to-sheet', () => {
  beforeEach(() => vi.clearAllMocks());

  it('writes sessions and readings to Sheet and returns counts', async () => {
    process.env.TREATMENT_SHEET_ID = 'test-sheet-id';
    const res = await makeApp().request('/api/treatment/sync-to-sheet', { method: 'POST' });
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(body.ok).toBe(true);
    expect(typeof body.sessions_written).toBe('number');
    expect(typeof body.readings_written).toBe('number');
    expect(mockSheetsUpdate).toHaveBeenCalled();
  });

  it('returns 500 when TREATMENT_SHEET_ID is missing', async () => {
    delete process.env.TREATMENT_SHEET_ID;
    const res = await makeApp().request('/api/treatment/sync-to-sheet', { method: 'POST' });
    expect(res.status).toBe(500);
    const body = await res.json() as Record<string, unknown>;
    expect(body.ok).toBe(false);
  });
});
```

- [ ] **Step 2: Run to confirm RED**

```bash
cd api && npx vitest run src/handlers/treatment.test.ts 2>&1 | tail -10
```

Expected: `FAIL` — sync-to-sheet route doesn't exist yet.

- [ ] **Step 3: Implement sync-to-sheet — append to treatment.ts**

Add after the existing token route in `api/src/handlers/treatment.ts`:

```ts
import { Firestore } from '@google-cloud/firestore';
import { google } from 'googleapis';

const SESSION_COLS = [
  'session_id', 'date',
  'pre_weight', 'uf_goal', 'uf_rate', 'pre_bp_sys', 'pre_bp_dia', 'pre_pulse',
  'post_weight', 'post_bp_sys', 'post_bp_dia', 'post_pulse',
  'duration_min', 'dialysate_volume', 'total_uf', 'blood_processed',
  'created_at',
] as const;

const READING_COLS = [
  'reading_id', 'session_id', 'seq', 'time',
  'bp_sys', 'bp_dia', 'pulse', 'blood_flow',
  'venous_pressure', 'arterial_pressure', 'note', 'created_at',
] as const;

function formatDuration(min: number): string {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

type SessionDoc = Record<string, unknown>;
type ReadingDoc = Record<string, unknown>;

function buildLegacyRows(sessions: SessionDoc[], readingsBySession: Map<string, ReadingDoc[]>): unknown[][] {
  const header = [
    'Date', 'Weight', 'UF Goal', 'UF rate', 'Blood Pressure', 'Pulse',
    'Time', 'Blood Pressure', 'Pulse', 'Bloodflow', 'Venous Pressure', 'Arterial Pressure', 'Note',
    'Weight', 'Blood Pressure', 'Pulse', 'Treatment Time', 'Dialysate volume', 'Total UF', 'Blood Processed',
  ];
  const rows: unknown[][] = [header];
  for (const s of sessions) {
    const rs = readingsBySession.get(String(s['session_id'])) ?? [];
    const n = Math.max(rs.length, 1);
    for (let i = 0; i < n; i++) {
      const r: ReadingDoc = rs[i] ?? {};
      const isFirst = i === 0;
      const isLast = i === n - 1;
      const preByp = (isFirst && s['pre_bp_sys'] && s['pre_bp_dia'])
        ? `${s['pre_bp_sys']}/${s['pre_bp_dia']}` : '';
      const rdgBp = (r['bp_sys'] && r['bp_dia'])
        ? `${r['bp_sys']}/${r['bp_dia']}` : '';
      const postBp = (isLast && s['post_bp_sys'] && s['post_bp_dia'])
        ? `${s['post_bp_sys']}/${s['post_bp_dia']}` : '';
      const dur = (isLast && typeof s['duration_min'] === 'number')
        ? formatDuration(s['duration_min']) : '';
      rows.push([
        isLast ? s['date'] : '',
        isFirst ? (s['pre_weight'] ?? '') : '',
        isFirst ? (s['uf_goal'] ?? '') : '',
        isFirst ? (s['uf_rate'] ?? '') : '',
        preByp,
        isFirst ? (s['pre_pulse'] ?? '') : '',
        r['time'] ?? '',
        rdgBp,
        r['pulse'] ?? '',
        r['blood_flow'] ?? '',
        r['venous_pressure'] ?? '',
        r['arterial_pressure'] ?? '',
        r['note'] ?? '',
        isLast ? (s['post_weight'] ?? '') : '',
        postBp,
        isLast ? (s['post_pulse'] ?? '') : '',
        dur,
        isLast ? (s['dialysate_volume'] ?? '') : '',
        isLast ? (s['total_uf'] ?? '') : '',
        isLast ? (s['blood_processed'] ?? '') : '',
      ]);
    }
  }
  return rows;
}
```

Then add the route (still in `treatment.ts`, chained on the `treatment` Hono instance — replace the export line with):

```ts
export const treatment = new Hono()
  .get('/token', async (c) => {
    try {
      const token = await getAuth().createCustomToken('homehd-treatment');
      const expires_at = Date.now() + 55 * 60 * 1000;
      return c.json({ ok: true, token, expires_at });
    } catch (err) {
      console.error('Token mint error:', err instanceof Error ? err.message : String(err));
      return c.json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  })
  .post('/sync-to-sheet', async (c) => {
    const sheetId = process.env.TREATMENT_SHEET_ID;
    if (!sheetId) return c.json({ ok: false, error: 'TREATMENT_SHEET_ID not set' }, 500);
    try {
      const db = new Firestore();

      // Read all sessions ordered by date ascending
      const sessSnap = await db.collection('treatment_sessions').orderBy('date').get();
      const sessions: SessionDoc[] = sessSnap.docs.map(d => d.data());

      // Read all readings (order by session_id, seq)
      const readSnap = await db.collection('treatment_readings').orderBy('session_id').orderBy('seq').get();
      const readings: ReadingDoc[] = readSnap.docs.map(d => d.data());

      // Group readings by session
      const readingsBySession = new Map<string, ReadingDoc[]>();
      for (const r of readings) {
        const sid = String(r['session_id']);
        if (!readingsBySession.has(sid)) readingsBySession.set(sid, []);
        readingsBySession.get(sid)!.push(r);
      }

      // Build rows
      const sessionRows = [SESSION_COLS, ...sessions.map(s => SESSION_COLS.map(c => s[c] ?? ''))];
      const readingRows = [READING_COLS, ...readings.map(r => READING_COLS.map(c => r[c] ?? ''))];
      const legacyRows = buildLegacyRows(sessions, readingsBySession);

      // Write to Sheet via Sheets API v4
      const auth = new google.auth.GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/spreadsheets'],
      });
      const sheets = google.sheets({ version: 'v4', auth: await auth.getClient() as never });

      async function writeTab(tabName: string, values: unknown[][]): Promise<void> {
        await sheets.spreadsheets.values.clear({ spreadsheetId: sheetId, range: tabName });
        await sheets.spreadsheets.values.update({
          spreadsheetId: sheetId,
          range: `${tabName}!A1`,
          valueInputOption: 'RAW',
          requestBody: { values },
        });
      }

      await writeTab('sessions', sessionRows);
      await writeTab('readings', readingRows);
      await writeTab('legacy_view', legacyRows);

      return c.json({
        ok: true,
        sessions_written: sessions.length,
        readings_written: readings.length,
        synced_at: new Date().toISOString(),
      });
    } catch (err) {
      console.error('Sync-to-sheet error:', err instanceof Error ? err.message : String(err));
      return c.json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  });
```

- [ ] **Step 4: Run tests to confirm GREEN**

```bash
cd api && npx vitest run src/handlers/treatment.test.ts 2>&1 | grep -E "Tests |Test Files"
```

Expected: `Tests  4 passed (4)`

- [ ] **Step 5: Typecheck**

```bash
cd api && npx tsc --noEmit 2>&1 | head -20
echo "exit: $?"
```

Expected: `exit: 0`

---

### Task 5: Wire into index.ts + deploy

**Files:**
- Modify: `api/src/index.ts`

- [ ] **Step 1: Add treatment route to index.ts**

In `api/src/index.ts`, add the import and route:

```ts
import { treatment } from './handlers/treatment.js';
```

And after the existing routes (before `app.notFound`):

```ts
app.route('/api/treatment', treatment);
```

- [ ] **Step 2: Run full api test suite to confirm no regressions**

```bash
cd api && npx vitest run 2>&1 | grep -E "Test Files|Tests " | tail -3
```

Expected: all previously passing tests still pass, treatment tests now included.

- [ ] **Step 3: Deploy with TREATMENT_SHEET_ID env var (inherit secrets)**

Replace `SPREADSHEET_ID_HERE` with the ID you recorded in Task 1 Step 4:

```bash
cd api && gcloud run deploy homehd-api \
  --source . --region=europe-west2 --allow-unauthenticated \
  --project=homehd-personal \
  --update-env-vars=TREATMENT_SHEET_ID=SPREADSHEET_ID_HERE \
  --format='value(status.latestReadyRevisionName)' 2>&1 | tail -5
```

Expected: new revision deployed (e.g. `homehd-api-000NN-xxx`).

**IMPORTANT:** Use `--update-env-vars` (not `--set-env-vars`) so existing env vars are merged. Do NOT use `--set-secrets` — it would drop the Health OAuth secrets.

- [ ] **Step 4: Smoke-test token endpoint**

```bash
KEY=$(security find-generic-password -a "$USER" -s "homehd-main-key" -w)
curl -s -H "Authorization: Bearer $KEY" "https://homehd.web.app/api/treatment/token"
```

Expected: `{"ok":true,"token":"eyJ...","expires_at":NNNNN}` (a JWT string starting with `eyJ`)

- [ ] **Step 5: Create Cloud Scheduler job**

Replace `<YOUR_KEY>` with the actual key value from Keychain (same as above):

```bash
KEY=$(security find-generic-password -a "$USER" -s "homehd-main-key" -w)
gcloud scheduler jobs create http treatment-weekly-sheet-sync \
  --location=europe-west2 \
  --schedule="0 8 * * 0" \
  --time-zone="Europe/London" \
  --uri="https://homehd.web.app/api/treatment/sync-to-sheet" \
  --http-method=POST \
  --headers="Authorization=Bearer ${KEY}" \
  --attempt-deadline=120s \
  --description="Weekly Sunday rebuild of Google Sheet from Firestore (clinical team)" \
  --project=homehd-personal 2>&1 | grep -v "Authorization"
```

Expected: job created with `state: ENABLED`.

- [ ] **Step 6: Commit backend changes**

```bash
cd ~/Documents/Personal_Projects/treatment_tracker
git add api/src/handlers/treatment.ts api/src/handlers/treatment.test.ts api/src/index.ts api/package.json api/package-lock.json
git commit -m "$(cat <<'EOF'
feat(api): treatment token endpoint + weekly sync-to-sheet

GET /api/treatment/token mints a Firebase custom token (uid:
homehd-treatment) for client-side Firestore auth. POST
/api/treatment/sync-to-sheet reads Firestore and rebuilds the
sessions/readings/legacy_view Sheet tabs for the clinical team.
Cloud Scheduler job treatment-weekly-sheet-sync fires Sunday 08:00 UTC.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — Backfill

### Task 6: Write and run backfill script

**Files:**
- Create: `api/scripts/backfill-treatment.ts`

- [ ] **Step 1: Create the backfill script**

Create `api/scripts/backfill-treatment.ts`:

```ts
// One-time script: reads all sessions + readings from Apps Script and writes to Firestore.
// Run from api/ directory: npx tsx scripts/backfill-treatment.ts
// Env: HD_URL (Apps Script exec URL), HD_SECRET (shared secret)

import { Firestore } from '@google-cloud/firestore';

const HD_URL = process.env.HD_URL;
const HD_SECRET = process.env.HD_SECRET;

if (!HD_URL || !HD_SECRET) {
  console.error('Missing HD_URL or HD_SECRET env vars');
  process.exit(1);
}

interface Session { session_id: string; date: string; [k: string]: unknown }
interface Reading { reading_id: string; session_id: string; seq: number; [k: string]: unknown }

async function fetchFromAppsScript(): Promise<{ sessions: Session[]; readings: Reading[] }> {
  const url = `${HD_URL}?secret=${encodeURIComponent(HD_SECRET)}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Apps Script GET failed: ${res.status}`);
  const body = await res.json() as { ok: boolean; sessions?: Session[]; readings?: Reading[] };
  if (!body.ok) throw new Error(`Apps Script error: ${JSON.stringify(body)}`);
  return { sessions: body.sessions ?? [], readings: body.readings ?? [] };
}

async function batchWrite(
  db: Firestore,
  collectionName: string,
  docs: Array<{ id: string; data: Record<string, unknown> }>,
  skipExisting: boolean,
): Promise<{ written: number; skipped: number }> {
  let written = 0;
  let skipped = 0;
  const chunks: typeof docs[] = [];
  for (let i = 0; i < docs.length; i += 490) chunks.push(docs.slice(i, i + 490));

  for (const chunk of chunks) {
    const batch = db.batch();
    for (const { id, data } of chunk) {
      const ref = db.collection(collectionName).doc(id);
      if (skipExisting) {
        const snap = await ref.get();
        if (snap.exists) { skipped++; continue; }
      }
      // Convert string numbers to actual numbers
      const coerced: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(data)) {
        if (v === '' || v === null || v === undefined) continue;
        const n = typeof v === 'string' ? Number(v) : NaN;
        coerced[k] = !isNaN(n) && k !== 'session_id' && k !== 'reading_id' && k !== 'date'
          && k !== 'time' && k !== 'note' && k !== 'created_at' ? n : v;
      }
      batch.set(ref, coerced);
      written++;
    }
    await batch.commit();
  }
  return { written, skipped };
}

async function main() {
  console.log('Fetching from Apps Script...');
  const { sessions, readings } = await fetchFromAppsScript();
  console.log(`  Sessions: ${sessions.length}, Readings: ${readings.length}`);

  const db = new Firestore();
  const skipExisting = !process.argv.includes('--overwrite');
  console.log(`Writing to Firestore (skipExisting=${skipExisting})...`);

  const sr = await batchWrite(db, 'treatment_sessions',
    sessions.map(s => ({ id: s.session_id, data: s as Record<string, unknown> })),
    skipExisting);
  console.log(`  Sessions: ${sr.written} written, ${sr.skipped} skipped`);

  const rr = await batchWrite(db, 'treatment_readings',
    readings.map(r => ({ id: r.reading_id, data: r as Record<string, unknown> })),
    skipExisting);
  console.log(`  Readings: ${rr.written} written, ${rr.skipped} skipped`);

  console.log('Done.');
}

main().catch(e => { console.error(e); process.exit(1); });
```

- [ ] **Step 2: Run the backfill**

```bash
cd ~/Documents/Personal_Projects/treatment_tracker/api
HD_URL=$(security find-generic-password -a "$USER" -s "hd-tracker-url" -w 2>/dev/null || echo "PASTE_URL_HERE")
HD_SECRET=$(security find-generic-password -a "$USER" -s "hd-tracker-secret" -w)
HD_URL="$HD_URL" HD_SECRET="$HD_SECRET" npx tsx scripts/backfill-treatment.ts
```

If `hd-tracker-url` is not in Keychain, set `HD_URL` manually to the Apps Script `/exec` URL from the vault note (`AKfycbxJUgV...exec`).

Expected output:
```
Fetching from Apps Script...
  Sessions: N, Readings: M
Writing to Firestore (skipExisting=true)...
  Sessions: N written, 0 skipped
  Readings: M written, 0 skipped
Done.
```

- [ ] **Step 3: Verify counts in Firestore**

```bash
cd api && node -e "
import('@google-cloud/firestore').then(async ({ Firestore }) => {
  const db = new Firestore();
  const [s, r] = await Promise.all([
    db.collection('treatment_sessions').count().get(),
    db.collection('treatment_readings').count().get(),
  ]);
  console.log('sessions:', s.data().count, 'readings:', r.data().count);
});
"
```

Confirm counts match what the Apps Script returned.

- [ ] **Step 4: Commit backfill script**

```bash
cd ~/Documents/Personal_Projects/treatment_tracker
git add api/scripts/backfill-treatment.ts
git commit -m "$(cat <<'EOF'
chore: one-time backfill script for Treatment Sheet → Firestore

Reads sessions + readings from Apps Script GET, coerces string numbers to
actual numbers, batch-writes to treatment_sessions + treatment_readings.
Safe to re-run (skips existing docs by default).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — Frontend

### Task 7: Install Firebase SDK + create firebaseClient.ts

**Files:**
- Modify: `frontend/package.json`
- Create: `frontend/src/lib/firebaseClient.ts`

- [ ] **Step 1: Install Firebase JS SDK**

```bash
cd ~/Documents/Personal_Projects/treatment_tracker/frontend && npm install firebase
```

- [ ] **Step 2: Get Firebase web config from CLI**

```bash
firebase apps:sdkconfig web --project homehd-personal 2>/dev/null | grep -A20 "firebaseConfig"
```

If that doesn't work:
```bash
firebase apps:list --project homehd-personal
# Note the App ID for your web app, then:
firebase apps:sdkconfig web APP_ID_HERE --project homehd-personal
```

Copy the `apiKey`, `authDomain`, `projectId`, `storageBucket`, `messagingSenderId`, `appId` values.

- [ ] **Step 3: Create frontend/src/lib/firebaseClient.ts**

Replace the placeholder values with the real ones from Step 2:

```ts
import { getApps, initializeApp } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
import { getAuth } from 'firebase/auth';

// These are public values (Firebase web config is not secret).
// Retrieved from: firebase apps:sdkconfig web --project homehd-personal
const firebaseConfig = {
  apiKey: 'REPLACE_WITH_REAL_API_KEY',
  authDomain: 'homehd-personal.firebaseapp.com',
  projectId: 'homehd-personal',
  storageBucket: 'homehd-personal.firebasestorage.app',
  messagingSenderId: 'REPLACE_WITH_REAL_SENDER_ID',
  appId: 'REPLACE_WITH_REAL_APP_ID',
};

const app = getApps().length ? getApps()[0] : initializeApp(firebaseConfig);
export const db = getFirestore(app);
export const firebaseAuth = getAuth(app);
```

- [ ] **Step 4: Typecheck**

```bash
cd frontend && npx tsc -b --noEmit 2>&1 | head -10; echo "exit: $?"
```

Expected: `exit: 0`

---

### Task 8: Update Firestore security rules

**Files:**
- Create: `firestore.rules` (at repo root)

- [ ] **Step 1: Check current rules in Firebase console**

```bash
firebase firestore:rules:get --project homehd-personal 2>/dev/null | head -30
```

Note the existing rules (which cover `blood_tests`, `inventory_*` etc.) — you need to ADD the treatment rules without removing existing ones.

- [ ] **Step 2: Create firestore.rules at repo root**

Create `firestore.rules` (adjust existing rules if the command in Step 1 shows different ones):

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Treatment data — only the Firebase custom token user can read/write
    match /treatment_sessions/{id} {
      allow read, write: if request.auth != null
                         && request.auth.uid == 'homehd-treatment';
    }
    match /treatment_readings/{id} {
      allow read, write: if request.auth != null
                         && request.auth.uid == 'homehd-treatment';
    }

    // All other collections: deny by default (server-side Cloud Run SA bypasses rules)
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

- [ ] **Step 3: Deploy rules**

```bash
cd ~/Documents/Personal_Projects/treatment_tracker
firebase deploy --only firestore:rules --project homehd-personal 2>&1 | tail -5
```

Expected: `✔  Deploy complete!`

---

### Task 9: Replace Treatment/api.ts (TDD)

**Files:**
- Create: `frontend/src/routes/Treatment/api.test.ts`
- Replace: `frontend/src/routes/Treatment/api.ts`

- [ ] **Step 1: Write failing tests**

Create `frontend/src/routes/Treatment/api.test.ts`:

```ts
import { describe, it, expect, vi, beforeEach } from 'vitest';

const mockSetDoc = vi.fn().mockResolvedValue(undefined);
const mockUpdateDoc = vi.fn().mockResolvedValue(undefined);
const mockGetDocs = vi.fn();
const mockDoc = vi.fn((_db: unknown, path: string, id: string) => ({ _path: `${path}/${id}` }));
const mockCollection = vi.fn((_db: unknown, path: string) => ({ _path: path }));

vi.mock('firebase/firestore', () => ({
  setDoc: mockSetDoc,
  updateDoc: mockUpdateDoc,
  getDocs: mockGetDocs,
  doc: mockDoc,
  collection: mockCollection,
}));

vi.mock('../../../lib/firebaseClient', () => ({ db: { _mock: true } }));

import { saveSession, saveReading, updateSession, getAll, ApiError } from './api';
import type { Session, Reading } from './schemas';

const session: Session = {
  session_id: '2026-05-31',
  date: '2026-05-31',
  pre_weight: 61.2,
  pre_bp_sys: 135,
  pre_bp_dia: 82,
  pre_pulse: 72,
  created_at: '2026-05-31T18:00:00.000Z',
};

const reading: Reading = {
  reading_id: '2026-05-31-r1',
  session_id: '2026-05-31',
  seq: 1,
  time: '19:15',
  bp_sys: 128,
  bp_dia: 78,
};

beforeEach(() => vi.clearAllMocks());

describe('saveSession', () => {
  it('calls setDoc on treatment_sessions/{session_id}', async () => {
    await saveSession(session);
    expect(mockSetDoc).toHaveBeenCalledWith(
      expect.objectContaining({ _path: 'treatment_sessions/2026-05-31' }),
      session,
    );
  });

  it('stores numeric fields as numbers (not strings)', async () => {
    await saveSession(session);
    const written = mockSetDoc.mock.calls[0][1] as Session;
    expect(typeof written.pre_weight).toBe('number');
    expect(typeof written.pre_bp_sys).toBe('number');
  });

  it('throws ApiError on Firestore error', async () => {
    mockSetDoc.mockRejectedValueOnce(new Error('network'));
    await expect(saveSession(session)).rejects.toThrow(ApiError);
  });
});

describe('saveReading', () => {
  it('calls setDoc on treatment_readings/{reading_id}', async () => {
    await saveReading(reading);
    expect(mockSetDoc).toHaveBeenCalledWith(
      expect.objectContaining({ _path: 'treatment_readings/2026-05-31-r1' }),
      reading,
    );
  });
});

describe('updateSession', () => {
  it('calls updateDoc with only the patched fields (not session_id)', async () => {
    await updateSession({ session_id: '2026-05-31', post_weight: 59.0, post_bp_sys: 122 });
    expect(mockUpdateDoc).toHaveBeenCalledWith(
      expect.objectContaining({ _path: 'treatment_sessions/2026-05-31' }),
      { post_weight: 59.0, post_bp_sys: 122 },
    );
  });
});

describe('getAll', () => {
  it('returns sessions and readings from both collections', async () => {
    mockGetDocs
      .mockResolvedValueOnce({ docs: [{ data: () => session }] })
      .mockResolvedValueOnce({ docs: [{ data: () => reading }] });

    const result = await getAll();
    expect(result.ok).toBe(true);
    expect(result.sessions).toHaveLength(1);
    expect(result.readings).toHaveLength(1);
    expect(result.sessions[0].session_id).toBe('2026-05-31');
    expect(result.readings[0].reading_id).toBe('2026-05-31-r1');
  });

  it('throws ApiError with code "unauthorized" on permission-denied', async () => {
    mockGetDocs.mockRejectedValueOnce(new Error('Missing or insufficient permissions'));
    await expect(getAll()).rejects.toThrow(expect.objectContaining({ code: 'unauthorized' }));
  });
});
```

- [ ] **Step 2: Run to confirm RED**

```bash
cd frontend && npx vitest run src/routes/Treatment/api.test.ts 2>&1 | tail -10
```

Expected: `FAIL` — module not found or wrong exports.

- [ ] **Step 3: Replace Treatment/api.ts with Firestore implementation**

Overwrite `frontend/src/routes/Treatment/api.ts` entirely:

```ts
import { collection, doc, getDocs, setDoc, updateDoc } from 'firebase/firestore';
import { db } from '../../../lib/firebaseClient';
import type { GetResponse, Reading, Session } from './schemas';

export class ApiError extends Error {
  constructor(public code: string, message?: string) {
    super(message ?? code);
    this.name = 'ApiError';
  }
}

function wrapError(e: unknown): never {
  const msg = e instanceof Error ? e.message : String(e);
  const code = msg.toLowerCase().includes('permission') ? 'unauthorized' : 'network_error';
  throw new ApiError(code, msg);
}

export async function saveSession(session: Session): Promise<void> {
  try {
    await setDoc(doc(db, 'treatment_sessions', session.session_id), session);
  } catch (e) { wrapError(e); }
}

export async function saveReading(reading: Reading): Promise<void> {
  try {
    await setDoc(doc(db, 'treatment_readings', reading.reading_id), reading);
  } catch (e) { wrapError(e); }
}

export async function updateSession(
  patch: Partial<Session> & { session_id: string },
): Promise<void> {
  const { session_id, ...rest } = patch;
  try {
    await updateDoc(doc(db, 'treatment_sessions', session_id), rest);
  } catch (e) { wrapError(e); }
}

export async function getAll(): Promise<GetResponse> {
  try {
    const [sessSnap, readSnap] = await Promise.all([
      getDocs(collection(db, 'treatment_sessions')),
      getDocs(collection(db, 'treatment_readings')),
    ]);
    return {
      ok: true,
      sessions: sessSnap.docs.map(d => d.data() as Session),
      readings: readSnap.docs.map(d => d.data() as Reading),
    };
  } catch (e) { wrapError(e); }
}
```

- [ ] **Step 4: Run tests to confirm GREEN**

```bash
cd frontend && npx vitest run src/routes/Treatment/api.test.ts 2>&1 | grep -E "Tests |Test Files"
```

Expected: `Tests  7 passed (7)`

---

### Task 10: Update schemas.ts

**Files:**
- Modify: `frontend/src/routes/Treatment/schemas.ts`

- [ ] **Step 1: Remove Settings type and update coerce**

In `frontend/src/routes/Treatment/schemas.ts`:

1. Delete the `Settings` schema and type at the bottom of the file (remove these lines):
```ts
export const Settings = z.object({
  script_url: z.string().url(),
  shared_secret: z.string().min(1),
});
export type Settings = z.infer<typeof Settings>;
```

2. Replace all `z.coerce.number()` with `z.number()` (Firestore stores real numbers):
```bash
cd frontend && sed -i '' 's/z\.coerce\.number()/z.number()/g' src/routes/Treatment/schemas.ts
```

3. Verify the file:
```bash
grep -n "coerce\|Settings" frontend/src/routes/Treatment/schemas.ts
```

Expected: no output (both removed).

- [ ] **Step 2: Typecheck**

```bash
cd frontend && npx tsc -b --noEmit 2>&1 | head -20; echo "exit: $?"
```

Expected errors about `Settings` being missing in imports — that's expected. Fix them in the next tasks.

---

### Task 11: Update auth/storage.ts

**Files:**
- Modify: `frontend/src/auth/storage.ts`

- [ ] **Step 1: Update AuthSettings interface**

In `frontend/src/auth/storage.ts`, replace the `AuthSettings` interface:

```ts
export interface AuthSettings {
  mainKey: string;
  treatmentToken?: string;
  treatmentTokenExpiresAt?: number;
}
```

The `appsScriptUrl` and `appsScriptSecret` fields are removed. Existing IndexedDB entries with those fields will load fine — TypeScript ignores extra fields on read.

- [ ] **Step 2: Typecheck**

```bash
cd frontend && npx tsc -b --noEmit 2>&1 | head -30; echo "exit: $?"
```

Note the remaining errors (in SetupWizard + Treatment screens) — you'll fix them in subsequent tasks.

---

### Task 12: Update SetupWizard.tsx

**Files:**
- Replace: `frontend/src/auth/SetupWizard.tsx`

- [ ] **Step 1: Replace SetupWizard.tsx**

Overwrite `frontend/src/auth/SetupWizard.tsx` entirely:

```tsx
import { useState } from 'react';
import { Activity, KeyRound, Save } from 'lucide-react';
import { saveAuth } from './storage';
import type { AuthSettings } from './storage';
import { signInWithCustomToken } from 'firebase/auth';
import { firebaseAuth } from '../lib/firebaseClient';

interface Props {
  onSaved: () => void;
  message?: string;
}

export function SetupWizard({ onSaved, message }: Props) {
  const [mainKey, setMainKey] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setError(null);
    if (!mainKey.trim()) { setError('Main API key must not be empty.'); return; }

    setBusy(true);
    try {
      // 1. Verify mainKey works against /api/health
      const healthRes = await fetch('/api/health', {
        headers: { Authorization: `Bearer ${mainKey.trim()}` },
      });
      if (healthRes.status === 401) throw new Error('Main API key rejected — check the value and try again.');
      if (!healthRes.ok) throw new Error(`API health check failed (${healthRes.status}). Is the API running?`);

      // 2. Fetch Firebase custom token
      const tokenRes = await fetch('/api/treatment/token', {
        headers: { Authorization: `Bearer ${mainKey.trim()}` },
      });
      if (tokenRes.status === 401) throw new Error('Main API key rejected by treatment endpoint.');
      if (!tokenRes.ok) throw new Error(`Failed to fetch treatment token (${tokenRes.status}).`);
      const { token, expires_at } = await tokenRes.json() as { token: string; expires_at: number };

      // 3. Sign into Firebase
      await signInWithCustomToken(firebaseAuth, token);

      // 4. Save auth to IndexedDB
      const settings: AuthSettings = {
        mainKey: mainKey.trim(),
        treatmentToken: token,
        treatmentTokenExpiresAt: expires_at,
      };
      await saveAuth(settings);
      onSaved();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      <h1 className="text-2xl font-bold inline-flex items-center gap-2">
        <Activity size={22} className="text-accent" /> Setup
      </h1>
      {message && (
        <div className="bg-amber-900/40 border border-amber-700 text-amber-200 rounded-lg px-3 py-2 text-sm">
          {message}
        </div>
      )}
      <p className="text-sm text-slate-400">Enter your API key. It is stored on this device only.</p>

      <label className="block">
        <span className="text-sm text-slate-400 mb-1 inline-flex items-center gap-1.5">
          <KeyRound size={14} /> Main API key
        </span>
        <input
          type="password"
          value={mainKey}
          onChange={e => setMainKey(e.target.value)}
          placeholder="long-random-string"
          autoComplete="off"
          className="w-full bg-panel border border-slate-700 rounded-lg px-3 py-2 text-sm focus:border-accent focus:outline-none"
        />
      </label>

      <button
        type="button"
        onClick={submit}
        disabled={busy}
        className="w-full bg-accent text-bg font-semibold rounded-lg py-3 disabled:opacity-50 inline-flex items-center justify-center gap-2"
      >
        <Save size={18} /> {busy ? 'Verifying…' : 'Save and continue'}
      </button>

      {error && (
        <div className="bg-red-900/40 border border-red-700 text-red-200 rounded-lg px-3 py-2 text-sm">
          {error}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Typecheck**

```bash
cd frontend && npx tsc -b --noEmit 2>&1 | head -30; echo "exit: $?"
```

---

### Task 13: Update Treatment/index.tsx

**Files:**
- Modify: `frontend/src/routes/Treatment/index.tsx`

- [ ] **Step 1: Replace Treatment/index.tsx**

Overwrite `frontend/src/routes/Treatment/index.tsx` entirely:

```tsx
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { signInWithCustomToken } from 'firebase/auth';
import { getAuth, saveAuth, type AuthSettings } from '../../auth/storage';
import { firebaseAuth } from '../../lib/firebaseClient';
import { cloudGet } from '../../api/cloudRun';
import {
  clearActiveState,
  getActiveState,
  saveActiveState,
} from './storage';
import type { SessionConsumed } from './storage';
import type { PendingReading, Session } from './schemas';
import { Home } from './screens/Home';
import { PreTreatment } from './screens/PreTreatment';
import { ActiveSession } from './screens/ActiveSession';
import { PostTreatment } from './screens/PostTreatment';

type Screen =
  | { name: 'loading' }
  | { name: 'home' }
  | { name: 'pre'; existingIds: string[] }
  | { name: 'active'; session: Session; readings: PendingReading[]; heparinUsed: boolean; countdownStartedAt?: number; targetMin?: number }
  | { name: 'post'; session: Session; consumed: SessionConsumed };

interface TokenResponse { token: string; expires_at: number }

async function ensureFirebaseAuth(auth: AuthSettings): Promise<AuthSettings> {
  const now = Date.now();
  const needsRefresh = !auth.treatmentToken
    || !auth.treatmentTokenExpiresAt
    || auth.treatmentTokenExpiresAt - now < 10 * 60 * 1000;

  if (needsRefresh) {
    const { token, expires_at } = await cloudGet<TokenResponse>(auth, '/api/treatment/token');
    const updated = { ...auth, treatmentToken: token, treatmentTokenExpiresAt: expires_at };
    await saveAuth(updated);
    auth = updated;
  }
  await signInWithCustomToken(firebaseAuth, auth.treatmentToken!);
  return auth;
}

export default function Treatment() {
  const navigate = useNavigate();
  const [screen, setScreen] = useState<Screen>({ name: 'loading' });
  const [auth, setAuth] = useState<AuthSettings | null>(null);

  useEffect(() => {
    let cancelled = false;
    getAuth().then(async (a) => {
      if (!a) { navigate('/setup', { replace: true }); return; }

      let currentAuth = a;
      try {
        currentAuth = await ensureFirebaseAuth(a);
      } catch (e) {
        // Token refresh failed — Firebase session may still be valid for up to 1h
        console.warn('Firebase token refresh failed:', e);
      }

      if (cancelled) return;
      setAuth(currentAuth);

      const active = getActiveState();
      if (active?.screen === 'pre' && active.existingIds) {
        setScreen({ name: 'pre', existingIds: active.existingIds });
      } else if (active?.screen === 'active' && active.session) {
        const readings = (active.readings ?? []).map(r =>
          r.status === 'pending' ? { ...r, status: 'error' as const, errorMsg: 'interrupted' } : r
        );
        setScreen({ name: 'active', session: active.session, readings, heparinUsed: active.heparinUsed ?? false, countdownStartedAt: active.countdownStartedAt, targetMin: active.targetMin });
      } else if (active?.screen === 'post' && active.session) {
        const consumed: SessionConsumed = active.consumed ?? { needles: 2, onOffPacks: 1, heparinUsed: false };
        setScreen({ name: 'post', session: active.session, consumed });
      } else {
        setScreen({ name: 'home' });
      }
    }).catch(() => { if (!cancelled) navigate('/setup', { replace: true }); });
    return () => { cancelled = true; };
  }, [navigate]);

  useEffect(() => {
    if (screen.name === 'pre') {
      saveActiveState({ screen: 'pre', existingIds: screen.existingIds });
    } else if (screen.name === 'active') {
      saveActiveState({ screen: 'active', session: screen.session, readings: screen.readings, heparinUsed: screen.heparinUsed, countdownStartedAt: screen.countdownStartedAt, targetMin: screen.targetMin });
    } else if (screen.name === 'post') {
      saveActiveState({ screen: 'post', session: screen.session, consumed: screen.consumed });
    } else if (screen.name === 'home') {
      clearActiveState();
    }
  }, [screen]);

  if (screen.name === 'loading') {
    return <div className="p-4 text-slate-400">Loading…</div>;
  }

  if (screen.name === 'home') {
    return (
      <Home
        onStartSession={existingIds => setScreen({ name: 'pre', existingIds })}
      />
    );
  }
  if (screen.name === 'pre') {
    return (
      <PreTreatment
        auth={auth}
        existingIds={screen.existingIds}
        onSaved={(session, heparinUsed) =>
          setScreen({ name: 'active', session, readings: [], heparinUsed })
        }
        onCancel={() => setScreen({ name: 'home' })}
      />
    );
  }
  if (screen.name === 'active') {
    return (
      <ActiveSession
        session={screen.session}
        initialReadings={screen.readings}
        initialCountdownStartedAt={screen.countdownStartedAt}
        initialTargetMin={screen.targetMin}
        onReadingsChange={rs =>
          setScreen(s => (s.name === 'active' ? { ...s, readings: rs } : s))
        }
        onCountdownChange={(startedAt, targetMin) =>
          setScreen(s => s.name === 'active' ? { ...s, countdownStartedAt: startedAt ?? undefined, targetMin } : s)
        }
        onEnd={consumed =>
          setScreen({ name: 'post', session: screen.session, consumed: { ...consumed, heparinUsed: screen.heparinUsed } })
        }
      />
    );
  }
  if (screen.name === 'post') {
    return (
      <PostTreatment
        auth={auth}
        session={screen.session}
        consumed={screen.consumed}
        onSaved={() => setScreen({ name: 'home' })}
      />
    );
  }

  const _exhaustive: never = screen;
  return _exhaustive;
}
```

- [ ] **Step 2: Typecheck**

```bash
cd frontend && npx tsc -b --noEmit 2>&1 | head -30; echo "exit: $?"
```

Expected: errors in the screen files (Settings prop still referenced). Fix those in Task 14.

---

### Task 14: Update screen Props (remove settings)

**Files:**
- Modify: `frontend/src/routes/Treatment/screens/Home.tsx`
- Modify: `frontend/src/routes/Treatment/screens/PreTreatment.tsx`
- Modify: `frontend/src/routes/Treatment/screens/ActiveSession.tsx`
- Modify: `frontend/src/routes/Treatment/screens/PostTreatment.tsx`

- [ ] **Step 1: Update Home.tsx**

In `frontend/src/routes/Treatment/screens/Home.tsx`:

1. Remove `import type { Session, Settings } from '../schemas';` — replace with:
```ts
import type { Session } from '../schemas';
```

2. Change the `Props` interface — remove `settings`:
```ts
interface Props {
  onStartSession: (existingIds: string[]) => void;
}
```

3. Change the function signature:
```ts
export function Home({ onStartSession }: Props) {
```

4. Change the `load()` call — remove `settings` argument:
```ts
const r = await getAll();
```

- [ ] **Step 2: Update PreTreatment.tsx**

In `frontend/src/routes/Treatment/screens/PreTreatment.tsx`:

1. Remove `import type { Session, Settings } from '../schemas';` — replace with:
```ts
import type { Session } from '../schemas';
```

2. Change `Props`:
```ts
interface Props {
  auth: AuthSettings | null;
  existingIds: string[];
  onSaved: (session: Session, heparinUsed: boolean) => void;
  onCancel: () => void;
}
```

3. Change function signature:
```ts
export function PreTreatment({ auth, existingIds, onSaved, onCancel }: Props) {
```

4. Change `saveSession` call — remove `settings`:
```ts
await saveSession(session);
```

- [ ] **Step 3: Update ActiveSession.tsx**

In `frontend/src/routes/Treatment/screens/ActiveSession.tsx`:

1. Remove `Settings` from the schemas import.

2. Remove `settings: Settings;` from the Props interface.

3. Remove `settings,` from the destructured props.

4. Change both `saveReading` calls — remove `settings`:
```ts
await saveReading(settings, reading);   // → await saveReading(reading);
await saveReading(settings, wire);      // → await saveReading(wire);
```

- [ ] **Step 4: Update PostTreatment.tsx**

In `frontend/src/routes/Treatment/screens/PostTreatment.tsx`:

1. Remove `Settings` from the schemas import.

2. Remove `settings: Settings;` from the Props interface.

3. Remove `settings,` from the destructured props.

4. Change `updateSession` call — remove `settings`:
```ts
await updateSession(settings, {     // → await updateSession({
  session_id: sessionId,
  ...form,
  total_uf: effectiveTotalUf,
});
```

- [ ] **Step 5: Typecheck — should be clean**

```bash
cd frontend && npx tsc -b --noEmit 2>&1 | head -20; echo "exit: $?"
```

Expected: `exit: 0`

- [ ] **Step 6: Run full frontend test suite**

```bash
cd frontend && npx vitest run 2>&1 | grep -E "Test Files|Tests " | tail -3
```

Expected: all 96 existing tests pass + 7 new api.test.ts tests.

---

### Task 15: Build + deploy frontend

**Files:** none (deploy)

- [ ] **Step 1: Build**

```bash
cd frontend && npm run build 2>&1 | tail -10
```

Expected: `✓ built in N.NNs` with no type errors.

- [ ] **Step 2: Deploy to Firebase Hosting**

```bash
cd ~/Documents/Personal_Projects/treatment_tracker
firebase deploy --only hosting --project homehd-personal 2>&1 | tail -8
```

Expected: `✔  Deploy complete!`

- [ ] **Step 3: On-device smoke test**

On your Android device, open `homehd.web.app`. If the PWA was already installed:
- The service worker will update on next page focus (or force: Settings → Clear site data → reinstall)
- Go through Setup (enter just mainKey — the Apps Script fields are gone)
- Navigate to Treatment → verify sessions load from Firestore
- Start a new session: Pre → Active (add one reading) → Post
- Verify the session appears in Home list

- [ ] **Step 4: Commit all frontend changes**

```bash
cd ~/Documents/Personal_Projects/treatment_tracker
git add \
  frontend/package.json frontend/package-lock.json \
  frontend/src/lib/firebaseClient.ts \
  frontend/src/routes/Treatment/api.ts \
  frontend/src/routes/Treatment/api.test.ts \
  frontend/src/routes/Treatment/schemas.ts \
  frontend/src/auth/storage.ts \
  frontend/src/auth/SetupWizard.tsx \
  frontend/src/routes/Treatment/index.tsx \
  frontend/src/routes/Treatment/screens/Home.tsx \
  frontend/src/routes/Treatment/screens/PreTreatment.tsx \
  frontend/src/routes/Treatment/screens/ActiveSession.tsx \
  frontend/src/routes/Treatment/screens/PostTreatment.tsx \
  firestore.rules

git commit -m "$(cat <<'EOF'
feat(treatment): migrate to Firestore client SDK (Approach A)

Replaces Apps Script + Google Sheet writes with client-side Firestore SDK,
eliminating Cloud Run cold-start risk during dialysis sessions. Auth via
Firebase custom token (GET /api/treatment/token exchanged for mainKey).
SetupWizard simplified to a single mainKey field. Numbers stored as real
numbers, not strings. security rules: treatment_sessions + treatment_readings
locked to uid homehd-treatment.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5 — Verify + tidy

### Task 16: Verify sync-to-sheet + update vault note

**Files:** vault note

- [ ] **Step 1: Manually trigger sync-to-sheet**

```bash
KEY=$(security find-generic-password -a "$USER" -s "homehd-main-key" -w)
curl -s -X POST -H "Authorization: Bearer $KEY" \
  "https://homehd.web.app/api/treatment/sync-to-sheet" | python3 -m json.tool
```

Expected: `{"ok":true,"sessions_written":N,"readings_written":M,"synced_at":"..."}`

- [ ] **Step 2: Verify Sheet tabs**

Open the Google Sheet. Confirm:
- `sessions` tab has the correct columns + all backfilled sessions
- `readings` tab has all readings
- `legacy_view` tab has the pre/during/post layout the clinical team knows

- [ ] **Step 3: Update vault note**

Add a `### 2026-06-01 — Treatment migrated to Firestore` entry in the Update Log section of `Home HD Knowledge Base and Tracking System.md`. Include:
- Firestore as primary (two collections: `treatment_sessions`, `treatment_readings`)
- Apps Script dormant but not decommissioned
- Weekly Sunday sync-to-sheet via Cloud Scheduler
- Token auth: `GET /api/treatment/token` → `signInWithCustomToken`
- Backfill: N sessions + M readings imported
- `MAIN_API_KEY` rotation still pending

- [ ] **Step 4: Final commit**

```bash
cd ~/Documents/Personal_Projects/treatment_tracker
git add "/Users/ntg/Documents/Obsidian Notes/Work/Project_ideas/Home HD Knowledge Base and Tracking System.md"
git commit -m "$(cat <<'EOF'
docs: update vault note for Treatment Firestore migration

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Cutover verification checklist

- [ ] Firestore `treatment_sessions` doc count == Sheet `sessions` row count (minus header)
- [ ] Firestore `treatment_readings` doc count == Sheet `readings` row count (minus header)
- [ ] Token endpoint returns a valid JWT (`eyJ...`)
- [ ] New session written to Firestore appears in Home list on next load
- [ ] `POST /api/treatment/sync-to-sheet` writes all three tabs correctly
- [ ] Apps Script left deployed (dormant) — do NOT decommission for 2+ weeks
- [ ] Cloud Scheduler job `treatment-weekly-sheet-sync` shows `ENABLED`
- [ ] `MAIN_API_KEY` rotation still pending (separate task — see vault note)
