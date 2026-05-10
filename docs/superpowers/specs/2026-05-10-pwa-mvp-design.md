# Home HD Tracker — PWA MVP Design

**Date:** 2026-05-10
**Status:** Approved, ready for implementation plan
**Source design:** `~/Project_ideas/Home HD Knowledge Base and Tracking System.md` (sections "BP Tracking System — design finalized" 2026-04-16 and "Apps Script backend deployed" 2026-05-06)

This spec covers only the PWA frontend MVP. Backend (Apps Script web app on the bound Sheet) is already deployed, verified end-to-end, and **out of scope here** — see the source doc for backend details, deployment URL, and curl smoke tests.

## Goal

Replace mobile-Sheets entry during home dialysis sessions with a purpose-built Android PWA that writes to the same Sheet through the deployed Apps Script web app. Clinical team continues to read the Sheet (via the auto-rebuilt `legacy_view` tab) and is not a user of this app.

## Non-goals (MVP)

Explicitly deferred to Phase 2 per the source doc:
- Dashboard with charts (Recharts)
- CSV export (date range, last 16, last 3 months, all)
- Edit past sessions
- Session detail view

Explicitly deferred to Phase 3:
- Auto-duration from start/end timestamps
- Auto-flag sessions with big BP drops or missed UF
- Push reminder if no reading >90min into active session

Out of scope entirely for the tracker (covered by separate future projects):
- NxStage error knowledge base
- Blood test analytics
- Inventory tracking
- Clinical team as users

## Stack

- **Vite** + **React 18** + **TypeScript** (strict mode)
- **Tailwind CSS** for styling
- **zod** for form validation and parsing API responses
- **vite-plugin-pwa** for manifest + service worker (installable on Android)
- **idb** for IndexedDB wrapper (storing shared secret + script URL + last-session cache)
- No global state library — `useState`/`useReducer` plus a small `api.ts` module is enough at this scope.

## Repo layout

Single repo at `/Users/ntg/Documents/Personal_Projects/treatment_tracker/`.

```
treatment_tracker/
├── src/
│   ├── main.tsx
│   ├── App.tsx                    # router, screen state
│   ├── api.ts                     # POST/GET against /exec, retries
│   ├── storage.ts                 # IndexedDB: secret, url, last-session
│   ├── schemas.ts                 # zod schemas mirroring SESSION_COLS, READING_COLS
│   ├── types.ts                   # TS types derived from zod schemas
│   ├── screens/
│   │   ├── Setup.tsx              # first-launch: paste URL + secret
│   │   ├── Home.tsx               # last 5 sessions, "Start session" button
│   │   ├── PreTreatment.tsx
│   │   ├── ActiveSession.tsx      # readings list + "Add reading" + "End session"
│   │   └── PostTreatment.tsx
│   ├── components/
│   │   ├── NumberField.tsx        # inputmode="decimal", consistent styling
│   │   ├── AddReadingModal.tsx
│   │   ├── SessionListItem.tsx
│   │   └── SaveButton.tsx         # spinner + retry on error
│   └── pwa/
│       ├── manifest.ts            # name, icons, theme_color
│       └── icons/                 # 192/512 PNG
├── docs/superpowers/specs/2026-05-10-pwa-mvp-design.md
├── index.html
├── vite.config.ts
├── tsconfig.json
├── tailwind.config.ts
├── postcss.config.js
├── package.json
├── .gitignore
└── README.md
```

## Data model (mirrors deployed Apps Script)

**`sessions` row** (one per session):
`session_id, date, pre_weight, uf_goal, uf_rate, pre_bp_sys, pre_bp_dia, pre_pulse, post_weight, post_bp_sys, post_bp_dia, post_pulse, duration_min, dialysate_volume, total_uf, blood_processed, created_at`

**`readings` row** (one per intra-session reading):
`reading_id, session_id, seq, time, bp_sys, bp_dia, pulse, blood_flow, venous_pressure, arterial_pressure, note, created_at`

`session_id` format: `YYYY-MM-DD`, with `-N` suffix if a session for today already exists locally or in the fetched last-5 list.
`reading_id` format: `${session_id}-r${seq}`.
`time`: `HH:MM` 24-hour string.
`created_at`: client-generated ISO timestamp; backend overwrites with its own server-side ISO.

All numeric fields are sent as JSON numbers. Backend stores as text (per the `appendAsText_` patch noted in the source doc), so the wire format must be JSON-correct on the way out.

## API contract (frozen by deployed backend)

Single endpoint: the `/exec` URL (stored per-install in IndexedDB).

**POST** `Content-Type: application/json`, body:
```json
{ "secret": "<shared_secret>", "action": "<save_session|save_reading|update_session>", "data": { ... } }
```

**GET** `?secret=<shared_secret>&since=<YYYY-MM-DD>` returns:
```json
{ "ok": true, "sessions": [...], "readings": [...] }
```

**Response convention:** all responses are HTTP 200 with `{"ok": true, ...}` or `{"ok": false, "error": "<code>"}`. Per the source doc, Apps Script web apps cannot set custom HTTP status codes — clients **must** check `body.ok`, not HTTP status.

**Browser POST notes:** The PWA runs in the browser, so curl's `--post301/302/303` problem does not apply (browsers preserve POST across same-origin redirects via the Fetch API, and the script's `googleusercontent.com` redirect is followed transparently). CORS: Apps Script web apps respond with permissive CORS for the JSON content-type used here; the request will be a CORS preflight only if we add custom headers — keep it to `Content-Type: application/json` only.

## Screens

### 1. Setup (first launch only)
- Two text fields: Apps Script URL, shared secret.
- Validate URL with a GET probe (`/exec?secret=…`); on `ok:true` save both to IndexedDB and route to Home. On `ok:false` show error and let the user retry.
- After saved, never shown again unless user explicitly clears settings (a small "Settings" link on Home).

### 2. Home
- Header: "Home HD Tracker"
- Primary CTA button: "Start session" → routes to PreTreatment.
- List: last 5 sessions, fetched via GET on mount. Each row shows date, pre→post BP, total UF. Read-only in MVP.
- Footer: "Settings" link (clears or rotates secret/URL).

### 3. Pre-treatment form
- Fields: weight, UF goal, UF rate, BP sys, BP dia, pulse.
- UF goal and UF rate default to last session's values (read from cached last-session in IndexedDB).
- All numeric inputs use `inputmode="decimal"`.
- Submit → POST `save_session` with pre values + generated `session_id` + `date`. On success, cache the new session locally and route to ActiveSession.

### 4. Active session
- Header: shows pre values (weight, UF goal, BP/pulse) for reference.
- "+ Add reading" button → opens modal.
- Readings list, sorted by `seq` descending (newest first). Each row: time, BP, pulse, blood flow, VP, AP, note (truncated). No edit in MVP. Sort key is `seq`, not `time`, because `time` is user-editable and not guaranteed monotonic.
- "End session" button → routes to PostTreatment.
- No charts.

### 5. Add reading modal
- Fields: time (defaults to "now", editable), BP sys, BP dia, pulse, blood flow (defaults to last reading's value, or empty for first), VP, AP, note.
- Submit → POST `save_reading` with `reading_id` and incremented `seq`.
- Optimistic UI: row appears immediately with a small "saving" indicator; on error, row is marked failed with a Retry button. No background buffering — user must explicitly retry.

### 6. Post-treatment form
- Fields: weight, BP sys, BP dia, pulse, duration (min), dialysate volume, total UF, blood processed.
- Submit → POST `update_session` with `session_id` + post values. On success, route to Home.

## State and storage

**IndexedDB (via `idb`):**
- `settings` store: `script_url`, `shared_secret`
- `cache` store: `last_session` (object) — used to default UF goal/rate on next pre-treatment

**In-memory (React state):**
- Current screen / route
- Current draft session (in-flight pre values before first save)
- Current session_id and accumulated readings list while in ActiveSession

No router library — a `Screen` union type and `useState` is sufficient for ~5 screens. Avoids react-router weight.

## Error handling

- Every POST awaits the response; UI shows a spinner on the submit button while in flight.
- On network error or `body.ok === false`: inline error banner with the error code, plus a "Retry" button that re-runs the same payload. No silent retries, no offline queue (per the source doc: home WiFi is rock-solid; offline buffering explicitly out of scope).
- On Setup probe failure: show the error code; let the user re-paste URL/secret.
- Defensive zod parsing on responses: if backend returns a row missing expected fields, surface a clear "Backend schema mismatch — backend code may be out of date" error rather than rendering `undefined`.

## Auth

- Shared secret + script URL stored only in IndexedDB on the device.
- The shared secret must never be logged, never printed to console, never included in URLs that might end up in browser history. POST bodies only. (GET requires the secret in the query string per the backend contract — unavoidable; documented limitation.)
- "Settings" screen lets user clear or rotate. Rotating means: paste new values, GET probe, replace.

## PWA / installability

- `vite-plugin-pwa` with `registerType: 'autoUpdate'`.
- Manifest: name "HD Tracker", short_name "HD", display "standalone", theme_color a calm dark-blue, 192/512 icons.
- Service worker caches the app shell only. API responses are NOT cached (we always want fresh data from the Sheet).
- Test installability: Chrome on Android → Add to Home Screen; verify launch is full-screen.

## Testing

MVP testing strategy is light by design (single-user app, deployed backend already validated):
- TypeScript strict mode catches most shape errors at compile time.
- zod parsing of API responses catches drift at runtime.
- Manual smoke test plan after each screen lands:
  1. Fresh install → Setup → save URL+secret → reach Home
  2. Start session → fill Pre → submit → verify row in `sessions` tab
  3. Add 3 readings → verify rows in `readings` tab and `legacy_view` rebuilds
  4. End session → fill Post → submit → verify same `session_id` row updated
  5. Reload PWA → Home shows the new session in the last-5 list
- One focused unit test on `session_id` generation (handles `-N` suffix when same-day session exists).
- Vitest set up but minimal; expand only if a real bug demands it.

## Build & deploy

- `npm run dev` for local dev (Vite default port).
- `npm run build` produces a static `dist/` directory.
- Hosting: TBD by user. Options that work well for a single-user PWA: GitHub Pages, Cloudflare Pages, Netlify free tier. **Hosting choice is deferred — for MVP, building and serving locally then `npx serve dist` over HTTPS via a tunnel (e.g. cloudflared) is acceptable for first installs.** Final hosting decision belongs in the implementation plan or a follow-up note.

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| CORS preflight on POST blocks the request | Use only `Content-Type: application/json`; no custom headers. Validated during Setup probe (GET) and first session save. |
| `appendAsText_` regression on backend re-deploy stores `"19:15"` as Date again | zod parser on GET response treats `time` as string; if a Date sneaks through it'll fail-loud rather than silently render junk. |
| User taps Submit twice and creates duplicate readings | Disable submit button while in flight; `reading_id` is deterministic (`${session_id}-r${seq}`) so even a duplicate submit overwrites the same row rather than creating a phantom. |
| Service worker caches a stale UI bundle | `registerType: 'autoUpdate'` + `skipWaiting`. Reload after deploy picks up the new bundle. |
| User rotates the script URL but device still has old one cached | Settings screen explicitly supports clearing/replacing both fields. |

## Open questions (defer to Phase 2 or as they arise)

- Final hosting decision (Pages vs tunnel-from-laptop)
- Whether to add a "draft" state for sessions that started but never had Post filled in (currently they live indefinitely as half-saved rows)
- Whether to surface a soft-warning if today already has a session before generating `-2` suffix

These are intentionally not blocking MVP — flag and revisit after a week of real use.
