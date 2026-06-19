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
