# Treatment: Firestore migration + weekly Sheet sync

Combined spec + implementation plan. Migrates Treatment session/reading writes from
Apps Script + Google Sheet (primary) to Firestore (primary), with a weekly Cloud Scheduler
job that rebuilds the Sheet for the clinical team. Approved in design session 2026-06-01.

## Goal

Move Treatment data to Firestore so it is:
- **Reliable during dialysis** — client-side Firestore SDK bypasses Cloud Run entirely,
  eliminating the cold-start risk that blocked this migration previously
- **Properly typed** — numerics stored as numbers, not strings; no `appendAsText_` hack
- **Queryable** — Firestore collections vs Sheet rows; enables future analytics
- **Maintainable** — no Apps Script quirks (date coercion, HTTP-status inertness, `||=` parser
  issues, CORS `text/plain` workaround)

Clinical team constraint: Google Sheet remains populated, refreshed every Sunday morning via
Cloud Scheduler → Cloud Run → Sheets API. No change to how they access their data.

## What changes / what stays the same

**Changes:**
- Treatment reads + writes go through Firestore client SDK (not Apps Script)
- `AuthSettings` drops `appsScriptUrl` + `appsScriptSecret`; adds `treatmentToken?` +
  `treatmentTokenExpiresAt?`
- Setup Wizard loses the two Apps Script input fields
- `Treatment/api.ts` replaced entirely (same function signatures, new implementation)
- New backend handler `api/src/handlers/treatment.ts` (token endpoint + sync-to-sheet)
- Cloud Scheduler job `treatment-weekly-sheet-sync` (Sunday 08:00 UTC)
- One-time backfill script `scripts/backfill-treatment.ts`

**Unchanged:**
- All Treatment UI screens (Pre, Active, Post, Home) — zero UX changes
- `session_id` / `reading_id` format and all field names
- `Treatment/storage.ts` (active-state localStorage, last-session IDB cache, dried-weight)
- `Treatment/schemas.ts` structure (minor: `z.coerce.number()` becomes `z.number()` on reads)
- `mainKey` as the single credential the user manages
- Google Sheet file (stays; clinical team keeps reading it)
- Apps Script (stays deployed but dormant after cutover)

## Architecture

```
BEFORE:
PWA ──(text/plain POST)──▶ Apps Script /exec ──▶ Google Sheet (primary)
PWA ──(GET)──────────────▶ Apps Script /exec ──▶ reads from Sheet

AFTER:
PWA ──(Firestore SDK)────▶ Firestore (primary)   ← reads + writes, no cold-start
Cloud Scheduler (Sun 08:00 UTC)
  ──▶ POST /api/treatment/sync-to-sheet
       ──▶ Cloud Run reads Firestore
            ──▶ Sheets API writes sessions/readings/legacy_view tabs
```

## Firestore data model

Two collections, document IDs match the existing primary keys:

```
treatment_sessions/{session_id}
  session_id       string   (e.g. "2026-05-31")
  date             string   YYYY-MM-DD
  pre_weight       number?
  uf_goal          number?
  uf_rate          number?
  pre_bp_sys       number?  (int)
  pre_bp_dia       number?  (int)
  pre_pulse        number?  (int)
  post_weight      number?
  post_bp_sys      number?  (int)
  post_bp_dia      number?  (int)
  post_pulse       number?  (int)
  duration_min     number?  (int)
  dialysate_volume number?
  total_uf         number?
  blood_processed  number?
  created_at       string   ISO timestamp

treatment_readings/{reading_id}
  reading_id       string   (e.g. "2026-05-31-r1")
  session_id       string
  seq              number   (int)
  time             string   HH:MM
  bp_sys           number?  (int)
  bp_dia           number?  (int)
  pulse            number?  (int)
  blood_flow       number?  (int)
  venous_pressure  number?  (int)
  arterial_pressure number?  (int)
  note             string?
  created_at       string   ISO timestamp
```

All numerics stored as **numbers** (not strings) — main correctness win over the Sheet backend.

**Firestore security rules:**
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /treatment_sessions/{id} {
      allow read, write: if request.auth != null
                         && request.auth.uid == 'homehd-treatment';
    }
    match /treatment_readings/{id} {
      allow read, write: if request.auth != null
                         && request.auth.uid == 'homehd-treatment';
    }
  }
}
```

The fixed UID `'homehd-treatment'` is baked into both the rules and the custom token the
backend mints. All other collections (blood_tests, inventory_*) remain unchanged.

## Auth flow

**Setup / token refresh:**
1. User enters `mainKey` in Setup Wizard (same as today, minus the two Apps Script fields)
2. Setup calls `GET /api/treatment/token` with `Authorization: Bearer <mainKey>`
3. Cloud Run mints a Firebase custom token: `auth().createCustomToken('homehd-treatment')`
4. Frontend receives `{ token, expires_at }`, calls `signInWithCustomToken(firebaseAuth, token)`
5. `token` + `expires_at` saved to IndexedDB in `AuthSettings`

**Silent refresh (on every Treatment mount):**
- If `treatmentTokenExpiresAt` is within 10 minutes → re-fetch `/api/treatment/token` silently
- On network failure during dialysis: existing Firebase session stays valid for its remaining
  window (Firebase ID tokens last 1 hour after custom token exchange) — writes still work
- If completely expired AND no network: show a non-blocking warning, continue with cached
  active state (localStorage survives)

## Backend — `api/src/handlers/treatment.ts`

Mounted under the existing bearer-auth router in `index.ts`. Two routes:

### `GET /api/treatment/token`

```ts
.get('/token', async (c) => {
  const token = await getAuth().createCustomToken('homehd-treatment');
  const expires_at = Date.now() + 55 * 60 * 1000; // 55 min (custom tokens expire at 60)
  return c.json({ ok: true, token, expires_at });
})
```

Firebase Admin SDK `getAuth()` uses the Cloud Run service account automatically (Application
Default Credentials). **New IAM grant needed:** `roles/iam.serviceAccountTokenCreator` on the
Cloud Run service account (`266908773576-compute@developer.gserviceaccount.com`).

### `POST /api/treatment/sync-to-sheet`

1. Read all `treatment_sessions` (ordered by `date` asc) + all `treatment_readings` from Firestore
2. Group readings by `session_id`, sort by `seq`
3. Write to three Sheet tabs via Google Sheets API v4 (service account auth, same SA):
   - `sessions` tab — one row per session, column order matching `SESSION_COLS`
   - `readings` tab — one row per reading, column order matching `READING_COLS`
   - `legacy_view` tab — rebuilt in the pre/during/post layout the clinical team knows
     (port of the existing Apps Script `rebuildLegacyView_` logic)
4. Returns `{ ok, sessions_written, readings_written, synced_at }`

The Sheet ID is stored as an env var `TREATMENT_SHEET_ID` injected at deploy time
(not a secret — it's the spreadsheet ID from the URL, not a credential). The service account
needs **Editor** access granted on the specific Sheet (one-time manual step in Google Drive).

**Google Sheets API enable:**
```bash
gcloud services enable sheets.googleapis.com --project=homehd-personal
```

### Cloud Scheduler job

```
name:     treatment-weekly-sheet-sync
schedule: 0 8 * * 0   (Sunday 08:00 UTC = 09:00 BST / 08:00 GMT)
target:   POST https://homehd.web.app/api/treatment/sync-to-sheet
auth:     Authorization: Bearer <MAIN_API_KEY>
```

## Frontend changes

### `frontend/src/lib/firebaseClient.ts` (new)

Firebase app init + `getFirestore()` + `getAuth()` singletons. Imported by
`Treatment/api.ts` only. Uses the existing Firebase project (`homehd-personal`) — no new
project needed; Firestore is already active.

```ts
import { initializeApp, getApps } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
import { getAuth } from 'firebase/auth';

const firebaseConfig = {
  projectId: 'homehd-personal',
  // apiKey etc. from Firebase console — these are public, not secrets
};

const app = getApps().length ? getApps()[0] : initializeApp(firebaseConfig);
export const db = getFirestore(app);
export const firebaseAuth = getAuth(app);
```

### `Treatment/api.ts` (replaced)

Same exported function signatures. Implementation swaps to Firestore SDK:

```ts
export async function saveSession(session: Session): Promise<void>
export async function saveReading(reading: Reading): Promise<void>
export async function updateSession(patch: Partial<Session> & { session_id: string }): Promise<void>
export async function getAll(): Promise<GetResponse>
```

- `saveSession` / `saveReading` → `setDoc` (upsert by document ID — idempotent on retry)
- `updateSession` → `updateDoc` (partial update)
- `getAll` → two `getDocs(collection(...))` calls, combined into `{ sessions, readings }`
- `ApiError` class stays (same codes reused by the screens); network errors surface as
  `'network_error'`; Firestore permission errors surface as `'unauthorized'`
- No more `Settings` type, `postJson`, `stripEmptyRows`, `probe` — all gone
- Screens call `saveSession(session)` not `saveSession(settings, session)` — settings param
  dropped (Firestore auth is handled at init time, not per-call)

**Note:** screens currently pass `settings` as the first argument. Each call site in
`index.tsx` and the screen files needs this argument removed — grep for `settings,` in
`routes/Treatment/`.

### `auth/storage.ts`

```ts
export interface AuthSettings {
  mainKey: string;
  // removed: appsScriptUrl, appsScriptSecret
  treatmentToken?: string;
  treatmentTokenExpiresAt?: number;
}
```

Existing installs that have `appsScriptUrl`/`appsScriptSecret` in IndexedDB will still load
fine — TypeScript just ignores the extra fields on read; no migration needed.

### `auth/SetupWizard.tsx`

Remove the Apps Script URL + shared secret input fields and the `probe()` call that validated
them. New setup flow: enter `mainKey` → probe `/api/health` → fetch treatment token via
`GET /api/treatment/token` → `signInWithCustomToken` → save auth → navigate to `/treatment`.

### `Treatment/index.tsx` — token lifecycle

Add a `ensureFirebaseAuth()` call at the top of the `useEffect` that currently calls `getAll`:

```ts
async function ensureFirebaseAuth(auth: AuthSettings): Promise<void> {
  const now = Date.now();
  const needsRefresh = !auth.treatmentToken
    || !auth.treatmentTokenExpiresAt
    || auth.treatmentTokenExpiresAt - now < 10 * 60 * 1000;

  if (needsRefresh) {
    const { token, expires_at } = await cloudGet<TokenResponse>(auth, '/api/treatment/token');
    await saveAuth({ ...auth, treatmentToken: token, treatmentTokenExpiresAt: expires_at });
    auth = { ...auth, treatmentToken: token, treatmentTokenExpiresAt: expires_at };
  }
  await signInWithCustomToken(firebaseAuth, auth.treatmentToken!);
}
```

## Backfill script — `scripts/backfill-treatment.ts`

One-time terminal tool. Run before cutover:

```bash
cd scripts
HD_URL='...' HD_SECRET='...' npx ts-node backfill-treatment.ts
```

Steps:
1. `GET` from Apps Script URL with `secret` → all sessions + readings (existing `getAll` shape)
2. Init Firebase Admin SDK with application default credentials
3. Batch-write sessions to `treatment_sessions/{session_id}` (set, not merge — overwrite safe)
4. Batch-write readings to `treatment_readings/{reading_id}`
5. Skip documents that already exist (`--skip-existing` flag, default on)
6. Print: `N sessions written, M readings written, K skipped`

Uses Firestore batch writes (max 500 per batch — split if needed).

**Cutover order:**
```
1. Run backfill (Apps Script still live, no user impact)
2. Verify: Firestore doc count == Sheet row count
3. Deploy new frontend + backend (single gcloud + firebase deploy)
4. Run one real session end-to-end on device
5. Manually trigger sync-to-sheet: POST /api/treatment/sync-to-sheet
6. Verify Sheet tabs match Firestore
7. Leave Apps Script deployed but stop using it
```

## Repo facts (verified 2026-06-01)

- Cloud Run SA: `266908773576-compute@developer.gserviceaccount.com`
- Firebase project: `homehd-personal` (Firestore already active, Native mode, europe-west2)
- Existing Firestore collections: `blood_tests`, `inventory_stock`, `inventory_events`,
  `inventory_config` — `treatment_*` collections are new
- Frontend Firebase SDK: **not present** in `frontend/package.json` — must be added (`npm install firebase`)
- `TREATMENT_SHEET_ID` = the spreadsheet ID from the Sheet URL (the part between `/d/` and `/edit`
  in the Google Sheets URL — not the Apps Script `/exec` URL). Add to Cloud Run env at deploy.

## IAM / API checklist (manual steps before deploy)

```bash
# 1. Grant token-minting permission
gcloud projects add-iam-policy-binding homehd-personal \
  --member="serviceAccount:266908773576-compute@developer.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator"

# 2. Enable Sheets API
gcloud services enable sheets.googleapis.com --project=homehd-personal

# 3. Share the Google Sheet with the service account as Editor
#    (one-time in Google Drive UI — share with 266908773576-compute@developer.gserviceaccount.com)

# 4. Add TREATMENT_SHEET_ID env var at deploy time
#    (gcloud run deploy ... --set-env-vars=TREATMENT_SHEET_ID=<sheet-id>)
```

## Testing

- **`api/src/handlers/treatment.test.ts`** (new) — token endpoint (mock Admin SDK `createCustomToken`), sync-to-sheet (mock Firestore `getDocs` + mock Sheets API write), per-type isolation
- **`frontend/src/routes/Treatment/api.test.ts`** (new) — `saveSession`/`saveReading`/`updateSession`/`getAll` against mocked Firestore SDK; verify numeric types stored as numbers
- **Existing 96 frontend tests** — screen-level tests unchanged (no UX changes)
- **Manual cutover checklist** — run backfill → verify counts → deploy → complete one full session → trigger sync-to-sheet → verify Sheet

## Implementation plan (ordered tasks)

### Phase 1 — Backend + IAM (no user impact)
1. Grant `roles/iam.serviceAccountTokenCreator` to Cloud Run SA
2. Enable Sheets API; share Sheet with service account as Editor
3. Implement `GET /api/treatment/token` in `api/src/handlers/treatment.ts` (+ test)
4. Implement `POST /api/treatment/sync-to-sheet` (+ test)
5. Add `TREATMENT_SHEET_ID` env var; deploy `homehd-api` (inherit secrets — no `--set-secrets`)
6. Smoke-test token endpoint: `curl -H "Authorization: Bearer $KEY" .../api/treatment/token`
7. Create Cloud Scheduler job `treatment-weekly-sheet-sync`

### Phase 2 — Backfill
8. Write `scripts/backfill-treatment.ts`
9. Run backfill against live Apps Script; verify Firestore doc counts == Sheet row counts

### Phase 3 — Frontend + cutover
10. `npm install firebase` in `frontend/`; add `frontend/src/lib/firebaseClient.ts`
11. Update Firestore security rules (deploy via `firebase deploy --only firestore:rules`)
12. Replace `Treatment/api.ts` with Firestore SDK implementation (+ test)
13. Update `auth/storage.ts` — drop Apps Script fields, add token fields
14. Update `SetupWizard.tsx` — remove Apps Script inputs, add token fetch
15. Update `Treatment/index.tsx` — add `ensureFirebaseAuth()` before `getAll`
16. Remove `settings` arg from all Treatment call sites
17. Build + deploy frontend; on-device end-to-end test (Pre → Active → Post)

### Phase 4 — Verify + tidy
18. Manually trigger `sync-to-sheet`; verify Sheet tabs match Firestore
19. Commit everything; update vault note
20. Leave Apps Script dormant (do not decommission until 2+ weeks of stable use)
