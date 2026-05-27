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

- Custom domain choice (`homehd.<yourdomain>` vs accept `homehd.web.app`). Defaults to the `.web.app` URL until decided.
- Whether to ship `apps-script/Code.gs` as a checked-in copy of the live Sheet-bound script for readability. Recommend yes — currently the live source is only visible inside the Sheet's editor, which is fragile.
- Whether to add `GET /api/blood-tests/markers` (a thin endpoint returning the canonical marker list) in Phase 2 or defer. Defer — `useMemo` over the bulk-fetched rows is fine for now.
- Whether placeholder routes should be visible-but-disabled tabs from day one or hidden until each feature lands. Recommend visible — clearer app shape, and the bottom-tab bar's column count is more stable as features land.
- Bottom-tab vs top-tab navigation on phone vs desktop. Recommend bottom-tab on mobile breakpoints (Treatment thumb-reach during a session), top-tab on desktop.

---

## Implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the live Treatment PWA and live Blood Tests dashboard into a single unified GCP-hosted app across three gated phases, without breaking live dialysis-session entry at any point.

**Architecture:** React Router SPA in `frontend/` behind Firebase Hosting; Hono API service in `api/` on Cloud Run; unified IndexedDB auth store; Treatment writes bypass Cloud Run directly to Apps Script. Blood-test data is baked into the Cloud Run image as JSON (generated from `scripts/pkb_backfill/blood_tests.csv` locally before deploy).

**Tech Stack:** Vite + React 18 + TypeScript + Tailwind + React Router v6 + Recharts + zod + idb + vite-plugin-pwa (frontend); Hono + Node 20 + @hono/node-server (api); Firebase Hosting + Cloud Run + Secret Manager (GCP).

**Pre-flight checks (do before Task 1):**
- Confirm `gcloud` CLI is installed: `gcloud version`
- Confirm `firebase-tools` is installed: `firebase --version` (install via `npm i -g firebase-tools` if not)
- Confirm `tsx` is available for build-data scripts: `npx tsx --version`

---

### Task 1: Root workspace scaffold + GCP one-time setup

**Files:**
- Create: `package.json` (repo root)
- Create: `.firebaserc`
- Create: `firebase.json` (Phase 1 — hosting only, NO `/api/**` rewrite yet)
- Modify: `.gitignore`

- [ ] **Step 1: Create the GCP project and enable APIs**

Run these one at a time. Each may take 10–30 s.

```bash
gcloud projects create homehd-personal --name="Home HD"
gcloud config set project homehd-personal
gcloud billing accounts list   # note your BILLING_ACCOUNT_ID
gcloud billing projects link homehd-personal --billing-account=<BILLING_ACCOUNT_ID>

# Set a $5/month budget alert BEFORE enabling any paid API
gcloud billing budgets create \
  --billing-account=<BILLING_ACCOUNT_ID> \
  --display-name="homehd-budget" \
  --budget-amount=5USD \
  --threshold-rules-percent=100

# Enable all APIs needed across all three phases now
gcloud services enable \
  firebase.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  --project=homehd-personal
```

- [ ] **Step 2: Initialize Firebase**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker
firebase login   # interactive browser login
firebase projects:addfirebase homehd-personal
firebase use --add homehd-personal   # alias: default
```

- [ ] **Step 3: Create root `package.json` (npm workspaces)**

```json
{
  "name": "homehd",
  "private": true,
  "workspaces": ["frontend", "api"],
  "scripts": {
    "build-data": "tsx scripts/build-data.ts"
  },
  "devDependencies": {
    "tsx": "^4.19.0"
  }
}
```

- [ ] **Step 4: Create `.firebaserc`**

```json
{
  "projects": {
    "default": "homehd-personal"
  }
}
```

- [ ] **Step 5: Create Phase 1 `firebase.json`**

No `/api/**` rewrite yet — Cloud Run doesn't exist in Phase 1. It gets added in Task 13.

```json
{
  "hosting": {
    "public": "frontend/dist",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      { "source": "**", "destination": "/index.html" }
    ],
    "headers": [
      {
        "source": "/sw.js",
        "headers": [{ "key": "Cache-Control", "value": "no-cache" }]
      }
    ]
  }
}
```

- [ ] **Step 6: Update `.gitignore`**

Add these sections (keep existing entries):

```
# Personal health data — never commit
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

- [ ] **Step 7: Install root deps and commit**

```bash
npm install   # installs tsx at root
git add package.json package-lock.json .firebaserc firebase.json .gitignore
git commit -m "chore: root workspace scaffold, GCP/Firebase project init"
```

Expected: clean commit; `ls node_modules/.bin/tsx` exists.

---

### Task 2: `frontend/` scaffold (Vite + React Router + Tailwind + PWA)

**Files:**
- Create: `frontend/package.json`
- Create: `frontend/vite.config.ts`
- Create: `frontend/tailwind.config.ts`
- Create: `frontend/postcss.config.js`
- Create: `frontend/tsconfig.json`
- Create: `frontend/tsconfig.node.json`
- Create: `frontend/vitest.config.ts`
- Create: `frontend/index.html`
- Create: `frontend/src/index.css`
- Create: `frontend/src/main.tsx`

- [ ] **Step 1: Create `frontend/package.json`**

```json
{
  "name": "homehd-frontend",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc -b --noEmit"
  },
  "dependencies": {
    "idb": "^8.0.0",
    "lucide-react": "^1.14.0",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-router-dom": "^6.28.0",
    "recharts": "^2.13.0",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@types/react": "^18.3.12",
    "@types/react-dom": "^18.3.1",
    "@vitejs/plugin-react": "^4.3.3",
    "autoprefixer": "^10.5.0",
    "postcss": "^8.5.14",
    "tailwindcss": "^3.4.19",
    "typescript": "^5.6.3",
    "vite": "^5.4.10",
    "vite-plugin-pwa": "^0.20.5",
    "vitest": "^2.1.4"
  }
}
```

- [ ] **Step 2: Create `frontend/vite.config.ts`**

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['apple-touch-icon.png'],
      manifest: {
        name: 'Home HD',
        short_name: 'Home HD',
        description: 'Home hemodialysis personal toolkit',
        theme_color: '#0f172a',
        background_color: '#0f172a',
        display: 'standalone',
        start_url: '/',
        scope: '/',
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: 'icon-512-maskable.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        navigateFallback: '/index.html',
        // Never cache /api/* — those are Cloud Run calls, not static assets.
        navigateFallbackDenylist: [/^\/api/],
        runtimeCaching: [],
      },
    }),
  ],
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          treatment: [
            './src/routes/Treatment/index.tsx',
            './src/routes/Treatment/screens/Home.tsx',
            './src/routes/Treatment/screens/PreTreatment.tsx',
            './src/routes/Treatment/screens/ActiveSession.tsx',
            './src/routes/Treatment/screens/PostTreatment.tsx',
          ],
          'blood-tests': [
            './src/routes/BloodTests/index.tsx',
          ],
          recharts: ['recharts'],
        },
      },
    },
  },
  server: { port: 5173 },
});
```

- [ ] **Step 3: Create `frontend/tailwind.config.ts`**

```ts
import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#0f172a',
        panel: '#1e293b',
        accent: '#38bdf8',
      },
    },
  },
  plugins: [],
} satisfies Config;
```

- [ ] **Step 4: Create `frontend/postcss.config.js`**

```js
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
```

- [ ] **Step 5: Create `frontend/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": false,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

- [ ] **Step 6: Create `frontend/tsconfig.node.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "skipLibCheck": true,
    "strict": true
  },
  "include": ["vite.config.ts", "tailwind.config.ts", "postcss.config.js"]
}
```

- [ ] **Step 7: Create `frontend/vitest.config.ts`**

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
});
```

- [ ] **Step 8: Create `frontend/index.html`**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
    <meta name="theme-color" content="#0f172a" />
    <link rel="apple-touch-icon" href="/apple-touch-icon.png" />
    <title>Home HD</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **Step 9: Create `frontend/src/index.css`**

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  @apply bg-bg text-slate-100 min-h-screen;
}
```

- [ ] **Step 10: Create stub `frontend/src/main.tsx`**

```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <div className="p-4 text-slate-400">Loading…</div>
  </React.StrictMode>,
);
```

- [ ] **Step 11: Copy icons from pwa/public/**

```bash
cp -r pwa/public frontend/public
```

- [ ] **Step 12: Install dependencies and verify build**

```bash
cd frontend && npm install && npm run build
```

Expected: `dist/` created, `npm run build` exits 0. The stub renders "Loading…".

- [ ] **Step 13: Commit**

```bash
git add frontend/
git commit -m "chore: scaffold frontend/ Vite + React Router + Tailwind + PWA"
```

---

### Task 3: Unified auth storage module

**Files:**
- Create: `frontend/src/auth/storage.ts`

- [ ] **Step 1: Create `frontend/src/auth/storage.ts`**

```ts
import { openDB } from 'idb';

export interface AuthSettings {
  mainKey: string;
  appsScriptUrl: string;
  appsScriptSecret: string;
}

const DB_NAME = 'homehd-auth';
const DB_VERSION = 1;
const STORE = 'auth';

let dbPromise: ReturnType<typeof openDB> | null = null;

function db() {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(d) {
        if (!d.objectStoreNames.contains(STORE)) d.createObjectStore(STORE);
      },
    }).catch(err => { dbPromise = null; throw err; });
  }
  return dbPromise;
}

export async function getAuth(): Promise<AuthSettings | undefined> {
  return (await db()).get(STORE, 'auth') as Promise<AuthSettings | undefined>;
}

export async function saveAuth(a: AuthSettings): Promise<void> {
  await (await db()).put(STORE, a, 'auth');
}

export async function clearAuth(): Promise<void> {
  await (await db()).delete(STORE, 'auth');
}
```

- [ ] **Step 2: Verify build passes**

```bash
cd frontend && npm run build
```

Expected: exits 0 (auth/storage.ts is not imported yet, but should not cause build errors).

- [ ] **Step 3: Commit**

```bash
git add frontend/src/auth/storage.ts
git commit -m "feat: unified auth storage module (IDB-backed AuthSettings)"
```

---

### Task 4: SetupWizard (Phase 1 — Apps Script probe only)

**Files:**
- Create: `frontend/src/auth/SetupWizard.tsx`

The main key is stored as non-empty but not probed in Phase 1 (Cloud Run doesn't exist yet). The probe is added in Task 13 after Cloud Run is live.

- [ ] **Step 1: Create `frontend/src/auth/SetupWizard.tsx`**

```tsx
import { useState } from 'react';
import { Activity, KeyRound, Link2, Save } from 'lucide-react';
import { saveAuth } from './storage';
import type { AuthSettings } from './storage';

interface Props {
  onSaved: () => void;
  message?: string;
}

async function probeAppsScript(url: string, secret: string): Promise<void> {
  let res: Response;
  try {
    res = await fetch(`${url}?secret=${encodeURIComponent(secret)}`);
  } catch {
    throw new Error('Could not reach the Apps Script URL. Check the URL and try again.');
  }
  let body: unknown;
  try { body = await res.json(); } catch {
    throw new Error('Apps Script returned non-JSON. Check the deployment access setting (must be "Anyone").');
  }
  const b = body as Record<string, unknown>;
  if (b.ok === false) throw new Error(`Apps Script rejected the secret: ${String(b.error)}`);
  if (b.ok !== true) throw new Error('Apps Script returned an unexpected response.');
}

export function SetupWizard({ onSaved, message }: Props) {
  const [mainKey, setMainKey] = useState('');
  const [url, setUrl] = useState('');
  const [secret, setSecret] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setError(null);
    if (!mainKey.trim()) { setError('Main API key must not be empty.'); return; }

    let parsedUrl: URL;
    try { parsedUrl = new URL(url.trim()); }
    catch { setError('Apps Script URL must be a valid URL.'); return; }
    if (!secret.trim()) { setError('Apps Script secret must not be empty.'); return; }

    setBusy(true);
    try {
      await probeAppsScript(parsedUrl.toString(), secret.trim());
      const settings: AuthSettings = {
        mainKey: mainKey.trim(),
        appsScriptUrl: parsedUrl.toString(),
        appsScriptSecret: secret.trim(),
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
      <p className="text-sm text-slate-400">Enter three values. They are stored on this device only, never sent to any third party.</p>

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

      <label className="block">
        <span className="text-sm text-slate-400 mb-1 inline-flex items-center gap-1.5">
          <Link2 size={14} /> Apps Script URL
        </span>
        <input
          type="url"
          value={url}
          onChange={e => setUrl(e.target.value)}
          placeholder="https://script.google.com/macros/s/.../exec"
          className="w-full bg-panel border border-slate-700 rounded-lg px-3 py-2 text-sm focus:border-accent focus:outline-none"
        />
      </label>

      <label className="block">
        <span className="text-sm text-slate-400 mb-1 inline-flex items-center gap-1.5">
          <KeyRound size={14} /> Apps Script secret
        </span>
        <input
          type="password"
          value={secret}
          onChange={e => setSecret(e.target.value)}
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

- [ ] **Step 2: Verify build passes**

```bash
cd frontend && npm run build
```

Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/auth/SetupWizard.tsx
git commit -m "feat: SetupWizard — 3-field auth entry, Apps Script probe"
```

---

### Task 5: App shell, routing, placeholder routes

**Files:**
- Create: `frontend/src/components/ErrorBoundary.tsx`
- Create: `frontend/src/components/AppShell.tsx`
- Create: `frontend/src/routes/KB/index.tsx`
- Create: `frontend/src/routes/Inventory/index.tsx`
- Create: `frontend/src/routes/Fitness/index.tsx`
- Create: `frontend/src/routes/Chat/index.tsx`
- Modify: `frontend/src/App.tsx` (replaces the stub main.tsx eventually; full file below)
- Modify: `frontend/src/main.tsx` (wire RouterProvider)

- [ ] **Step 1: Create `frontend/src/components/ErrorBoundary.tsx`**

```tsx
import { Component, type ReactNode } from 'react';

interface Props { children: ReactNode; fallback?: ReactNode; }
interface State { error: Error | null; }

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(e: Error): State {
    return { error: e };
  }

  render() {
    if (this.state.error) {
      return this.props.fallback ?? (
        <div className="p-4 text-red-400">
          Something went wrong: {this.state.error.message}
          <button
            type="button"
            onClick={() => this.setState({ error: null })}
            className="ml-4 underline text-sm"
          >
            Retry
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
```

- [ ] **Step 2: Create `frontend/src/components/AppShell.tsx`**

Bottom-tab bar on mobile, top-tab bar on desktop. Six tabs; inactive placeholders show "coming soon".

```tsx
import { Outlet, NavLink, useNavigate } from 'react-router-dom';
import { Activity, FlaskConical, BookOpen, Package, Dumbbell, MessageSquare } from 'lucide-react';
import { clearAuth } from '../auth/storage';
import { ErrorBoundary } from './ErrorBoundary';

const TABS = [
  { to: '/treatment', label: 'Treatment', Icon: Activity },
  { to: '/blood-tests', label: 'Tests', Icon: FlaskConical },
  { to: '/kb', label: 'KB', Icon: BookOpen },
  { to: '/inventory', label: 'Inv', Icon: Package },
  { to: '/fitness', label: 'Fitness', Icon: Dumbbell },
  { to: '/chat', label: 'Chat', Icon: MessageSquare },
];

export function AppShell() {
  const navigate = useNavigate();

  async function handleResetAuth() {
    if (!confirm('Clear all saved credentials on this device?')) return;
    await clearAuth();
    navigate('/setup');
  }

  const tabClass = ({ isActive }: { isActive: boolean }) =>
    `flex flex-col items-center gap-0.5 px-3 py-2 text-xs transition-colors ${
      isActive ? 'text-accent' : 'text-slate-500 hover:text-slate-300'
    }`;

  return (
    <div className="flex flex-col min-h-screen">
      {/* Top bar (desktop) */}
      <nav className="hidden md:flex items-center border-b border-slate-700 bg-panel px-4 gap-1">
        <span className="text-sm font-semibold text-slate-300 mr-4">Home HD</span>
        {TABS.map(({ to, label }) => (
          <NavLink key={to} to={to} className={tabClass}>
            {label}
          </NavLink>
        ))}
        <button
          type="button"
          onClick={handleResetAuth}
          className="ml-auto text-xs text-slate-500 hover:text-slate-300 py-2"
        >
          Settings
        </button>
      </nav>

      {/* Page content */}
      <main className="flex-1 overflow-y-auto pb-16 md:pb-0">
        <ErrorBoundary>
          <Outlet />
        </ErrorBoundary>
      </main>

      {/* Bottom tab bar (mobile) */}
      <nav className="fixed bottom-0 left-0 right-0 flex md:hidden border-t border-slate-700 bg-panel safe-area-inset-bottom">
        {TABS.map(({ to, label, Icon }) => (
          <NavLink key={to} to={to} className={({ isActive }) =>
            `flex-1 flex flex-col items-center gap-0.5 py-2 text-xs transition-colors ${
              isActive ? 'text-accent' : 'text-slate-500 hover:text-slate-300'
            }`
          }>
            <Icon size={20} />
            {label}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
```

- [ ] **Step 3: Create placeholder routes**

```tsx
// frontend/src/routes/KB/index.tsx
export default function KB() {
  return <div className="p-8 text-slate-400 text-center">NxStage error KB — coming soon.</div>;
}

// frontend/src/routes/Inventory/index.tsx
export default function Inventory() {
  return <div className="p-8 text-slate-400 text-center">Supply inventory — coming soon.</div>;
}

// frontend/src/routes/Fitness/index.tsx
export default function Fitness() {
  return <div className="p-8 text-slate-400 text-center">Fitness tracker — coming soon.</div>;
}

// frontend/src/routes/Chat/index.tsx
export default function Chat() {
  return <div className="p-8 text-slate-400 text-center">RAG chatbot — coming soon.</div>;
}
```

Create each as its own file at the path shown.

- [ ] **Step 4: Create `frontend/src/App.tsx`**

```tsx
import { lazy, Suspense, useEffect, useState } from 'react';
import {
  createBrowserRouter,
  RouterProvider,
  Navigate,
  useNavigate,
} from 'react-router-dom';
import { getAuth } from './auth/storage';
import { SetupWizard } from './auth/SetupWizard';
import { AppShell } from './components/AppShell';
import { ErrorBoundary } from './components/ErrorBoundary';

const Treatment = lazy(() => import('./routes/Treatment'));
const BloodTests = lazy(() => import('./routes/BloodTests'));
const KB = lazy(() => import('./routes/KB'));
const Inventory = lazy(() => import('./routes/Inventory'));
const Fitness = lazy(() => import('./routes/Fitness'));
const Chat = lazy(() => import('./routes/Chat'));

function AuthGuard({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate();
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    getAuth().then(a => {
      if (!a) navigate('/setup', { replace: true });
      else setChecked(true);
    }).catch(() => navigate('/setup', { replace: true }));
  }, [navigate]);

  if (!checked) return <div className="p-4 text-slate-400">Loading…</div>;
  return <>{children}</>;
}

function SetupRoute() {
  const navigate = useNavigate();
  return (
    <SetupWizard
      onSaved={() => navigate('/treatment', { replace: true })}
    />
  );
}

const router = createBrowserRouter([
  { path: '/setup', element: <SetupRoute /> },
  {
    element: (
      <AuthGuard>
        <AppShell />
      </AuthGuard>
    ),
    children: [
      { index: true, element: <Navigate to="/treatment" replace /> },
      {
        path: '/treatment/*',
        element: (
          <ErrorBoundary>
            <Suspense fallback={<div className="p-4 text-slate-400">Loading…</div>}>
              <Treatment />
            </Suspense>
          </ErrorBoundary>
        ),
      },
      {
        path: '/blood-tests',
        element: (
          <ErrorBoundary>
            <Suspense fallback={<div className="p-4 text-slate-400">Loading…</div>}>
              <BloodTests />
            </Suspense>
          </ErrorBoundary>
        ),
      },
      { path: '/kb', element: <Suspense fallback={null}><KB /></Suspense> },
      { path: '/inventory', element: <Suspense fallback={null}><Inventory /></Suspense> },
      { path: '/fitness', element: <Suspense fallback={null}><Fitness /></Suspense> },
      { path: '/chat', element: <Suspense fallback={null}><Chat /></Suspense> },
    ],
  },
]);

export function App() {
  return <RouterProvider router={router} />;
}
```

- [ ] **Step 5: Update `frontend/src/main.tsx`**

```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import { App } from './App';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
```

- [ ] **Step 6: Create stub `frontend/src/routes/BloodTests/index.tsx`** (placeholder until Task 15)

```tsx
export default function BloodTests() {
  return <div className="p-8 text-slate-400 text-center">Blood tests dashboard — loading…</div>;
}
```

- [ ] **Step 7: Create stub `frontend/src/routes/Treatment/index.tsx`** (full port in Task 6)

```tsx
export default function Treatment() {
  return <div className="p-8 text-slate-400 text-center">Treatment — loading…</div>;
}
```

- [ ] **Step 8: Verify build passes with all routes wired**

```bash
cd frontend && npm run build
```

Expected: exits 0; `dist/` contains chunk files for treatment and blood-tests.

- [ ] **Step 9: Commit**

```bash
git add frontend/src/
git commit -m "feat: app shell, routing, placeholder routes"
```

---

### Task 6: Port Treatment route

**Files:**
- Create: `frontend/src/routes/Treatment/` (full directory)
- Modify: `frontend/src/routes/Treatment/index.tsx` (replaces stub)
- Modify: `frontend/src/routes/Treatment/storage.ts` (drops getSettings/saveSettings/clearSettings)
- Test: `frontend/src/routes/Treatment/sessionId.test.ts` (ported verbatim)

The Treatment internals (`api.ts`, `schemas.ts`, `screens/`, `components/`) are ported verbatim. `storage.ts` drops the three settings functions — auth now lives in `auth/storage.ts`. The route entry `index.tsx` reads `AuthSettings` from `getAuth()` and maps to the `Settings` shape that Treatment's `api.ts` expects.

- [ ] **Step 1: Copy source files verbatim**

```bash
# From repo root:
mkdir -p frontend/src/routes/Treatment/screens frontend/src/routes/Treatment/components

# Port files that need no changes:
cp pwa/src/api.ts         frontend/src/routes/Treatment/api.ts
cp pwa/src/schemas.ts     frontend/src/routes/Treatment/schemas.ts
cp pwa/src/sessionId.ts   frontend/src/routes/Treatment/sessionId.ts
cp pwa/src/sessionId.test.ts frontend/src/routes/Treatment/sessionId.test.ts
cp pwa/src/screens/PreTreatment.tsx    frontend/src/routes/Treatment/screens/PreTreatment.tsx
cp pwa/src/screens/ActiveSession.tsx   frontend/src/routes/Treatment/screens/ActiveSession.tsx
cp pwa/src/screens/PostTreatment.tsx   frontend/src/routes/Treatment/screens/PostTreatment.tsx
cp pwa/src/components/AddReadingModal.tsx frontend/src/routes/Treatment/components/AddReadingModal.tsx
cp pwa/src/components/NumberField.tsx     frontend/src/routes/Treatment/components/NumberField.tsx
cp pwa/src/components/SaveButton.tsx      frontend/src/routes/Treatment/components/SaveButton.tsx
cp pwa/src/components/SessionListItem.tsx frontend/src/routes/Treatment/components/SessionListItem.tsx
```

- [ ] **Step 2: Fix import paths in verbatim-copied files**

Every copied file imports from `'../schemas'`, `'../api'`, `'../storage'`, etc. Those relative paths still work — the directory structure is the same depth. No changes needed to these files.

Run a quick check:
```bash
grep -rn "from '\.\." frontend/src/routes/Treatment/ | head -20
```
Expected: all imports resolve within `frontend/src/routes/Treatment/`.

- [ ] **Step 3: Create `frontend/src/routes/Treatment/storage.ts`**

Same as `pwa/src/storage.ts` but with `getSettings/saveSettings/clearSettings` removed (those live in `auth/storage.ts` now). The IDB `DB_NAME` stays `'hd-tracker'` to avoid orphaning the existing install's cached data.

```ts
import { openDB, type IDBPDatabase } from 'idb';
import type { PendingReading, Session } from './schemas';

const ACTIVE_TTL_MS = 24 * 60 * 60 * 1000;

export interface ActiveState {
  screen: 'pre' | 'active' | 'post';
  session?: Session;
  existingIds?: string[];
  readings?: PendingReading[];
  savedAt: number;
}

// Keep DB_NAME as 'hd-tracker' — changing it would orphan the existing
// install's last_session cache and dried_weight on the user's phone.
const DB_NAME = 'hd-tracker';
const DB_VERSION = 1;
const STORE_KV = 'kv';

let dbPromise: Promise<IDBPDatabase> | null = null;

function db(): Promise<IDBPDatabase> {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(d) {
        if (!d.objectStoreNames.contains(STORE_KV)) d.createObjectStore(STORE_KV);
      },
    }).catch(err => { dbPromise = null; throw err; });
  }
  return dbPromise;
}

async function get<T>(key: string): Promise<T | undefined> {
  return (await db()).get(STORE_KV, key) as Promise<T | undefined>;
}
async function set<T>(key: string, value: T): Promise<void> {
  await (await db()).put(STORE_KV, value, key);
}

export async function getLastSession(): Promise<Session | undefined> {
  return get<Session>('last_session');
}
export async function saveLastSession(s: Session): Promise<void> {
  await set('last_session', s);
}
export async function getCachedSessions(): Promise<Session[] | undefined> {
  return get<Session[]>('sessions_cache');
}
export async function saveCachedSessions(sessions: Session[]): Promise<void> {
  await set('sessions_cache', sessions);
}

const DRIED_WEIGHT_DEFAULT = 59;
export async function getDriedWeight(): Promise<number> {
  const v = await get<number>('dried_weight');
  return typeof v === 'number' && Number.isFinite(v) ? v : DRIED_WEIGHT_DEFAULT;
}
export async function saveDriedWeight(kg: number): Promise<void> {
  await set('dried_weight', kg);
}

// Active state in localStorage: iOS kills IDB mid-transaction; localStorage
// writes flush synchronously before setItem returns.
const ACTIVE_KEY = 'treatment_active_state';

export function getActiveState(): ActiveState | undefined {
  try {
    const raw = localStorage.getItem(ACTIVE_KEY);
    if (!raw) return undefined;
    const s = JSON.parse(raw) as ActiveState;
    if (Date.now() - s.savedAt > ACTIVE_TTL_MS) {
      localStorage.removeItem(ACTIVE_KEY);
      return undefined;
    }
    return s;
  } catch { return undefined; }
}
export function saveActiveState(s: Omit<ActiveState, 'savedAt'>): void {
  try {
    localStorage.setItem(ACTIVE_KEY, JSON.stringify({ ...s, savedAt: Date.now() }));
  } catch {}
}
export function clearActiveState(): void {
  try { localStorage.removeItem(ACTIVE_KEY); } catch {}
}
```

Note: `ACTIVE_KEY` changed from `'active_state'` (pwa) to `'treatment_active_state'` so it doesn't collide with any future route state. Existing PWA users lose their in-progress active state on first load of the new app — acceptable one-time migration cost.

- [ ] **Step 4: Create `frontend/src/routes/Treatment/screens/Home.tsx`**

Port from `pwa/src/screens/Home.tsx`. Only change: remove `clearSettings` import (the settings gear now calls `clearAuth` from the app shell, not a local button). The `onSettingsCleared` prop is removed; the component no longer has a settings gear button (that lives in AppShell).

```tsx
import { useEffect, useState } from 'react';
import { Activity, CalendarDays, Check, Pencil, Play, RefreshCw, X } from 'lucide-react';
import { getAll, ApiError } from '../api';
import {
  getCachedSessions,
  getDriedWeight,
  saveCachedSessions,
  saveDriedWeight,
} from '../storage';
import type { Session, Settings } from '../schemas';
import { SessionListItem } from '../components/SessionListItem';

interface Props {
  settings: Settings;
  onStartSession: (existingIds: string[]) => void;
}

export function Home({ settings, onStartSession }: Props) {
  const [sessions, setSessions] = useState<Session[] | null>(null);
  const [freshLoaded, setFreshLoaded] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [driedWeight, setDriedWeight] = useState<number | null>(null);
  const [editingDried, setEditingDried] = useState(false);
  const [driedDraft, setDriedDraft] = useState('');

  useEffect(() => {
    getDriedWeight().then(setDriedWeight).catch(() => setDriedWeight(59));
  }, []);

  function startEditDried() {
    setDriedDraft(driedWeight != null ? String(driedWeight) : '');
    setEditingDried(true);
  }

  async function commitDried() {
    const n = Number(driedDraft);
    if (!Number.isFinite(n) || n <= 0) { setEditingDried(false); return; }
    setDriedWeight(n);
    setEditingDried(false);
    saveDriedWeight(n).catch(() => {});
  }

  async function load() {
    setError(null);
    setRefreshing(true);
    try {
      const r = await getAll(settings);
      const sorted = [...r.sessions].sort((a, b) => b.date.localeCompare(a.date));
      setSessions(sorted);
      setFreshLoaded(true);
      saveCachedSessions(sorted).catch(() => {});
    } catch (e) {
      setError(e instanceof ApiError ? `Load failed: ${e.code}` : String(e));
    } finally {
      setRefreshing(false);
    }
  }

  useEffect(() => {
    let cancelled = false;
    getCachedSessions()
      .then(cached => { if (!cancelled && cached && sessions === null) setSessions(cached); })
      .catch(() => {})
      .finally(() => { if (!cancelled) load(); });
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const ids = sessions?.map(s => s.session_id) ?? [];

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-bold inline-flex items-center gap-2">
          <Activity size={24} className="text-accent" /> Treatment
        </h1>
      </header>

      <button
        type="button"
        onClick={() => onStartSession(ids)}
        disabled={!freshLoaded}
        className="w-full bg-accent text-bg font-semibold rounded-lg py-4 text-lg disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
      >
        <Play size={22} fill="currentColor" /> Start session
      </button>

      <div className="bg-panel border border-slate-700 rounded-lg px-3 py-2 flex items-center justify-between gap-3">
        <span className="text-sm text-slate-400">Dried weight</span>
        {editingDried ? (
          <div className="flex items-center gap-2">
            <input
              type="number"
              inputMode="decimal"
              step="any"
              autoFocus
              value={driedDraft}
              onChange={e => setDriedDraft(e.target.value)}
              onKeyDown={e => {
                if (e.key === 'Enter') commitDried();
                if (e.key === 'Escape') setEditingDried(false);
              }}
              className="w-20 bg-bg border border-slate-700 rounded px-2 py-1 text-right focus:border-accent focus:outline-none"
            />
            <span className="text-sm text-slate-500">kg</span>
            <button type="button" onClick={commitDried} aria-label="Save" className="text-accent hover:opacity-80 p-1">
              <Check size={18} />
            </button>
            <button type="button" onClick={() => setEditingDried(false)} aria-label="Cancel" className="text-slate-500 hover:text-slate-300 p-1">
              <X size={18} />
            </button>
          </div>
        ) : (
          <button type="button" onClick={startEditDried} className="inline-flex items-center gap-2 text-slate-200 hover:text-accent">
            <span className="font-semibold">{driedWeight != null ? `${driedWeight} kg` : '—'}</span>
            <Pencil size={14} className="text-slate-500" />
          </button>
        )}
      </div>

      <section className="space-y-2">
        <h2 className="text-sm uppercase tracking-wide text-slate-500 inline-flex items-center justify-between w-full">
          <span className="inline-flex items-center gap-2">
            <CalendarDays size={14} /> Recent sessions
          </span>
          {refreshing && sessions !== null && (
            <span className="inline-flex items-center gap-1 normal-case tracking-normal text-slate-500">
              <RefreshCw size={12} className="animate-spin" /> refreshing
            </span>
          )}
        </h2>
        {error && (
          <div className="bg-red-900/40 border border-red-700 text-red-200 rounded-lg px-3 py-2 text-sm">
            {error} <button type="button" className="underline ml-2" onClick={load}>Retry</button>
          </div>
        )}
        {!sessions && !error && <div className="text-slate-500 text-sm">Loading…</div>}
        {sessions && sessions.length === 0 && <div className="text-slate-500 text-sm">No sessions yet.</div>}
        {sessions?.slice(0, 5).map(s => <SessionListItem key={s.session_id} session={s} />)}
      </section>
    </div>
  );
}
```

- [ ] **Step 5: Create `frontend/src/routes/Treatment/index.tsx`**

Reads `AuthSettings` from `getAuth()`, maps to `Settings` shape, runs the existing screen state machine. Redirects to `/setup` if auth is missing.

```tsx
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { getAuth } from '../../auth/storage';
import {
  clearActiveState,
  getActiveState,
  saveActiveState,
} from './storage';
import type { PendingReading, Session, Settings } from './schemas';
import { Home } from './screens/Home';
import { PreTreatment } from './screens/PreTreatment';
import { ActiveSession } from './screens/ActiveSession';
import { PostTreatment } from './screens/PostTreatment';

type Screen =
  | { name: 'loading' }
  | { name: 'home' }
  | { name: 'pre'; existingIds: string[] }
  | { name: 'active'; session: Session; readings: PendingReading[] }
  | { name: 'post'; session: Session };

export default function Treatment() {
  const navigate = useNavigate();
  const [screen, setScreen] = useState<Screen>({ name: 'loading' });
  const [settings, setSettings] = useState<Settings | null>(null);

  useEffect(() => {
    getAuth().then(auth => {
      if (!auth) { navigate('/setup', { replace: true }); return; }
      const s: Settings = {
        script_url: auth.appsScriptUrl,
        shared_secret: auth.appsScriptSecret,
      };
      setSettings(s);
      const active = getActiveState();
      if (active?.screen === 'pre' && active.existingIds) {
        setScreen({ name: 'pre', existingIds: active.existingIds });
      } else if (active?.screen === 'active' && active.session) {
        const readings = (active.readings ?? []).map(r =>
          r.status === 'pending' ? { ...r, status: 'error' as const, errorMsg: 'interrupted' } : r
        );
        setScreen({ name: 'active', session: active.session, readings });
      } else if (active?.screen === 'post' && active.session) {
        setScreen({ name: 'post', session: active.session });
      } else {
        setScreen({ name: 'home' });
      }
    }).catch(() => navigate('/setup', { replace: true }));
  }, [navigate]);

  useEffect(() => {
    if (screen.name === 'pre') {
      saveActiveState({ screen: 'pre', existingIds: screen.existingIds });
    } else if (screen.name === 'active') {
      saveActiveState({ screen: 'active', session: screen.session, readings: screen.readings });
    } else if (screen.name === 'post') {
      saveActiveState({ screen: 'post', session: screen.session });
    } else if (screen.name === 'home') {
      clearActiveState();
    }
  }, [screen]);

  if (screen.name === 'loading' || !settings) {
    return <div className="p-4 text-slate-400">Loading…</div>;
  }

  if (screen.name === 'home') {
    return (
      <Home
        settings={settings}
        onStartSession={existingIds => setScreen({ name: 'pre', existingIds })}
      />
    );
  }
  if (screen.name === 'pre') {
    return (
      <PreTreatment
        settings={settings}
        existingIds={screen.existingIds}
        onSaved={session => setScreen({ name: 'active', session, readings: [] })}
        onCancel={() => setScreen({ name: 'home' })}
      />
    );
  }
  if (screen.name === 'active') {
    return (
      <ActiveSession
        settings={settings}
        session={screen.session}
        initialReadings={screen.readings}
        onReadingsChange={rs =>
          setScreen(s => (s.name === 'active' ? { ...s, readings: rs } : s))
        }
        onEnd={() => setScreen({ name: 'post', session: screen.session })}
      />
    );
  }
  if (screen.name === 'post') {
    return (
      <PostTreatment
        settings={settings}
        session={screen.session}
        onSaved={() => setScreen({ name: 'home' })}
      />
    );
  }

  const _exhaustive: never = screen;
  return _exhaustive;
}
```

- [ ] **Step 6: Run the ported tests**

```bash
cd frontend && npm test
```

Expected: 5 `sessionId` tests pass, 0 failures.

- [ ] **Step 7: Verify build**

```bash
cd frontend && npm run build
```

Expected: exits 0. Verify `dist/assets/` contains a `treatment-*.js` chunk.

- [ ] **Step 8: Commit**

```bash
git add frontend/src/routes/Treatment/
git commit -m "feat: port Treatment route from pwa/ — screens, storage, API client"
```

---

### Task 7: Copy `apps-script/Code.gs`

**Files:**
- Create: `apps-script/Code.gs`

This is a manual copy from the Sheet's Apps Script editor. The file content is the live deployed version (with `appendAsText_`, `ensureHeader_`, and the `rebuildLegacyView_` perf fix from 2026-05-15 — not the older skeleton in the Obsidian note).

- [ ] **Step 1: Open the live script and copy it**

1. Open the Google Sheet in a browser.
2. Extensions → Apps Script.
3. Select all code in `Code.gs`, copy.
4. Create `apps-script/Code.gs` and paste.

- [ ] **Step 2: Verify it contains the key patches**

```bash
grep -c "appendAsText_" apps-script/Code.gs
```

Expected: ≥ 2 (the function definition + calls from saveSession_ and saveReading_).

```bash
grep "rebuildLegacyView_" apps-script/Code.gs | grep "save_reading" | wc -l
```

Expected: 0 — the reading-save path should NOT call rebuildLegacyView_ (2026-05-15 perf fix).

- [ ] **Step 3: Commit**

```bash
git add apps-script/Code.gs
git commit -m "docs: add checked-in copy of live Apps Script Code.gs"
```

---

### Task 8: Phase 1 Firebase deploy + acceptance gate

- [ ] **Step 1: Build the frontend**

```bash
cd frontend && npm run build
```

Expected: exits 0; `dist/` present.

- [ ] **Step 2: Deploy to Firebase Hosting**

```bash
firebase deploy --only hosting
```

Expected output includes `Hosting URL: https://homehd.web.app` (or similar). Note the URL.

- [ ] **Step 3: Install as PWA on Android alongside the existing Cloudflare PWA**

1. Open `https://homehd.web.app` in Chrome on Android.
2. Browser menu → "Add to home screen" → Install.
3. Open the new app. You should reach the Setup screen.
4. Enter: Main API key (any non-empty string for now), Apps Script URL, Apps Script secret (from macOS Keychain: `security find-generic-password -a "$USER" -s "hd-tracker-secret" -w`).
5. Tap "Save and continue". Expected: redirects to `/treatment`, shows Home screen with last 5 sessions.

- [ ] **Step 4: Run a real dialysis session through the new app**

Go through Pre → Active (add at least 2 readings) → Post. After Post, verify:

```bash
export HD_URL='...'   # from Keychain or the note
export HD_SECRET=$(security find-generic-password -a "$USER" -s "hd-tracker-secret" -w)
curl -L "$HD_URL?secret=$HD_SECRET" | python3 -m json.tool | grep session_id | tail -3
```

Expected: the session you just ran appears in `sessions`. Check the Sheet directly: `sessions`, `readings`, and `legacy_view` tabs all updated correctly.

- [ ] **Step 5: Commit the firebase hosting state**

```bash
git add .firebase/ firebase.json .firebaserc
git commit -m "chore: Phase 1 Firebase deploy — Treatment route live on homehd.web.app"
```

The old Cloudflare PWA stays installed on the phone for ~4 weeks as fallback. Do not uninstall it yet.

---

### Task 9: `api/` scaffold — Hono skeleton + bearer auth middleware (TDD)

**Files:**
- Create: `api/package.json`
- Create: `api/tsconfig.json`
- Create: `api/src/index.ts`
- Create: `api/src/lib/auth.ts`
- Create: `api/src/lib/auth.test.ts`
- Create: `api/src/handlers/kb.ts` (placeholder)
- Create: `api/src/handlers/inventory.ts` (placeholder)
- Create: `api/src/handlers/fitness.ts` (placeholder)
- Create: `api/src/handlers/chat.ts` (placeholder)

- [ ] **Step 1: Create `api/package.json`**

```json
{
  "name": "homehd-api",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js",
    "test": "vitest run"
  },
  "dependencies": {
    "@hono/node-server": "^1.13.7",
    "hono": "^4.6.0"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "tsx": "^4.19.0",
    "typescript": "^5.6.3",
    "vitest": "^2.1.4"
  }
}
```

- [ ] **Step 2: Create `api/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "strict": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true
  },
  "include": ["src"]
}
```

- [ ] **Step 3: Write the failing auth middleware test**

Create `api/src/lib/auth.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { Hono } from 'hono';
import { bearerAuth } from './auth';

function makeApp(key: string | undefined) {
  const app = new Hono();
  app.use('/protected/*', bearerAuth(() => key));
  app.get('/protected/data', (c) => c.json({ ok: true }));
  app.get('/api/health', (c) => c.json({ ok: true }));
  return app;
}

async function req(app: Hono, path: string, authHeader?: string) {
  const headers: Record<string, string> = {};
  if (authHeader) headers['Authorization'] = authHeader;
  return app.request(path, { headers });
}

describe('bearerAuth middleware', () => {
  it('returns 401 when Authorization header is missing', async () => {
    const res = await req(makeApp('secret'), '/protected/data');
    expect(res.status).toBe(401);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('unauthorized');
  });

  it('returns 401 when the key is wrong', async () => {
    const res = await req(makeApp('secret'), '/protected/data', 'Bearer wrong');
    expect(res.status).toBe(401);
  });

  it('passes through with the correct key', async () => {
    const res = await req(makeApp('secret'), '/protected/data', 'Bearer secret');
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean };
    expect(body.ok).toBe(true);
  });

  it('returns 500 when the env key is not set', async () => {
    const res = await req(makeApp(undefined), '/protected/data', 'Bearer anything');
    expect(res.status).toBe(500);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('server_misconfigured');
  });

  it('does not protect routes outside the middleware path', async () => {
    const res = await req(makeApp('secret'), '/api/health');
    expect(res.status).toBe(200);
  });
});
```

- [ ] **Step 4: Run test — verify it fails**

```bash
cd api && npm install && npm test
```

Expected: FAIL — `auth.ts` not found.

- [ ] **Step 5: Create `api/src/lib/auth.ts`**

```ts
import type { MiddlewareHandler } from 'hono';

export function bearerAuth(getKey: () => string | undefined): MiddlewareHandler {
  return async (c, next) => {
    const key = getKey();
    if (!key) {
      return c.json({ error: 'server_misconfigured', message: 'API key env var not set.' }, 500);
    }
    const header = c.req.header('Authorization');
    if (header !== `Bearer ${key}`) {
      return c.json({ error: 'unauthorized' }, 401);
    }
    await next();
  };
}
```

- [ ] **Step 6: Run test — verify it passes**

```bash
cd api && npm test
```

Expected: 5/5 pass.

- [ ] **Step 7: Create stub handlers**

```ts
// api/src/handlers/kb.ts
import { Hono } from 'hono';
export const kb = new Hono().get('/', (c) => c.json({ ok: true, note: 'coming soon' }));

// api/src/handlers/inventory.ts
import { Hono } from 'hono';
export const inventory = new Hono().get('/', (c) => c.json({ ok: true, note: 'coming soon' }));

// api/src/handlers/fitness.ts
import { Hono } from 'hono';
export const fitness = new Hono().get('/', (c) => c.json({ ok: true, note: 'coming soon' }));

// api/src/handlers/chat.ts
import { Hono } from 'hono';
export const chat = new Hono().get('/', (c) => c.json({ ok: true, note: 'coming soon' }));
```

- [ ] **Step 8: Create `api/src/index.ts`**

```ts
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
```

Note: imports use `.js` extension — required for NodeNext module resolution with TypeScript.

- [ ] **Step 9: Verify build**

```bash
cd api && npm run build
```

Expected: exits 0; `dist/index.js` + `dist/lib/` + `dist/handlers/` created.

- [ ] **Step 10: Smoke-test locally**

```bash
MAIN_API_KEY=dev-key node dist/index.js &
curl -s http://localhost:8080/api/health
# Expected: {"ok":true}
curl -s -H "Authorization: Bearer dev-key" http://localhost:8080/api/kb
# Expected: {"ok":true,"note":"coming soon"}
curl -s http://localhost:8080/api/kb
# Expected: {"error":"unauthorized"}
kill %1
```

- [ ] **Step 11: Commit**

```bash
git add api/
git commit -m "feat: api/ Hono skeleton + bearer auth middleware (TDD)"
```

---

### Task 10: Blood-test data pipeline (port `scripts/build-data.ts`)

**Files:**
- Create: `scripts/csv.ts` (ported from `dashboard/scripts/csv.ts`)
- Create: `scripts/build-data.ts` (ported from `dashboard/scripts/build-data.ts`)
- Modify: root `package.json` (add csv-parse devDep)

- [ ] **Step 1: Add `csv-parse` to root devDependencies**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker
npm install --save-dev csv-parse
```

- [ ] **Step 2: Create `scripts/csv.ts`**

Verbatim port from `dashboard/scripts/csv.ts` — only the import path for `BloodTestRow` changes (no longer `'../src/schemas'`, inlined as a local type alias so this script stays standalone).

```ts
import { parse } from 'csv-parse/sync';

export interface BloodTestRow {
  marker: string;
  datetime: string;
  value: number;
  unit: string;
  ref_low: number | null;
  ref_high: number | null;
  timing: '' | 'pre' | 'post';
  note: string;
  source: string;
  lab_id: string;
  phase: string;
  created_at: string;
  qualitative: boolean;
}

function num(v: string | undefined): number | null {
  const t = (v ?? '').trim();
  if (t === '') return null;
  const n = Number(t.replace(/,/g, ''));
  return Number.isFinite(n) ? n : null;
}

export function csvToRows(csvText: string): BloodTestRow[] {
  const records = parse(csvText, {
    columns: true,
    skip_empty_lines: true,
    relax_column_count: true,
  }) as Record<string, string>[];

  const rows: BloodTestRow[] = [];
  for (const r of records) {
    const marker = (r.marker ?? '').trim();
    const datetime = (r.datetime ?? '').trim();
    if (!marker || !datetime) continue;
    const value = num(r.value) ?? 0;
    const timing = (r.timing ?? '').trim();
    rows.push({
      marker, datetime, value,
      unit: (r.unit ?? '').trim(),
      ref_low: num(r.ref_low),
      ref_high: num(r.ref_high),
      timing: timing === 'pre' || timing === 'post' ? timing : '',
      note: (r.note ?? '').trim(),
      source: (r.source ?? '').trim(),
      lab_id: (r.lab_id ?? '').trim(),
      phase: (r.phase ?? '').trim(),
      created_at: (r.created_at ?? '').trim(),
      qualitative: value === 0,
    });
  }
  rows.sort((a, b) => a.datetime.localeCompare(b.datetime));
  return rows;
}
```

- [ ] **Step 3: Create `scripts/build-data.ts`**

```ts
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { csvToRows } from './csv.js';

const here = dirname(fileURLToPath(import.meta.url));
const csvPath = resolve(here, 'pkb_backfill/blood_tests.csv');
const outPath = resolve(here, '../api/src/data/blood_tests.json');

const rows = csvToRows(readFileSync(csvPath, 'utf8'));
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(rows));
console.log(`build-data: wrote ${rows.length} rows to ${outPath}`);
```

- [ ] **Step 4: Run the script and verify output**

```bash
npm run build-data
```

Expected output: `build-data: wrote 2391 rows to .../api/src/data/blood_tests.json`

```bash
node -e "const d = require('./api/src/data/blood_tests.json'); console.log(d.length, d[0].marker)"
```

Expected: `2391 <some-marker-name>`.

- [ ] **Step 5: Commit**

```bash
git add scripts/csv.ts scripts/build-data.ts package.json package-lock.json
git commit -m "feat: blood-test data pipeline (CSV → JSON prebuild script)"
```

---

### Task 11: `bloodTests` handler + `queryFilter` port to `api/src/lib/`

**Files:**
- Create: `api/src/lib/queryFilter.ts` (ported from `dashboard/src/lib/queryFilter.ts`)
- Create: `api/src/lib/queryFilter.test.ts` (ported from `dashboard/src/lib/queryFilter.test.ts`)
- Create: `api/src/schemas/bloodTests.ts` (BloodTestRow + PHASES)
- Create: `api/src/handlers/bloodTests.ts` (ported from `dashboard/functions/api/blood-tests.ts`)
- Modify: `api/src/index.ts` (mount bloodTests route)

- [ ] **Step 1: Create `api/src/schemas/bloodTests.ts`**

```ts
import { z } from 'zod';

export const PHASES = ['admission', 'in-center-hd', 'home-hd'] as const;

export const BloodTestRowSchema = z.object({
  marker: z.string().min(1),
  datetime: z.string().min(1),
  value: z.number(),
  unit: z.string(),
  ref_low: z.number().nullable(),
  ref_high: z.number().nullable(),
  timing: z.enum(['pre', 'post', '']),
  note: z.string(),
  source: z.string(),
  lab_id: z.string(),
  phase: z.enum(PHASES),
  created_at: z.string(),
  qualitative: z.boolean(),
});

export type BloodTestRow = z.infer<typeof BloodTestRowSchema>;
```

Add `zod` to `api/package.json` dependencies:
```bash
cd api && npm install zod
```

- [ ] **Step 2: Write the failing queryFilter test**

Create `api/src/lib/queryFilter.test.ts` (verbatim port from `dashboard/src/lib/queryFilter.test.ts`, updating imports):

```ts
import { describe, it, expect } from 'vitest';
import { filterRows, isValidBound } from './queryFilter.js';
import type { BloodTestRow } from '../schemas/bloodTests.js';

function row(over: Partial<BloodTestRow>): BloodTestRow {
  return {
    marker: 'urea', datetime: '2026-03-15T12:00:00', value: 5, unit: 'mmol/L',
    ref_low: 2.5, ref_high: 7.8, timing: '', note: '', source: 'imperial-pkb',
    lab_id: '1', phase: 'home-hd', created_at: '', qualitative: false, ...over,
  };
}

const rows: BloodTestRow[] = [
  row({ marker: 'urea', datetime: '2026-01-10T09:00:00', phase: 'home-hd' }),
  row({ marker: 'urea', datetime: '2026-04-15T09:00:00', phase: 'home-hd' }),
  row({ marker: 'creatinine', datetime: '2026-04-20T09:00:00', phase: 'home-hd' }),
  row({ marker: 'urea', datetime: '2025-06-01T09:00:00', phase: 'in-center-hd' }),
];

describe('isValidBound', () => {
  it('accepts YYYY-MM and YYYY-MM-DD', () => {
    expect(isValidBound('2026-04')).toBe(true);
    expect(isValidBound('2026-04-15')).toBe(true);
  });
  it('rejects malformed bounds', () => {
    expect(isValidBound('2026')).toBe(false);
    expect(isValidBound('April')).toBe(false);
  });
});

describe('filterRows', () => {
  it('filters by marker', () => {
    expect(filterRows(rows, { marker: ['creatinine'] })).toHaveLength(1);
  });
  it('filters by phase', () => {
    expect(filterRows(rows, { phase: ['in-center-hd'] })).toHaveLength(1);
  });
  it('month-granularity `to` keeps the whole month', () => {
    const r = filterRows(rows, { to: '2026-04' });
    expect(r.map((x) => x.datetime).sort()).toEqual([
      '2025-06-01T09:00:00', '2026-01-10T09:00:00', '2026-04-15T09:00:00', '2026-04-20T09:00:00',
    ]);
  });
  it('month range from/to is inclusive on both ends', () => {
    expect(filterRows(rows, { from: '2026-01', to: '2026-04' })).toHaveLength(3);
  });
  it('day-granularity bounds work', () => {
    const r = filterRows(rows, { from: '2026-04-16', to: '2026-04-20' });
    expect(r.map((x) => x.marker)).toEqual(['creatinine']);
  });
  it('combines marker + phase + range', () => {
    const r = filterRows(rows, { marker: ['urea'], phase: ['home-hd'], from: '2026-02' });
    expect(r.map((x) => x.datetime)).toEqual(['2026-04-15T09:00:00']);
  });
  it('empty params returns everything', () => {
    expect(filterRows(rows, {})).toHaveLength(4);
  });
});
```

- [ ] **Step 3: Run test — verify it fails**

```bash
cd api && npm test
```

Expected: FAIL — `queryFilter.js` not found.

- [ ] **Step 4: Create `api/src/lib/queryFilter.ts`**

Verbatim port from `dashboard/src/lib/queryFilter.ts`, updating the import:

```ts
import type { BloodTestRow } from '../schemas/bloodTests.js';

export type QueryParams = {
  marker?: string[];
  phase?: string[];
  from?: string;
  to?: string;
};

const BOUND_RE = /^\d{4}-\d{2}(-\d{2})?$/;

export function isValidBound(s: string): boolean {
  return BOUND_RE.test(s);
}

export function matchesFrom(datetime: string, from: string): boolean {
  return datetime.slice(0, from.length) >= from;
}

export function matchesTo(datetime: string, to: string): boolean {
  return datetime.slice(0, to.length) <= to;
}

export function filterRows(rows: BloodTestRow[], p: QueryParams): BloodTestRow[] {
  return rows.filter((r) => {
    if (p.marker?.length && !p.marker.includes(r.marker)) return false;
    if (p.phase?.length && !p.phase.includes(r.phase)) return false;
    if (p.from && !matchesFrom(r.datetime, p.from)) return false;
    if (p.to && !matchesTo(r.datetime, p.to)) return false;
    return true;
  });
}
```

- [ ] **Step 5: Run tests — verify all pass**

```bash
cd api && npm test
```

Expected: auth tests (5) + queryFilter tests (7) = 12 pass.

- [ ] **Step 6: Create `api/src/handlers/bloodTests.ts`**

Port from `dashboard/functions/api/blood-tests.ts`. Converts `PagesFunction` shape → Hono handler. Auth is handled by the middleware in `index.ts`, not per-handler.

`readFileSync` is used rather than a static JSON import because:
- `import.meta.url` gives the runtime path of the compiled file (`dist/handlers/bloodTests.js`)
- `resolve(here, '../data/blood_tests.json')` therefore resolves to `dist/data/blood_tests.json` — exactly where the Dockerfile puts it (`COPY src/data/ ./dist/data/`)
- A static `import '../../src/data/blood_tests.json'` would resolve to `src/data/` at runtime from `dist/handlers/`, which doesn't exist in the container

```ts
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Hono } from 'hono';
import { filterRows, isValidBound, type QueryParams } from '../lib/queryFilter.js';
import { PHASES, type BloodTestRow } from '../schemas/bloodTests.js';

const here = dirname(fileURLToPath(import.meta.url));
const rows: BloodTestRow[] = JSON.parse(
  readFileSync(resolve(here, '../data/blood_tests.json'), 'utf8'),
);

export const bloodTests = new Hono().get('/', (c) => {
  const params = c.req.query();
  const p: QueryParams = {};

  const marker = params['marker'];
  if (marker) p.marker = marker.split(',').map((s) => s.trim()).filter(Boolean);

  const phase = params['phase'];
  if (phase) {
    p.phase = phase.split(',').map((s) => s.trim()).filter(Boolean);
    if (p.phase.some((x) => !(PHASES as readonly string[]).includes(x))) {
      return c.json({ error: 'invalid phase param' }, 400);
    }
  }

  const from = params['from'];
  if (from) {
    if (!isValidBound(from)) return c.json({ error: 'invalid from param' }, 400);
    p.from = from;
  }

  const to = params['to'];
  if (to) {
    if (!isValidBound(to)) return c.json({ error: 'invalid to param' }, 400);
    p.to = to;
  }

  const result = filterRows(rows, p);
  return c.json({ count: result.length, rows: result });
});
```

- [ ] **Step 7: Mount the handler in `api/src/index.ts`**

Add to `api/src/index.ts` (after the existing imports):

```ts
import { bloodTests } from './handlers/bloodTests.js';
```

And add after the other `app.route` calls:

```ts
app.route('/api/blood-tests', bloodTests);
```

- [ ] **Step 8: Verify build**

```bash
npm run build-data   # from repo root — ensure JSON is up to date
cd api && npm run build
```

Expected: exits 0.

- [ ] **Step 9: Commit**

```bash
git add api/src/lib/queryFilter.ts api/src/lib/queryFilter.test.ts api/src/schemas/ api/src/handlers/bloodTests.ts api/src/index.ts api/package.json api/package-lock.json
git commit -m "feat: blood-tests handler + queryFilter (TDD) in api/"
```

---

### Task 12: Dockerfile + `.gcloudignore` + first Cloud Run deploy

**Files:**
- Create: `api/Dockerfile` (multi-stage)
- Create: `api/.gcloudignore`

- [ ] **Step 1: Create `api/Dockerfile`**

Multi-stage: `builder` compiles TypeScript; production stage copies only the dist + pre-built data JSON. The `src/data/blood_tests.json` is pre-built locally and included in the Cloud Build context via `.gcloudignore`.

```dockerfile
FROM node:20-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY src/ ./src/
COPY tsconfig.json ./
RUN npm run build

FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=builder /app/dist ./dist
COPY src/data/ ./dist/data/
ENV PORT=8080
CMD ["node", "dist/index.js"]
```

- [ ] **Step 2: Create `api/.gcloudignore`**

This file controls what `gcloud run deploy --source .` sends to Cloud Build. `src/data/` must NOT be excluded — the pre-built `blood_tests.json` lives there and must reach the image. Only exclude things that are large and irrelevant.

```
node_modules/
dist/
```

Without this file `gcloud` falls back to the root `.gitignore`, which excludes `api/src/data/` — the blood-test JSON would never reach Cloud Build.

- [ ] **Step 3: Create the Secret Manager secret**

```bash
gcloud secrets create main-api-key \
  --replication-policy=automatic \
  --project=homehd-personal

# Pipe a fresh random key (do not reuse the Cloudflare DASHBOARD_KEY)
openssl rand -base64 32 | gcloud secrets versions add main-api-key \
  --data-file=- \
  --project=homehd-personal

# Store it in macOS Keychain for local use:
security add-generic-password -a "$USER" -s "homehd-main-key" -w
# (paste the same random string when prompted)
```

- [ ] **Step 4: Pre-build the data JSON**

```bash
# From repo root:
npm run build-data
ls -lh api/src/data/blood_tests.json
```

Expected: file exists, ~350 KB.

- [ ] **Step 5: Deploy Cloud Run**

```bash
cd api
gcloud run deploy homehd-api \
  --source . \
  --region=europe-west2 \
  --allow-unauthenticated \
  --set-secrets=MAIN_API_KEY=main-api-key:latest \
  --min-instances=0 \
  --max-instances=1 \
  --memory=256Mi \
  --concurrency=20 \
  --cpu=1 \
  --timeout=30s \
  --project=homehd-personal
```

Expected: deployment URL like `https://homehd-api-<hash>-ew.a.run.app`. Note the URL.

- [ ] **Step 6: Smoke-test the deployed service**

```bash
export CLOUD_RUN_URL='https://homehd-api-<hash>-ew.a.run.app'
export MAIN_KEY=$(security find-generic-password -a "$USER" -s "homehd-main-key" -w)

# Health check (no auth required)
curl -s "$CLOUD_RUN_URL/api/health"
# Expected: {"ok":true}

# Auth check
curl -s -H "Authorization: Bearer $MAIN_KEY" \
  "$CLOUD_RUN_URL/api/blood-tests?phase=home-hd&to=1900-01-01"
# Expected: {"count":0,"rows":[]}

# Real data query
curl -s -H "Authorization: Bearer $MAIN_KEY" \
  "$CLOUD_RUN_URL/api/blood-tests?marker=urea&phase=home-hd" | python3 -m json.tool | head -20
# Expected: JSON with count > 0 and rows array
```

- [ ] **Step 7: Commit**

```bash
git add api/Dockerfile api/.gcloudignore
git commit -m "feat: Cloud Run Dockerfile (multi-stage) + .gcloudignore — first deploy"
```

---

### Task 13: Add `/api/**` rewrite to Firebase + update SetupWizard with main key probe

**Files:**
- Modify: `firebase.json` (add `/api/**` rewrite)
- Modify: `frontend/src/auth/SetupWizard.tsx` (add main key probe)

- [ ] **Step 1: Update `firebase.json`**

```json
{
  "hosting": {
    "public": "frontend/dist",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      {
        "source": "/api/**",
        "run": { "serviceId": "homehd-api", "region": "europe-west2" }
      },
      { "source": "**", "destination": "/index.html" }
    ],
    "headers": [
      {
        "source": "/sw.js",
        "headers": [{ "key": "Cache-Control", "value": "no-cache" }]
      }
    ]
  }
}
```

- [ ] **Step 2: Deploy hosting to wire the rewrite**

```bash
cd frontend && npm run build
firebase deploy --only hosting
```

- [ ] **Step 3: Verify the rewrite is live**

```bash
export HOSTING_URL='https://homehd.web.app'
export MAIN_KEY=$(security find-generic-password -a "$USER" -s "homehd-main-key" -w)

curl -s "$HOSTING_URL/api/health"
# Expected: {"ok":true}   (no auth header needed for /api/health)

curl -s -H "Authorization: Bearer $MAIN_KEY" \
  "$HOSTING_URL/api/blood-tests?phase=home-hd&to=1900-01-01"
# Expected: {"count":0,"rows":[]}
```

This confirms Firebase Hosting proxies `/api/**` to Cloud Run and the `Authorization` header is forwarded correctly.

- [ ] **Step 4: Update `frontend/src/auth/SetupWizard.tsx`** to probe the main key

Replace the `submit` function (the rest of the file is unchanged):

```tsx
async function submit() {
  setError(null);
  if (!mainKey.trim()) { setError('Main API key must not be empty.'); return; }

  let parsedUrl: URL;
  try { parsedUrl = new URL(url.trim()); }
  catch { setError('Apps Script URL must be a valid URL.'); return; }
  if (!secret.trim()) { setError('Apps Script secret must not be empty.'); return; }

  setBusy(true);
  try {
    // Probe the main key against /api/blood-tests (cheap: returns 0 rows for a far-future to date)
    const apiRes = await fetch('/api/blood-tests?to=1900-01-01', {
      headers: { Authorization: `Bearer ${mainKey.trim()}` },
    });
    if (apiRes.status === 401) throw new Error('Main API key rejected — check the value and try again.');
    if (!apiRes.ok) throw new Error(`/api/blood-tests returned ${apiRes.status}. Is the API running?`);

    // Probe the Apps Script
    await probeAppsScript(parsedUrl.toString(), secret.trim());

    const settings: AuthSettings = {
      mainKey: mainKey.trim(),
      appsScriptUrl: parsedUrl.toString(),
      appsScriptSecret: secret.trim(),
    };
    await saveAuth(settings);
    onSaved();
  } catch (e) {
    setError(e instanceof Error ? e.message : String(e));
  } finally {
    setBusy(false);
  }
}
```

- [ ] **Step 5: Rebuild frontend and re-deploy**

```bash
cd frontend && npm run build
firebase deploy --only hosting
```

- [ ] **Step 6: Test Setup Wizard on-device with a wrong main key**

Open the app → Settings → Reset auth → re-enter. Try a wrong main key. Expected: "Main API key rejected" error. Enter the correct key. Expected: both probes pass, redirects to `/treatment`.

- [ ] **Step 7: Commit**

```bash
git add firebase.json frontend/src/auth/SetupWizard.tsx
git commit -m "feat: /api/** Firebase rewrite live; SetupWizard probes main key"
```

---

### Task 14: `cloudRun.ts` fetch wrapper

**Files:**
- Create: `frontend/src/api/cloudRun.ts`

- [ ] **Step 1: Create `frontend/src/api/cloudRun.ts`**

```ts
import type { AuthSettings } from '../auth/storage';

export class CloudRunError extends Error {
  constructor(
    public code: 'unauthorized' | 'network' | 'bad_data' | 'server',
    message: string,
  ) {
    super(message);
    this.name = 'CloudRunError';
  }
}

export async function cloudGet<T>(
  auth: AuthSettings,
  path: string,
  params?: Record<string, string>,
): Promise<T> {
  const url = new URL(path, window.location.origin);
  if (params) {
    Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  }
  let res: Response;
  try {
    res = await fetch(url.toString(), {
      headers: { Authorization: `Bearer ${auth.mainKey}` },
    });
  } catch {
    throw new CloudRunError('network', 'Could not reach the server.');
  }
  if (res.status === 401) {
    throw new CloudRunError('unauthorized', 'Access key rejected.');
  }
  if (!res.ok) {
    throw new CloudRunError('server', `Server error (${res.status}).`);
  }
  let body: unknown;
  try { body = await res.json(); } catch {
    throw new CloudRunError('bad_data', 'Server returned invalid JSON.');
  }
  return body as T;
}
```

- [ ] **Step 2: Verify build**

```bash
cd frontend && npm run build
```

Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/api/cloudRun.ts
git commit -m "feat: cloudRun.ts — Bearer-auth fetch wrapper for /api/* routes"
```

---

### Task 15: Port BloodTests frontend route

**Files:**
- Create: `frontend/src/routes/BloodTests/schemas.ts` + `schemas.test.ts`
- Create: `frontend/src/routes/BloodTests/markers.ts` + `markers.test.ts`
- Create: `frontend/src/routes/BloodTests/lib/queryFilter.ts` + `queryFilter.test.ts`
- Create: `frontend/src/routes/BloodTests/lib/scorecard.ts` + `scorecard.test.ts`
- Create: `frontend/src/routes/BloodTests/components/FilterBar.tsx`
- Create: `frontend/src/routes/BloodTests/components/Scorecard.tsx`
- Create: `frontend/src/routes/BloodTests/components/ScorecardTile.tsx`
- Create: `frontend/src/routes/BloodTests/components/TrendChart.tsx`
- Modify: `frontend/src/routes/BloodTests/index.tsx` (replaces placeholder stub)

- [ ] **Step 1: Copy pure modules verbatim**

```bash
# Pure modules port verbatim — only import paths update
mkdir -p frontend/src/routes/BloodTests/lib frontend/src/routes/BloodTests/components

cp dashboard/src/schemas.ts           frontend/src/routes/BloodTests/schemas.ts
cp dashboard/src/schemas.test.ts      frontend/src/routes/BloodTests/schemas.test.ts
cp dashboard/src/markers.ts           frontend/src/routes/BloodTests/markers.ts
cp dashboard/src/markers.test.ts      frontend/src/routes/BloodTests/markers.test.ts
cp dashboard/src/lib/queryFilter.ts   frontend/src/routes/BloodTests/lib/queryFilter.ts
cp dashboard/src/lib/queryFilter.test.ts frontend/src/routes/BloodTests/lib/queryFilter.test.ts
cp dashboard/src/lib/scorecard.ts     frontend/src/routes/BloodTests/lib/scorecard.ts
cp dashboard/src/lib/scorecard.test.ts frontend/src/routes/BloodTests/lib/scorecard.test.ts
cp dashboard/src/components/FilterBar.tsx    frontend/src/routes/BloodTests/components/FilterBar.tsx
cp dashboard/src/components/Scorecard.tsx    frontend/src/routes/BloodTests/components/Scorecard.tsx
cp dashboard/src/components/ScorecardTile.tsx frontend/src/routes/BloodTests/components/ScorecardTile.tsx
cp dashboard/src/components/TrendChart.tsx   frontend/src/routes/BloodTests/components/TrendChart.tsx
```

- [ ] **Step 2: Fix import paths in copied files**

The copied files use imports like `'../schemas'`, `'./queryFilter'`, `'../lib/scorecard'`. These still resolve correctly relative to their new location. Run a quick sanity check:

```bash
grep -rn "from '\.\." frontend/src/routes/BloodTests/ | grep -v node_modules
```

Confirm no import escapes `frontend/src/routes/BloodTests/` (i.e., no `../../` paths). There should be none in these pure modules.

- [ ] **Step 3: Run the ported tests**

```bash
cd frontend && npm test
```

Expected: sessionId (5) + BloodTests pure modules (schemas, markers, queryFilter, scorecard) = ~30 total tests pass. 0 failures.

- [ ] **Step 4: Create `frontend/src/routes/BloodTests/api.ts`**

Replaces `dashboard/src/api.ts`. Uses `cloudGet` instead of raw fetch + localStorage key.

```ts
import { cloudGet, CloudRunError } from '../../api/cloudRun';
import type { AuthSettings } from '../../auth/storage';
import { ApiResponseSchema, type ApiResponse } from './schemas';

export { CloudRunError as ApiError };

export async function fetchAll(auth: AuthSettings): Promise<ApiResponse> {
  const data = await cloudGet<unknown>(auth, '/api/blood-tests');
  const parsed = ApiResponseSchema.safeParse(data);
  if (!parsed.success) {
    throw new CloudRunError('bad_data', 'Response did not match the expected shape.');
  }
  return parsed.data;
}
```

- [ ] **Step 5: Create `frontend/src/routes/BloodTests/index.tsx`**

Strips the key-entry/state-machine from `dashboard/src/App.tsx` and `dashboard/src/screens/Dashboard.tsx`. Reads auth from `getAuth()`, fetches once on mount, renders the existing Dashboard component.

```tsx
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { getAuth } from '../../auth/storage';
import { fetchAll, ApiError } from './api';
import type { BloodTestRow } from './schemas';
import { useMemo } from 'react';
import { filterRows } from './lib/queryFilter';
import { FilterBar, type FilterState } from './components/FilterBar';
import { Scorecard } from './components/Scorecard';
import { TrendChart } from './components/TrendChart';

type State =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; rows: BloodTestRow[] };

type Tab = 'scorecard' | 'trend';

function ResultsTable({ rows }: { rows: BloodTestRow[] }) {
  if (rows.length === 0) return null;
  const sorted = [...rows].sort((a, b) => b.datetime.localeCompare(a.datetime));
  return (
    <table className="m-4 w-[calc(100%-2rem)] text-left text-sm">
      <thead className="text-xs uppercase text-slate-400">
        <tr>
          <th className="py-1 pr-4">Date</th>
          <th className="py-1 pr-4">Value</th>
          <th className="py-1 pr-4">Range</th>
          <th className="py-1 pr-4">Flag</th>
          <th className="py-1 pr-4">Timing</th>
          <th className="py-1">Note</th>
        </tr>
      </thead>
      <tbody className="text-slate-300">
        {sorted.map((r) => {
          const flag =
            r.qualitative || r.ref_low == null || r.ref_high == null
              ? null
              : r.value >= r.ref_low && r.value <= r.ref_high ? 'in' : 'out';
          return (
            <tr key={`${r.marker}-${r.lab_id}`} className="border-t border-slate-800">
              <td className="py-1 pr-4">{r.datetime.slice(0, 16).replace('T', ' ')}</td>
              <td className="py-1 pr-4">{r.qualitative ? r.unit : `${r.value} ${r.unit}`}</td>
              <td className="py-1 pr-4">
                {r.ref_low != null && r.ref_high != null ? `${r.ref_low}–${r.ref_high}` : '—'}
              </td>
              <td className={`py-1 pr-4 ${flag === 'out' ? 'text-red-400' : flag === 'in' ? 'text-emerald-400' : ''}`}>
                {flag ?? '—'}
              </td>
              <td className="py-1 pr-4">{r.timing || '—'}</td>
              <td className="py-1">{r.note || '—'}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

function Dashboard({ rows }: { rows: BloodTestRow[] }) {
  const markers = useMemo(() => [...new Set(rows.map((r) => r.marker))].sort(), [rows]);
  const [tab, setTab] = useState<Tab>('scorecard');
  const [filter, setFilter] = useState<FilterState>({
    phases: ['home-hd'],
    from: '',
    to: '',
    granularity: 'month',
    marker: markers[0] ?? '',
  });

  const scoped = useMemo(
    () => filterRows(rows, { phase: filter.phases, from: filter.from || undefined, to: filter.to || undefined }),
    [rows, filter.phases, filter.from, filter.to],
  );
  const trendRows = useMemo(() => scoped.filter((r) => r.marker === filter.marker), [scoped, filter.marker]);

  return (
    <div className="min-h-screen bg-slate-900 text-slate-100">
      <FilterBar filter={filter} markers={markers} onChange={setFilter} />
      <div className="flex gap-2 border-b border-slate-700 bg-slate-800 px-3">
        {(['scorecard', 'trend'] as Tab[]).map((t) => (
          <button key={t} type="button" onClick={() => setTab(t)}
            className={`px-3 py-2 text-sm capitalize ${tab === t ? 'border-b-2 border-cyan-400 text-cyan-300' : 'text-slate-400'}`}>
            {t}
          </button>
        ))}
      </div>
      {tab === 'scorecard' ? (
        <Scorecard rows={scoped} onSelectMarker={(marker) => { setFilter((f) => ({ ...f, marker })); setTab('trend'); }} />
      ) : (
        <>
          <TrendChart marker={filter.marker} rows={trendRows} />
          <ResultsTable rows={trendRows} />
        </>
      )}
    </div>
  );
}

export default function BloodTests() {
  const navigate = useNavigate();
  const [state, setState] = useState<State>({ status: 'loading' });

  useEffect(() => {
    getAuth().then(async (auth) => {
      if (!auth) { navigate('/setup', { replace: true }); return; }
      try {
        const { rows } = await fetchAll(auth);
        setState({ status: 'ready', rows });
      } catch (e) {
        if (e instanceof ApiError && e.code === 'unauthorized') {
          navigate('/setup', { replace: true, state: { message: 'Access key rejected — please re-enter.' } });
        } else {
          setState({ status: 'error', message: e instanceof Error ? e.message : 'Unknown error.' });
        }
      }
    }).catch(() => navigate('/setup', { replace: true }));
  }, [navigate]);

  if (state.status === 'loading') {
    return <div className="min-h-screen bg-slate-900 p-8 text-slate-400">Loading…</div>;
  }
  if (state.status === 'error') {
    return (
      <div className="min-h-screen bg-slate-900 p-8 text-center">
        <p className="mb-4 text-red-400">{state.message}</p>
        <button type="button" onClick={() => window.location.reload()}
          className="rounded bg-cyan-600 px-4 py-2 font-medium text-white hover:bg-cyan-500">
          Retry
        </button>
      </div>
    );
  }
  return <Dashboard rows={state.rows} />;
}
```

- [ ] **Step 6: Run all tests**

```bash
cd frontend && npm test
```

Expected: all tests pass (sessionId + BloodTests pure modules).

- [ ] **Step 7: Verify build**

```bash
cd frontend && npm run build
```

Expected: exits 0. Check `dist/assets/` contains separate `blood-tests-*.js` and `recharts-*.js` chunks.

- [ ] **Step 8: Deploy and acceptance test**

```bash
firebase deploy --only hosting
```

On device: navigate to the Tests tab. Expected: FilterBar renders, Scorecard shows markers, switching to Trend renders a chart for a selected marker. Spot-check a known value — e.g., latest `urea` in `home-hd` phase should match `blood_tests.csv`.

- [ ] **Step 9: Commit**

```bash
git add frontend/src/routes/BloodTests/ frontend/src/api/cloudRun.ts
git commit -m "feat: BloodTests route — Scorecard + Trend chart live on unified app"
```

---

### Task 16: Phase 3 decommission + cleanup

Do this only after both Phase 1 and Phase 2 have been running for ~4 weeks with no regressions.

**Files:**
- Delete: `pwa/` (directory)
- Delete: `dashboard/` (directory)
- Modify: `package.json` (root — remove dashboard-specific devDeps like `wrangler`)
- Modify: `frontend/package.json` (remove `wrangler`)
- Rename: local directory `treatment_tracker` → `homehd`

- [ ] **Step 1: Decommission Cloudflare Pages projects**

1. Log into Cloudflare dashboard → Workers & Pages.
2. Select `treatment-tracker` → Settings → Delete project. Confirm.
3. Select `treatment-dashboard` → Settings → Delete project. Confirm.

- [ ] **Step 2: Remove wrangler and dashboard-only artifacts**

```bash
cd frontend && npm uninstall wrangler
```

Remove from `frontend/package.json` devDependencies: `wrangler`, `@cloudflare/workers-types` (if still present from the dashboard copy).

- [ ] **Step 3: Delete the old app directories**

Git history preserves them — this is a safe delete.

```bash
git rm -r pwa/ dashboard/
git commit -m "chore: remove pwa/ and dashboard/ — unified app is the source of truth"
```

- [ ] **Step 4: Rename the local directory**

```bash
# From the parent directory:
mv /Users/ntg/Documents/Personal_Projects/treatment_tracker \
   /Users/ntg/Documents/Personal_Projects/homehd
```

Update any shell aliases or bookmarks accordingly.

- [ ] **Step 5: Rename the GitHub remote**

On GitHub: repository Settings → General → Repository name → rename to `homehd`.

Then update the local remote:

```bash
cd /Users/ntg/Documents/Personal_Projects/homehd
git remote set-url origin https://github.com/<username>/homehd.git
git push origin --all   # confirm connection works
```

- [ ] **Step 6: Final commit**

```bash
git add package.json frontend/package.json
git commit -m "chore: Phase 3 cleanup — remove Cloudflare artifacts, repo renamed to homehd"
```

---

## Deploy reference (post-migration)

**Rebuild blood-test data after monthly CSV update:**
```bash
# From repo root (homehd/):
npm run build-data
cd api && npm run build
gcloud run deploy homehd-api --source . \
  --region=europe-west2 --allow-unauthenticated \
  --set-secrets=MAIN_API_KEY=main-api-key:latest \
  --min-instances=0 --max-instances=1 --memory=256Mi --concurrency=20 \
  --project=homehd-personal
```

**Deploy frontend changes:**
```bash
cd frontend && npm run build
firebase deploy --only hosting
```

**Rollback:**
```bash
# Frontend
firebase hosting:rollback

# API
gcloud run services update-traffic homehd-api \
  --to-revisions=<previous-revision>=100 \
  --region=europe-west2 --project=homehd-personal
```

