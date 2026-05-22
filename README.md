# Treatment tracker

A small, self-hosted progressive web app for logging **home hemodialysis** sessions to a Google Sheet you already own. Built for one person doing dialysis at home with an NxStage machine — designed to be easy to fork and adapt for any similar tracking need.

<p align="center">
  <img src="public/icon-512.png" alt="Treatment tracker icon" width="128" height="128" />
</p>

> ⚠️ **Medical disclaimer.** This software is **not a medical device**. It does not provide clinical decision support, alarms, or diagnostic functions. It is a personal data-logging tool, provided **as-is, with no warranty of any kind** (see [LICENSE](LICENSE)). Do not use it as a substitute for any device, monitor, or professional advice. If you adopt or modify it, you do so at your own risk.

---

## What it does

- 5 mobile-first screens covering one full dialysis session: **Setup → Home → Pre-treatment → Active session → Post-treatment**.
- Writes structured rows to a Google Sheet you own. No third-party server, no analytics, no telemetry.
- Auto-rebuilds a **legacy view tab** in the same Sheet that matches the multi-row-per-session layout clinical readers already know — so adopting the app doesn't force a workflow change on the people reading the data.
- Installable as a PWA on Android (and iOS) home screen.
- Auto-fill formulas for the predictable fields (UF goal, UF rate, total UF, duration, dialysate volume) — calculated from prior inputs and overridable per session.

## Architecture

```
   ┌─────────────────────┐         ┌──────────────────────────────┐         ┌────────────────────┐
   │  PWA (this repo)    │  POST   │  Google Apps Script /exec    │ writes  │  Google Sheet      │
   │  React + Vite + TS  │ ──────▶ │  (backend/Code.gs)           │ ──────▶ │  sessions          │
   │  hosted as static   │  GET    │  bound to the Sheet,         │         │  readings          │
   │  files on any CDN   │ ◀────── │  shared-secret auth          │         │  legacy_view       │
   └─────────────────────┘         └──────────────────────────────┘         └────────────────────┘
                                             ▲                                       ▲
                                             │                                       │
                                             └─── you set SHARED_SECRET once         └─── clinical team reads this tab
                                                  via PropertiesService                     (auto-rebuilt on every write)
```

- **No backend to host.** The "server" is a Google Apps Script web app bound to your Sheet — Google runs it for free, scales to zero, and there are no cold starts that affect single-user use.
- **No database to manage.** The Sheet *is* the database. You can browse, edit, export, share rows with anyone you'd normally share a Sheet with.
- **Single-tenant by design.** Each install is one user pointing at one Sheet. There's no multi-user, no accounts, no PII routing.

## Quick start

You need: a Google account, Node 20+, and ~15 minutes for the first setup.

### 1. Backend — Apps Script bound to your Sheet

1. Create a new Google Sheet. Name it whatever you like.
2. **Extensions → Apps Script** to open the bound script editor.
3. Replace the contents of `Code.gs` with the contents of [`backend/Code.gs`](backend/Code.gs) from this repo. Save.
4. Set your shared secret:
   - Edit the `setSecret` function at the bottom of `Code.gs`: uncomment the body and replace the placeholder with a long random string (40+ characters, e.g. `openssl rand -hex 32`).
   - Run `setSecret` once from the editor's Run menu (it'll ask for permissions — approve them).
   - **Re-comment** the body and save so it doesn't accidentally execute again.
5. **Deploy → New deployment → Web app**
   - Description: `v1`
   - Execute as: **Me**
   - Who has access: **Anyone**
   - Click Deploy. Copy the `/exec` URL — this is what the PWA POSTs to.
6. (Optional) Smoke-test the deployment from a terminal before you build any UI:
   ```bash
   curl -L --post301 --post302 --post303 -X POST '<YOUR_EXEC_URL>' \
     -H 'Content-Type: application/json' \
     -d '{"secret":"<YOUR_SECRET>","action":"save_session","data":{"session_id":"test","date":"2026-05-12"}}'
   ```
   Expected: `{"ok":true,"session_id":"test"}` and a row in the `sessions` tab.

> **Common pitfall:** if you redeploy via **Deploy → New deployment** instead of **Deploy → Manage deployments → Edit → New version**, the "Who has access" dropdown defaults back to a stricter setting and POSTs will return Google's HTML 401 wall (not the script's JSON). Always use **Manage deployments → New version** for updates.

### 2. Frontend — install, build, and host

```bash
git clone https://github.com/ntg2208/home-hemodialysis-tracker.git
cd home-hemodialysis-tracker
npm install
npm run dev         # local dev at http://localhost:5173
npm run build       # produces dist/ for hosting
```

### 3. Hosting — pick any static host

Built `dist/` is a static PWA — host it on any CDN. We use **Cloudflare Pages** (free, no laptop required to stay online).

**Cloudflare Pages via Wrangler** (one-time):

```bash
npx wrangler login                                                    # opens browser
npx wrangler pages project create treatment-tracker --production-branch=master
npx wrangler pages deploy dist --project-name=treatment-tracker --branch=master
```

You get a permanent URL like `https://treatment-tracker.pages.dev`. Future redeploys land at the same URL:

```bash
npm run build
npx wrangler pages deploy dist --project-name=treatment-tracker --branch=master --commit-dirty=true
```

Other hosts that work with zero config: Netlify (drag `dist/` onto [app.netlify.com/drop](https://app.netlify.com/drop)), Vercel, GitHub Pages, any static webserver.

### 4. Install on a phone

1. Open your hosted URL in **Chrome on Android** (Safari on iOS).
2. Menu → **Install app** (or **Add to Home screen**).
3. Launch from the home-screen icon. The Setup screen asks for:
   - **Script URL** — the `/exec` URL you copied in step 1.5.
   - **Shared secret** — the value you set in step 1.4.
4. Both are stored in IndexedDB on the device only. They are not committed, transmitted, or backed up anywhere outside the device.

### 5. Daily use (and full smoke test)

Run this end-to-end checklist to verify a fresh install:

1. Fresh install → Setup → save URL + secret → land on Home.
2. **Start session** → fill Pre-treatment (weight, UF goal/rate auto-fill from formulas) → submit → check the `sessions` tab in the Sheet has a new row.
3. **Add reading** ×3 → check `readings` tab and that `legacy_view` rebuilds.
4. **End session** → fill Post-treatment (duration / dialysate vol / total UF auto-fill) → submit → check the same `session_id` row was updated in `sessions`.
5. Reload PWA → Home shows the new session in the recent list.

## Stack

- **Frontend:** Vite + React 18 + TypeScript (strict), Tailwind CSS, [zod](https://zod.dev) for schema validation, [idb](https://github.com/jakearchibald/idb) for IndexedDB, [vite-plugin-pwa](https://vite-pwa-org.netlify.app/) for service worker + manifest, [lucide-react](https://lucide.dev) for icons, [Vitest](https://vitest.dev) for unit tests.
- **Backend:** Google Apps Script (V8 runtime) bound to a Google Sheet. No external dependencies.
- **Deployment:** Cloudflare Pages (or any static host). Local-only secrets via macOS Keychain or equivalent.

## Repository layout

```
.
├── backend/
│   └── Code.gs                  ← paste this into Apps Script editor
├── public/
│   ├── icon-source.svg          ← editable icon source
│   ├── icon-maskable-source.svg ← editable maskable variant
│   ├── icon-192.png             ← generated
│   ├── icon-512.png             ← generated
│   ├── icon-512-maskable.png    ← generated
│   └── apple-touch-icon.png     ← generated
├── src/
│   ├── App.tsx                  ← screen-routing state machine
│   ├── api.ts                   ← network client (Apps Script POST/GET)
│   ├── schemas.ts               ← zod source of truth for response shapes
│   ├── storage.ts               ← IndexedDB wrapper
│   ├── sessionId.ts             ← unit-tested session_id generator
│   ├── components/              ← reusable form bits (NumberField, SaveButton, …)
│   └── screens/                 ← Setup, Home, Pre, Active, Post
├── docs/                        ← design specs and implementation plans (kept for context)
├── vite.config.ts               ← Vite + PWA manifest
└── README.md                    ← you are here
```

## Customising for your own workflow

The hard-coded assumptions are clustered enough that you can fork and adapt without much pain:

- **Auto-fill formulas** for UF goal, UF rate, duration, dialysate volume, total UF live in `src/screens/PreTreatment.tsx` and `src/screens/PostTreatment.tsx`. Search for `derived` / `DEFAULT_`.
- **Dry weight target** (`pre_weight - 59` in the UF goal default) is in `PreTreatment.tsx` — change `59` to your number.
- **Treatment time default** (`4:15 = 255` minutes) and **dialysate volume default** (`49 L`) are constants at the top of `PostTreatment.tsx`.
- **Column lists** are in two places that must stay in sync: `SESSION_COLS` / `READING_COLS` in `backend/Code.gs` and the zod schemas in `src/schemas.ts`.
- **Legacy view layout** lives in `rebuildLegacyView_` in `backend/Code.gs` — adapt the header row and per-row mapping to match your clinical team's expected format.

## Development

```bash
npm run dev         # vite dev server, hot reload
npm test            # vitest (unit tests for sessionId and a few helpers)
npm run build       # production build to dist/
npm run preview     # preview the production build locally
```

TypeScript runs in strict mode and the build fails on type errors. The CI surface is intentionally tiny — `npm run build` runs `tsc -b && vite build`, which is the single gate for "does this compile and bundle."

## Security model — what you should know before adopting

- **Single shared secret** posted with every request. Suitable for one user logging their own data over HTTPS. **Not suitable** for multi-user, multi-tenant, or any scenario where the secret could leak from one device and matter on another.
- **No transport-layer secret protection** beyond HTTPS — the secret is in the request body of every POST and the query string of every GET. Treat it like a password for that specific Sheet.
- **Apps Script web app set to "Anyone with the link"** is correct here: the secret-in-body is the auth, the URL itself is non-sensitive. But anyone who has both URL *and* secret has full read/write access to that Sheet.
- **The Sheet is the source of truth.** All data lives in your Google Sheet. The PWA caches nothing except your Setup credentials and the last session for prefill — clearing the PWA's IndexedDB loses nothing.
- **No analytics, no telemetry, no third-party calls.** The only network requests are to your own Apps Script `/exec` URL.

## Known limitations & future work

Phase-2 ideas tracked for later:

- Dashboard view with monthly trend charts (BP, weight gain, UF achievement, access function).
- CSV export (sessions + readings, last 30/90 days / all).
- Edit past sessions (currently insert-only after submit).
- Friendlier error prose (today the UI shows internal codes like `network_error`).
- Auto-flag sessions with large intra-dialytic BP drops or unmet UF goals.

## Contributing

Contributions welcome via PRs. For substantial changes please open an issue first to discuss scope — this codebase is intentionally small and the bar for adding surface area is high.

If you're using this for your own care or someone else's, I'd be glad to hear what worked, what didn't, and what you had to adapt. Issues are a fine place to leave that feedback.

## License

[MIT](LICENSE) © 2026 Truong Giang Nguyen.

If you build on this, please keep the medical disclaimer prominent in any fork that other people might find.
