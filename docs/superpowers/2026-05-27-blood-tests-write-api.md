# Blood Tests Write API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `POST /api/blood-tests` to write new rows to Firestore, and update `GET /api/blood-tests` to merge static JSON rows with Firestore rows so new monthly data is queryable without a redeploy.

**Architecture:** The existing static `blood_tests.json` baked into the Docker image stays as the historical backfill. New rows are written to a Firestore `blood_tests` collection keyed by `lab_id`. On every GET, the handler fetches Firestore rows, merges them with the static rows (Firestore wins on `lab_id` collision), then filters and returns. No schema changes to the API response — callers see a single merged dataset.

**Tech Stack:** Node 20, Hono 4, TypeScript (NodeNext modules), Zod, `@google-cloud/firestore`, Vitest. Cloud Run + Firestore in `homehd-personal` GCP project.

---

## Context for the implementer

### Repo layout (relevant paths)

```
api/
  src/
    index.ts                    # Hono app, mounts all routes
    handlers/
      bloodTests.ts             # GET /api/blood-tests — reads static JSON, returns filtered rows
    lib/
      auth.ts                   # bearerAuth middleware
      auth.test.ts
      queryFilter.ts            # filterRows(), isValidBound()
      queryFilter.test.ts
    schemas/
      bloodTests.ts             # BloodTestRowSchema, PHASES
    data/
      blood_tests.json          # ~2400 rows, static backfill
  package.json
  tsconfig.json
  Dockerfile
```

### Key constraints

- **TypeScript `NodeNext` modules** — all internal imports must use `.js` extensions, even for `.ts` source files (e.g. `import { x } from './foo.js'`).
- **`noUnusedLocals` / `noUnusedParameters` strict** — don't leave dead code.
- **Test files excluded from `tsc`** — the tsconfig `exclude` already lists `src/**/*.test.ts`. Tests run via `npm test` (vitest).
- **Firestore ADC** — on Cloud Run, credentials come from the metadata server automatically. Locally: `gcloud auth application-default login` + `GOOGLE_CLOUD_PROJECT=homehd-personal`.
- **Firestore Native mode** must already be enabled in `homehd-personal`. Verify at console.firebase.google.com before deploying.
- **Cloud Run SA** needs `roles/datastore.user` — one-time IAM grant in Task 6.

### Existing `GET /api/blood-tests` behaviour (preserved verbatim)

- Query params: `marker` (comma-separated), `phase` (comma-separated, validated against `PHASES`), `from`/`to` (`YYYY-MM` or `YYYY-MM-DD`, inclusive).
- Response: `{ count: number, rows: BloodTestRow[] }`.
- Invalid phase/bound → `400`.

### `BloodTestRow` shape (existing)

```typescript
{
  marker: string;
  datetime: string;       // ISO, e.g. "2026-05-18T14:18:00"
  value: number;
  unit: string;
  ref_low: number | null;
  ref_high: number | null;
  timing: 'pre' | 'post' | '';
  note: string;
  source: string;
  lab_id: string;         // natural primary key — Firestore doc ID
  phase: 'admission' | 'in-center-hd' | 'home-hd';
  created_at: string;     // ISO, set by server on write
  qualitative: boolean;
}
```

---

## File map

| File | Action | What changes |
|---|---|---|
| `api/package.json` | Modify | Add `@google-cloud/firestore` dependency |
| `api/src/schemas/bloodTests.ts` | Modify | Add `BloodTestRowInputSchema`, `PostBodySchema` |
| `api/src/schemas/bloodTests.test.ts` | **Create** | Tests for `PostBodySchema` |
| `api/src/lib/mergeRows.ts` | **Create** | Pure `mergeRows(static, firestore)` function |
| `api/src/lib/mergeRows.test.ts` | **Create** | Tests for `mergeRows` |
| `api/src/lib/firestore.ts` | **Create** | Firestore singleton `getDb()` |
| `api/src/handlers/bloodTests.ts` | Modify | Add POST handler; update GET to merge |
| `api/src/handlers/bloodTests.test.ts` | **Create** | Handler integration tests (Firestore mocked) |

---

## Task 1: Install Firestore SDK

**Files:**
- Modify: `api/package.json`

- [ ] **Step 1: Install the package**

```bash
cd /path/to/treatment_tracker/api
npm install @google-cloud/firestore
```

- [ ] **Step 2: Verify the build still passes**

```bash
npm run build
```

Expected: exits `0`, `dist/` contains `handlers/bloodTests.js`.

- [ ] **Step 3: Commit**

```bash
git add package.json package-lock.json
git commit -m "chore: add @google-cloud/firestore dependency"
```

---

## Task 2: Add POST body schemas

**Files:**
- Modify: `api/src/schemas/bloodTests.ts`
- Create: `api/src/schemas/bloodTests.test.ts`

- [ ] **Step 1: Write the failing test**

Create `api/src/schemas/bloodTests.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { PostBodySchema } from './bloodTests.js';

const validRow = {
  marker: 'creatinine',
  datetime: '2026-06-15T14:00:00',
  value: 980,
  unit: 'umol/L',
  ref_low: 64,
  ref_high: 104,
  timing: 'pre' as const,
  note: '',
  source: 'imperial-pkb',
  lab_id: '99261234567',
  phase: 'home-hd' as const,
  qualitative: false,
};

describe('PostBodySchema', () => {
  it('accepts a valid rows array', () => {
    expect(PostBodySchema.safeParse({ rows: [validRow] }).success).toBe(true);
  });

  it('rejects an empty rows array', () => {
    expect(PostBodySchema.safeParse({ rows: [] }).success).toBe(false);
  });

  it('rejects rows with an invalid phase', () => {
    expect(PostBodySchema.safeParse({ rows: [{ ...validRow, phase: 'icu' }] }).success).toBe(false);
  });

  it('rejects rows with an invalid timing', () => {
    expect(PostBodySchema.safeParse({ rows: [{ ...validRow, timing: 'during' }] }).success).toBe(false);
  });

  it('rejects rows missing required fields', () => {
    const { marker: _m, ...noMarker } = validRow;
    expect(PostBodySchema.safeParse({ rows: [noMarker] }).success).toBe(false);
  });

  it('does not require created_at on input rows', () => {
    const result = PostBodySchema.safeParse({ rows: [validRow] });
    expect(result.success).toBe(true);
    if (result.success) {
      expect('created_at' in result.data.rows[0]).toBe(false);
    }
  });

  it('accepts multiple rows', () => {
    const result = PostBodySchema.safeParse({ rows: [validRow, { ...validRow, lab_id: 'other' }] });
    expect(result.success).toBe(true);
    if (result.success) expect(result.data.rows).toHaveLength(2);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
npm test -- bloodTests
```

Expected: FAIL — `PostBodySchema` is not exported from `bloodTests.ts`.

- [ ] **Step 3: Add the schemas**

Append to `api/src/schemas/bloodTests.ts` (keep all existing exports unchanged):

```typescript
export const BloodTestRowInputSchema = BloodTestRowSchema.omit({ created_at: true });
export type BloodTestRowInput = z.infer<typeof BloodTestRowInputSchema>;

export const PostBodySchema = z.object({
  rows: z.array(BloodTestRowInputSchema).min(1).max(100),
});
export type PostBody = z.infer<typeof PostBodySchema>;
```

- [ ] **Step 4: Run test to verify it passes**

```bash
npm test -- bloodTests
```

Expected: 7 tests pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add src/schemas/bloodTests.ts src/schemas/bloodTests.test.ts
git commit -m "feat: add PostBodySchema for blood-test write endpoint"
```

---

## Task 3: Add mergeRows pure function

**Files:**
- Create: `api/src/lib/mergeRows.ts`
- Create: `api/src/lib/mergeRows.test.ts`

- [ ] **Step 1: Write the failing test**

Create `api/src/lib/mergeRows.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { mergeRows } from './mergeRows.js';
import type { BloodTestRow } from '../schemas/bloodTests.js';

function row(over: Partial<BloodTestRow>): BloodTestRow {
  return {
    marker: 'creatinine', datetime: '2026-05-18T14:00:00', value: 1073,
    unit: 'umol/L', ref_low: 64, ref_high: 104, timing: 'pre', note: '',
    source: 'imperial-pkb', lab_id: 'abc123', phase: 'home-hd',
    created_at: '2026-05-22T10:00:00', qualitative: false, ...over,
  };
}

describe('mergeRows', () => {
  it('returns static rows when Firestore rows is empty', () => {
    const result = mergeRows([row({ lab_id: 'a' })], []);
    expect(result).toHaveLength(1);
    expect(result[0].lab_id).toBe('a');
  });

  it('returns Firestore rows when static rows is empty', () => {
    const result = mergeRows([], [row({ lab_id: 'b' })]);
    expect(result).toHaveLength(1);
    expect(result[0].lab_id).toBe('b');
  });

  it('combines rows from both sources with no overlap', () => {
    const result = mergeRows([row({ lab_id: 'a' })], [row({ lab_id: 'b' })]);
    expect(result).toHaveLength(2);
  });

  it('Firestore row wins on lab_id collision', () => {
    const staticRow = row({ lab_id: 'x', value: 100, created_at: '2026-05-01T00:00:00' });
    const fsRow    = row({ lab_id: 'x', value: 999, created_at: '2026-05-27T00:00:00' });
    const result = mergeRows([staticRow], [fsRow]);
    expect(result).toHaveLength(1);
    expect(result[0].value).toBe(999);
  });

  it('returns empty array when both inputs are empty', () => {
    expect(mergeRows([], [])).toHaveLength(0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
npm test -- mergeRows
```

Expected: FAIL — `mergeRows` module not found.

- [ ] **Step 3: Implement mergeRows**

Create `api/src/lib/mergeRows.ts`:

```typescript
import type { BloodTestRow } from '../schemas/bloodTests.js';

export function mergeRows(staticRows: BloodTestRow[], firestoreRows: BloodTestRow[]): BloodTestRow[] {
  const map = new Map<string, BloodTestRow>();
  for (const r of staticRows) map.set(r.lab_id, r);
  for (const r of firestoreRows) map.set(r.lab_id, r);
  return Array.from(map.values());
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
npm test -- mergeRows
```

Expected: 5 tests pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add src/lib/mergeRows.ts src/lib/mergeRows.test.ts
git commit -m "feat: add mergeRows — dedupe static + Firestore rows by lab_id"
```

---

## Task 4: Add Firestore client singleton

**Files:**
- Create: `api/src/lib/firestore.ts`

No unit test — the singleton wraps the Firestore SDK which requires ADC; it is covered indirectly by the mocked handler tests in Task 5.

- [ ] **Step 1: Create the singleton**

Create `api/src/lib/firestore.ts`:

```typescript
import { Firestore } from '@google-cloud/firestore';

let _db: Firestore | null = null;

export function getDb(): Firestore {
  if (!_db) _db = new Firestore();
  return _db;
}
```

- [ ] **Step 2: Verify the build passes**

```bash
npm run build
```

Expected: exits `0`, no TypeScript errors.

- [ ] **Step 3: Commit**

```bash
git add src/lib/firestore.ts
git commit -m "feat: add Firestore singleton"
```

---

## Task 5: Update bloodTests handler — POST + merged GET

**Files:**
- Modify: `api/src/handlers/bloodTests.ts`
- Create: `api/src/handlers/bloodTests.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `api/src/handlers/bloodTests.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { Hono } from 'hono';
import { bearerAuth } from '../lib/auth.js';

const { mockCommit, mockSet, mockDoc, mockGet } = vi.hoisted(() => ({
  mockCommit: vi.fn(),
  mockSet: vi.fn(),
  mockDoc: vi.fn(),
  mockGet: vi.fn(),
}));

vi.mock('../lib/firestore.js', () => ({
  getDb: () => ({
    collection: () => ({ get: mockGet, doc: mockDoc }),
    batch: () => ({ set: mockSet, commit: mockCommit }),
  }),
}));

import { bloodTests } from './bloodTests.js';

function makeApp() {
  const app = new Hono();
  app.use('/api/*', bearerAuth(() => 'test-key'));
  app.route('/api/blood-tests', bloodTests);
  return app;
}

function get(app: Hono, path: string) {
  return app.request(path, { headers: { Authorization: 'Bearer test-key' } });
}

function post(app: Hono, body: unknown) {
  return app.request('/api/blood-tests', {
    method: 'POST',
    headers: { Authorization: 'Bearer test-key', 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

const validRow = {
  marker: 'creatinine', datetime: '2026-06-15T14:00:00', value: 980,
  unit: 'umol/L', ref_low: 64, ref_high: 104, timing: 'pre', note: '',
  source: 'imperial-pkb', lab_id: '99261234567', phase: 'home-hd', qualitative: false,
};

describe('GET /api/blood-tests', () => {
  beforeEach(() => {
    mockGet.mockResolvedValue({ docs: [] });
  });

  it('returns 200 with count and rows', async () => {
    const res = await get(makeApp(), '/api/blood-tests');
    expect(res.status).toBe(200);
    const body = await res.json() as { count: number; rows: unknown[] };
    expect(typeof body.count).toBe('number');
    expect(Array.isArray(body.rows)).toBe(true);
    expect(body.rows).toHaveLength(body.count);
  });

  it('merges Firestore rows into the response', async () => {
    const fsRow = { ...validRow, lab_id: 'fs-only', created_at: '2026-05-27T00:00:00' };
    mockGet.mockResolvedValue({ docs: [{ data: () => fsRow }] });
    const res = await get(makeApp(), '/api/blood-tests?marker=creatinine&phase=home-hd&from=2026-06&to=2026-06');
    expect(res.status).toBe(200);
    const body = await res.json() as { rows: { lab_id: string }[] };
    expect(body.rows.some((r) => r.lab_id === 'fs-only')).toBe(true);
  });

  it('returns 400 for invalid phase', async () => {
    const res = await get(makeApp(), '/api/blood-tests?phase=bad-phase');
    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid from bound', async () => {
    const res = await get(makeApp(), '/api/blood-tests?from=not-a-date');
    expect(res.status).toBe(400);
  });
});

describe('POST /api/blood-tests', () => {
  beforeEach(() => {
    mockCommit.mockResolvedValue(undefined);
    mockSet.mockReturnValue(undefined);
    mockDoc.mockReturnValue({});
  });

  it('returns ok:true and count on valid input', async () => {
    const res = await post(makeApp(), { rows: [validRow] });
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean; count: number };
    expect(body.ok).toBe(true);
    expect(body.count).toBe(1);
  });

  it('writes to Firestore keyed by lab_id with server-set created_at', async () => {
    await post(makeApp(), { rows: [validRow] });
    expect(mockDoc).toHaveBeenCalledWith('99261234567');
    expect(mockSet).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ lab_id: '99261234567', created_at: expect.any(String) }),
    );
  });

  it('accepts multiple rows and returns the correct count', async () => {
    const rows = [validRow, { ...validRow, lab_id: 'other-id' }];
    const res = await post(makeApp(), { rows });
    expect(res.status).toBe(200);
    const body = await res.json() as { count: number };
    expect(body.count).toBe(2);
  });

  it('returns 400 for empty rows array', async () => {
    const res = await post(makeApp(), { rows: [] });
    expect(res.status).toBe(400);
  });

  it('returns 400 for rows with missing required fields', async () => {
    const res = await post(makeApp(), { rows: [{ marker: 'creatinine' }] });
    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid JSON body', async () => {
    const res = await makeApp().request('/api/blood-tests', {
      method: 'POST',
      headers: { Authorization: 'Bearer test-key', 'Content-Type': 'application/json' },
      body: 'not-json',
    });
    expect(res.status).toBe(400);
  });

  it('returns 401 without auth header', async () => {
    const res = await makeApp().request('/api/blood-tests', { method: 'POST' });
    expect(res.status).toBe(401);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
npm test -- handlers/bloodTests
```

Expected: FAIL — tests import `./bloodTests.js` which has no POST handler and no merge logic.

- [ ] **Step 3: Rewrite the handler**

Replace the entire contents of `api/src/handlers/bloodTests.ts`:

```typescript
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Hono } from 'hono';
import { filterRows, isValidBound, type QueryParams } from '../lib/queryFilter.js';
import { mergeRows } from '../lib/mergeRows.js';
import { getDb } from '../lib/firestore.js';
import {
  PHASES,
  BloodTestRowSchema,
  PostBodySchema,
  type BloodTestRow,
} from '../schemas/bloodTests.js';

const here = dirname(fileURLToPath(import.meta.url));
const staticRows: BloodTestRow[] = JSON.parse(
  readFileSync(resolve(here, '../data/blood_tests.json'), 'utf8'),
);

export const bloodTests = new Hono()
  .get('/', async (c) => {
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

    const snap = await getDb().collection('blood_tests').get();
    const firestoreRows: BloodTestRow[] = snap.docs
      .map((d) => BloodTestRowSchema.safeParse(d.data()))
      .filter((r): r is { success: true; data: BloodTestRow } => r.success)
      .map((r) => r.data);

    const merged = mergeRows(staticRows, firestoreRows);
    const result = filterRows(merged, p);
    return c.json({ count: result.length, rows: result });
  })
  .post('/', async (c) => {
    let body: unknown;
    try {
      body = await c.req.json();
    } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }

    const parsed = PostBodySchema.safeParse(body);
    if (!parsed.success) {
      return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);
    }

    const now = new Date().toISOString();
    const db = getDb();
    const col = db.collection('blood_tests');
    const batch = db.batch();
    for (const row of parsed.data.rows) {
      batch.set(col.doc(row.lab_id), { ...row, created_at: now });
    }
    await batch.commit();

    return c.json({ ok: true, count: parsed.data.rows.length });
  });
```

- [ ] **Step 4: Run all tests**

```bash
npm test
```

Expected: all tests pass (auth, queryFilter, mergeRows, bloodTests schemas, bloodTests handler).

- [ ] **Step 5: Verify build**

```bash
npm run build
```

Expected: exits `0`, no TypeScript errors.

- [ ] **Step 6: Commit**

```bash
git add src/handlers/bloodTests.ts src/handlers/bloodTests.test.ts
git commit -m "feat: add POST /api/blood-tests and merge Firestore rows into GET"
```

---

## Task 6: GCP one-time setup — Firestore permissions

This is a one-time IAM step. Skip if already done.

- [ ] **Step 1: Confirm Firestore is enabled in Native mode**

Open https://console.firebase.google.com → project `homehd-personal` → Firestore Database. If it shows "Create database", create it in **Native mode**, region `europe-west2`. If it already exists, skip.

- [ ] **Step 2: Grant the Cloud Run service account Firestore access**

```bash
PROJECT_NUMBER=$(gcloud projects describe homehd-personal --format='value(projectNumber)')
gcloud projects add-iam-policy-binding homehd-personal \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/datastore.user"
```

Expected: output includes `Updated IAM policy for project [homehd-personal]`.

---

## Task 7: Deploy and smoke test

- [ ] **Step 1: Deploy the API**

```bash
cd /path/to/treatment_tracker/api
gcloud run deploy homehd-api \
  --source . \
  --region=europe-west2 \
  --allow-unauthenticated \
  --set-secrets=MAIN_API_KEY=main-api-key:latest \
  --project=homehd-personal
```

Expected: `Service [homehd-api] revision [...] has been deployed`.

- [ ] **Step 2: Load the API key**

```bash
KEY=$(security find-generic-password -a "$USER" -s "homehd-main-key" -w)
```

- [ ] **Step 3: Verify GET still works (Firestore empty)**

```bash
curl -s -H "Authorization: Bearer $KEY" \
  'https://homehd.web.app/api/blood-tests?to=1900-01-01'
```

Expected: `{"count":0,"rows":[]}`.

- [ ] **Step 4: POST a test row**

```bash
curl -s -X POST \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "rows": [{
      "marker": "creatinine",
      "datetime": "2026-06-15T14:00:00",
      "value": 980,
      "unit": "umol/L",
      "ref_low": 64,
      "ref_high": 104,
      "timing": "pre",
      "note": "smoke test row",
      "source": "imperial-pkb",
      "lab_id": "smoke-test-001",
      "phase": "home-hd",
      "qualitative": false
    }]
  }' \
  'https://homehd.web.app/api/blood-tests'
```

Expected: `{"ok":true,"count":1}`.

- [ ] **Step 5: GET to verify the row is returned**

```bash
curl -s -H "Authorization: Bearer $KEY" \
  'https://homehd.web.app/api/blood-tests?marker=creatinine&phase=home-hd&from=2026-06&to=2026-06'
```

Expected: `count` ≥ 1, `rows` contains an entry with `"lab_id":"smoke-test-001"` and `"note":"smoke test row"`.

- [ ] **Step 6: Clean up the smoke-test row (optional but recommended)**

The Firestore console at https://console.firebase.google.com → `homehd-personal` → Firestore → `blood_tests` collection → delete document `smoke-test-001`.

- [ ] **Step 7: Commit the plan as complete**

```bash
git add .
git commit -m "chore: blood-tests write API — all tasks complete"
```

---

## Self-review

**Spec coverage:**
- POST endpoint accepting rows array ✅ Task 5
- Firestore write keyed by `lab_id` ✅ Task 5
- GET merges static + Firestore rows ✅ Task 5
- Firestore wins on `lab_id` collision ✅ Task 3 (mergeRows)
- `created_at` set by server, not caller ✅ Task 5 (POST handler)
- Existing GET filtering unchanged ✅ Task 5 (param parsing preserved verbatim)
- Firestore IAM grant ✅ Task 6
- End-to-end smoke test ✅ Task 7

**Placeholder scan:** None found. All steps include exact code or commands.

**Type consistency:**
- `BloodTestRowInputSchema` → `BloodTestRowInput` (Task 2) used as `parsed.data.rows[0]` shape in Task 5 handler ✅
- `PostBodySchema` → `PostBody` (Task 2) used via `PostBodySchema.safeParse` in Task 5 ✅
- `mergeRows(staticRows, firestoreRows)` signature (Task 3) matches call site in Task 5 ✅
- `getDb()` returns `Firestore` (Task 4); `.collection().get()` and `.batch()` match Firestore SDK API ✅
