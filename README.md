# treatment_tracker

Two apps supporting home haemodialysis:

- **`pwa/`** — Home HD session tracker (Android PWA). See `pwa/README.md`.
- **`dashboard/`** — Blood test analytics dashboard + query endpoint.

## Dashboard

**Live:** https://treatment-dashboard.pages.dev (key-gated; pass `Authorization: Bearer <DASHBOARD_KEY>` to `/api/blood-tests`).

Design: `docs/superpowers/specs/2026-05-22-blood-test-dashboard-design.md` · Plan: `docs/superpowers/plans/2026-05-22-blood-test-dashboard.md`

### Develop

```bash
cd dashboard
npm install
npm run dev          # regenerates data/blood_tests.json, then starts Vite
```

### Test the endpoint locally

```bash
cd dashboard
npm run build
echo 'DASHBOARD_KEY=<dev-key>' > .dev.vars   # gitignored
npx wrangler pages dev dist
```

### Deploy

One-time:

```bash
cd dashboard
npx wrangler pages project create treatment-dashboard --production-branch=main
npx wrangler pages secret put DASHBOARD_KEY --project-name=treatment-dashboard
```

Each deploy:

```bash
cd dashboard
npm run build
npx wrangler pages deploy dist --project-name=treatment-dashboard --branch=main --commit-dirty=true
```

The monthly data refresh is: edit `scripts/pkb_backfill/blood_tests.csv`, then redeploy.
