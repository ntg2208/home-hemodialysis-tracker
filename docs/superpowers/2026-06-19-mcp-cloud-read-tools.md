# MCP Cloud Read Tools — data-context layer on Cloud Run

> Status: **Spec** (design approved 2026-06-19). Implementation plan to be appended below by writing-plans.

## Summary

Give external MCP clients (Claude Code, Gemini CLI) read access to the patient's
health data by embedding an **MCP server inside the existing `homehd-api` Cloud Run
service**, mounted at `/api/mcp`, exposing **read-only Tools**. This is the
"data-context" half of the deferred MCP Phase 2 roadmap, served from the cloud
(always-on) rather than the phone.

The phone's embedded MCP server (already shipped, `feat/mcp-phase2-tools`) keeps its
role as the **action/navigation** layer. This cloud server is the **read/context**
layer. The two are independent: phone = drive the app, cloud = read the data.

## Goal & non-goals

**Goal:** an agent connected to `https://<cloud-run-url>/api/mcp` can call tools to
read treatment sessions, blood markers, out-of-range flags, and inventory — and
reason over them — without the phone being on.

**Non-goals (this cycle):**
- No writes. Read-only surface.
- No patient-KB tool yet (KB is not persisted server-side — see Future).
- No fitness tool yet (dropped for a tighter first cut; `fitness/summary` exists and
  can be wrapped later).
- No foreground service / bearer-key work on the *phone* server — out of scope.
- No new Cloud Run service — reuse `homehd-api`.

## Context (current state, verified 2026-06-19)

- `homehd-api` is a Hono app (Node 20) on Cloud Run `europe-west2`, project
  `homehd-personal`. Entry: `api/src/index.ts`.
- Auth: `app.use('/api/*', bearerAuth(() => process.env.MAIN_API_KEY))` — bearer
  guard over everything under `/api/*` (`api/src/lib/auth.ts`).
- Read logic today is **welded into Hono route closures**, not reusable functions:
  - `handlers/bloodTests.ts` `GET /` — Firestore `blood_tests` + static
    `data/blood_tests.json`, merged (`mergeRows`) and filtered (`queryFilter`) by
    `marker` / `phase` / `from` / `to`.
  - `handlers/inventory.ts` `GET /` — `inventory_stock` + `inventory_config` (cycle,
    pak) + `pak_history`, with computed fields.
  - `handlers/treatment.ts` — **no GET for sessions/readings.** Treatment data is
    read client-side via the Firestore SDK. Collections `treatment_sessions` /
    `treatment_readings` exist; `POST /sync-to-sheet` shows the server-side read
    pattern to copy.
  - `handlers/kb.ts` `GET /` — **stub** (`{ ok: true, note: 'coming soon' }`). KB is
    client-side only (`kbStore` in Flutter).
  - `handlers/fitness.ts` `GET /summary` — computed summary (exists; not used here).

## Key decision: Tools, not Resources

The roadmap notes say "Resources (`health://`)". This spec exposes **Tools** instead.

- The data access is **parameterized** (markers by name/range/phase, sessions by
  range) — a Tool shape, not an addressable-document shape.
- Clients (Claude Code, Gemini CLI) **autonomously invoke Tools**; MCP Resources
  generally require the user to *manually attach* them, so a Resource-only surface
  would likely sit unused for "let the agent reason over my data."
- Lets us mirror the proven in-app chat retrieval surface
  (`get_sessions` / `get_blood_markers` / `get_out_of_range_markers` /
  `get_inventory`) directly — maximum reuse.

## Architecture

```
MCP client (Claude Code / Gemini CLI)
   │  HTTP + Authorization: Bearer <MAIN_API_KEY>
   ▼
homehd-api (Hono, Cloud Run)
   ├─ app.use('/api/*', bearerAuth)        ← MCP route sits INSIDE this guard
   ├─ /api/blood-tests, /api/inventory ... ← existing REST routes (unchanged)
   └─ /api/mcp   →  StreamableHTTPServerTransport (stateless)
                       │
                       ▼
                    McpServer  ── 4 read tools
                       │
                       ▼
                 api/src/lib/reads/*.ts   ← extracted read fns (shared)
                       │
                       ▼
                    Firestore
```

### Refactor: extract read functions (shared by REST + MCP)

Pull the welded read logic into pure-ish functions so both the existing REST routes
and the new MCP tools call the same code — no duplication, existing endpoints keep
identical behavior:

- `api/src/lib/reads/bloodTestReads.ts` — `getBloodMarkers(params)` (marker, phase,
  from, to). Refactor `bloodTests.ts` `GET /` to call it.
- `api/src/lib/reads/inventoryReads.ts` — `getInventory()`. Refactor `inventory.ts`
  `GET /` to call it.
- `api/src/lib/reads/sessionReads.ts` — `getSessions(params)` (**new**; read
  `treatment_sessions` + `treatment_readings`, join readings per session, support
  `from`/`to`/`limit`). Pattern lifted from `sync-to-sheet`.
- Out-of-range: a helper over blood rows, `getOutOfRangeMarkers(params)`, flagging
  rows where `value < ref_low` or `value > ref_high`. Lives in `bloodTestReads.ts`.

### MCP server module

- `api/src/mcp/server.ts` — builds the `McpServer`, registers the 4 tools. Each tool
  validates its args (zod, reusing existing schemas where possible), calls the read
  fn, returns JSON as MCP `TextContent`.
- Mounted into Hono at `/api/mcp`, **inside** `bearerAuth`.
- **Transport: stateless Streamable HTTP** (`StreamableHTTPServerTransport` with
  `sessionIdGenerator: undefined`). Cloud Run scales to zero and runs multiple
  instances, so any session/SSE-affinity mode would break when requests land on
  different instances.

> **Implementation unknown to pin before the plan finalizes:** the exact
> `@modelcontextprotocol/sdk` Streamable HTTP API + how to bridge it to a Hono /
> `@hono/node-server` route (the SDK transport speaks Node `req`/`res`). The
> Streamable HTTP API has shifted across SDK versions. Resolve via a context7 docs
> check + a tiny throwaway spike (mirror the phone-side Task 2 spike), then delete the
> spike. This gates the handler code.

## Tool surface

| Tool | Args | Returns | Backed by |
|---|---|---|---|
| `get_sessions` | `from?` (ISO date), `to?`, `limit?` | sessions with joined readings | `sessionReads.getSessions` (new) |
| `get_blood_markers` | `marker?` (csv), `phase?` (csv), `from?`, `to?` | blood rows | `bloodTestReads.getBloodMarkers` (extracted) |
| `get_out_of_range_markers` | `from?`, `to?` | rows outside `ref_low`/`ref_high` | `bloodTestReads.getOutOfRangeMarkers` (new helper) |
| `get_inventory` | — | stock + config + computed | `inventoryReads.getInventory` (extracted) |

Each tool's description should carry the symptom-driven hints from the in-app chat
spec (e.g. itching → phosphate/calcium) so the model picks the right marker.

## Auth & client connection

Reuse `MAIN_API_KEY`. No new secret. The `/api/mcp` route inherits the existing
`/api/*` bearer guard — an unauthenticated health-data endpoint is exactly the leak
to avoid, so confirm the mount is inside the middleware.

Prefer the **Firebase Hosting rewrite** as the stable URL: `homehd.web.app/api/**`
already rewrites to this Cloud Run service, so `https://homehd.web.app/api/mcp` is a
permanent endpoint that survives Cloud Run revision/URL changes. (Stateless Streamable
HTTP is request/response, so it passes through the rewrite cleanly.) The raw Cloud Run
URL works too.

```bash
claude mcp add --transport http homehd \
  https://homehd.web.app/api/mcp \
  --header "Authorization: Bearer <MAIN_API_KEY>"
```

## Testing

- Unit tests for each extracted read fn (`getBloodMarkers`, `getInventory`,
  `getSessions`, `getOutOfRangeMarkers`) — this boundary currently has no tests.
  Use the existing vitest setup; mock Firestore as the existing handler tests do.
- One integration test: in-process MCP client → `tools/list` returns 4 →
  `tools/call get_blood_markers` round-trips a known fixture. Mirrors the phone-side
  E2E already done.
- Existing REST route tests must still pass after the extract refactor (behavior
  unchanged).

## Deploy

Same as `homehd-api` today (no new service): `npm run build` in `api/`, deploy the
Cloud Run service. Verify `/api/mcp` answers `tools/list` with the bearer header and
401s without it.

## Future: patient KB & RAG (forward-reference, not this cycle)

The user wants custom context via the patient KB next. Two prerequisites and a
size-dependent fork, documented so the path is clear:

**Prerequisite — persist KB server-side.** KB is currently client-side (`kbStore`)
and the Cloud Run `kb` handler is a stub. Both KB options below need the KB in
Firestore first (a `kb` collection), with the in-app KB editor writing through
Cloud Run.

**Then, size-dependent:**
- **Small KB (likely for a long time): full-context `get_kb` tool.** Return the whole
  KB. No embeddings, no staleness, model sees everything. Simplest; hard to beat for a
  small corpus.
- **When KB outgrows the context budget (or semantic recall across years is wanted):
  `search_kb` RAG tool.** Same MCP interface, RAG implementation behind it:
  - Embeddings: **Vertex AI** (`europe-west2`, DPA, no training) — *not* the AI Studio
    key, because embedding KB text sends special-category health data to the API
    (per the 2026-06-05 chat privacy review).
  - Vector store: **Firestore vector search** (`findNearest` KNN) — store an
    `embedding` field per KB doc, query top-k. Zero new infra. For a tiny corpus,
    brute-force cosine per request is also fine. **Avoid** Vertex AI Vector
    Search / Matching Engine (always-on min nodes, real cost).
  - Embed-on-write: compute + store each note's embedding when added/edited.
  - Cloud Run note: don't hold an in-memory index across requests (cold starts /
    multi-instance rebuild it) — rely on Firestore vector search or per-request
    brute force.

Switching `get_kb` → `search_kb` is invisible to the client; only the implementation
changes.

---

# MCP Cloud Read Tools — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose four read-only MCP tools (`get_sessions`, `get_blood_markers`, `get_out_of_range_markers`, `get_inventory`) over a stateless Streamable HTTP endpoint at `POST /api/mcp` inside the existing `homehd-api` Cloud Run service.

**Architecture:** Extract the welded Firestore-read logic from the existing Hono handlers into shared `api/src/lib/reads/*` functions, so both the REST routes and the new MCP tools call one code path. Build an `McpServer` that registers the four tools, and mount it on a Hono route that bridges to the SDK's Node transport via `@hono/node-server`'s raw `incoming`/`outgoing`, inside the existing `MAIN_API_KEY` bearer guard.

**Tech Stack:** Node 20, TypeScript (ESM, `.js` import specifiers), Hono 4 + `@hono/node-server`, `@modelcontextprotocol/sdk`, `@google-cloud/firestore`, zod 3, vitest.

## Global Constraints

- ESM project: all relative imports use the `.js` extension (e.g. `'../lib/firestore.js'`), matching the existing codebase.
- Reuse `getDb()` from `api/src/lib/firestore.js` for all Firestore access — never construct `new Firestore()` ad hoc in new code.
- The MCP route MUST sit **inside** `app.use('/api/*', bearerAuth(...))` — it must 401 without `Authorization: Bearer <MAIN_API_KEY>`.
- Transport is **stateless**: `new StreamableHTTPServerTransport({ sessionIdGenerator: undefined })`, a fresh transport + `McpServer` per request.
- Tools are **read-only** — no Firestore writes anywhere in this plan.
- Existing REST route behavior must not change; existing tests must stay green after each refactor.
- Run all commands from the `api/` directory. Test runner: `npm test` (vitest).

---

### Task 1: Add the SDK and pin the Streamable-HTTP + Hono bridge via a spike

**Files:**
- Modify: `api/package.json` (add dependency)
- Create (throwaway): `api/src/mcp/spike.ts` (deleted at end of task)

**Interfaces:**
- Produces (recorded in the Update Log of this doc, consumed by Tasks 5–6): the exact import paths for `McpServer` and `StreamableHTTPServerTransport`, the `registerTool` signature, and the confirmed Hono bridge symbols (`c.env.incoming`, `c.env.outgoing`, `RESPONSE_ALREADY_SENT`).

- [ ] **Step 1: Install the SDK**

```bash
cd api && npm install @modelcontextprotocol/sdk
```

- [ ] **Step 2: Write a throwaway spike route**

Create `api/src/mcp/spike.ts`. Use the stable v1.x subpath imports below; if `npm ls @modelcontextprotocol/sdk` shows a 2.x line, switch to the modular packages (`@modelcontextprotocol/server`, `@modelcontextprotocol/node`) and record the change.

```ts
import { Hono } from 'hono';
import { serve, RESPONSE_ALREADY_SENT } from '@hono/node-server';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { z } from 'zod';

const app = new Hono();

app.post('/api/mcp', async (c) => {
  const { incoming, outgoing } = c.env as unknown as {
    incoming: IncomingMessage;
    outgoing: ServerResponse;
  };
  const body = await c.req.json().catch(() => undefined);

  const server = new McpServer({ name: 'spike', version: '0.0.0' });
  server.registerTool(
    'echo',
    { description: 'echo back', inputSchema: { text: z.string() } },
    async ({ text }) => ({ content: [{ type: 'text', text }] }),
  );

  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
  outgoing.on('close', () => { transport.close(); server.close(); });
  await server.connect(transport);
  await transport.handleRequest(incoming, outgoing, body);
  return RESPONSE_ALREADY_SENT;
});

serve({ fetch: app.fetch, port: 8787 });
console.log('spike on :8787/api/mcp');
```

- [ ] **Step 3: Run the spike and round-trip a client**

```bash
cd api && npx tsx src/mcp/spike.ts
```

In another shell, list tools and call `echo`:

```bash
npx -y @modelcontextprotocol/inspector --cli http://localhost:8787/api/mcp --method tools/list
npx -y @modelcontextprotocol/inspector --cli http://localhost:8787/api/mcp \
  --method tools/call --tool-name echo --tool-arg text=hi
```

Expected: `tools/list` returns the `echo` tool; `tools/call` returns content `hi`.

- [ ] **Step 4: Record findings in this doc's Update Log**

Append a dated entry to `docs/superpowers/2026-06-19-mcp-cloud-read-tools.md` noting: installed SDK version, the exact import paths that worked, the `registerTool` signature, and that the `c.env.incoming`/`c.env.outgoing` + `RESPONSE_ALREADY_SENT` bridge round-tripped. If any symbol differed, write the corrected form — Tasks 5–6 depend on it.

- [ ] **Step 5: Delete the spike, commit the dependency**

```bash
rm api/src/mcp/spike.ts
cd api && git add package.json package-lock.json && \
  git commit -m "chore(mcp): add @modelcontextprotocol/sdk (API + Hono bridge pinned via spike)"
```

---

### Task 2: Extract blood-test reads + out-of-range helper

**Files:**
- Create: `api/src/lib/reads/bloodTestReads.ts`
- Test: `api/src/lib/reads/bloodTestReads.test.ts`
- Modify: `api/src/handlers/bloodTests.ts` (GET `/` calls the extracted fn)

**Interfaces:**
- Consumes: `filterRows`, `QueryParams` from `../queryFilter.js`; `mergeRows` from `../mergeRows.js`; `BloodTestRowSchema`, `BloodTestRow` from `../../schemas/bloodTests.js`; `getDb` from `../firestore.js`.
- Produces: `selectOutOfRange(rows: BloodTestRow[]): BloodTestRow[]` (pure); `fetchBloodRows(): Promise<BloodTestRow[]>` (I/O: Firestore + static merge); `getBloodMarkers(p: QueryParams): Promise<BloodTestRow[]>`; `getOutOfRangeMarkers(p: QueryParams): Promise<BloodTestRow[]>`.

- [ ] **Step 1: Write the failing test for the pure out-of-range predicate**

```ts
// api/src/lib/reads/bloodTestReads.test.ts
import { describe, it, expect } from 'vitest';
import { selectOutOfRange } from './bloodTestReads.js';
import type { BloodTestRow } from '../../schemas/bloodTests.js';

const row = (over: Partial<BloodTestRow>): BloodTestRow => ({
  marker: 'potassium', datetime: '2026-05-01T09:00:00', value: 5.0, unit: 'mmol/L',
  ref_low: 3.5, ref_high: 5.3, timing: '', note: '', source: 'test',
  lab_id: '1', phase: 'home-hd', created_at: '2026-05-01T09:00:00', qualitative: false,
  ...over,
});

describe('selectOutOfRange', () => {
  it('keeps values below ref_low or above ref_high', () => {
    const rows = [
      row({ lab_id: 'a', value: 5.0 }),               // in range
      row({ lab_id: 'b', value: 6.1 }),               // above
      row({ lab_id: 'c', value: 2.9 }),               // below
    ];
    expect(selectOutOfRange(rows).map(r => r.lab_id)).toEqual(['b', 'c']);
  });

  it('ignores qualitative rows and rows missing a bound', () => {
    const rows = [
      row({ lab_id: 'q', value: 9, qualitative: true }),
      row({ lab_id: 'n', value: 9, ref_high: null }),
    ];
    expect(selectOutOfRange(rows)).toEqual([]);
  });
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd api && npm test -- bloodTestReads`
Expected: FAIL — `selectOutOfRange` is not exported / module missing.

- [ ] **Step 3: Implement `bloodTestReads.ts`**

```ts
// api/src/lib/reads/bloodTestReads.ts
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { getDb } from '../firestore.js';
import { filterRows, type QueryParams } from '../queryFilter.js';
import { mergeRows } from '../mergeRows.js';
import { BloodTestRowSchema, type BloodTestRow } from '../../schemas/bloodTests.js';

const here = dirname(fileURLToPath(import.meta.url));
const staticRows: BloodTestRow[] = JSON.parse(
  readFileSync(resolve(here, '../../data/blood_tests.json'), 'utf8'),
);

/** Pure: rows whose numeric value falls outside a present reference bound. */
export function selectOutOfRange(rows: BloodTestRow[]): BloodTestRow[] {
  return rows.filter((r) => {
    if (r.qualitative) return false;
    if (r.ref_low != null && r.value < r.ref_low) return true;
    if (r.ref_high != null && r.value > r.ref_high) return true;
    return false;
  });
}

/** I/O: Firestore blood_tests merged over the static seed set. */
export async function fetchBloodRows(): Promise<BloodTestRow[]> {
  const snap = await getDb().collection('blood_tests').get();
  const firestoreRows: BloodTestRow[] = snap.docs
    .map((d) => BloodTestRowSchema.safeParse(d.data()))
    .filter((r): r is { success: true; data: BloodTestRow } => r.success)
    .map((r) => r.data);
  return mergeRows(staticRows, firestoreRows);
}

export async function getBloodMarkers(p: QueryParams): Promise<BloodTestRow[]> {
  return filterRows(await fetchBloodRows(), p);
}

export async function getOutOfRangeMarkers(p: QueryParams): Promise<BloodTestRow[]> {
  return selectOutOfRange(filterRows(await fetchBloodRows(), p));
}
```

Note the path: `bloodTests.ts` reads the static file at `../data/blood_tests.json`; from `lib/reads/` it is `../../data/blood_tests.json`.

- [ ] **Step 4: Run the test, verify it passes**

Run: `cd api && npm test -- bloodTestReads`
Expected: PASS (both cases).

- [ ] **Step 5: Refactor `bloodTests.ts` GET to use the extracted fn**

Replace the body of the `.get('/')` handler so it parses params (keep the existing `marker`/`phase`/`from`/`to` parsing + validation), then calls `getBloodMarkers(p)` instead of the inline Firestore read + `mergeRows` + `filterRows`. Remove the now-unused `staticRows`/`mergeRows`/`getDb` imports from `bloodTests.ts` if nothing else in the file uses them (POST/DELETE still use `getDb`, so keep that import). Leave POST and DELETE untouched.

- [ ] **Step 6: Run the full suite, verify green**

Run: `cd api && npm test`
Expected: PASS — existing blood-test/schema tests still pass; behavior unchanged.

- [ ] **Step 7: Commit**

```bash
cd api && git add src/lib/reads/bloodTestReads.ts src/lib/reads/bloodTestReads.test.ts src/handlers/bloodTests.ts
git commit -m "refactor(api): extract blood-test reads + out-of-range helper"
```

---

### Task 3: Extract session reads (new server-side reader)

**Files:**
- Create: `api/src/lib/reads/sessionReads.ts`
- Test: `api/src/lib/reads/sessionReads.test.ts`

**Interfaces:**
- Consumes: `getDb` from `../firestore.js`.
- Produces: `SessionParams = { from?: string; to?: string; limit?: number }`; `type SessionWithReadings = Record<string, unknown> & { readings: Record<string, unknown>[] }`; pure `joinSessions(sessions, readings, p): SessionWithReadings[]`; I/O `getSessions(p: SessionParams): Promise<SessionWithReadings[]>`.

- [ ] **Step 1: Write the failing test for the pure join/filter/limit**

```ts
// api/src/lib/reads/sessionReads.test.ts
import { describe, it, expect } from 'vitest';
import { joinSessions } from './sessionReads.js';

const sessions = [
  { session_id: 's1', date: '2026-05-01' },
  { session_id: 's2', date: '2026-05-03' },
  { session_id: 's3', date: '2026-05-05' },
];
const readings = [
  { reading_id: 'r1', session_id: 's2', seq: 2, bp_sys: 120 },
  { reading_id: 'r2', session_id: 's2', seq: 1, bp_sys: 130 },
];

describe('joinSessions', () => {
  it('attaches readings sorted by seq, newest sessions first', () => {
    const out = joinSessions(sessions, readings, {});
    expect(out.map((s) => s.session_id)).toEqual(['s3', 's2', 's1']);
    const s2 = out.find((s) => s.session_id === 's2')!;
    expect(s2.readings.map((r) => r.seq)).toEqual([1, 2]);
  });

  it('filters by from/to (date prefix) and applies limit', () => {
    const out = joinSessions(sessions, readings, { from: '2026-05-03', limit: 1 });
    expect(out.map((s) => s.session_id)).toEqual(['s3']); // s1 excluded, newest first, limit 1
  });
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd api && npm test -- sessionReads`
Expected: FAIL — module/`joinSessions` missing.

- [ ] **Step 3: Implement `sessionReads.ts`**

```ts
// api/src/lib/reads/sessionReads.ts
import { getDb } from '../firestore.js';

export type SessionParams = { from?: string; to?: string; limit?: number };
export type SessionWithReadings = Record<string, unknown> & {
  readings: Record<string, unknown>[];
};

/** Pure: join readings onto sessions, filter by date prefix, newest first, limit. */
export function joinSessions(
  sessions: Record<string, unknown>[],
  readings: Record<string, unknown>[],
  p: SessionParams,
): SessionWithReadings[] {
  const bySession = new Map<string, Record<string, unknown>[]>();
  for (const r of readings) {
    const sid = String(r['session_id']);
    if (!bySession.has(sid)) bySession.set(sid, []);
    bySession.get(sid)!.push(r);
  }
  for (const rs of bySession.values()) {
    rs.sort((a, b) => Number(a['seq'] ?? 0) - Number(b['seq'] ?? 0));
  }

  let out = sessions
    .filter((s) => {
      const date = String(s['date'] ?? '');
      if (p.from && date < p.from) return false;
      if (p.to && date > p.to) return false;
      return true;
    })
    .sort((a, b) => String(b['date'] ?? '').localeCompare(String(a['date'] ?? '')))
    .map((s) => ({ ...s, readings: bySession.get(String(s['session_id'])) ?? [] }));

  if (p.limit != null) out = out.slice(0, p.limit);
  return out;
}

/** I/O: read sessions + readings, then join. */
export async function getSessions(p: SessionParams): Promise<SessionWithReadings[]> {
  const db = getDb();
  const [sessSnap, readSnap] = await Promise.all([
    db.collection('treatment_sessions').get(),
    db.collection('treatment_readings').get(),
  ]);
  const sessions = sessSnap.docs.map((d) => d.data());
  const readings = readSnap.docs.map((d) => d.data());
  return joinSessions(sessions, readings, p);
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `cd api && npm test -- sessionReads`
Expected: PASS (both cases).

- [ ] **Step 5: Commit**

```bash
cd api && git add src/lib/reads/sessionReads.ts src/lib/reads/sessionReads.test.ts
git commit -m "feat(api): add server-side treatment session reader"
```

---

### Task 4: Extract inventory read

**Files:**
- Create: `api/src/lib/reads/inventoryReads.ts`
- Test: `api/src/lib/reads/inventoryReads.test.ts`
- Modify: `api/src/handlers/inventory.ts` (GET `/` calls the extracted fn; move `averagePakLifespan`)

**Interfaces:**
- Consumes: `getDb` from `../firestore.js`.
- Produces: pure `averagePakLifespan(docs): number | null`; I/O `getInventory(): Promise<{ stock: Record<string, number>; cycle: unknown; pak_installed_at: string | null; pak_sessions: number; pak_avg_sessions: number | null }>`.

- [ ] **Step 1: Write the failing test for the pure average helper**

```ts
// api/src/lib/reads/inventoryReads.test.ts
import { describe, it, expect } from 'vitest';
import { averagePakLifespan } from './inventoryReads.js';

const doc = (sessions: number, replaced_at: string) => ({ data: () => ({ sessions, replaced_at }) });

describe('averagePakLifespan', () => {
  it('returns null with no history', () => {
    expect(averagePakLifespan([])).toBeNull();
  });
  it('averages the 6 most recent valid lifespans', () => {
    const docs = [
      doc(10, '2026-01-01'), doc(20, '2026-02-01'), doc(30, '2026-03-01'),
      doc(40, '2026-04-01'), doc(50, '2026-05-01'), doc(60, '2026-06-01'),
      doc(999, '2025-01-01'), // older than the most recent 6 → excluded
    ];
    expect(averagePakLifespan(docs)).toBe(35); // (10+20+30+40+50+60)/6
  });
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd api && npm test -- inventoryReads`
Expected: FAIL — module/`averagePakLifespan` missing.

- [ ] **Step 3: Implement `inventoryReads.ts`**

Move `averagePakLifespan` verbatim from `inventory.ts` (it is already a pure function) and add `getInventory()` holding the current GET `/` body.

```ts
// api/src/lib/reads/inventoryReads.ts
import { getDb } from '../firestore.js';

export function averagePakLifespan(
  docs: { data: () => { sessions?: number; replaced_at?: string } }[],
): number | null {
  const lifespans = docs
    .map((d) => d.data())
    .filter(
      (d): d is { sessions: number; replaced_at: string } =>
        typeof d.sessions === 'number' && d.sessions > 0 && typeof d.replaced_at === 'string',
    )
    .sort((a, b) => b.replaced_at.localeCompare(a.replaced_at))
    .slice(0, 6)
    .map((d) => d.sessions);
  if (lifespans.length === 0) return null;
  return lifespans.reduce((a, b) => a + b, 0) / lifespans.length;
}

export async function getInventory() {
  const db = getDb();
  const [stockSnap, cycleDoc, pakDoc, pakHistorySnap] = await Promise.all([
    db.collection('inventory_stock').get(),
    db.collection('inventory_config').doc('cycle').get(),
    db.collection('inventory_config').doc('pak').get(),
    db.collection('pak_history').get(),
  ]);

  const stock: Record<string, number> = {};
  for (const doc of stockSnap.docs) {
    const d = doc.data() as { qty: number };
    if (typeof d.qty === 'number') stock[doc.id] = d.qty;
  }

  const cycle = cycleDoc.exists ? (cycleDoc.data() ?? null) : null;
  const pakData = pakDoc.exists ? (pakDoc.data() as { installed_at?: string }) : null;
  const pak_installed_at = pakData?.installed_at ?? null;

  let pak_sessions = 0;
  if (pak_installed_at) {
    const sessionsSnap = await db.collection('treatment_sessions')
      .where('date', '>=', pak_installed_at)
      .get();
    pak_sessions = sessionsSnap.docs.length;
  }

  const pak_avg_sessions = averagePakLifespan(pakHistorySnap.docs);
  return { stock, cycle, pak_installed_at, pak_sessions, pak_avg_sessions };
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `cd api && npm test -- inventoryReads`
Expected: PASS.

- [ ] **Step 5: Refactor `inventory.ts` GET to use `getInventory()`**

Replace the `.get('/')` body with `return c.json(await getInventory());` and delete the now-duplicated `averagePakLifespan` definition from `inventory.ts`, importing it is unnecessary (only the GET used it). Add `import { getInventory } from '../lib/reads/inventoryReads.js';`. Leave all POST/PUT/PATCH/DELETE handlers and `addDays` untouched.

- [ ] **Step 6: Run the full suite, verify green**

Run: `cd api && npm test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd api && git add src/lib/reads/inventoryReads.ts src/lib/reads/inventoryReads.test.ts src/handlers/inventory.ts
git commit -m "refactor(api): extract inventory read"
```

---

### Task 5: Build the MCP server module (four tools)

**Files:**
- Create: `api/src/mcp/server.ts`
- Test: `api/src/mcp/server.test.ts`

**Interfaces:**
- Consumes: `getBloodMarkers`, `getOutOfRangeMarkers` from `../lib/reads/bloodTestReads.js`; `getSessions` from `../lib/reads/sessionReads.js`; `getInventory` from `../lib/reads/inventoryReads.js`; `McpServer` from the SDK path pinned in Task 1.
- Produces: `buildMcpServer(): McpServer` with four registered tools.

- [ ] **Step 1: Write the failing test (in-memory client round-trip, read fns mocked)**

```ts
// api/src/mcp/server.test.ts
import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('../lib/reads/bloodTestReads.js', () => ({
  getBloodMarkers: vi.fn(async () => [{ marker: 'potassium', value: 5.0 }]),
  getOutOfRangeMarkers: vi.fn(async () => [{ marker: 'potassium', value: 6.1 }]),
}));
vi.mock('../lib/reads/sessionReads.js', () => ({
  getSessions: vi.fn(async () => [{ session_id: 's1', readings: [] }]),
}));
vi.mock('../lib/reads/inventoryReads.js', () => ({
  getInventory: vi.fn(async () => ({ stock: { 'CAR-172-C': 4 } })),
}));

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { buildMcpServer } from './server.js';
import { getBloodMarkers } from '../lib/reads/bloodTestReads.js';

async function connected() {
  const [clientT, serverT] = InMemoryTransport.createLinkedPair();
  const server = buildMcpServer();
  const client = new Client({ name: 'test', version: '0.0.0' });
  await Promise.all([server.connect(serverT), client.connect(clientT)]);
  return client;
}

describe('buildMcpServer', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lists the four read tools', async () => {
    const client = await connected();
    const names = (await client.listTools()).tools.map((t) => t.name).sort();
    expect(names).toEqual(
      ['get_blood_markers', 'get_inventory', 'get_out_of_range_markers', 'get_sessions'],
    );
  });

  it('get_blood_markers passes args through and returns JSON text', async () => {
    const client = await connected();
    const res = await client.callTool({
      name: 'get_blood_markers',
      arguments: { marker: 'potassium', phase: 'home-hd' },
    });
    expect(getBloodMarkers).toHaveBeenCalledWith({ marker: ['potassium'], phase: ['home-hd'] });
    const text = (res.content as { type: string; text: string }[])[0].text;
    expect(JSON.parse(text)).toEqual([{ marker: 'potassium', value: 5.0 }]);
  });
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd api && npm test -- mcp/server`
Expected: FAIL — `buildMcpServer` / module missing.

- [ ] **Step 3: Implement `server.ts`**

`marker`/`phase` arrive as comma-or-single strings and are normalised to `string[]` to match `QueryParams`. Adjust the import paths if Task 1 recorded different ones.

```ts
// api/src/mcp/server.ts
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { getBloodMarkers, getOutOfRangeMarkers } from '../lib/reads/bloodTestReads.js';
import { getSessions } from '../lib/reads/sessionReads.js';
import { getInventory } from '../lib/reads/inventoryReads.js';
import type { QueryParams } from '../lib/queryFilter.js';

const csv = (s?: string): string[] | undefined =>
  s ? s.split(',').map((x) => x.trim()).filter(Boolean) : undefined;

const json = (data: unknown) => ({
  content: [{ type: 'text' as const, text: JSON.stringify(data) }],
});

const bloodArgs = {
  marker: z.string().optional().describe('Marker name(s), comma-separated. Symptom hints: itching→phosphate,calcium; fatigue→haemoglobin,ferritin; cramps→potassium,calcium; swelling→albumin,sodium.'),
  phase: z.string().optional().describe('One or more of: admission, in-center-hd, home-hd (comma-separated).'),
  from: z.string().optional().describe('Inclusive start, YYYY-MM or YYYY-MM-DD.'),
  to: z.string().optional().describe('Inclusive end, YYYY-MM or YYYY-MM-DD.'),
};

export function buildMcpServer(): McpServer {
  const server = new McpServer({ name: 'HD Tracker (read)', version: '1.0.0' });

  server.registerTool(
    'get_sessions',
    {
      description: 'Treatment session history with intra-session readings (BP trends, UF, weights).',
      inputSchema: {
        from: z.string().optional().describe('Inclusive start date YYYY-MM-DD.'),
        to: z.string().optional().describe('Inclusive end date YYYY-MM-DD.'),
        limit: z.number().int().positive().optional().describe('Max sessions, newest first.'),
      },
    },
    async ({ from, to, limit }) => json(await getSessions({ from, to, limit })),
  );

  server.registerTool(
    'get_blood_markers',
    { description: 'Blood test history filtered by marker/phase/date.', inputSchema: bloodArgs },
    async ({ marker, phase, from, to }) => {
      const p: QueryParams = { marker: csv(marker), phase: csv(phase), from, to };
      return json(await getBloodMarkers(p));
    },
  );

  server.registerTool(
    'get_out_of_range_markers',
    { description: 'Blood markers whose value falls outside its reference range.', inputSchema: { from: bloodArgs.from, to: bloodArgs.to } },
    async ({ from, to }) => json(await getOutOfRangeMarkers({ from, to })),
  );

  server.registerTool(
    'get_inventory',
    { description: 'Current consumable stock levels, order cycle, and PAK status.', inputSchema: {} },
    async () => json(await getInventory()),
  );

  return server;
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `cd api && npm test -- mcp/server`
Expected: PASS (lists 4 tools; args pass through; JSON round-trips).

- [ ] **Step 5: Commit**

```bash
cd api && git add src/mcp/server.ts src/mcp/server.test.ts
git commit -m "feat(mcp): four read-only tools (sessions, blood, out-of-range, inventory)"
```

---

### Task 6: Mount `/api/mcp` inside the bearer guard

**Files:**
- Create: `api/src/mcp/route.ts`
- Modify: `api/src/index.ts` (mount the route after `bearerAuth`)
- Test: `api/src/mcp/route.test.ts`

**Interfaces:**
- Consumes: `buildMcpServer` from `./server.js`; SDK transport + `RESPONSE_ALREADY_SENT` per Task 1.
- Produces: `mcpRoute: Hono` exposing `POST /` that bridges to the stateless transport.

- [ ] **Step 1: Write the failing test (route is mounted under the bearer guard)**

This test exercises auth wiring without a live socket: it asserts the assembled app 401s an unauthenticated POST to `/api/mcp`.

```ts
// api/src/mcp/route.test.ts
import { describe, it, expect, beforeAll } from 'vitest';

beforeAll(() => { process.env.MAIN_API_KEY = 'test-key'; });

import { app } from '../index.js';

describe('/api/mcp auth', () => {
  it('rejects an unauthenticated POST with 401', async () => {
    const res = await app.request('/api/mcp', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
    });
    expect(res.status).toBe(401);
  });
});
```

This requires `index.ts` to export the `app` instance (Step 3). The 401 comes from the existing `bearerAuth` middleware before the MCP handler runs, so no live transport is needed.

- [ ] **Step 2: Run it, verify it fails**

Run: `cd api && npm test -- mcp/route`
Expected: FAIL — `app` is not exported from `index.ts` (and/or route not mounted).

- [ ] **Step 3: Implement `route.ts`**

```ts
// api/src/mcp/route.ts
import { Hono } from 'hono';
import { RESPONSE_ALREADY_SENT } from '@hono/node-server';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { buildMcpServer } from './server.js';

export const mcpRoute = new Hono().post('/', async (c) => {
  const { incoming, outgoing } = c.env as unknown as {
    incoming: IncomingMessage;
    outgoing: ServerResponse;
  };
  const body = await c.req.json().catch(() => undefined);

  const server = buildMcpServer();
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
  outgoing.on('close', () => { transport.close(); server.close(); });
  await server.connect(transport);
  await transport.handleRequest(incoming, outgoing, body);
  return RESPONSE_ALREADY_SENT;
});
```

- [ ] **Step 4: Mount it and export `app` in `index.ts`**

In `api/src/index.ts`: add `import { mcpRoute } from './mcp/route.js';`, change `const app = new Hono();` to `export const app = new Hono();`, and after the existing `app.route('/api/treatment', treatment);` line (i.e. after `bearerAuth` is applied) add:

```ts
app.route('/api/mcp', mcpRoute);
```

Leave the `serve({ fetch: app.fetch, ... })` call as the last line.

- [ ] **Step 5: Run the test, verify it passes**

Run: `cd api && npm test -- mcp/route`
Expected: PASS (401 without bearer).

- [ ] **Step 6: Run the full suite + build**

Run: `cd api && npm test && npm run build`
Expected: all tests PASS; `tsc` build succeeds with no type errors.

- [ ] **Step 7: Local end-to-end smoke test**

```bash
cd api && MAIN_API_KEY=test-key npx tsx src/index.ts &   # starts on :8080
npx -y @modelcontextprotocol/inspector --cli http://localhost:8080/api/mcp \
  --method tools/list --header "Authorization: Bearer test-key"
```

Expected: four tools listed. Without the header: HTTP 401. Stop the background server when done.

- [ ] **Step 8: Commit**

```bash
cd api && git add src/mcp/route.ts src/mcp/route.test.ts src/index.ts
git commit -m "feat(mcp): mount stateless /api/mcp inside bearer guard"
```

---

### Task 7: Deploy and verify on Cloud Run

**Files:** none (deploy + verification only)

- [ ] **Step 1: Deploy `homehd-api`**

Deploy using the project's existing Cloud Run deploy command for `homehd-api` (same as prior `api/` deploys — `gcloud run deploy` per the repo's deploy notes). No new env vars; `MAIN_API_KEY` already set in the service.

- [ ] **Step 2: Verify the live endpoint requires auth and lists tools**

```bash
KEY=$(security find-generic-password -a "$USER" -s homehd-main-key -w)
# Auth required:
npx -y @modelcontextprotocol/inspector --cli https://homehd.web.app/api/mcp --method tools/list
# Expected: 401 / unauthorized.
# With key:
npx -y @modelcontextprotocol/inspector --cli https://homehd.web.app/api/mcp \
  --method tools/list --header "Authorization: Bearer $KEY"
# Expected: four tools.
```

- [ ] **Step 3: Round-trip one real read tool**

```bash
npx -y @modelcontextprotocol/inspector --cli https://homehd.web.app/api/mcp \
  --method tools/call --tool-name get_out_of_range_markers \
  --header "Authorization: Bearer $KEY"
```

Expected: JSON text content listing any out-of-range markers (possibly empty `[]`).

- [ ] **Step 4: Connect from Claude Code and confirm autodiscovery**

```bash
claude mcp add --transport http homehd https://homehd.web.app/api/mcp \
  --header "Authorization: Bearer $KEY"
```

In a Claude Code session, confirm the four `homehd` tools appear and `get_inventory` returns live stock.

- [ ] **Step 5: Update the breadcrumb note**

Add a dated entry to the Obsidian vault note `Health & Home HD/Home HD - AI Command Control.md` Update Log recording: cloud read-tools shipped, four tools live at `homehd.web.app/api/mcp`, Tools-not-Resources decision, KB/RAG deferred. Update the `Home HD Knowledge Base and Tracking System.md` "Current State" / deferred-roadmap section to move "Resources (`health://`)" → done-as-Tools, KB/RAG still deferred.

## Self-Review

- **Spec coverage:** embed-in-homehd-api ✓ (T6), `/api/mcp` inside bearer guard ✓ (T6 S4 + T6 test), stateless Streamable HTTP ✓ (T1 pinned, T5/T6 used), Tools-not-Resources ✓ (T5, four tools), extract-the-query refactor ✓ (T2/T3/T4), `get_sessions` new reader ✓ (T3), out-of-range helper ✓ (T2), KB excluded/forward-ref ✓ (no task, documented in spec), Firebase Hosting rewrite URL ✓ (T7), SDK-API spike ✓ (T1), tests for extracted reads + integration round-trip ✓ (T2/T3/T4 unit, T5 in-memory, T7 live).
- **Placeholder scan:** none — every code step shows full code; the only deploy abstraction (Step 7 T7) defers to the repo's existing documented deploy command rather than inventing one.
- **Type consistency:** `QueryParams` (`marker?: string[]`, `phase?: string[]`) is produced by `csv()` in T5 and consumed by `getBloodMarkers`/`filterRows` from T2 — aligned. `SessionParams`/`joinSessions`/`getSessions` names match across T3 and T5. `buildMcpServer` name matches across T5/T6. `selectOutOfRange`/`getOutOfRangeMarkers` match T2↔T5. `app` export in T6 matches the T6 route test import.

## Update Log

### 2026-06-19 — Task 1 spike: SDK + Hono bridge pinned

- Installed `@modelcontextprotocol/sdk@1.29.0`. All planned v1.x subpaths resolve:
  `server/mcp.js`, `server/streamableHttp.js`, `client/index.js`,
  `client/streamableHttp.js`, `inMemory.js`. No switch to 2.x modular packages
  needed.
- **Plan correction:** `RESPONSE_ALREADY_SENT` is **not** a top-level export of
  `@hono/node-server` (v1.19.14). Correct import is
  `import { RESPONSE_ALREADY_SENT } from '@hono/node-server/utils/response';`.
  Apply this in Task 6 `route.ts` (the plan body shows it from `@hono/node-server`).
- Confirmed bridge: `c.env.incoming` (IncomingMessage) + `c.env.outgoing`
  (ServerResponse) + `transport.handleRequest(incoming, outgoing, body)` +
  `return RESPONSE_ALREADY_SENT`. Stateless transport
  (`sessionIdGenerator: undefined`), fresh `McpServer` per request.
- `registerTool(name, { description, inputSchema: <ZodRawShape> }, async (args) => ({ content: [{ type: 'text', text }] }))`
  confirmed. Tool handler return shape `{ content: [{ type: 'text', text }] }` works.
- Round-trip verified with an in-SDK `StreamableHTTPClientTransport` client (no
  external inspector needed): `tools/list` → `['echo']`,
  `tools/call echo {text}` → `[{"type":"text","text":"hi-from-spike"}]`.
