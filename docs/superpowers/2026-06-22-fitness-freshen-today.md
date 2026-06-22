# Fitness "Freshen Today" Intraday Read — Spec + Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fetch *today's* partial intraday fitness data (sleep + the overnight-scored readiness metrics) on demand and on a mid-morning schedule, without advancing the durable sync cursor — so the future energy-pacing morning call can read same-day data instead of yesterday's.

**Architecture:** The existing `list`-endpoint sync (`runSync`) already pulls intraday data, but is hard-clamped to `yesterday` and advances a per-type `sync_state` cursor. This adds a *second, separate* read — `freshenToday()` — that fetches a single day (today) for a fixed set of `list`-strategy types and writes to a distinct `raw/{type}/today/{date}.json` namespace. It **never reads or writes `sync_state`**, so the archival cursor sync is untouched and tomorrow's normal sync still pulls the now-complete day. A `POST /api/fitness/freshen` route triggers it; Cloud Scheduler calls it across the 09:00–11:00 window.

**Tech Stack:** TypeScript (strict), Hono, vitest, Google Cloud Run (`homehd-api`, `europe-west2`), GCS bucket `gs://homehd-fitness`, Cloud Scheduler. Project `homehd-personal`.

## Why (context)

The premise that "Google Health data is delayed 1 day" was found to be **partly a self-imposed code clamp, not the API**. Evidence in the codebase as of 2026-06-22:
- `SYNC_TYPE_STRATEGY` (`api/src/lib/googleHealth.ts`) already uses `method: 'list'` for every readiness type — the `list` endpoint returns granular intraday data and *can* return today's.
- `runSync` is handed `lastInclusiveDate: clampSyncEnd(c.req.query('to'), yesterday())` (`api/src/handlers/fitness.ts`) — hard-capped at yesterday. The sync simply never asks for today.

Only the *overnight-scored* derived metrics (daily HRV, sleep stages, resting HR) have a genuine floor: they appear once Fitbit scores the night (~mid-morning). This work un-clamps for those types via a non-cursor-advancing read. **Webhooks were considered and rejected as over-engineering for a single-user, once-daily ritual.** Full breadcrumb: vault note `Home HD Knowledge Base and Tracking System.md` → 2026-06-22 entries.

## Global Constraints

- **Cursor invariant (critical):** `freshenToday()` and the `/freshen` route MUST NOT read or write `sync_state`. The durable, cursor-advancing archival sync stays `yesterday`-clamped. Violating this permanently loses the rest of a partial day.
- **List-types only:** freshen operates only on types whose `SYNC_TYPE_STRATEGY` is `{ method: 'list' }`. A non-list type is an error result, not a throw.
- **Per-type isolation:** one type's failure is recorded as `{ status: 'error', error }` and does not abort the others (mirror `runSync`).
- **Idempotent:** re-running for the same date overwrites `raw/{type}/today/{date}.json` — each run is a fresh full-day snapshot.
- **UTC dates:** `today` = `new Date().toISOString().slice(0, 10)`, matching `yesterday()`.
- **Auth:** the `/freshen` route mounts on the existing bearer-authed `fitness` Hono instance (same `MAIN_API_KEY` guard as `/sync`).
- **Test runner:** `cd api && npx vitest run` (single file: `npx vitest run src/handlers/fitness.test.ts`).

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `api/src/lib/googleHealth.ts` | Adds `FRESHEN_TYPES` constant next to `SYNC_TYPES`. | Modify |
| `api/src/handlers/fitness.ts` | Adds `freshenToday()` core + `today()` helper + `POST /freshen` route. | Modify |
| `api/src/handlers/fitness.test.ts` | Unit tests for `freshenToday()`. | Modify |

`freshenToday()` reuses `dataTypePath` (already imported from `gcs.ts`) and `SYNC_TYPE_STRATEGY` (already imported from `googleHealth.ts`).

---

### Task 1: `FRESHEN_TYPES` + `freshenToday()` core

**Files:**
- Modify: `api/src/lib/googleHealth.ts` (add `FRESHEN_TYPES` after `SYNC_TYPE_STRATEGY`)
- Modify: `api/src/handlers/fitness.ts` (add `freshenToday` + types, exported)
- Test: `api/src/handlers/fitness.test.ts`

**Interfaces:**
- Consumes: `SYNC_TYPE_STRATEGY`, `SyncType`, `FetchStrategy` (from `googleHealth.ts`); `dataTypePath` (from `gcs.ts`).
- Produces:
  - `FRESHEN_TYPES: readonly SyncType[]`
  - `interface FreshenDeps { uploadJson: (path: string, data: unknown) => Promise<void>; fetchList: (args: { dataType: string; filterField: string; filterDateField: Extract<FetchStrategy, { method: 'list' }>['filterDateField']; startDate: string; endDate: string }) => Promise<unknown[]> }`
  - `type FreshenResult = { count: number; status: 'ok' } | { status: 'error'; error: string }`
  - `type FreshenSummary = Record<string, FreshenResult>`
  - `freshenToday(deps: FreshenDeps, opts: { types: readonly SyncType[]; date: string }): Promise<FreshenSummary>`

- [ ] **Step 1: Write the failing tests**

In `api/src/handlers/fitness.test.ts`, add (adjust the import line to match the file's existing import of other `fitness.ts` exports):

```ts
import { freshenToday } from './fitness';

describe('freshenToday', () => {
  it('fetches a single day, writes to the today/ namespace, and never advances a cursor', async () => {
    const uploads: Array<{ path: string; data: any }> = [];
    const deps = {
      uploadJson: vi.fn(async (path: string, data: unknown) => {
        uploads.push({ path, data: data as any });
      }),
      fetchList: vi.fn(async () => [{ a: 1 }, { a: 2 }]),
    };

    const summary = await freshenToday(deps, { types: ['sleep'], date: '2026-06-22' });

    expect(deps.fetchList).toHaveBeenCalledWith(
      expect.objectContaining({ dataType: 'sleep', startDate: '2026-06-22', endDate: '2026-06-22' }),
    );
    expect(uploads).toHaveLength(1);
    expect(uploads[0].path).toBe('raw/sleep/today/2026-06-22.json');
    expect(uploads[0].data.count).toBe(2);
    expect(uploads[0].data.date).toBe('2026-06-22');
    expect(summary).toEqual({ sleep: { count: 2, status: 'ok' } });
    // FreshenDeps deliberately has no readSyncState/writeSyncState — cursor cannot move.
    expect('readSyncState' in deps).toBe(false);
    expect('writeSyncState' in deps).toBe(false);
  });

  it('records a non-list type as an error result, without throwing', async () => {
    const deps = { uploadJson: vi.fn(async () => {}), fetchList: vi.fn(async () => []) };
    // 'steps' is the only dailyRollUp type in SYNC_TYPE_STRATEGY.
    const summary = await freshenToday(deps, { types: ['steps'], date: '2026-06-22' });
    expect(summary.steps.status).toBe('error');
    expect(deps.fetchList).not.toHaveBeenCalled();
  });

  it('isolates a failing type instead of aborting the rest', async () => {
    const deps = {
      uploadJson: vi.fn(async () => {}),
      fetchList: vi.fn(async () => { throw new Error('boom'); }),
    };
    const summary = await freshenToday(deps, { types: ['sleep'], date: '2026-06-22' });
    expect(summary.sleep.status).toBe('error');
    if (summary.sleep.status === 'error') expect(summary.sleep.error).toBe('boom');
  });
});
```

If `vi` / `describe` / `it` / `expect` are not already imported at the top of the file, add: `import { describe, it, expect, vi } from 'vitest';` (check first — the file already has tests, so they are likely present).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd api && npx vitest run src/handlers/fitness.test.ts -t freshenToday`
Expected: FAIL — `freshenToday is not a function` / import not found.

- [ ] **Step 3: Add `FRESHEN_TYPES` to `googleHealth.ts`**

After the `SYNC_TYPE_STRATEGY` object, add:

```ts
// The list-strategy types whose same-day ("today") values feed the energy-pacing
// morning call. All are method:'list' (no dailyRollUp). Excludes raw 'heart-rate'
// (huge, daytime/HR-ceiling concern only) and 'steps' (dailyRollUp, inherently T-1).
export const FRESHEN_TYPES = [
  'sleep',
  'daily-heart-rate-variability',
  'daily-resting-heart-rate',
  'respiratory-rate-sleep-summary',
  'daily-sleep-temperature-derivations',
] as const satisfies readonly SyncType[];
```

- [ ] **Step 4: Add `freshenToday()` to `fitness.ts`**

Add the import for `FRESHEN_TYPES` to the existing `googleHealth` import in `fitness.ts`. Then add, near `runSync`:

```ts
export interface FreshenDeps {
  uploadJson: (path: string, data: unknown) => Promise<void>;
  fetchList: (args: {
    dataType: string;
    filterField: string;
    filterDateField: Extract<FetchStrategy, { method: 'list' }>['filterDateField'];
    startDate: string;
    endDate: string;
  }) => Promise<unknown[]>;
}

export type FreshenResult = { count: number; status: 'ok' } | { status: 'error'; error: string };
export type FreshenSummary = Record<string, FreshenResult>;

// Fetch a single day ("today", partial) for the given list-strategy types and write each
// to raw/{type}/today/{date}.json. Deliberately does NOT touch sync_state: this is the
// non-cursor-advancing "freshen" read. The archival runSync (yesterday-clamped) still
// pulls the complete day tomorrow and supersedes the partial.
export async function freshenToday(
  deps: FreshenDeps,
  opts: { types: readonly SyncType[]; date: string },
): Promise<FreshenSummary> {
  const summary: FreshenSummary = {};
  for (const type of opts.types) {
    try {
      const strategy = SYNC_TYPE_STRATEGY[type];
      if (strategy.method !== 'list') {
        summary[type] = { status: 'error', error: `freshen supports list types only; ${type} is ${strategy.method}` };
        continue;
      }
      const points = await deps.fetchList({
        dataType: type,
        filterField: strategy.filterField,
        filterDateField: strategy.filterDateField,
        startDate: opts.date,
        endDate: opts.date,
      });
      await deps.uploadJson(dataTypePath(type, `today/${opts.date}`), {
        fetched_at: new Date().toISOString(),
        date: opts.date,
        count: points.length,
        data: points,
      });
      summary[type] = { count: points.length, status: 'ok' };
    } catch (err) {
      summary[type] = { status: 'error', error: err instanceof Error ? err.message : String(err) };
    }
  }
  return summary;
}
```

Ensure `FetchStrategy` is imported from `googleHealth.ts` in `fitness.ts` (it already is — `SyncDeps.fetchList` uses it).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd api && npx vitest run src/handlers/fitness.test.ts -t freshenToday`
Expected: PASS (3 tests).

- [ ] **Step 6: Typecheck + full test file**

Run: `cd api && npx tsc --noEmit && npx vitest run src/handlers/fitness.test.ts`
Expected: no type errors; all fitness tests pass.

- [ ] **Step 7: Commit**

```bash
git add api/src/lib/googleHealth.ts api/src/handlers/fitness.ts api/src/handlers/fitness.test.ts
git commit -m "feat(fitness): freshenToday() — non-cursor-advancing same-day intraday read"
```

---

### Task 2: `POST /api/fitness/freshen` route

**Files:**
- Modify: `api/src/handlers/fitness.ts` (add `today()` helper + route on the `fitness` Hono instance)

**Interfaces:**
- Consumes: `freshenToday`, `FRESHEN_TYPES` (Task 1); `getOAuthConfig`, `getRefreshToken`, `refreshAccessToken`, `fetchListAll`, `uploadJson` (already imported/defined in `fitness.ts`).
- Produces: `POST /freshen` → `{ ok: boolean; freshened: FreshenSummary }`.

This is thin glue mirroring the existing `.post('/sync', …)` handler; it is verified live in Task 3 rather than by a brittle network-mocked route test.

- [ ] **Step 1: Add a `today()` helper**

Next to the existing `yesterday()` in `fitness.ts`:

```ts
function today(): string {
  return new Date().toISOString().slice(0, 10);
}
```

- [ ] **Step 2: Add the route**

On the `export const fitness = new Hono()` chain (alongside `.post('/sync', …)`):

```ts
  .post('/freshen', async (c) => {
    try {
      const { clientId, clientSecret } = getOAuthConfig();
      const refreshToken = await getRefreshToken();
      const accessToken = await refreshAccessToken({ refreshToken, clientId, clientSecret });

      const summary = await freshenToday(
        {
          uploadJson,
          fetchList: ({ dataType, filterField, filterDateField, startDate, endDate }) =>
            fetchListAll({ accessToken, dataType, filterField, filterDateField, startDate, endDate }),
        },
        { types: FRESHEN_TYPES, date: today() },
      );

      const anyError = Object.values(summary).some((r) => r.status === 'error');
      return c.json({ ok: !anyError, freshened: summary });
    } catch (err) {
      console.error('Freshen error:', err instanceof Error ? err.message : String(err));
      return c.json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  })
```

- [ ] **Step 3: Typecheck + full api test suite**

Run: `cd api && npx tsc --noEmit && npx vitest run`
Expected: no type errors; all tests pass (no regressions).

- [ ] **Step 4: Commit**

```bash
git add api/src/handlers/fitness.ts
git commit -m "feat(fitness): POST /freshen route — triggers freshenToday for FRESHEN_TYPES"
```

---

### Task 3: Live validation probe (GATE — do not skip)

**Purpose:** The premise that `list` returns *today's* sleep/HRV mid-morning is **unverified**. This task confirms it on real data before any scheduling is built. If today's sleep is empty at mid-morning, T-1 is inherent to Fitbit's scoring and un-clamping does not help — **stop here** and record the finding.

**Files:** none (deploy + curl + gsutil).

- [ ] **Step 1: Deploy the api**

Run: `npm run deploy:api`
(= `cd api && gcloud run deploy homehd-api --source . --region=europe-west2 --allow-unauthenticated --project=homehd-personal`)
Expected: new revision deployed.

- [ ] **Step 2: Trigger freshen mid-morning (run between ~09:30 and 11:00 local)**

```bash
curl -s -X POST https://homehd.web.app/api/fitness/freshen \
  -H "Authorization: Bearer $MAIN_API_KEY" | jq
```
Expected: `{ "ok": true, "freshened": { "sleep": { "count": …, "status": "ok" }, … } }`.

- [ ] **Step 3: Inspect what actually landed for today**

```bash
TODAY=$(date -u +%F)
gsutil cat gs://homehd-fitness/raw/sleep/today/$TODAY.json | jq '.count'
gsutil cat gs://homehd-fitness/raw/daily-heart-rate-variability/today/$TODAY.json | jq '.count'
gsutil cat gs://homehd-fitness/raw/daily-resting-heart-rate/today/$TODAY.json | jq '.count'
```

- [ ] **Step 4: Decide the gate**

- **`sleep` count > 0 (last night's sleep present) → PASS.** Un-clamping works; proceed to Task 4.
- **`sleep` count == 0 at mid-morning → FAIL.** Re-run once ~1h later to rule out timing. If still 0, T-1 is inherent: **do not build Task 4.** Record in the vault note (2026-06-22 thread) that `list`-for-today does not expose same-day sleep, and revisit the at-wake-ritual fallback (check-in + dialysis schedule as the same-day signal).

---

### Task 4: Mid-morning Cloud Scheduler triggers (only after Task 3 PASSES)

**Purpose:** Run `/freshen` a few times across the scoring window so the freshest available data is on hand by the ~09–10am ritual, with no webhook.

**Files:** none (gcloud).

- [ ] **Step 1: Confirm the existing daily-sync scheduler job's auth header shape**

```bash
gcloud scheduler jobs list --location=europe-west2 --project=homehd-personal
gcloud scheduler jobs describe <daily-fitness-sync-job> --location=europe-west2 --project=homehd-personal \
  --format='value(httpTarget.headers)'
```
Mirror the same `Authorization: Bearer …` header convention for the new jobs.

- [ ] **Step 2: Create three freshen jobs (09:00 / 10:00 / 11:00 Europe/London)**

```bash
for HH in 09 10 11; do
  gcloud scheduler jobs create http "fitness-freshen-$HH" \
    --location=europe-west2 \
    --schedule="0 $HH * * *" \
    --time-zone="Europe/London" \
    --uri="https://homehd.web.app/api/fitness/freshen" \
    --http-method=POST \
    --headers="Authorization=Bearer $MAIN_API_KEY" \
    --project=homehd-personal
done
```

- [ ] **Step 3: Force-run one job and verify**

```bash
gcloud scheduler jobs run fitness-freshen-10 --location=europe-west2 --project=homehd-personal
# then re-check the GCS today/ object timestamp
gsutil ls -l gs://homehd-fitness/raw/sleep/today/$(date -u +%F).json
```
Expected: object `fetched_at` / GCS update time reflects the just-run job.

- [ ] **Step 4: Record completion in the vault breadcrumb**

Add a short dated entry to `Home HD Knowledge Base and Tracking System.md` (2026-06-22 thread): freshen-today shipped, premise validated (sleep visible by ~Xam), webhooks not built. Note the `raw/{type}/today/{date}.json` namespace so the future readiness compute knows where same-day data lives.

---

## Out of Scope (separate cycles)

- **The readiness compute / energy-pacing tab** that *consumes* `raw/{type}/today/{date}.json` — that is the 2026-06-20 fitness-tab-redesign build (`daily_energy` Firestore doc, REST/STEADY/PUSH engine, LLM brief). This plan only makes same-day data *available*.
- **Webhooks** — explicitly rejected for this use case; mechanics recorded in the vault note for a future live-daytime-HR-alerts feature if ever wanted.
- **Raw `heart-rate` intraday freshening** — excluded from `FRESHEN_TYPES` (volume; only needed for daytime HR-ceiling, a Path B concern).

## Self-Review

- **Spec coverage:** un-clamp for today (Task 1 `freshenToday`, date=today, no cursor) ✓; on-demand trigger (Task 2 route) ✓; premise validation (Task 3 gate) ✓; morning cron (Task 4) ✓; cursor invariant (Global Constraints + Task 1 test asserts no sync_state in deps) ✓.
- **Placeholder scan:** all code blocks are concrete; the only `<…>` is the operator-supplied existing scheduler job name in Task 4 Step 1 (a lookup, not code).
- **Type consistency:** `FreshenDeps.fetchList` signature matches `SyncDeps.fetchList` and the real `fetchListAll` params; `FRESHEN_TYPES` is `readonly SyncType[]`, accepted by `freshenToday`'s `opts.types`; route passes `FRESHEN_TYPES` + `today()` string. `dataTypePath(type, \`today/${date}\`)` → `raw/{type}/today/{date}.json` matches the Task 1 test assertion.
