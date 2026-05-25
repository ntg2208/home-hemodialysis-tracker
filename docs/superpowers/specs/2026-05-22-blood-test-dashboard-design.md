# Blood Test Dashboard — Design

**Date:** 2026-05-22
**Status:** **Superseded by `2026-05-25-homehd-unified-app-design.md`** — the dashboard ships as a tab inside the unified app. Code produced under this spec (and its plan) is preserved and ported, not rewritten. Kept here as design history.
**Source design:** `~/Project_ideas/Home HD Knowledge Base and Tracking System.md` (section 3 "Monthly Blood Test Analytics", and Update Log entries 2026-05-12, 2026-05-13, 2026-05-22)

A personal analytics dashboard for monthly blood test results, plus a query endpoint. The backfill parser (`scripts/pkb_backfill/parse_pkb.py`) and dataset (`blood_tests.csv`, 2391 rows) already exist and are **out of scope here** — this spec covers only the dashboard app and its endpoint.

## Goal

Make the blood test history queryable and monitorable: see current marker status at a glance, drill into any marker's trend over time, and pull the data programmatically. The data lives independently of the BP tracker's Google Sheet — the clinical team does not read it, so the Sheet write-back constraint that shaped the PWA does not apply here.

## Key decisions (from brainstorming, 2026-05-22)

- **Right-sized working tool**, not a GCP-skills exercise — so no BigQuery, no Cloud Run, no data warehouse. 2391 rows growing ~40/month is in-memory data.
- **Offline viewing is no longer a hard requirement** (the original section-3 constraint was cost-driven; cost is now a non-issue). An always-online dashboard is acceptable. A static site is offline-capable for free anyway.
- **Lives as a subfolder in the `treatment_tracker` repo** — full restructure into `pwa/` + `dashboard/`.
- **v1 = scorecard + trend + endpoint.** The multi-marker compare view is v2.
- **Auth = single shared access key.** The endpoint is the only data gateway for both the dashboard and any notebooks.

## Non-goals

Deferred to v2:
- **Compare view** — multiple markers via small multiples or normalized-within-reference-range overlay.

Out of scope entirely (separate future projects):
- NxStage error knowledge base, inventory tracking.
- Monthly-entry tooling (a Part-A/B parser or PWA "Add blood test" screen) — the dashboard consumes whatever is in `blood_tests.csv`; how rows get into the CSV is a separate concern.
- Writing blood test data back to the Google Sheet.

## Stack

- **Vite** + **React 18** + **TypeScript** (strict mode)
- **Tailwind CSS** for styling
- **Recharts** for the trend chart
- **zod** for parsing the endpoint response
- No router — two app states (key entry, dashboard) handled with `useState`.
- No global state library, no IndexedDB — `localStorage` holds only the access key.

## Repo layout

Full restructure of `~/Documents/Personal_Projects/treatment_tracker/` into two sibling apps. The existing PWA files move into `pwa/` verbatim; the dashboard is new.

```
treatment_tracker/
├── pwa/                          # all current PWA files move here unchanged
│   ├── src/  public/  index.html  package.json  vite.config.ts  …
├── dashboard/                    # new — second Vite app
│   ├── src/
│   │   ├── main.tsx
│   │   ├── App.tsx               # key-entry vs dashboard state
│   │   ├── api.ts                # GET /api/blood-tests with the access key
│   │   ├── storage.ts            # localStorage: access key only
│   │   ├── schemas.ts            # zod schema for a blood_tests row
│   │   ├── filters.ts            # pure: client-side phase/date/marker filtering
│   │   ├── markers.ts            # marker→panel map, display names
│   │   ├── screens/
│   │   │   ├── KeyEntry.tsx
│   │   │   └── Dashboard.tsx     # filter bar + Scorecard/Trend tabs
│   │   └── components/
│   │       ├── FilterBar.tsx
│   │       ├── Scorecard.tsx     # panel-grouped marker tiles
│   │       ├── ScorecardTile.tsx
│   │       └── TrendChart.tsx    # Recharts line chart + results table
│   ├── functions/api/
│   │   └── blood-tests.ts        # Cloudflare Pages Function (the endpoint)
│   ├── scripts/
│   │   └── build-data.ts         # CSV → JSON, runs as npm prebuild hook
│   ├── data/
│   │   └── blood_tests.json      # generated, gitignored, bundled into the Function
│   ├── index.html  package.json  vite.config.ts  tsconfig.json  tailwind.config.ts  …
├── scripts/pkb_backfill/         # unchanged (parser, blood_tests.csv, pastes/)
├── docs/superpowers/             # specs/ + plans/ stay at repo root
└── README.md                     # updated: two apps, two deploy commands
```

Two independent Cloudflare Pages projects: `treatment-tracker` (PWA, unchanged) and `treatment-dashboard` (new). No shared code package — the dashboard is self-contained; duplicating a ~10-line localStorage helper is cheaper than a shared package.

**Gitignore additions** (the open-source-release safeguard — these files hold personal health data and are currently untracked but not explicitly ignored):
```
dashboard/data/
scripts/pkb_backfill/blood_tests.csv
scripts/pkb_backfill/pastes/
scripts/pkb_backfill/*.txt
```

## Data model

`blood_tests.csv` — one row per `(marker, datetime)` reading, 12 columns:

`marker, datetime, value, unit, ref_low, ref_high, timing, note, source, lab_id, phase, created_at`

- `marker` — canonical snake_case name (controlled vocab; 51 markers).
- `datetime` — ISO; sorts/compares lexically.
- `value` — numeric. Qualitative results (serology/pathology) are stored as `value=0.0` with `unit=<result text>`.
- `ref_low` / `ref_high` — per-row (ranges drift over years); may be blank (`mch`/`mchc`/`mcv`, open-ended `egfr`).
- `timing` — `pre` / `post` / blank; set only for the 6 dialysis-cleared markers' home-hd pairs.
- `phase` — `admission` (≤2023-10-15) / `in-center-hd` (2023-10-16→2026-01-31) / `home-hd` (2026-02-01→).
- `lab_id` — natural dedupe key. `(marker, datetime)` is **not** unique (pre/post draws can share a lab-receipt minute); `(marker, lab_id)` is.

## Data pipeline

```
blood_tests.csv ──build-data.ts (npm prebuild)──▶ dashboard/data/blood_tests.json
                                                          │
                                                          └─ bundled into ──▶ functions/api/blood-tests.ts
                                                                                      │
                          dashboard React app ──fetch('/api/blood-tests', +key)───────┘
```

- `build-data.ts` (Node/TS, no Python dependency in the dashboard) reads the CSV, drops empty rows (the PWA's `stripEmptyRows` lesson), coerces numeric fields, sorts by `datetime`, derives a `qualitative` boolean (true when the row carried a non-numeric result), and writes a typed JSON array.
- Runs automatically as an npm `prebuild` hook, so `npm run build` always reflects the current CSV.
- The JSON (~350 KB for 2391 rows; ~40 rows/month growth = decades of headroom under the 1 MB compressed Worker bundle limit) is **baked into the Pages Function bundle** — it is not a publicly-readable static file. The dashboard React bundle contains no data; everything comes through the authed endpoint.
- Monthly workflow is unchanged: edit `blood_tests.csv` → `npm run build` → deploy.

## Endpoint contract — `GET /api/blood-tests`

A single Cloudflare Pages Function, `GET` only.

**Auth:** shared key stored as a Cloudflare Pages **Secret** (`DASHBOARD_KEY` — encrypted at rest, not a plain env var). Client sends `Authorization: Bearer <key>`. No CORS headers in v1 — the dashboard calls it same-origin, and notebooks are not browsers.

**Query params** (none → return all rows; that is the dashboard's bulk load):

| Param | Form | Behaviour |
|---|---|---|
| `marker` | `creatinine` or `creatinine,urea` | filter to these canonical markers |
| `from` / `to` | `YYYY-MM` *or* `YYYY-MM-DD` | inclusive bounds, matched on the `datetime` prefix at the param's granularity — `to=2026-04` keeps all of April. Covers all five query types: by date, by month, date range, month range, single day/month (`from`==`to`) |
| `phase` | `home-hd` (comma-separated allowed) | filter by phase |

**Response:** `200` with `{ "count": <n>, "rows": [ <row>, … ] }`.

**Errors:** `401` missing/wrong key · `400` malformed `from`/`to` or unknown `phase` · `405` non-GET · all with JSON body `{ "error": "<message>" }`. An unknown `marker` is not an error — it simply yields zero rows.

*Future work:* `from=` already enables incremental refresh (fetch only rows since last sync). v1 does not ship it, but the API shape will not have to change.

## Dashboard UI

Two app states in `App.tsx`:

1. **Key entry** — shown on first load when `localStorage` has no key (PWA Setup-style, one field + save). On save, the key is stored and the dashboard attempts its data load.
2. **Dashboard** — on load with a stored key, one bulk `GET /api/blood-tests` (no params) fetches all rows into memory, zod-validated. All filtering is client-side from there. A `401` clears the stored key and returns to key entry — no separate probe request.

**Filter bar** (shared, drives both tabs):
- **Phase** selector — defaults to `home-hd`; switchable to `in-center-hd`, `admission`, or all.
- **Date/month range** — `from`/`to` pickers with a month-vs-date granularity toggle. Defaults to the full range of the selected phase.
- **Marker** selector — selects the marker shown in the Trend tab.

**Tab 1 — Scorecard:** markers grouped into panels (Renal, Liver, Bone, Haematology, Other) via a static `marker→panel` map in `markers.ts`; unmapped markers fall into Other. Each marker is a tile showing the latest value + unit, the delta vs the previous reading (↑/↓/→), and in/out-of-range color — all computed within the current filter scope (phase + date range). Markers with no reference range render with neutral coloring. Clicking a tile sets the Trend marker and switches to the Trend tab.

**Tab 2 — Trend:** one marker, a Recharts line chart:
- value over time (x = `datetime`, y = `value`),
- reference-range band — stepped `ReferenceArea` segments from per-row `ref_low`/`ref_high` (omitted where blank),
- pre vs post as two series for the 6 dialysis-cleared markers (`timing` set),
- phase-boundary `ReferenceLine`s,
- out-of-range points highlighted,
- `Brush` for date-range zoom.
- A results table below lists the filtered rows (date, value, unit, range, flag, note). Qualitative rows (`qualitative === true`) appear in the table only — never plotted as a misleading `0.0` point.

## Error handling

**Endpoint:** see the errors row in the contract above.

**Dashboard:**
- Bulk fetch network failure → error state with a Retry button.
- `401` → clear the stored key, return to key entry with a "key rejected" message.
- zod validation failure on the response → "data format error" state (the PWA's `schema_mismatch` lesson).
- A filter matching nothing → friendly empty state, not an error.
- Markers with no reference range → trend omits the band, scorecard tile colors neutral.
- Qualitative results → flagged by `build-data.ts`, excluded from the trend line, listed in the table.

## Auth

- One shared key, stored server-side as a Cloudflare Pages **Secret** and client-side in `localStorage` on the device.
- The key is sent only in the `Authorization` header — never in a URL, never logged.
- Wrong/expired key surfaces as a `401`; the dashboard clears local state and re-prompts. Rotating the key means updating the Pages Secret and re-entering it on each device.

## Testing

Light by design (single-user app), mirroring the PWA:
- TypeScript strict mode catches shape errors at compile time; zod catches response drift at runtime.
- Unit tests (Vitest) on the non-obvious pure logic: the endpoint's `from`/`to` date-prefix granularity matching, and the scorecard's delta + in-range computation.
- `npm run build` produces a working `dist/` for both apps.
- Manual acceptance: deploy, enter key, spot-check the scorecard and a trend chart against known values in `blood_tests.csv`.
- **PWA regression check** — after the `pwa/` move, confirm the PWA still builds and deploys (its Cloudflare Pages project is unaffected; only the local build path changes).

## Build & deploy

- `cd dashboard && npm run dev` — local dev (Vite). `prebuild` regenerates `data/blood_tests.json` from the CSV.
- `cd dashboard && npm run build` — static `dist/` + the bundled Function.
- `cd dashboard && npx wrangler pages deploy dist --project-name=treatment-dashboard --branch=main --commit-dirty=true`
- The PWA's deploy command gains a `pwa/` path prefix; README updated for both apps.
- One-time: create the `treatment-dashboard` Pages project with `--production-branch=main` (matching the local git branch, so the deploy `--branch` unambiguously hits Production — avoids the production/preview mismatch that bit the PWA on 2026-05-15), and set the `DASHBOARD_KEY` secret.

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| The `pwa/` move breaks the live PWA's build/deploy | Move files verbatim; re-run `npm run build` and a deploy from `pwa/`; verify the installed PWA still loads. PWA regression check is an explicit test item. |
| Health-data CSV/JSON committed to the open-source-bound repo | Explicit `.gitignore` entries for `dashboard/data/`, the CSV, and `pastes/`. |
| Baked-in dataset outgrows the Worker bundle limit | ~350 KB now vs 1 MB limit; ~40 rows/month. Decades of headroom. Revisit only if markers-per-event or cadence changes drastically. |
| `(marker, datetime)` collisions (pre/post same minute) render as overlapping points | Trend plots pre/post as separate series keyed off `timing`; `lab_id` distinguishes rows in the table. |
| Access key leaks via URL/logs | Header-only (`Authorization: Bearer`); never query string. |

## Open questions (non-blocking)

- Default date range on first load — full phase history vs last 12 months. Start with full phase history; revisit if the trend chart feels cluttered.
- Whether the Trend tab should allow a quick dual-marker overlay before the full v2 Compare view lands. Deferred — v2 decides.
