# Home HD — API Reference

All Cloud Run endpoints live behind `https://homehd.web.app` (Firebase Hosting rewrites `/api/**` to Cloud Run `homehd-api`, `europe-west2`).

---

## Authentication

### Cloud Run API (`/api/*`)

Every request requires a Bearer token:

```
Authorization: Bearer <MAIN_API_KEY>
```

Key is stored in macOS Keychain as `homehd-main-key`. Retrieve with:

```bash
security find-generic-password -a "$USER" -s "homehd-main-key" -w
```

Returns `401` if the key is missing or wrong.

### Treatment API — Firestore (client-side)

Session and reading data is written directly to Firestore from the PWA using the Firebase JS SDK (bypasses Cloud Run entirely — no cold-start risk during dialysis). The PWA authenticates by exchanging `MAIN_API_KEY` for a Firebase custom token via the token endpoint below.

---

## Treatment API

**Base URL:** `https://homehd.web.app/api/treatment`

Session/reading data: Firestore collections `treatment_sessions/{session_id}` and `treatment_readings/{reading_id}`. All numeric fields stored as numbers (not strings).

### `GET /api/treatment/token`

Mints a short-lived Firebase custom token. Called by the PWA on setup and silently refreshed every 55 minutes.

**Response**
```json
{ "ok": true, "token": "eyJ...", "expires_at": 1748822400000 }
```

| Field | Description |
|---|---|
| `token` | Firebase custom token — pass to `signInWithCustomToken(firebaseAuth, token)` |
| `expires_at` | Unix milliseconds; token expires at 60 min, client refreshes at 55 min |

The token encodes `uid: 'homehd-treatment'`. Firestore security rules allow read/write on `treatment_sessions` and `treatment_readings` only when `request.auth.uid == 'homehd-treatment'`.

---

### `POST /api/treatment/sync-to-sheet`

Reads all Firestore sessions and readings and rebuilds three tabs on the clinical Google Sheet (`sessions`, `readings`, `legacy_view`). Called automatically by Cloud Scheduler every Sunday 08:00 UTC (09:00 BST). Can be triggered manually.

**No request body required.**

**Response**
```json
{
  "ok": true,
  "sessions_written": 11,
  "readings_written": 33,
  "synced_at": "2026-06-01T22:56:41.000Z"
}
```

The `legacy_view` tab is written first (highest clinical value); if that write fails, the raw data tabs are untouched. Requires `TREATMENT_SHEET_ID` env var on Cloud Run (the spreadsheet ID from the Sheet URL).

---

### Firestore data model

**`treatment_sessions/{session_id}`** — one document per dialysis session:

| Field | Type | Description |
|---|---|---|
| `session_id` | string | YYYY-MM-DD (or YYYY-MM-DD-N for same-day collisions) |
| `date` | string | YYYY-MM-DD |
| `pre_weight` | number? | kg |
| `uf_goal` | number? | L |
| `uf_rate` | number? | mL/h |
| `pre_bp_sys` / `pre_bp_dia` / `pre_pulse` | number? | mmHg / bpm |
| `post_weight` / `post_bp_sys` / `post_bp_dia` / `post_pulse` | number? | kg / mmHg / bpm |
| `duration_min` | number? | minutes |
| `dialysate_volume` | number? | L |
| `total_uf` | number? | L |
| `blood_processed` | number? | L |
| `created_at` | string | ISO timestamp |

**`treatment_readings/{reading_id}`** — one document per intra-session reading:

| Field | Type | Description |
|---|---|---|
| `reading_id` | string | `{session_id}-r{seq}` |
| `session_id` | string | Parent session |
| `seq` | number | 1-based order |
| `time` | string | HH:MM |
| `bp_sys` / `bp_dia` / `pulse` | number? | mmHg / bpm |
| `blood_flow` | number? | mL/min |
| `venous_pressure` / `arterial_pressure` | number? | mmHg |
| `note` | string? | Free text |
| `created_at` | string | ISO timestamp |

---

## Fitness API

**Base URL:** `https://homehd.web.app/api/fitness`

Raw data is stored in GCS `gs://homehd-fitness/raw/{type}/{startDate}_to_{endDate}.json`. Sync state at `gs://homehd-fitness/sync_state.json`.

---

### `GET /api/fitness`

Returns the list of synced data types.

**Response** `{ "ok": true, "types": ["steps", "daily-resting-heart-rate", ...] }`

---

### `GET /api/fitness/summary`

Aggregates per-type stats from GCS. Heart-rate count comes from a byte-range read (the 43 MB blob is never fully downloaded).

**Response**
```json
{
  "ok": true,
  "generated_at": "2026-06-01T10:00:00.000Z",
  "types": [
    {
      "type": "daily-resting-heart-rate",
      "last_synced": "2026-05-31",
      "count": 35,
      "first_date": "2026-05-01",
      "last_date": "2026-05-31",
      "stale": false,
      "latest": { "label": "Resting HR", "value": "83", "unit": "bpm", "at": "2026-05-31" },
      "bytes": 1128
    }
  ],
  "totals": { "types": 9, "healthy": 9, "stale": 0, "bytes": 44415331 }
}
```

`stale: true` when `last_synced` is more than 2 days old. Types with fetch errors include an `error` field instead of the normal fields. `latest` is `null` for status-only types (`heart-rate`, `heart-rate-variability`).

---

### `POST /api/fitness/sync`

Pulls new data from the Google Health API into GCS for each type. Incremental — resumes from `sync_state.json`. Per-type isolation: one failing type is recorded as `{ status: 'error' }` without aborting the rest.

| Query param | Default | Description |
|---|---|---|
| `days` | `365` | Backfill window in days if no prior state (max 3650) |
| `type` | all types | Sync only a single type (escape hatch / recovery) |

**Response**
```json
{
  "ok": true,
  "synced": {
    "steps":                    { "from": "2026-06-01", "to": "2026-06-01", "days_covered": 1, "status": "ok" },
    "daily-resting-heart-rate": { "from": "2026-06-01", "to": "2026-06-01", "days_covered": 1, "status": "ok" },
    "heart-rate":               { "status": "error", "error": "fetchList(heart-rate) failed: 429" }
  }
}
```

`ok: false` in the top-level response when any type has `status: 'error'`. Automated daily at 09:00 London via Cloud Scheduler job `homehd-fitness-daily-sync`.

**Synced data types (9 total, ordered sparse → dense):**

| Type | Method | Cadence | Latest value in summary? |
|---|---|---|---|
| `steps` | `dailyRollUp` | 1/day | ✅ step count |
| `daily-resting-heart-rate` | `list` | 1/day | ✅ bpm |
| `sleep` | `list` | 1/night | ✅ duration + deep minutes |
| `oxygen-saturation` | `list` | overnight samples | ✅ latest sample % |
| `daily-heart-rate-variability` | `list` | 1/day | ✅ RMSSD ms |
| `respiratory-rate-sleep-summary` | `list` | 1/night | ✅ deep-sleep breaths/min |
| `daily-sleep-temperature-derivations` | `list` | 1/day | ✅ nightly °C |
| `heart-rate-variability` | `list` | overnight samples | status only |
| `heart-rate` | `list` | every 2–3s (~36k/day) | status only |

**Note on `heart-rate` memory:** a 30-day backfill in one request OOM'd at 256 MiB. Cloud Run is now at 512 MiB. Daily incremental runs (~36k samples, ~11 MB on disk) are safe. If the schedule lapses >5 days, recover with `?type=heart-rate&days=N` in small windows.

---

### `GET /api/fitness/oauth/start`

Initiates the Google Health API OAuth flow (browser-initiated, no bearer auth needed). Redirects to Google consent screen.

---

### `GET /api/fitness/oauth/callback`

OAuth callback. On success stores the refresh token in Secret Manager (`health-oauth-refresh-token`) and returns a confirmation page.

---

## Blood Tests API

**Base URL:** `https://homehd.web.app/api/blood-tests`

Data source: static JSON file bundled with the API (`~2 400 rows`, 51 markers, 2023-09-23 → present) merged with live Firestore rows (`blood_tests` collection). Firestore rows override static rows on `lab_id + marker` key.

---

### `GET /api/blood-tests`

Returns filtered blood test rows.

| Query param | Type | Description |
|---|---|---|
| `marker` | `string` | Comma-separated marker names, e.g. `Haemoglobin,Ferritin` |
| `phase` | `string` | Comma-separated phases: `admission`, `in-center-hd`, `home-hd` |
| `from` | `YYYY-MM` or `YYYY-MM-DD` | Earliest datetime (prefix match) |
| `to` | `YYYY-MM` or `YYYY-MM-DD` | Latest datetime (prefix match) |

All params are optional. No params returns every row.

**Response**
```json
{
  "count": 12,
  "rows": [
    {
      "marker": "Haemoglobin",
      "datetime": "2026-05-01T08:30:00",
      "value": 118,
      "unit": "g/L",
      "ref_low": 130,
      "ref_high": 170,
      "timing": "pre",
      "note": "",
      "source": "PKB",
      "lab_id": "LAB-20260501",
      "phase": "home-hd",
      "created_at": "2026-05-02T10:00:00.000Z",
      "qualitative": false
    }
  ]
}
```

**Row fields**

| Field | Type | Notes |
|---|---|---|
| `marker` | string | Canonical name (e.g. `Haemoglobin`) |
| `datetime` | ISO 8601 string | `YYYY-MM-DDTHH:MM:SS` |
| `value` | number | Numeric value; `0` when `qualitative: true` |
| `unit` | string | Unit label (e.g. `g/L`, `mmol/L`) |
| `ref_low` / `ref_high` | number \| null | Reference range; `null` if not provided |
| `timing` | `"pre"` \| `"post"` \| `""` | Dialysis timing |
| `note` | string | Free text |
| `source` | string | Data origin (e.g. `PKB`, `manual`) |
| `lab_id` | string | Unique lab request ID |
| `phase` | `admission` \| `in-center-hd` \| `home-hd` | |
| `qualitative` | boolean | If `true`, `value` is not meaningful; `unit` carries the result |

---

### `POST /api/blood-tests`

Writes new rows to Firestore. Accepts 1–100 rows per call.

**Request body**
```json
{
  "rows": [
    {
      "marker": "Haemoglobin",
      "datetime": "2026-05-01T08:30:00",
      "value": 118,
      "unit": "g/L",
      "ref_low": 130,
      "ref_high": 170,
      "timing": "pre",
      "note": "",
      "source": "manual",
      "lab_id": "LAB-20260501",
      "phase": "home-hd",
      "qualitative": false
    }
  ]
}
```

`created_at` is set by the server. Rows are keyed by `{lab_id}_{marker}` in Firestore — re-posting the same key overwrites the row.

**Response** `{ "ok": true, "count": 1 }`

---

## Inventory API

**Base URL:** `https://homehd.web.app/api/inventory`

Firestore layout:
```
inventory_stock/{itemCode}     { qty: number, updated_at: ISO string }
inventory_events/{autoId}      { type, timestamp, deltas, note? }
inventory_config/cycle         { call_date, delivery_date, order?, order_placed_at, delivery_applied_at }
inventory_config/pak           { installed_at: YYYY-MM-DD }
```

Item codes match the `ITEMS` constant in `frontend/src/routes/Inventory/constants.ts`.

---

### `GET /api/inventory`

Returns current stock, active delivery cycle, and PAK usage.

**Response**
```json
{
  "stock": {
    "SAK-303": 18,
    "CAR-172-C": 12,
    "UK00000880": 20
  },
  "cycle": {
    "call_date": "2026-06-23",
    "delivery_date": "2026-06-30",
    "order": { "SAK-303": 16, "CAR-172-C": 18 },
    "order_placed_at": "2026-06-23T10:15:00.000Z",
    "delivery_applied_at": null
  },
  "pak_installed_at": "2026-04-01",
  "pak_sessions": 23
}
```

`cycle` is `null` if no cycle has been set up. `pak_sessions` counts `session` events since `pak_installed_at`.

---

### `POST /api/inventory/event`

Logs a stock event. Three types:

| `type` | Effect | Notes |
|---|---|---|
| `session` | Increments stock by `deltas` (use negative values to deduct) | Auto-called on session end |
| `manual` | Same as session but tagged manual | For ad-hoc adjustments |
| `stock_count` | Sets stock to the absolute values in `deltas` | Overwrites running estimate |

**Request body**
```json
{
  "type": "manual",
  "deltas": { "SAK-303": -1, "CAR-172-C": -1 },
  "note": "prep failure"
}
```

`note` is optional.

**Response** `{ "ok": true }`

---

### `POST /api/inventory/confirm-order`

Stores a new delivery cycle and marks the order as placed.

**Request body**
```json
{
  "call_date": "2026-06-23",
  "delivery_date": "2026-06-30",
  "order": {
    "SAK-303": 16,
    "CAR-172-C": 18,
    "UK00000880": 20
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `call_date` | Yes | YYYY-MM-DD |
| `delivery_date` | No | YYYY-MM-DD; defaults to `call_date + 7 days` if omitted |
| `order` | Yes | Units (not boxes). Empty `{}` initialises a cycle without placing an order. |

Passing `{}` as `order` sets `order_placed_at: null` (cycle setup without order). `delivery_applied_at` is always reset to `null`.

**Response** `{ "ok": true }`

---

### `POST /api/inventory/apply-delivery`

Applies the stored order to stock and advances the cycle by 28 days.

**Request body**
```json
{
  "adjustments": { "SAK-303": 14 }
}
```

`adjustments` is optional. If provided, its values override the stored `order` for the specified items; other items use the stored order quantities unchanged. Pass `{}` or omit to apply the stored order as-is.

Increments stock using `FieldValue.increment` for each item. Logs a `delivery` event. Sets `order_placed_at: null`, `delivery_applied_at: <now>`, and rolls `call_date` forward 28 days.

Returns `404` if no cycle exists.

**Response** `{ "ok": true }`

---

### `PUT /api/inventory/stock`

Directly sets stock quantities for one or more items. Overwrites the stored qty (not an increment). Also logs a `stock_count` event for audit.

**Request body**
```json
{
  "items": {
    "SAK-303": 18,
    "CAR-172-C": 12
  }
}
```

All values must be non-negative integers.

**Response** `{ "ok": true, "updated": 2 }`

---

### `PATCH /api/inventory/order`

Replaces the `order` map on the current cycle without touching `order_placed_at`, `delivery_applied_at`, or the cycle dates. Use this to correct an order after it has been placed.

Returns `404` if no cycle exists.

**Request body**
```json
{
  "order": {
    "SAK-303": 16,
    "CAR-172-C": 18,
    "UK00000880": 20
  }
}
```

**Response** `{ "ok": true }`

---

### `POST /api/inventory/update-cycle-dates`

Updates `call_date` and `delivery_date` on the current cycle using a merge write. Does not touch `order`, `order_placed_at`, or `delivery_applied_at`.

**Request body**
```json
{
  "call_date": "2026-06-23",
  "delivery_date": "2026-07-02"
}
```

Both fields required, YYYY-MM-DD.

**Response** `{ "ok": true }`

---

### `GET /api/inventory/deliveries`

Returns all past delivery events, newest first.

**Response**
```json
{
  "deliveries": [
    {
      "timestamp": "2026-05-30T14:00:00.000Z",
      "deltas": { "SAK-303": 16, "CAR-172-C": 18 },
      "note": "delivery applied"
    }
  ]
}
```

---

### `POST /api/inventory/set-pak-install`

Records the date a new PAK cartridge was installed. Used to calculate `pak_sessions` in the GET response.

**Request body**
```json
{ "installed_at": "2026-04-01" }
```

**Response** `{ "ok": true }`

---

## Error Responses

All Cloud Run endpoints return JSON errors:

| Status | Body | Cause |
|---|---|---|
| `400` | `{ "error": "invalid JSON" }` | Malformed request body |
| `400` | `{ "error": "invalid request", "details": [...] }` | Zod validation failure |
| `401` | `{ "error": "Unauthorized" }` | Missing or wrong Bearer token |
| `404` | `{ "error": "no active cycle" }` | Order/delivery endpoints called with no cycle |
| `404` | `{ "error": "not_found" }` | Route not matched |
| `500` | `{ "error": "server_error", "message": "..." }` | Unhandled exception |
