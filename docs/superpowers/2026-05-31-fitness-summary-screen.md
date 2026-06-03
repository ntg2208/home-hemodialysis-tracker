# Fitness summary screen — pipeline verification with latest values

Combined spec + implementation plan. Replaces the placeholder `routes/Fitness/index.tsx`
("coming soon") with a screen that confirms the Phase 6 ingest pipeline is working and
shows the latest reading per metric. Backend gains one read endpoint.

## Goal

Primary purpose: **verify the daily Fitbit/Google Health → GCS pipeline is landing data
correctly**, at a glance. Secondary: surface the most-recent value per metric. This is the
first piece of fitness UI; it is intentionally a status/summary screen, not a trend dashboard
(charts stay deferred until weeks of data accumulate).

Scope chosen (2026-05-31): **health status + latest values.** Per type: last-synced date,
record count, date range, OK/stale status; plus a "latest readings" card with the most recent
value per metric.

## Design decisions (from discussion)

- **Approach A — on-demand server-side aggregation.** New `GET /api/fitness/summary` reads
  GCS each request and returns small JSON. No precomputed `summary.json` (rejected: couples the
  sync path, premature), no dates-only (rejected: under-delivers on chosen scope), no caching
  (YAGNI at this access frequency).
- **Never download the 43 MB heart-rate blob on read.** Heart-rate appears only in the per-type
  status row (count + size), never in "latest readings" (a single instantaneous HR is
  meaningless; resting HR covers the HR signal). Its count comes from a byte-range read of the
  `count` field, its size from GCS object metadata — no full download.
- **Filenames encode date ranges** (`{start}_to_{end}.json`) → first/last date and "which file
  is newest" are derived from object listing, no download.
- **Per-type extraction is isolated** — one unreadable/unmapped type renders as "—", doesn't
  fail the whole screen (same philosophy as `runSync`'s per-type try/catch).

## Repo facts (verified 2026-05-31)

- Backend: `api/src/handlers/fitness.ts` (Hono). Existing routes: `GET /api/fitness`
  (returns `{ok, types}`), `POST /api/fitness/sync`. GCS helpers in `api/src/lib/gcs.ts`
  (`readSyncState`, `dataTypePath`, plus we'll add list/read/range helpers). `SYNC_TYPES`
  (9) + `SYNC_TYPE_STRATEGY` in `api/src/lib/googleHealth.ts`.
- Cloud Run service `homehd-api`, 512 MiB, behind Firebase `/api/**` rewrite at
  `homehd.web.app`. Auth: `Authorization: Bearer <MAIN_API_KEY>`.
- Frontend: lazy routes wired in `App.tsx` + `components/AppShell.tsx` nav. `/fitness` route
  already exists → `routes/Fitness/index.tsx` (currently a one-line placeholder).
- API client: `api/cloudRun.ts` — `cloudGet(auth, path, params)` / `cloudPost(auth, path, body)`,
  typed `CloudRunError` (`network|unauthorized|server|bad_data`), retries idempotent GETs.
  `getAuth()` from `auth/storage.ts` yields `{ mainKey }`. BloodTests is the reference screen
  for loading/error/empty states.

### GCS stored-file shapes (per ingest wrapper)

- **list types** (8 of 9): `{ fetched_at, start, end, count, data: [ dataPoint, … ] }`, where
  each `dataPoint` has a type-specific sub-object (e.g. `{ dataSource, dailyRestingHeartRate: {…} }`).
- **dailyRollUp** (steps only): `{ fetched_at, start, end, data: { rollupDataPoints: [ … ] } }` —
  **no top-level `count`**, `data` is an object not an array.
- Multiple files per type accumulate (one per sync range; the 365-day seed wrote 5 step chunks).
  Summary must aggregate across all files of a type.

### Data shapes for "latest value" — VERIFIED against live files 2026-05-31

Each dataPoint nests its payload under a type-specific key. **Arrays are NOT time-sorted** —
`extractLatest` must scan for the max date/sampleTime, never take `data[-1]`. Card = appears in
the "latest readings" card; status-only = per-type table count only.

| type | card? | key | date path | value |
|---|---|---|---|---|
| `daily-resting-heart-rate` | ✅ | `dailyRestingHeartRate` | `.date` | `.beatsPerMinute` (string) bpm |
| `steps` | ✅ | `rollupDataPoints[]` | `.civilStartTime.date` | `.steps.countSum` (string) |
| `sleep` | ✅ | `sleep` | `.interval.endTime` (RFC3339) | `.summary.minutesAsleep` + `stagesSummary[DEEP].minutes` |
| `daily-heart-rate-variability` | ✅ | `dailyHeartRateVariability` | `.date` | `.averageHeartRateVariabilityMilliseconds` (num) ms |
| `respiratory-rate-sleep-summary` | ✅ | `respiratoryRateSleepSummary` | `.sampleTime.civilTime.date` | `.deepSleepStats.breathsPerMinute` (num) /min |
| `daily-sleep-temperature-derivations` | ✅ | `dailySleepTemperatureDerivations` | `.date` | `.nightlyTemperatureCelsius` (num) °C — **baseline is `"NaN"` until 30d; show absolute, no Δ yet** |
| `oxygen-saturation` | ✅ | `oxygenSaturation` | `.sampleTime.civilTime.date` | `.percentage` (num) % — latest sample, label "(latest sample)" |
| `heart-rate-variability` (raw) | status-only | `heartRateVariability` | `.sampleTime.civilTime.date` | redundant w/ daily HRV |
| `heart-rate` | status-only | — | — | range-read count only, never parsed |

**`"NaN"` guard:** temp baseline/stddev fields arrive as the JSON string `"NaN"`; treat non-finite
numeric strings as missing. **SpO2 caveat:** a single latest sample is noisy (saw 90.1%); label it
"(latest sample)" so it's not read as a daily figure. Both are acceptable for a verification screen.

## Backend — `GET /api/fitness/summary`

Bearer-authed, mounted alongside `POST /sync` in `fitness.ts`. Response:

```jsonc
{
  "ok": true,
  "generated_at": "2026-05-31T…Z",
  "types": [
    { "type": "daily-resting-heart-rate", "last_synced": "2026-05-30",
      "count": 30, "first_date": "2026-05-01", "last_date": "2026-05-30",
      "stale": false,
      "latest": { "label": "Resting HR", "value": "83", "unit": "bpm", "at": "2026-05-30" } }
    // … one per type; heart-rate has latest: null
  ],
  "totals": { "types": 9, "healthy": 9, "stale": 0, "bytes": 45872... }
}
```

- `stale` = `last_synced` is null or older than 2 days before today (UTC). Daily job keeps it at yesterday.
- **Aggregation per type:** list GCS objects under `raw/{type}/`; derive `first_date`/`last_date`
  from filenames; pick the newest file (max end) for the latest value; sum `count` across files.
- **Cost rules:** sparse types — download + parse each file (all small). `steps` — parse (tiny,
  no count field → use `rollupDataPoints.length`). `heart-rate` — do **not** download: `count`
  via byte-range read of each file's leading bytes (`"count":<n>` lives before `data`), `bytes`
  from object metadata, `latest: null`.
- **Per-type isolation:** wrap each type's aggregation in try/catch; on failure emit
  `{ type, error }` (frontend shows "—"), never throw the whole request.
- **New `gcs.ts` helpers:** `listFiles(prefix)` (names + sizes), `readJsonAt(path)`,
  `readCountPrefix(path)` (range GET first ~512 bytes, regex `"count":(\d+)`).
- **Extractors are pure functions** in a new `api/src/lib/fitnessSummary.ts`:
  `extractLatest(type, fileJson) → { value, unit, at } | null` and
  `countOf(type, fileJson) → number`, unit-tested with fixtures. This is the only nontrivial
  logic; the handler stays thin.

## Frontend — `routes/Fitness/index.tsx`

Replace placeholder. On mount: `getAuth()` → `cloudGet<Summary>(auth, '/api/fitness/summary')`.

- **States:** loading spinner; `CloudRunError` → message by code (reuse BloodTests pattern);
  empty (no files yet) → "No fitness data synced yet."
- **Layout (matches the approved mockup):**
  - Header: title, last-sync line with ✅/⚠️ and "N/9 types healthy", **"Sync now"** button.
  - "Latest readings" card: one row per metric with a value (skips types whose `latest` is null).
  - Per-type status table: type · count · through-date · ✅/⚠️ (stale).
  - Footer: total bytes stored.
- **"Sync now":** `cloudPost(auth, '/api/fitness/sync')`, disabled+spinner while running, then
  refetch the summary. Surfaces the per-type `{ status }` from the sync response if any errored.
- Use existing lucide icons + Tailwind classes consistent with other screens.

## Data flow

`Fitness mount → cloudGet /api/fitness/summary → handler: readSyncState + per-type (list files →
newest-file parse / heart-rate range-read) → aggregate → small JSON → render`. "Sync now":
`cloudPost /api/fitness/sync → refetch summary`.

## Error handling

- Backend: per-type try/catch (one bad type → `{error}`); top-level try/catch → `{ok:false,error}` 500.
- Frontend: `CloudRunError` codes → friendly messages; types with `error` render "—" in the table.

## Testing

- Unit-test `extractLatest` + `countOf` per type with small fixture JSON (one fixture per type,
  including the steps `rollupDataPoints` shape and a list-type shape). Pure functions, no GCP.
- Unit-test `stale` boundary (null, exactly 2 days, older).
- Manual: load `/fitness` on device against live data; hit "Sync now"; confirm counts match
  `gcloud storage` reality.

## Implementation plan (ordered)

0. **Verify live shapes.** `gcloud storage cat` one newest file per type; confirm the table above,
   especially `oxygen-saturation` (uninspected) and the exact `respiratory-rate` / HRV wrapper keys.
   Adjust the extractor table before coding.
1. **gcs.ts helpers** — `listFiles`, `readJsonAt`, `readCountPrefix` (+ unit-ish coverage where practical).
2. **Extractors** (`fitnessSummary.ts` or in `googleHealth.ts`) — `extractLatest`, `countOf`,
   `isStale`; unit tests with fixtures. TDD.
3. **`GET /api/fitness/summary` handler** — aggregation + per-type isolation; wire into the bearer router.
4. **Deploy** `homehd-api` (inherit secrets — no `--set-secrets`); smoke-test the endpoint with curl.
5. **Frontend Fitness screen** — fetch, states, latest-readings card, status table, Sync-now.
6. **Build + deploy frontend** (Firebase Hosting); on-device check; confirm counts vs GCS.

## Open / risks

- `oxygen-saturation` shape unknown — task 0 resolves before mapping; if odd, ship it as count-only
  (no latest) rather than block.
- Range-read `"count"` assumes the field precedes `data` in the serialized JSON — true for the
  current `uploadJson` wrapper (object key order preserved). If a file predates the wrapper, fall
  back to size-only for that file.
- Multiple-files-per-type aggregation is the only fiddly part; keep it in one well-tested function.
