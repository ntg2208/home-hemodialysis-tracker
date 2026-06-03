# Home HD — Architecture

Personal health management app for a home haemodialysis patient. Tracks treatment sessions, blood test results, and supply inventory. Mobile-first PWA, single user.

---

## System Overview

```
Browser (PWA)
    │
    ├── /treatment/*   ──POST──►  Apps Script Web App  ──►  Google Sheets
    │                                                         (sessions + readings)
    │
    └── /api/**        ──►  Firebase Hosting rewrite
                                    │
                                    └──►  Cloud Run  homehd-api  (europe-west2)
                                                │
                                                ├── Firestore  (homehd-personal)
                                                │     ├── blood_tests/
                                                │     ├── inventory_stock/
                                                │     ├── inventory_events/
                                                │     ├── inventory_config/
                                                │     └── (fitness, chat, kb — future)
                                                │
                                                └── GCS  (fitness data — ingest only)
```

**Why two backends?** Treatment writes go direct to Apps Script / Google Sheets because the dialysis machine is in use during a session — any cold-start latency on Cloud Run (3–10 s) would cause a missed reading. Apps Script responds in <1 s. Everything else uses Cloud Run.

---

## Infrastructure

| Component | Service | Config |
|---|---|---|
| Frontend hosting | Firebase Hosting | Site: `homehd`, project: `homehd-personal` |
| Public URL | `https://homehd.web.app` | |
| API | Cloud Run | Service: `homehd-api`, region: `europe-west2` |
| Database | Firestore | Native mode, same GCP project |
| Treatment storage | Google Sheets | Via Apps Script Web App |
| File storage | GCS | Bucket `homehd-fitness` (fitness ingest) |
| Deploy — frontend | `firebase deploy --only hosting` | Builds from `frontend/dist` |
| Deploy — API | `gcloud run deploy homehd-api --source api` | Docker multi-stage build |

**Firebase Hosting rewrites** (`firebase.json`):
- `/api/**` → Cloud Run `homehd-api`
- `**` → `/index.html` (SPA fallback)

---

## Repo Structure

```
treatment_tracker/          ← monorepo root (npm workspaces)
├── frontend/               ← Vite + React PWA
│   └── src/
│       ├── api/            ← shared HTTP client (cloudRun.ts)
│       ├── auth/           ← IndexedDB credential storage
│       ├── components/     ← AppShell, ErrorBoundary
│       ├── hooks/
│       └── routes/
│           ├── Treatment/  ← session recording
│           ├── BloodTests/ ← test results dashboard
│           ├── Inventory/  ← supply tracking
│           ├── Fitness/    ← fitness data viewer
│           ├── Chat/       ← RAG chatbot (stub)
│           └── KB/         ← NxStage knowledge base (stub)
├── api/                    ← Hono + Node 20 Cloud Run service
│   └── src/
│       ├── handlers/       ← one file per feature domain
│       ├── schemas/        ← Zod schemas (request + response)
│       ├── lib/            ← firestore, auth, gcs, queryFilter, mergeRows
│       └── data/           ← blood_tests.json (static historical data)
├── apps-script/
│   └── Code.gs             ← treatment write/read backend
├── scripts/                ← one-off data migration utilities
│   ├── build-data.ts       ← CSV → blood_tests.json
│   └── pkb_backfill/       ← PKB paste parser (Python)
└── docs/
    ├── architecture.md     ← this file
    ├── api-reference.md    ← endpoint reference
    └── superpowers/        ← design specs and implementation plans
```

---

## Frontend Architecture

**Stack:** Vite 5, React 18, React Router 6, TypeScript, Tailwind CSS, Vitest

### Entry and routing

`App.tsx` defines a `createBrowserRouter` with two top-level paths:
- `/setup` — unauthenticated `SetupWizard` to save credentials
- `/*` — wrapped in `AuthGuard` + `AppShell`; all feature routes are lazy-loaded chunks

`AuthGuard` checks IndexedDB on mount; redirects to `/setup` if credentials are absent.

`AppShell` renders the bottom nav bar and the `<Outlet>` for child routes.

### Auth / credentials

`frontend/src/auth/storage.ts` — stores `AuthSettings` (three fields) in IndexedDB via `idb`. This survives page reloads and works offline. No service worker intercepts auth; credentials are read per-request.

```ts
interface AuthSettings {
  mainKey: string;           // Bearer token for Cloud Run
  appsScriptUrl: string;     // Apps Script /exec URL
  appsScriptSecret: string;  // Apps Script shared secret
}
```

### HTTP client

`frontend/src/api/cloudRun.ts` — two functions: `cloudGet<T>` and `cloudPost<T>`. Both attach the `Authorization: Bearer <mainKey>` header, throw `CloudRunError` on network failure or non-2xx, and parse JSON. All route-level API modules import these.

Treatment calls are made directly to Apps Script using the raw `fetch` API in `routes/Treatment/api.ts`, bypassing `cloudRun.ts`.

### PWA

Vite PWA plugin (Workbox `generateSW` mode). Service worker precaches all build assets. `sw.js` has `Cache-Control: no-cache` via Firebase Hosting headers to ensure updates propagate immediately.

---

## Route Modules

Each route is a self-contained directory with a consistent internal structure:

```
routes/<Feature>/
├── index.tsx          ← page root, state management, data fetch
├── api.ts             ← typed wrappers over cloudGet/cloudPost
├── schemas.ts         ← Zod schemas for API responses
├── constants.ts       ← static data (e.g. ITEMS list)
├── components/        ← presentational components
└── lib/               ← pure functions + unit tests
```

### Treatment (`/treatment/*`)

Multi-screen flow: Home → PreTreatment → ActiveSession → PostTreatment.

State machine driven: `index.tsx` holds the current screen union type and threads shared state (session ID, auth, consumed supplies) through screen props.

**Write path:** every save calls Apps Script directly (no Cloud Run). Session start calls `save_session`, each reading calls `save_reading`, session end calls `update_session`.

**Inventory side-effects:** PostTreatment fires a Cloud Run `POST /api/inventory/event` (`type: session`) to deduct supplies. This is the only place treatment and inventory concerns intersect.

**Storage:** `routes/Treatment/storage.ts` — persists in-progress session to IndexedDB so a page reload mid-session doesn't lose data.

### Blood Tests (`/blood-tests`)

**Data source:** static JSON (2023 → ~May 2026, ~2 400 rows) merged with Firestore rows at query time. New rows added via `POST /api/blood-tests` are stored in Firestore and returned merged. `mergeRows.ts` deduplicates on `lab_id + marker`.

**Read path:** `GET /api/blood-tests` with optional `marker`, `phase`, `from`, `to` query params → all data loaded once per session, filtered client-side.

**UI:** FilterBar (phase, date range, marker selector) → Scorecard tab (horizontal tiles, starred markers first, sorted by category) → Trend tab (Nivo line chart per marker).

Key pure-function modules:
- `lib/scorecard.ts` — computes `MarkerSummary` (latest, previous, delta, status) per marker
- `lib/chartData.ts` — `toNivoSeries` (deduplicates same-day readings, pre > post priority), `getPointColor`, `getReferenceRange`
- `lib/queryFilter.ts` — client-side row filtering (prefix match on YYYY-MM date bounds)

### Inventory (`/inventory`)

**Data model:** Firestore-backed. Stock levels in `inventory_stock/{code}`, events in `inventory_events/`, active delivery cycle in `inventory_config/cycle`.

**UI flow:**
- Banner shows cycle state (call date, delivery date, order status)
- Stock list with [−]/[+] per item, ordered by needs-ordering first
- Order workflow: stock count → auto-calculated order list (edit boxes) → confirm → stored in cycle
- Delivery: one-tap "Delivered" or "Adjust" modal
- Edit order: `EditOrderModal` for correcting a placed order

Key pure-function module: `lib/stockCalc.ts` — `sessionsRemaining`, `stockStatus`, `needsOrdering`, `orderBoxes`, `sortStock`. All item definitions in `constants.ts` (`ITEMS` array with code, label, unit, boxSize, perSession, targetQty, section, priority).

---

## API Architecture

**Stack:** Node 20, Hono 4, Zod, TypeScript, `@google-cloud/firestore`, `@hono/node-server`

### Structure

`src/index.ts` — mounts all route handlers behind a single `bearerAuth` middleware. Fitness OAuth routes are mounted before the middleware.

```
/api/health               → health check (no auth)
/api/fitness/callback     → OAuth callback (no auth)
/api/blood-tests          → bloodTests handler
/api/inventory            → inventory handler
/api/fitness              → fitness handler
/api/chat                 → chat handler (stub)
/api/kb                   → kb handler (stub)
```

### Handler pattern

Each handler is a `Hono` instance exported as a named const and chained with route methods:

```ts
export const inventory = new Hono()
  .get('/', ...)
  .post('/event', ...)
  ...
```

Every POST/PUT/PATCH route: parse JSON → `safeParse` with Zod schema → operate on Firestore → return `{ ok: true }`. Validation errors return `400` with Zod issue details.

### Auth

`lib/auth.ts` — `bearerAuth` is a Hono middleware that extracts the `Authorization: Bearer <token>` header and compares it to `MAIN_API_KEY` from the environment. Returns `401` if missing or wrong.

`MAIN_API_KEY` is set as a Cloud Run environment variable sourced from Secret Manager at deploy time.

### Firestore

`lib/firestore.ts` — lazy singleton that calls `new Firestore()` once. The Cloud Run service account has Firestore read/write permissions via IAM.

---

## Data Architecture

### Blood tests

Historical data (2023–2026-05) lives as `api/src/data/blood_tests.json` — a build artifact generated by `scripts/build-data.ts` from cleaned CSVs. It is bundled into the Docker image at build time.

New rows from the write API land in Firestore `blood_tests/{lab_id}_{marker}`. The GET handler merges both sources, with Firestore rows taking precedence on key collision.

This hybrid avoids the cost of re-ingesting 2 400 rows into Firestore while keeping new data queryable. The split point is ~May 2026. To consolidate later: run `build-data.ts` including Firestore rows → replace JSON → redeploy.

### Inventory

Fully Firestore-backed. No static data.

```
inventory_stock/{code}          { qty, updated_at }
inventory_events/{autoId}       { type, timestamp, deltas, note }
inventory_config/cycle          { call_date, delivery_date, order,
                                  order_placed_at, delivery_applied_at }
inventory_config/pak            { installed_at }
```

Stock is only ever modified by:
1. `POST /event` (session deduction, manual adjustment, stock count)
2. `POST /apply-delivery` (delivery increment)
3. `PUT /stock` (direct admin edit)

### Treatment

Stored in Google Sheets (two tabs: `sessions`, `readings`). Apps Script provides the only read/write interface. Sheets are the source of truth — no Firestore copy.

The `legacy_view` tab is a denormalised multi-row-per-session layout rebuilt on every write, kept for clinical readability in Sheets.

---

## Auth Model

Two separate auth mechanisms, never mixed:

| Credential | Stored in | Used for | How stored on device |
|---|---|---|---|
| `MAIN_API_KEY` | Cloud Run env / Secret Manager | All `/api/*` routes | IndexedDB (`mainKey`) |
| `appsScriptSecret` | Apps Script `PropertiesService` | Treatment API | IndexedDB (`appsScriptSecret`) |

On first launch, `SetupWizard` prompts for both secrets and saves them to IndexedDB (`homehd-auth` DB, `auth` store). No credentials are stored in code or `.env` files.

---

## Build and Deploy

### Frontend

```bash
cd frontend && npm run build      # tsc -b && vite build → frontend/dist/
firebase deploy --only hosting    # uploads dist/ to Firebase Hosting
```

### API

```bash
gcloud run deploy homehd-api --source api --region europe-west2 --project homehd-personal
```

Uses `api/Dockerfile` — multi-stage: `node:20-slim` builder compiles TypeScript; production stage copies only `dist/` and prod `node_modules`. Static data (`src/data/`) is copied into `dist/data/`.

---

## Known Constraints and Trade-offs

| Constraint | Reason | Implication |
|---|---|---|
| Treatment bypasses Cloud Run | Cold-start risk during live dialysis | Any Treatment-side feature needs to work via Apps Script, not Cloud Run |
| Blood test data split between JSON and Firestore | Historical bulk not worth re-ingesting | Consolidation needed before adding server-side aggregation queries |
| Single `MAIN_API_KEY` for all routes | Single-user app, low risk | No per-feature scoping; a leaked key grants full API access |
| No auth on Apps Script URL | Apps Script web apps can't verify IP; secret-in-body is the only option | URL rotation is the only revocation mechanism |
| `inventory_config/cycle` is a single document | One active cycle per user | Need a new document schema if multi-cycle tracking (e.g. history) is added |
| PAK sessions counted by full collection scan | Small dataset now | Will need a counter or subcollection when event history grows large |
| No offline write queue for Cloud Run | PWA works offline read-only for non-treatment features | Inventory adjustments fail silently offline |

---

## Future Improvement Areas

### Near-term
- **Consolidate blood test data source** — merge static JSON and Firestore rows into a single Firestore collection; update `build-data.ts` to write to Firestore rather than a JSON file. Enables server-side aggregation queries.
- **Offline queue for inventory** — buffer `POST /event` calls in IndexedDB and replay on reconnect (like Treatment's in-progress session persistence).
- **Delivery history paging** — `GET /inventory/deliveries` currently returns all events; add cursor pagination before history grows.

### Medium-term
- **Treatment data in Firestore** — mirror sessions/readings to Firestore on each write for richer querying (trends, BP over time, UF correlation). Apps Script remains source of truth; Cloud Run becomes a read layer.
- **Chat / RAG feature** — `handlers/chat.ts` is stubbed. Architecture would be: GCS for document storage → Vertex AI Embeddings → Firestore vector search or a dedicated vector DB → Gemini for generation.
- **Multi-user / family access** — currently assumes single user. Adding auth would require: Firebase Auth or custom JWTs, per-user Firestore namespacing, and a way to share read access for clinical handovers.
- **Rename repo** — `treatment_tracker` → `homehd` (deferred from Phase 3, gated on 4 weeks of session stability).

### Longer-term
- **Decommission Cloudflare Pages** — original `treatment-tracker.pages.dev` and `treatment-dashboard.pages.dev` projects still exist; remove once all users migrated.
- **Automated blood test ingestion** — PKB (Patient Knows Best) has an export; a scheduled Cloud Run job could pull new results automatically instead of manual paste → CSV → build step.
- **Apps Script → Cloud Run migration for treatment** — once Cloud Run min-instances is viable cost-wise (currently ~$10/month for always-on), cold-start concern disappears and treatment can move to the unified backend.
