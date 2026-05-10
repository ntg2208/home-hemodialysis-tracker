# HD Tracker

Android PWA for recording home hemodialysis sessions. Writes to a Google Sheet via the Apps Script web app deployed against that sheet.

## Stack

Vite + React 18 + TypeScript (strict), Tailwind CSS, zod, vite-plugin-pwa, idb.

## Develop

```bash
npm install
npm run dev      # http://localhost:5173
npm test         # Vitest
npm run build    # static dist/
npm run preview  # serve dist/ on http://localhost:4173
```

## First-time setup on device

1. Build and serve `dist/` over HTTPS (PWA install requires HTTPS or localhost).
   - Quick option: `npm run build && npx serve dist` then `cloudflared tunnel --url http://localhost:3000` for a public HTTPS URL.
2. Open the URL in Chrome on Android → menu → "Install app".
3. On first launch the Setup screen asks for:
   - **Script URL** — the `/exec` URL from `Deploy → Manage deployments` in the bound Apps Script
   - **Shared secret** — the value set via `setSecret()` in the script
   Both are stored only in IndexedDB on the device.

## Backend

The backend is a Google Apps Script web app bound to the Sheet. Its source, deployment notes, and known gotchas live in `~/Project_ideas/Home HD Knowledge Base and Tracking System.md` (the 2026-04-16 and 2026-05-06 entries). Backend changes are made in the Apps Script editor, not in this repo.

## What's in MVP / what isn't

See `docs/superpowers/specs/2026-05-10-pwa-mvp-design.md` for the explicit scope split. Phase 2 (dashboard, CSV export, edit past sessions) is intentionally not built yet.

## Smoke test

After any deploy, run through this on the device:
1. Fresh install → Setup → save URL+secret → reach Home
2. Start session → fill Pre → submit → check `sessions` tab in Sheet
3. Add 3 readings → check `readings` tab and `legacy_view` rebuild
4. End session → fill Post → submit → check the same `session_id` row updated
5. Reload PWA → Home shows the new session
