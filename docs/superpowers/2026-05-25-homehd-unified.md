# Home HD Unified App

**Date:** 2026-05-25
**Status:** Design approved; implementation plan to be written and appended as `## Implementation plan` in this file.
**Source brainstorm:** Conversation with user on 2026-05-25, recorded as the `### 2026-05-25` Update Log entry in `~/Project_ideas/Home HD Knowledge Base and Tracking System.md`.
**Supersedes:** [`2026-05-22-blood-test-dashboard.md`](2026-05-22-blood-test-dashboard.md) — the dashboard becomes a tab inside this unified app. The dashboard's code is fully built and live on Cloudflare Pages (`treatment-dashboard.pages.dev`); this spec ports it to a new host and folder, it does not rebuild it.
**Carries forward:** [`2026-05-10-pwa-mvp.md`](2026-05-10-pwa-mvp.md) — the live treatment PWA moves verbatim into `frontend/src/routes/Treatment/`; its Apps Script + Sheet backend is unchanged.

A single Progressive Web App that consolidates every Home HD personal tool — live dialysis entry, blood-test analytics, NxStage error knowledge base, supply inventory, fitness tracker integration, and a RAG chatbot — behind one auth, one shell, one device install. Hosted on GCP (Firebase Hosting + Cloud Run + Firestore). Migrates the live treatment PWA and the live blood-test dashboard off Cloudflare Pages as part of the same restructure.

## Design

### Goal

Stop maintaining "a set of small purpose-built tools" once they've grown to the point where unification is cheaper than the friction of separate installs, separate auths, and separate deploys. Move to one app that holds the whole personal Home HD stack, designed so:

- The live dialysis-entry route is as reliable as today (Treatment's medical-use criticality is the constraint that shapes everything else).
- Adding a new feature is "add a route + add an `/api/*` handler", not "create a new app."
- The future RAG chatbot has a single substrate to embed and retrieve over.
- Hosting costs stay at $0 at this scale.

### Key decisions (from brainstorming, 2026-05-25)

- **Single app, route-split tabs** — Vite + React + React Router. Treatment, Blood Tests, KB, Inventory, Fitness, Chat are routes inside one app, one PWA install, one service worker. Each route is a lazy-loaded chunk so Treatment doesn't bloat as new features land.
- **GCP, on the free tier** — Firebase Hosting for the frontend, Cloud Run for the API surface, Firestore for writes, Secret Manager for keys. Vertex AI deferred to whenever RAG is designed (the only paid leg).
- **One Cloud Run service, multiple `/api/*` routes** — Hono router inside a single container. Firebase Hosting rewrites `/api/*` → Cloud Run, so the frontend calls same-origin (no CORS dance).
- **Treatment writes stay direct to Apps Script** — the clinical team reads the Sheet, that backend doesn't move; a Cloud Run cold start in the middle of a dialysis session is unacceptable, so the Treatment route bypasses Cloud Run entirely for its writes.
- **Hub + protected-core dropped** — the unified app is the tidier shape long-term, and the medical-reliability concern is mitigated by route-level code splitting, direct Apps Script calls, and one-command hosting rollback rather than physical app separation.
- **Both Cloudflare Pages projects decommissioned** — `treatment-tracker.pages.dev` (live PWA) and `treatment-dashboard.pages.dev` (live dashboard) retire as the new unified app comes up.
- **The dashboard's code is preserved, not rewritten.** The 16-task plan that landed between 2026-05-22 and 2026-05-25 produced clean, route-isolated, well-tested modules. Migration ports them; it does not redo them.

### Non-goals

Deferred — these features land later as tabs, each via its own brainstorm → spec → plan:

- NxStage error KB content design and parsing of the manual (only the `/kb/*` route shell and `/api/kb/*` placeholder are part of this spec).
- Inventory data model and write flows (only the route and endpoint shell are part of this spec).
- Fitness API integration — providers, OAuth flow, ingest schedule, dashboard (only the `/api/fitness/ingest` endpoint shell).
- RAG chatbot — vector store choice (Vertex AI Vector Search vs. Firestore vector embeddings), embedding strategy, retrieval ranking, LLM provider (only the `/chat` route and `/api/chat` endpoint shell).

Out of scope entirely:

- Migrating the Apps Script + Google Sheet backend for Treatment writes (clinical-team constraint).
- The `pkb_backfill` Python script (one-shot local tool — stays in `scripts/`).
- Multi-user support (single-user app by design).
- Rewriting or behaviourally changing anything the dashboard already does — the Scorecard logic, Trend chart, FilterBar, query filter, and `/api/blood-tests` contract are preserved verbatim.

### Stack

- **Frontend:** Vite + React 18 + TypeScript (strict), Tailwind CSS, React Router, Recharts, lucide-react, zod, idb, vite-plugin-pwa.
- **Backend:** Cloud Run (Node 20, Hono router), Firestore (Native mode, europe-west2), Secret Manager.
- **Hosting:** Firebase Hosting (custom domain optional; defaults to `*.web.app`).
- **CI/CD:** local terminal — `firebase deploy` + `gcloud run deploy`. GitHub Actions deferred.
- **Treatment backend (unchanged):** Apps Script web app bound to the existing Google Sheet (`sessions`, `readings`, `legacy_view`). The `blood_tests` tab planned in earlier section-3 designs is **no longer needed** — blood-test data lives in the API now, not the Sheet.

### Repo layout

Full restructure of `~/Documents/Personal_Projects/treatment_tracker/`. Rename the directory to `homehd/` during Phase 1; rename the GitHub remote at Phase 3.

```
homehd/
├── frontend/                          # single Vite app
│   ├── src/
│   │   ├── main.tsx
│   │   ├── App.tsx                    # router + auth shell
│   │   ├── routes/
│   │   │   ├── Treatment/             # ported verbatim from pwa/src/
│   │   │   │   ├── index.tsx          # route entry; was App.tsx's screen switcher
│   │   │   │   ├── screens/           # Home, Pre, Active, Post, AddReadingModal
│   │   │   │   ├── api.ts             # direct Apps Script client (unchanged)
│   │   │   │   ├── storage.ts         # IDB settings + localStorage active state
│   │   │   │   ├── schemas.ts
│   │   │   │   ├── sessionId.ts
│   │   │   │   └── sessionId.test.ts
│   │   │   ├── BloodTests/            # ported verbatim from dashboard/src/
│   │   │   │   ├── index.tsx          # was screens/Dashboard.tsx (Scorecard / Trend tabs)
│   │   │   │   ├── components/        # FilterBar, Scorecard, ScorecardTile, TrendChart
│   │   │   │   ├── lib/               # queryFilter, scorecard (pure + tests)
│   │   │   │   ├── markers.ts + markers.test.ts
│   │   │   │   ├── schemas.ts + schemas.test.ts
│   │   │   │   └── api.ts             # was dashboard/src/api.ts — uses /api/blood-tests
│   │   │   ├── KB/                    # placeholder route ("coming soon")
│   │   │   ├── Inventory/             # placeholder
│   │   │   ├── Fitness/               # placeholder
│   │   │   └── Chat/                  # placeholder
│   │   ├── api/
│   │   │   ├── cloudRun.ts            # fetch wrapper for /api/* with Bearer auth
│   │   │   └── appsScript.ts          # direct Apps Script client (Treatment uses this)
│   │   ├── auth/
│   │   │   ├── storage.ts             # IndexedDB: { mainKey, appsScriptUrl, appsScriptSecret }
│   │   │   └── SetupWizard.tsx        # first-launch screen
│   │   ├── components/                # shared shell: AppShell, NavBar, ErrorBoundary
│   │   ├── lib/
│   │   └── index.css
│   ├── public/                        # icons (existing droplet+ECG marks from pwa/public/)
│   ├── index.html
│   ├── package.json
│   ├── vite.config.ts                 # PWA plugin, route-level manualChunks
│   ├── tsconfig.json
│   ├── tailwind.config.ts
│   ├── postcss.config.js
│   ├── vitest.config.ts
│   └── README.md
├── api/                               # Cloud Run service (Node 20 + Hono)
│   ├── src/
│   │   ├── index.ts                   # Hono app, mounts all routes + auth middleware
│   │   ├── handlers/
│   │   │   ├── bloodTests.ts          # ported from dashboard/functions/api/blood-tests.ts
│   │   │   ├── kb.ts                  # placeholder
│   │   │   ├── inventory.ts           # placeholder
│   │   │   ├── fitness.ts             # placeholder
│   │   │   └── chat.ts                # placeholder
│   │   ├── lib/
│   │   │   ├── queryFilter.ts         # ported from dashboard/src/lib/queryFilter.ts
│   │   │   └── auth.ts                # Bearer-token middleware
│   │   ├── schemas/                   # shared zod schemas (mirror of frontend)
│   │   └── data/
│   │       └── blood_tests.json       # generated, gitignored, COPYed into image
│   ├── Dockerfile
│   ├── package.json
│   └── tsconfig.json
├── scripts/
│   ├── pkb_backfill/                  # unchanged (parser, blood_tests.csv, pastes/)
│   └── build-data.ts                  # CSV → api/src/data/blood_tests.json (prebuild hook)
├── apps-script/
│   └── Code.gs                        # documented copy of the live Sheet-bound script
├── firebase.json                      # hosting + /api/* rewrites
├── .firebaserc                        # project: homehd-personal
├── docs/superpowers/                             # flat: one file per project, design + plan combined
│   ├── 2026-05-10-pwa-mvp.md                     # Completed; PWA code carried forward
│   ├── 2026-05-22-blood-test-dashboard.md        # Completed; Superseded by this file
│   └── 2026-05-25-homehd-unified.md              # this file
├── package.json                       # workspace root (frontend + api)
├── .gitignore
└── README.md
```

**`.gitignore` additions (health-data + GCP-local):**

```
# Personal health data — never commit (repo is open-source-bound)
scripts/pkb_backfill/blood_tests.csv
scripts/pkb_backfill/pastes/
scripts/pkb_backfill/*.txt
api/src/data/

# Firebase / GCP local
.firebase/
firebase-debug.log
*-debug.log
.dev.vars

# Build artifacts
frontend/dist/
api/dist/
**/node_modules/
```

Existing `dashboard/data/`, `dashboard/`, `pwa/` paths drop out when those directories are moved/removed in Phase 1 and Phase 2.

### Routing and navigation

`React Router` with file-conventional routes. Single `RouterProvider` in `App.tsx`. Routes:

| Path | Route module | Status after Phase 2 |
|---|---|---|
| `/` | redirect to `/treatment` | shell |
| `/treatment` | `routes/Treatment/` | implemented (ported) |
| `/treatment/session/:id` | session detail | deferred placeholder |
| `/blood-tests` | `routes/BloodTests/` (Scorecard / Trend tabs internally) | implemented (ported) |
| `/kb` | `routes/KB/` | placeholder ("coming soon") |
| `/inventory` | `routes/Inventory/` | placeholder |
| `/fitness` | `routes/Fitness/` | placeholder |
| `/chat` | `routes/Chat/` | placeholder |
| `/setup` | `auth/SetupWizard` | implemented |

**Code splitting:** each `routes/*/index.tsx` imported with `React.lazy()` so its bundle is fetched on first navigation. Vite's `manualChunks` ensures Treatment's chunk excludes Recharts, BloodTests' chunk excludes Apps Script client, etc. — verify with `vite-bundle-visualizer` after Phase 2.

**Navigation shell:** a top tab bar on desktop, bottom tab bar on mobile breakpoints, shown on all routes except `/setup`. Tab order: Treatment, Tests, KB, Inv, Fitness, Chat. Inactive placeholder tabs are visible (route to a friendly "coming soon" card) so the shape of the app is obvious from day one.

### Auth model

**One main key** for `/api/*` access, plus the existing Apps Script URL + secret for Treatment writes. All three are entered once in the Setup Wizard.

**Storage (IndexedDB `auth` object store):**

```ts
type AuthSettings = {
  mainKey: string;            // sent as Authorization: Bearer ... to /api/*
  appsScriptUrl: string;      // Treatment writes endpoint
  appsScriptSecret: string;   // Treatment writes shared secret
};
```

IndexedDB (via `idb`) for static settings, mirroring the existing PWA pattern. The Treatment route's *active-session* state remains in localStorage per the 2026-05-15 lesson (iOS killing JS process between IDB transaction tick and disk flush) — only the static auth/settings live in IndexedDB.

**Server-side:** the main key is stored as a Secret Manager secret (`main-api-key`) and exposed to the Cloud Run service via `--set-secrets=MAIN_API_KEY=main-api-key:latest`. Rotated by `gcloud secrets versions add` plus re-entering the new value in the Setup Wizard on each device.

**Wrong key handling:** any `/api/*` route returning `401` triggers the frontend to push the user back to `/setup` with a "main key rejected — please re-enter" message. Apps Script auth errors stay scoped to the Treatment route (unchanged behaviour).

**Migration note:** the existing dashboard uses `DASHBOARD_KEY`; the existing PWA uses the Apps Script `SHARED_SECRET`. Phase 2 retires `DASHBOARD_KEY` and replaces it with the unified `MAIN_API_KEY`. The Apps Script secret stays as-is.

### Cloud Run service

**Single service** at `https://homehd-api-<hash>.europe-west2.run.app`, fronted by Firebase Hosting rewrites so the frontend calls `/api/*` same-origin.

**Hono router (`api/src/index.ts` skeleton):**

```ts
import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import { bearerAuth } from './lib/auth';
import { bloodTests } from './handlers/bloodTests';
import { kb } from './handlers/kb';
import { inventory } from './handlers/inventory';
import { fitness } from './handlers/fitness';
import { chat } from './handlers/chat';

const app = new Hono();

app.get('/api/health', (c) => c.json({ ok: true }));
app.use('/api/*', bearerAuth(() => process.env.MAIN_API_KEY!));

app.route('/api/blood-tests', bloodTests);
app.route('/api/kb',          kb);
app.route('/api/inventory',   inventory);
app.route('/api/fitness',     fitness);
app.route('/api/chat',        chat);

app.notFound((c) => c.json({ error: 'not_found' }, 404));
app.onError((err, c) => c.json({ error: 'server_error', message: String(err) }, 500));

serve({ fetch: app.fetch, port: Number(process.env.PORT ?? 8080) });
```

`/api/health` is intentionally before the auth middleware so the Setup Wizard can probe it without a key. It returns `{ ok: true }` only — never secrets.

**Dockerfile (`api/Dockerfile`):**

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY dist/ ./dist/
COPY src/data/ ./dist/data/
ENV PORT=8080
CMD ["node", "dist/index.js"]
```

**Deploy parameters:**

```bash
gcloud run deploy homehd-api \
  --source api/ \
  --region=europe-west2 \
  --allow-unauthenticated \
  --set-secrets=MAIN_API_KEY=main-api-key:latest \
  --min-instances=0 \
  --max-instances=1 \
  --memory=256Mi \
  --concurrency=20 \
  --cpu=1 \
  --timeout=30s
```

`--min-instances=0` accepts cold starts (~1.5–2 s on first hit after ~15 min idle) in exchange for free-tier pricing. `--max-instances=1` caps cost at a single instance ever — single-user app, no reason for more. `--allow-unauthenticated` is correct here — the bearer middleware is the auth boundary, not IAM.

**Why Hono:** TypeScript-first, tiny, zero dependencies, identical handler shape works locally (`@hono/node-server`) and on Cloud Run. Lift-and-shift compatible with Cloudflare Workers if priorities ever flip.

### Firebase Hosting rewrites

`firebase.json`:

```json
{
  "hosting": {
    "site": "homehd",
    "public": "frontend/dist",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      { "source": "/api/**",
        "run": { "serviceId": "homehd-api", "region": "europe-west2" } },
      { "source": "**",
        "destination": "/index.html" }
    ],
    "headers": [
      { "source": "/sw.js",
        "headers": [{ "key": "Cache-Control", "value": "no-cache" }] }
    ]
  }
}
```

The `/api/**` rewrite is the single most important detail: it makes the Cloud Run service same-origin from the browser, which means **no CORS preflight** — the `text/plain` workaround the PWA applied on 2026-05-11 (avoiding the preflight that Apps Script can't answer) is no longer needed for `/api/*`. Only the Treatment route's direct Apps Script call still uses that workaround (Apps Script behaviour is unchanged).

The `**` → `/index.html` rewrite handles SPA client-side routing.

The `sw.js` `no-cache` header ensures service-worker updates roll out on next page load.

### Blood-test data pipeline (ported)

```
scripts/pkb_backfill/blood_tests.csv
        │
        ▼ scripts/build-data.ts (npm prebuild in api/)
api/src/data/blood_tests.json
        │
        ▼ COPY in Dockerfile
container image
        │
        ▼ import at module load
api/src/handlers/bloodTests.ts
        │
        ▼ filterRows(rows, params)
GET /api/blood-tests?marker=…&from=…&to=…&phase=…
        │
        ▼ Firebase Hosting rewrite (/api/** → Cloud Run)
frontend fetch('/api/blood-tests', { Authorization: 'Bearer …' })
```

The Cloudflare equivalent (`dashboard/functions/api/blood-tests.ts` + `dashboard/scripts/build-data.ts`) is the source. `csvToRows`, `filterRows`, `isValidBound`, all the parsing edge cases (qualitative results, thousands commas, empty rows) come over unchanged. Only changes:

- Pages Function `onRequestGet` → Hono `handler.get('/')`
- Env var `DASHBOARD_KEY` → `MAIN_API_KEY` (via Hono middleware, not per-handler)
- Output path `dashboard/data/blood_tests.json` → `api/src/data/blood_tests.json`

Monthly workflow unchanged in shape: edit `blood_tests.csv` → `cd api && npm run build && gcloud run deploy --source .`.

JSON size at 2391 rows ≈ 350 KB. Cloud Run image limits are gigabytes; decades of headroom.

### Blood-test endpoint contract — `GET /api/blood-tests`

Preserved verbatim from the superseded dashboard spec:

- Auth: `Authorization: Bearer <MAIN_API_KEY>` (`401` missing/wrong).
- Query params: `marker` (canonical, comma-separated), `phase` (`admission`/`in-center-hd`/`home-hd`, comma-separated), `from` / `to` (`YYYY-MM` or `YYYY-MM-DD`, inclusive, granularity-matched).
- Response: `200` `{ "count": <n>, "rows": [...] }`.
- Errors: `401` unauthorized · `400` malformed `from`/`to` or unknown `phase` · `404` unknown path · `405` non-GET (Hono `app.on('GET', …)` returns this automatically when other methods hit a GET route) · `500` server error.

Future shape `GET /api/blood-tests/markers` returns the canonical marker list for the FilterBar dropdown (replaces deriving from a full bulk fetch). Not blocking.

### Treatment route — what changes

**Code:** moved verbatim from `pwa/src/` into `frontend/src/routes/Treatment/`. Same screens (Home, Pre, Active, AddReadingModal, Post), same direct Apps Script client, same localStorage-based active-session persistence (the 2026-05-15 lesson stands), same `appendAsText_` backend (lives in the Sheet's Apps Script editor, **not** moving).

**What's removed:**
- The standalone `Setup` screen — those fields move into the unified Setup Wizard.
- The standalone `Home` screen's `Settings` link — settings live in the app shell.
- The standalone `App.tsx` discriminated-union screen switcher — React Router handles route state; the existing exhaustiveness assertion can be applied per-route instead.

**What's added:**
- The route's "Home" screen becomes the `/treatment` index — last 5 sessions list, "Start session" CTA — but the app shell (top tab bar) wraps it.
- Treatment's in-progress active-session state is keyed in localStorage under a Treatment-specific prefix so other routes can't accidentally collide.

**Apps Script backend:** unchanged. `legacy_view` still rebuilds. The Sheet remains the clinical team's reading surface.

### Blood Tests route — what changes

**Code:** moved verbatim from `dashboard/src/` into `frontend/src/routes/BloodTests/`. Components, lib (queryFilter, scorecard), markers, schemas — all preserved with tests.

**What's removed:**
- `dashboard/src/screens/KeyEntry.tsx` — the Setup Wizard owns key entry now.
- `dashboard/src/App.tsx` (key-entry / loading / error / ready state machine) — App shell + route-level loader handle this.
- `dashboard/src/storage.ts` (one-key localStorage) — replaced by the unified IDB auth store.

**What's added:**
- `index.tsx` exports a route component that assumes auth exists, fetches `/api/blood-tests` once on mount via the unified `api/cloudRun.ts` client, renders Scorecard / Trend tabs as today.
- A loading skeleton and `ErrorBoundary` per the app-shell pattern.

**Endpoint:** `/api/blood-tests` contract preserved exactly. Only the runtime changes (Pages Function → Cloud Run handler).

### Error handling

**Cloud Run service:**
- `401` from `bearerAuth` middleware on missing/wrong main key (does not apply to `/api/health`).
- `400` from handler-level zod parsing of query params.
- `404` for unknown paths (Hono `notFound`).
- `500` for any uncaught throw (Hono `onError`).
- All errors JSON: `{ "error": "<code>", "message"?: "<detail>" }`.

**Frontend shell:**
- `401` anywhere → push to `/setup` with "main key rejected".
- Network failure → friendly retry on the affected route, app shell stays usable.
- zod validation failure on any `/api/*` response → "data format error" state with a retry.
- Treatment route's Apps Script errors stay scoped to that route (unchanged behaviour).
- React `ErrorBoundary` at the app shell **and** at each lazy route, so a render error in Inventory doesn't blank Treatment.

### Auth UX — Setup Wizard

Single screen at `/setup`, shown on first launch (when IndexedDB has no `auth` record) and on rotation. Three fields:

| Field | Purpose | Validation |
|---|---|---|
| Main API key | `/api/*` access | non-empty; GET `/api/health` then GET `/api/blood-tests?to=1900-01-01` (returns `count: 0` cheaply, proves the key works) |
| Apps Script URL | Treatment writes endpoint | URL shape; GET `?secret=<probe>` returns `401` (proves URL is alive) |
| Apps Script secret | Treatment writes auth | non-empty; combined GET `?secret=<value>` returns `200` (proves the pair) |

Probes happen on save in sequence; per-field error messages on failure, others untouched. On all-green, write to IndexedDB and redirect to `/treatment`.

A "Reset auth" button in the app shell's Settings panel clears IndexedDB and pushes to `/setup`.

### Migration — sequencing

Three landings, gated on real-use verification. **Both Cloudflare Pages apps continue serving production throughout the migration; nothing is decommissioned until its replacement is verified on a real session / real query.**

### Phase 1 — Restructure + Treatment cutover

1. **One-time GCP setup:** create `homehd-personal` project, link billing, set $5/month budget alert (mandatory, before any service is enabled), enable Firebase Hosting / Cloud Run / Artifact Registry / Secret Manager / Cloud Build APIs, install `gcloud` + `firebase-tools` (`firebase use --add homehd-personal`).
2. **Create the unified repo structure** in a new branch off the current `treatment_tracker` `main`:
   - Move `pwa/src/*` → `frontend/src/routes/Treatment/`.
   - Add React Router shell, `App.tsx`, the Setup Wizard, the placeholder route modules (each rendering a "coming soon" card).
   - Carry over `pwa/public/` icons to `frontend/public/`.
   - Configure `vite.config.ts` with the PWA plugin and route-level `manualChunks`.
3. **Treatment is the only fully-functional route** in Phase 1; Blood Tests is still a placeholder (its real port is Phase 2). The other tabs remain placeholders throughout.
4. **Deploy to Firebase Hosting:** `cd frontend && npm run build && firebase deploy --only hosting`. Get the `*.web.app` URL or attach the custom domain.
5. **Acceptance gate (medical-use):** install the new app on the phone *alongside* the existing PWA. Run a real dialysis session through the new app. Verify `sessions` / `readings` / `legacy_view` in the Sheet are correct. This is the same acceptance bar every prior PWA deploy uses.
6. **Cutover:** once Phase 1 is verified through one real session, uninstall the Cloudflare Pages PWA from the phone. Re-enter the auth on the new app. Cloudflare project `treatment-tracker` stays dormant for ~4 weeks as fallback.

### Phase 2 — Blood Tests port + Cloud Run API

1. **Scaffold `api/`** — Hono app skeleton, `bearerAuth` middleware, `/api/health`, stub handlers for the placeholder routes.
2. **Create the secret:** `gcloud secrets create main-api-key --replication-policy=automatic` + `gcloud secrets versions add main-api-key --data-file=-` (pipe in a long random string from `openssl rand -base64 32`).
3. **First Cloud Run deploy** with just `/api/health` and an empty `/api/blood-tests` stub:
   ```bash
   cd api && gcloud run deploy homehd-api --source . --region=europe-west2 \
     --allow-unauthenticated --set-secrets=MAIN_API_KEY=main-api-key:latest \
     --min-instances=0 --max-instances=1 --memory=256Mi
   ```
   Verify with `curl` against the Cloud Run URL.
4. **Wire the Hosting rewrite:** add `/api/**` → `homehd-api` to `firebase.json`. `firebase deploy --only hosting`. Verify same-origin `fetch('/api/health')` works from a browser tab on the deployed app.
5. **Port the blood-tests pipeline:**
   - `dashboard/scripts/csv.ts` → `scripts/build-data.ts` (single file; absorbs `dashboard/scripts/build-data.ts`).
   - `dashboard/src/lib/queryFilter.ts` + `queryFilter.test.ts` → `api/src/lib/queryFilter.ts` + test.
   - `dashboard/functions/api/blood-tests.ts` → `api/src/handlers/bloodTests.ts` (Hono shape; `onRequestGet` → handler function; env access via Hono context).
   - Run `cd api && npm run build` then redeploy Cloud Run.
   - `curl -H 'Authorization: Bearer <key>' https://homehd.web.app/api/blood-tests` returns the full dataset.
6. **Port the BloodTests route:**
   - `dashboard/src/{schemas,markers,markers.test,schemas.test}.ts` → `frontend/src/routes/BloodTests/`.
   - `dashboard/src/lib/scorecard*.ts` → `frontend/src/routes/BloodTests/lib/`.
   - `dashboard/src/components/*` → `frontend/src/routes/BloodTests/components/`.
   - `dashboard/src/screens/Dashboard.tsx` → `frontend/src/routes/BloodTests/index.tsx`. Strip the key-entry/state-machine wrapper; assume auth exists.
   - Replace the dashboard's `api.ts` and `storage.ts` with calls into the unified `frontend/src/api/cloudRun.ts` and `frontend/src/auth/storage.ts`.
   - Wire `/blood-tests` route into `App.tsx`.
7. **Acceptance:** on the deployed unified app, navigate to `/blood-tests`, see the panel-grouped Scorecard and at least one Trend chart render correctly against the live data. Spot-check known marker values match.

### Phase 3 — Decommission and tidy

1. **Decommission Cloudflare Pages projects** — both `treatment-tracker` and `treatment-dashboard` (Cloudflare console → project → Delete). Only after Phase 1 + 2 have been used for ~4 weeks.
2. **Remove Wrangler artefacts** — `wrangler` from `package.json`, `.wrangler/`, the Cloudflare-specific README sections in both `pwa/README.md` and `dashboard/README.md`. Delete `pwa/` and `dashboard/` directories (Git history preserves them).
3. **Old docs already merged + marked Superseded** — `2026-05-22-blood-test-dashboard.md` and `2026-05-10-pwa-mvp.md` were collapsed into single combined files (design + implementation plan together) under `docs/superpowers/` and their Status banners were updated in the same commit that introduced this spec; no further action needed in Phase 3.
4. **Rename:** local directory `treatment_tracker` → `homehd`; GitHub remote `treatment_tracker` → `homehd`.

### Future phases (each its own brainstorm → spec → plan)

| Phase | Feature | Notes |
|---|---|---|
| 4 | NxStage error KB | Manual parsing + `/api/kb/search` + KB tab UI. Copyright posture: personal use only, never reproduce manual text verbatim. |
| 5 | Inventory | Firestore-backed CRUD + Inventory tab UI. First true Firestore use; sets the pattern. |
| 6 | Fitness ingest | Provider choice (Fitbit / Strava / Apple Health via webhooks / Garmin), OAuth, Cloud Scheduler trigger, Firestore writes, Fitness tab dashboard. |
| 7 | RAG chatbot | Vector store decision (Firestore vectors vs Vertex AI Vector Search), embedding strategy across BP + blood tests + KB + fitness + inventory, LLM provider (BYO API key via Secret Manager), Chat tab UI. The only paid leg; explicit cost design at that point. |

### Build & deploy

**Local dev:**

```bash
# Frontend
cd frontend && npm install && npm run dev   # http://localhost:5173

# API locally (Node + Hono via @hono/node-server)
cd api && npm install
echo 'MAIN_API_KEY=dev-key-123' > .env.local
npm run dev                                # http://localhost:8080

# Firebase emulator (hosts frontend + proxies /api/* to local Cloud Run emulator if configured)
firebase emulators:start --only hosting
```

**Production deploy:**

```bash
# 1. API
cd api && npm run build
gcloud run deploy homehd-api --source . --region=europe-west2 \
  --allow-unauthenticated --set-secrets=MAIN_API_KEY=main-api-key:latest \
  --min-instances=0 --max-instances=1 --memory=256Mi --concurrency=20

# 2. Frontend
cd ../frontend && npm run build
firebase deploy --only hosting
```

**Rollback (single command each):**
- Frontend: `firebase hosting:rollback`
- API: `gcloud run services update-traffic homehd-api --to-revisions=<previous-revision>=100`

### Testing

Mirroring the existing "light by design" stance — single-user app, manual acceptance gates are the real tests:

- **TypeScript strict + zod** at every API boundary (same lessons as the existing PWA + dashboard).
- **Unit tests (Vitest), all ported with their tests:**
  - `api/src/lib/queryFilter.ts` (from `dashboard/src/lib/queryFilter.test.ts`)
  - `frontend/src/routes/Treatment/sessionId.ts` (existing PWA test, ported)
  - `frontend/src/routes/BloodTests/lib/scorecard.ts` (from `dashboard/src/lib/scorecard.test.ts`)
  - `frontend/src/routes/BloodTests/markers.ts` + `schemas.ts` (from `dashboard/src/markers.test.ts` + `schemas.test.ts`)
  - `api/src/lib/auth.ts` — new: bearer-token middleware (401 paths, missing-env-var path)
- **Build verification:** `npm run build` works in both `frontend/` and `api/`.
- **Acceptance gates (manual, after each Phase):**
  - Phase 1: real dialysis session through `/treatment` writes correctly to the Sheet.
  - Phase 2: `/blood-tests` Scorecard + at least one Trend chart render against live data; spot-check values.

### Risks and mitigations

| Risk | Mitigation |
|---|---|
| Treatment regression during Phase 1 cutover | New app runs alongside old PWA until a real session is verified; Cloudflare `treatment-tracker` stays dormant 4 weeks as fallback. |
| Cold-start latency on `/api/*` after idle | Acceptable for the personal-use tabs (1.5–2 s "loading…" state). Treatment never hits Cloud Run, so the medical-use path is unaffected. |
| One-deploy-affects-everything risk | Route-level code splitting + per-route `ErrorBoundary` + `firebase hosting:rollback` single-command revert. |
| Surprise GCP bill (Vertex AI in particular, later) | $5/month budget alert set in Phase 1 pre-flight, **before** any service is enabled. Vertex AI deferred to Phase 7 with its own cost-design step. |
| Health-data leakage if the open-source-bound repo is published | `.gitignore` entries listed above; `api/src/data/` ignored at scaffold time. |
| Origin change orphans existing PWA install / dashboard bookmark | Documented in migration plan: install new before uninstalling old, re-enter the three setup fields once. Custom domain in Phase 1 prevents recurrence for future moves. |
| Two secrets (main key + Apps Script secret) on each device | Single-user, single-device-class threat model; HTTPS-only; both rotatable independently. Acceptable. |
| Porting drift — behavioural change during the dashboard port | Pure modules (`queryFilter`, `scorecard`, `markers`, `schemas`) move with their tests intact; per-task acceptance is "tests still pass + Scorecard matches the live dashboard for a sampled marker". |
| Repo rename breaks local clones / bookmarks | Rename on disk during Phase 1, rename GitHub remote at Phase 3; the GitHub remote URL change is one `git remote set-url` per clone. |
| Apps Script `legacy_view` rebuild cost (2026-05-15 lesson) | Out of scope — backend unchanged. The fix is already in `Code.gs`. |

### Open questions (non-blocking)

- Custom domain choice (`homehd.<yourdomain>` vs accept `homehd-personal.web.app`). Defaults to the `.web.app` URL until decided.
- Whether to ship `apps-script/Code.gs` as a checked-in copy of the live Sheet-bound script for readability. Recommend yes — currently the live source is only visible inside the Sheet's editor, which is fragile.
- Whether to add `GET /api/blood-tests/markers` (a thin endpoint returning the canonical marker list) in Phase 2 or defer. Defer — `useMemo` over the bulk-fetched rows is fine for now.
- Whether placeholder routes should be visible-but-disabled tabs from day one or hidden until each feature lands. Recommend visible — clearer app shape, and the bottom-tab bar's column count is more stable as features land.
- Bottom-tab vs top-tab navigation on phone vs desktop. Recommend bottom-tab on mobile breakpoints (Treatment thumb-reach during a session), top-tab on desktop.
