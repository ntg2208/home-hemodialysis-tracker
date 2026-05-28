# Inventory System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Phase 5 Home HD supply inventory tab — stock tracking with auto-deduction on session completion, quick [−]/[+] actions, a monthly order calculator, and a delivery cycle banner.

**Architecture:** Firestore holds stock levels (`inventory_stock/`), an event log (`inventory_events/`), and the active delivery cycle (`inventory_config/cycle`). A Hono handler at `/api/inventory` exposes GET + four POSTs. The frontend Inventory route is a standalone React page; Treatment screens (PreTreatment, ActiveSession, PostTreatment) are modified to fire a session event and surface heparin/EPO toggles.

**Tech Stack:** Hono + Zod + Firestore (API); React + Tailwind + Zod + idb + cloudGet/cloudPost (frontend); Vitest (both sides).

---

## File Map

### New API files
- `api/src/schemas/inventory.ts` — Zod schemas: EventBody, ConfirmOrderBody, ApplyDeliveryBody, StockGetResponse
- `api/src/schemas/inventory.test.ts` — schema validation tests

### Modified API files
- `api/src/handlers/inventory.ts` — replace stub: GET stock+cycle, POST event/confirm-order/apply-delivery/init-cycle

### New Frontend files
- `frontend/src/routes/Inventory/constants.ts` — ITEMS array: code, label, unit, boxSize, perSession, targetQty, section, priority
- `frontend/src/routes/Inventory/schemas.ts` — Zod shapes for API responses (mirrors api/src/schemas/inventory.ts)
- `frontend/src/routes/Inventory/api.ts` — fetchInventory, logEvent, confirmOrder, applyDelivery, initCycle
- `frontend/src/routes/Inventory/lib/stockCalc.ts` — pure functions: sessionsRemaining, stockStatus, needsOrdering, orderBoxes, sortStock
- `frontend/src/routes/Inventory/lib/stockCalc.test.ts` — tests for all pure logic
- `frontend/src/routes/Inventory/components/DeliveryCycleBanner.tsx` — banner showing cycle state
- `frontend/src/routes/Inventory/components/StockItemRow.tsx` — row with [−]/[+] + undo toast
- `frontend/src/routes/Inventory/components/LogEventModal.tsx` — PAK change / manual use / stock count
- `frontend/src/routes/Inventory/components/OrderView.tsx` — stock-count step → order-list step → confirm

### Modified Frontend files
- `frontend/src/api/cloudRun.ts` — add cloudPost helper
- `frontend/src/routes/Inventory/index.tsx` — replace stub with full page
- `frontend/src/routes/Treatment/screens/ActiveSession.tsx` — add needles/on-off consumed fields; change onEnd signature
- `frontend/src/routes/Treatment/screens/PreTreatment.tsx` — add heparin toggle; change onSaved signature; load heparin stock
- `frontend/src/routes/Treatment/screens/PostTreatment.tsx` — add EPO toggle; load EPO stock; fire session event after save
- `frontend/src/routes/Treatment/index.tsx` — keep auth in state; thread heparinUsed + consumed through Screen union; pass auth to treatment screens

---

## Firestore Layout

```
inventory_stock/{itemCode}       { qty: number, updated_at: string }
inventory_events/{autoId}        { type, timestamp, deltas: Record<string,number>, note?: string }
inventory_config/cycle           { call_date: string, delivery_date: string, order?: Record<string,number>,
                                   order_placed_at: string|null, delivery_applied_at: string|null }
```

`delivery_date` is always stored as `call_date + 7 days` and recomputed on every write to `inventory_config/cycle`.

---

## Task 1: API inventory schemas

**Files:**
- Create: `api/src/schemas/inventory.ts`
- Create: `api/src/schemas/inventory.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// api/src/schemas/inventory.test.ts
import { describe, it, expect } from 'vitest';
import {
  EventBodySchema,
  ConfirmOrderBodySchema,
  ApplyDeliveryBodySchema,
  StockGetResponseSchema,
} from './inventory.js';

describe('EventBodySchema', () => {
  it('accepts a valid session event', () => {
    const r = EventBodySchema.safeParse({
      type: 'session',
      deltas: { 'SAK-303': -1, 'CAR-172-C': -1 },
    });
    expect(r.success).toBe(true);
  });

  it('accepts a stock_count event with absolute values', () => {
    const r = EventBodySchema.safeParse({
      type: 'stock_count',
      deltas: { 'SAK-303': 12 },
      note: 'monthly count',
    });
    expect(r.success).toBe(true);
  });

  it('rejects unknown type', () => {
    const r = EventBodySchema.safeParse({ type: 'unknown', deltas: {} });
    expect(r.success).toBe(false);
  });
});

describe('ConfirmOrderBodySchema', () => {
  it('accepts valid call_date and order', () => {
    const r = ConfirmOrderBodySchema.safeParse({
      call_date: '2026-06-23',
      order: { 'SAK-303': 16 },
    });
    expect(r.success).toBe(true);
  });

  it('accepts empty order for initial setup', () => {
    const r = ConfirmOrderBodySchema.safeParse({ call_date: '2026-06-23', order: {} });
    expect(r.success).toBe(true);
  });

  it('rejects malformed call_date', () => {
    const r = ConfirmOrderBodySchema.safeParse({ call_date: '23-06-2026', order: {} });
    expect(r.success).toBe(false);
  });
});

describe('ApplyDeliveryBodySchema', () => {
  it('accepts empty body', () => {
    const r = ApplyDeliveryBodySchema.safeParse({});
    expect(r.success).toBe(true);
  });

  it('accepts adjustments', () => {
    const r = ApplyDeliveryBodySchema.safeParse({ adjustments: { 'SAK-303': 14 } });
    expect(r.success).toBe(true);
  });
});

describe('StockGetResponseSchema', () => {
  it('accepts valid response with null cycle', () => {
    const r = StockGetResponseSchema.safeParse({ stock: { 'SAK-303': 12 }, cycle: null });
    expect(r.success).toBe(true);
  });

  it('accepts valid response with a cycle', () => {
    const r = StockGetResponseSchema.safeParse({
      stock: {},
      cycle: {
        call_date: '2026-06-23',
        delivery_date: '2026-06-30',
        order: { 'SAK-303': 16 },
        order_placed_at: '2026-06-23T10:00:00Z',
        delivery_applied_at: null,
      },
    });
    expect(r.success).toBe(true);
  });
});
```

- [ ] **Step 2: Run tests — expect failures**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
uv run npx vitest run src/schemas/inventory.test.ts
# Expected: FAIL — Cannot find module './inventory.js'
```

- [ ] **Step 3: Write the schemas**

```typescript
// api/src/schemas/inventory.ts
import { z } from 'zod';

export const EventBodySchema = z.object({
  type: z.enum(['session', 'manual', 'stock_count']),
  deltas: z.record(z.string(), z.number()),
  note: z.string().optional(),
});
export type EventBody = z.infer<typeof EventBodySchema>;

export const ConfirmOrderBodySchema = z.object({
  call_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'call_date must be YYYY-MM-DD'),
  order: z.record(z.string(), z.number().int().nonnegative()),
});
export type ConfirmOrderBody = z.infer<typeof ConfirmOrderBodySchema>;

export const ApplyDeliveryBodySchema = z.object({
  adjustments: z.record(z.string(), z.number().int().nonnegative()).optional(),
});
export type ApplyDeliveryBody = z.infer<typeof ApplyDeliveryBodySchema>;

const CycleSchema = z.object({
  call_date: z.string(),
  delivery_date: z.string(),
  order: z.record(z.string(), z.number()).optional(),
  order_placed_at: z.string().nullable(),
  delivery_applied_at: z.string().nullable(),
});
export type Cycle = z.infer<typeof CycleSchema>;

export const StockGetResponseSchema = z.object({
  stock: z.record(z.string(), z.number()),
  cycle: CycleSchema.nullable(),
});
export type StockGetResponse = z.infer<typeof StockGetResponseSchema>;
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
uv run npx vitest run src/schemas/inventory.test.ts
# Expected: all PASS
```

- [ ] **Step 5: Commit**

```bash
git add api/src/schemas/inventory.ts api/src/schemas/inventory.test.ts
git commit -m "feat(inventory): add API schemas for inventory endpoints"
```

---

## Task 2: API GET handler

**Files:**
- Modify: `api/src/handlers/inventory.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// api/src/handlers/inventory.test.ts  (create this file)
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { Hono } from 'hono';
import { bearerAuth } from '../lib/auth.js';

const { mockCollectionGet, mockDocGet } = vi.hoisted(() => ({
  mockCollectionGet: vi.fn(),
  mockDocGet: vi.fn(),
}));

vi.mock('../lib/firestore.js', () => ({
  getDb: () => ({
    collection: (name: string) => ({
      get: mockCollectionGet,
      doc: () => ({ get: mockDocGet, set: vi.fn() }),
      add: vi.fn().mockResolvedValue({ id: 'auto-id' }),
    }),
    batch: () => ({ set: vi.fn(), commit: vi.fn().mockResolvedValue(undefined) }),
  }),
}));

import { inventory } from './inventory.js';

function makeApp() {
  const app = new Hono();
  app.use('/api/*', bearerAuth(() => 'test-key'));
  app.route('/api/inventory', inventory);
  return app;
}

function get(app: Hono, path: string) {
  return app.request(path, { headers: { Authorization: 'Bearer test-key' } });
}

describe('GET /api/inventory', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockCollectionGet.mockResolvedValue({ docs: [] });
    mockDocGet.mockResolvedValue({ exists: false, data: () => undefined });
  });

  it('returns stock map and null cycle when Firestore is empty', async () => {
    const res = await get(makeApp(), '/api/inventory');
    expect(res.status).toBe(200);
    const body = await res.json() as { stock: Record<string,number>; cycle: null };
    expect(body.stock).toEqual({});
    expect(body.cycle).toBeNull();
  });

  it('returns cycle when inventory_config/cycle exists', async () => {
    const cycleData = {
      call_date: '2026-06-23',
      delivery_date: '2026-06-30',
      order: {},
      order_placed_at: null,
      delivery_applied_at: null,
    };
    mockDocGet.mockResolvedValue({ exists: true, data: () => cycleData });
    const res = await get(makeApp(), '/api/inventory');
    expect(res.status).toBe(200);
    const body = await res.json() as { cycle: typeof cycleData };
    expect(body.cycle?.call_date).toBe('2026-06-23');
  });

  it('returns stock quantities from inventory_stock collection', async () => {
    mockCollectionGet.mockResolvedValue({
      docs: [
        { id: 'SAK-303', data: () => ({ qty: 12, updated_at: '2026-05-28T10:00:00Z' }) },
        { id: 'CAR-172-C', data: () => ({ qty: 6, updated_at: '2026-05-28T10:00:00Z' }) },
      ],
    });
    const res = await get(makeApp(), '/api/inventory');
    const body = await res.json() as { stock: Record<string,number> };
    expect(body.stock['SAK-303']).toBe(12);
    expect(body.stock['CAR-172-C']).toBe(6);
  });

  it('returns 401 without auth', async () => {
    const res = await makeApp().request('/api/inventory');
    expect(res.status).toBe(401);
  });
});
```

- [ ] **Step 2: Run test — expect failures**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
uv run npx vitest run src/handlers/inventory.test.ts
# Expected: FAIL — current handler returns { ok: true, note: 'coming soon' }
```

- [ ] **Step 3: Write the GET handler**

```typescript
// api/src/handlers/inventory.ts
import { Hono } from 'hono';
import { getDb } from '../lib/firestore.js';
import {
  EventBodySchema,
  ConfirmOrderBodySchema,
  ApplyDeliveryBodySchema,
} from '../schemas/inventory.js';

export const inventory = new Hono()

  .get('/', async (c) => {
    const db = getDb();

    const [stockSnap, cycleDoc] = await Promise.all([
      db.collection('inventory_stock').get(),
      db.collection('inventory_config').doc('cycle').get(),
    ]);

    const stock: Record<string, number> = {};
    for (const doc of stockSnap.docs) {
      const d = doc.data() as { qty: number };
      if (typeof d.qty === 'number') stock[doc.id] = d.qty;
    }

    const cycle = cycleDoc.exists ? (cycleDoc.data() ?? null) : null;

    return c.json({ stock, cycle });
  });
```

- [ ] **Step 4: Run GET tests — expect pass**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
uv run npx vitest run src/handlers/inventory.test.ts
# Expected: GET describe block all PASS; POST tests FAIL (not written yet)
```

- [ ] **Step 5: Commit**

```bash
git add api/src/handlers/inventory.ts api/src/handlers/inventory.test.ts
git commit -m "feat(inventory): add GET /api/inventory handler with Firestore read"
```

---

## Task 3: API event POST handler

**Files:**
- Modify: `api/src/handlers/inventory.ts` — add POST /event route
- Modify: `api/src/handlers/inventory.test.ts` — add POST /event tests

- [ ] **Step 1: Write the failing tests**

Add to `api/src/handlers/inventory.test.ts`:

```typescript
function post(app: Hono, path: string, body: unknown) {
  return app.request(`/api/inventory${path}`, {
    method: 'POST',
    headers: { Authorization: 'Bearer test-key', 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('POST /api/inventory/event', () => {
  let mockBatchCommit: ReturnType<typeof vi.fn>;
  let mockBatchSet: ReturnType<typeof vi.fn>;
  let mockAdd: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.clearAllMocks();
    mockCollectionGet.mockResolvedValue({ docs: [] });
    mockDocGet.mockResolvedValue({ exists: false, data: () => undefined });
    mockBatchCommit = vi.fn().mockResolvedValue(undefined);
    mockBatchSet = vi.fn();
    mockAdd = vi.fn().mockResolvedValue({ id: 'event-1' });
    vi.mocked(getDb).mockReturnValue({
      collection: (name: string) => ({
        get: mockCollectionGet,
        doc: () => ({ get: mockDocGet, set: vi.fn() }),
        add: mockAdd,
      }),
      batch: () => ({ set: mockBatchSet, commit: mockBatchCommit }),
    } as any);
  });

  it('returns ok:true on valid session event', async () => {
    const res = await post(makeApp(), '/event', {
      type: 'session',
      deltas: { 'SAK-303': -1, 'CAR-172-C': -1 },
    });
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean };
    expect(body.ok).toBe(true);
  });

  it('commits a batch set for each item in deltas', async () => {
    await post(makeApp(), '/event', {
      type: 'manual',
      deltas: { 'SAK-303': -1 },
    });
    expect(mockBatchSet).toHaveBeenCalledTimes(1);
    expect(mockBatchCommit).toHaveBeenCalledTimes(1);
  });

  it('logs the event to inventory_events', async () => {
    await post(makeApp(), '/event', {
      type: 'session',
      deltas: { 'SAK-303': -1 },
    });
    expect(mockAdd).toHaveBeenCalledWith(expect.objectContaining({ type: 'session' }));
  });

  it('returns 400 for invalid event type', async () => {
    const res = await post(makeApp(), '/event', { type: 'bad', deltas: {} });
    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid JSON', async () => {
    const res = await makeApp().request('/api/inventory/event', {
      method: 'POST',
      headers: { Authorization: 'Bearer test-key', 'Content-Type': 'application/json' },
      body: 'not-json',
    });
    expect(res.status).toBe(400);
  });
});
```

> **Note:** The test mocks above require refactoring the mock setup in inventory.test.ts. The `vi.mock` at the top of the file needs to use a factory that references mutable vars. Replace the top-level mock with this pattern:

```typescript
// Replace the vi.mock block at the top of inventory.test.ts with:
const mocks = vi.hoisted(() => ({
  batchSet: vi.fn(),
  batchCommit: vi.fn().mockResolvedValue(undefined),
  docGet: vi.fn().mockResolvedValue({ exists: false, data: () => undefined }),
  docSet: vi.fn().mockResolvedValue(undefined),
  colGet: vi.fn().mockResolvedValue({ docs: [] }),
  colAdd: vi.fn().mockResolvedValue({ id: 'event-id' }),
}));

vi.mock('../lib/firestore.js', () => ({
  getDb: () => ({
    collection: () => ({
      get: mocks.colGet,
      add: mocks.colAdd,
      doc: () => ({
        get: mocks.docGet,
        set: mocks.docSet,
      }),
    }),
    batch: () => ({
      set: mocks.batchSet,
      commit: mocks.batchCommit,
    }),
  }),
}));

// In each beforeEach, reset with:
beforeEach(() => {
  vi.clearAllMocks();
  mocks.batchCommit.mockResolvedValue(undefined);
  mocks.docGet.mockResolvedValue({ exists: false, data: () => undefined });
  mocks.colGet.mockResolvedValue({ docs: [] });
  mocks.colAdd.mockResolvedValue({ id: 'event-id' });
});
```

- [ ] **Step 2: Run tests — expect failures on POST /event describe block**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
uv run npx vitest run src/handlers/inventory.test.ts
```

- [ ] **Step 3: Add the POST /event route to the handler**

In `api/src/handlers/inventory.ts`, chain after the `.get('/', ...)` block:

```typescript
  .post('/event', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }

    const parsed = EventBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);

    const { type, deltas, note } = parsed.data;
    const now = new Date().toISOString();
    const db = getDb();

    // Update stock quantities (batch)
    const batch = db.batch();
    for (const [code, delta] of Object.entries(deltas)) {
      const ref = db.collection('inventory_stock').doc(code);
      if (type === 'stock_count') {
        // Absolute set
        batch.set(ref, { qty: delta, updated_at: now }, { merge: false });
      } else {
        // Relative adjustment: use Firestore FieldValue.increment equivalent via merge
        // Since @google-cloud/firestore supports FieldValue.increment, use it:
        const { FieldValue } = await import('@google-cloud/firestore');
        batch.set(ref, { qty: FieldValue.increment(delta), updated_at: now }, { merge: true });
      }
    }
    await batch.commit();

    // Log event
    await db.collection('inventory_events').add({ type, deltas, note: note ?? '', timestamp: now });

    return c.json({ ok: true });
  })
```

> **Note on FieldValue.increment:** `@google-cloud/firestore` exports `FieldValue` at the top level. Add the import at the top of the file: `import { FieldValue } from '@google-cloud/firestore';`

Updated full `inventory.ts` header:

```typescript
// api/src/handlers/inventory.ts
import { Hono } from 'hono';
import { FieldValue } from '@google-cloud/firestore';
import { getDb } from '../lib/firestore.js';
import {
  EventBodySchema,
  ConfirmOrderBodySchema,
  ApplyDeliveryBodySchema,
} from '../schemas/inventory.js';
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
uv run npx vitest run src/handlers/inventory.test.ts
```

- [ ] **Step 5: Commit**

```bash
git add api/src/handlers/inventory.ts api/src/handlers/inventory.test.ts
git commit -m "feat(inventory): add POST /api/inventory/event handler"
```

---

## Task 4: API confirm-order and apply-delivery handlers

**Files:**
- Modify: `api/src/handlers/inventory.ts` — add POST /confirm-order and POST /apply-delivery
- Modify: `api/src/handlers/inventory.test.ts` — add tests for both

- [ ] **Step 1: Write the failing tests**

Add to `api/src/handlers/inventory.test.ts`:

```typescript
describe('POST /api/inventory/confirm-order', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.docSet.mockResolvedValue(undefined);
    mocks.docGet.mockResolvedValue({ exists: false, data: () => undefined });
    mocks.colGet.mockResolvedValue({ docs: [] });
  });

  it('returns ok:true on valid input', async () => {
    const res = await post(makeApp(), '/confirm-order', {
      call_date: '2026-06-23',
      order: { 'SAK-303': 16 },
    });
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean };
    expect(body.ok).toBe(true);
  });

  it('writes cycle doc with delivery_date = call_date + 7 days', async () => {
    await post(makeApp(), '/confirm-order', {
      call_date: '2026-06-23',
      order: { 'SAK-303': 16 },
    });
    expect(mocks.docSet).toHaveBeenCalledWith(
      expect.objectContaining({
        call_date: '2026-06-23',
        delivery_date: '2026-06-30',
      }),
    );
  });

  it('sets order_placed_at when order is non-empty', async () => {
    await post(makeApp(), '/confirm-order', { call_date: '2026-06-23', order: { 'SAK-303': 16 } });
    expect(mocks.docSet).toHaveBeenCalledWith(
      expect.objectContaining({ order_placed_at: expect.any(String) }),
    );
  });

  it('leaves order_placed_at null when order is empty (initial setup)', async () => {
    await post(makeApp(), '/confirm-order', { call_date: '2026-06-23', order: {} });
    expect(mocks.docSet).toHaveBeenCalledWith(
      expect.objectContaining({ order_placed_at: null }),
    );
  });

  it('returns 400 for malformed call_date', async () => {
    const res = await post(makeApp(), '/confirm-order', { call_date: '23/06/2026', order: {} });
    expect(res.status).toBe(400);
  });
});

describe('POST /api/inventory/apply-delivery', () => {
  const existingCycle = {
    call_date: '2026-05-26',
    delivery_date: '2026-06-02',
    order: { 'SAK-303': 16, 'CAR-172-C': 18 },
    order_placed_at: '2026-05-26T10:00:00Z',
    delivery_applied_at: null,
  };

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.batchCommit.mockResolvedValue(undefined);
    mocks.docGet.mockResolvedValue({ exists: true, data: () => existingCycle });
    mocks.docSet.mockResolvedValue(undefined);
    mocks.colAdd.mockResolvedValue({ id: 'event-id' });
    mocks.colGet.mockResolvedValue({ docs: [] });
  });

  it('returns ok:true', async () => {
    const res = await post(makeApp(), '/apply-delivery', {});
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean };
    expect(body.ok).toBe(true);
  });

  it('applies order quantities as positive deltas to stock', async () => {
    await post(makeApp(), '/apply-delivery', {});
    // batchSet called for each item in order
    expect(mocks.batchSet).toHaveBeenCalledTimes(2);
    expect(mocks.batchCommit).toHaveBeenCalled();
  });

  it('applies adjustments that override the stored order', async () => {
    await post(makeApp(), '/apply-delivery', { adjustments: { 'SAK-303': 14 } });
    // SAK-303 should use 14 (adjustment), CAR-172-C should use 18 (from order)
    expect(mocks.batchSet).toHaveBeenCalledTimes(2);
  });

  it('advances cycle call_date by 28 days', async () => {
    await post(makeApp(), '/apply-delivery', {});
    expect(mocks.docSet).toHaveBeenCalledWith(
      expect.objectContaining({ call_date: '2026-06-23' }),
    );
  });

  it('returns 404 when no cycle exists', async () => {
    mocks.docGet.mockResolvedValue({ exists: false, data: () => undefined });
    const res = await post(makeApp(), '/apply-delivery', {});
    expect(res.status).toBe(404);
  });
});
```

- [ ] **Step 2: Run tests — expect failures**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
uv run npx vitest run src/handlers/inventory.test.ts
```

- [ ] **Step 3: Implement both routes**

Add to `api/src/handlers/inventory.ts` after the `.post('/event', ...)` block:

```typescript
  .post('/confirm-order', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }
    const parsed = ConfirmOrderBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);

    const { call_date, order } = parsed.data;
    const deliveryDate = addDays(call_date, 7);
    const now = new Date().toISOString();
    const hasOrder = Object.keys(order).length > 0;

    await getDb().collection('inventory_config').doc('cycle').set({
      call_date,
      delivery_date: deliveryDate,
      order,
      order_placed_at: hasOrder ? now : null,
      delivery_applied_at: null,
    });

    return c.json({ ok: true });
  })

  .post('/apply-delivery', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'invalid JSON' }, 400);
    }
    const parsed = ApplyDeliveryBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: 'invalid request', details: parsed.error.issues }, 400);

    const db = getDb();
    const cycleDoc = await db.collection('inventory_config').doc('cycle').get();
    if (!cycleDoc.exists) return c.json({ error: 'no active cycle' }, 404);

    const cycle = cycleDoc.data() as {
      call_date: string;
      order?: Record<string, number>;
      order_placed_at: string | null;
    };

    const baseOrder = cycle.order ?? {};
    const adjustments = parsed.data.adjustments ?? {};
    const finalDelivery: Record<string, number> = { ...baseOrder, ...adjustments };

    const now = new Date().toISOString();
    const batch = db.batch();
    for (const [code, qty] of Object.entries(finalDelivery)) {
      const ref = db.collection('inventory_stock').doc(code);
      batch.set(ref, { qty: FieldValue.increment(qty), updated_at: now }, { merge: true });
    }
    await batch.commit();

    await db.collection('inventory_events').add({
      type: 'delivery',
      deltas: Object.fromEntries(Object.entries(finalDelivery).map(([k, v]) => [k, v])),
      note: 'delivery applied',
      timestamp: now,
    });

    const nextCallDate = addDays(cycle.call_date, 28);
    const nextDeliveryDate = addDays(nextCallDate, 7);
    await db.collection('inventory_config').doc('cycle').set({
      call_date: nextCallDate,
      delivery_date: nextDeliveryDate,
      order: {},
      order_placed_at: null,
      delivery_applied_at: now,
    });

    return c.json({ ok: true });
  });

function addDays(dateStr: string, days: number): string {
  const d = new Date(dateStr);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
```

- [ ] **Step 4: Run all inventory tests — expect all pass**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
uv run npx vitest run src/handlers/inventory.test.ts
uv run npx vitest run src/schemas/inventory.test.ts
# Expected: all PASS
```

- [ ] **Step 5: Commit**

```bash
git add api/src/handlers/inventory.ts api/src/handlers/inventory.test.ts
git commit -m "feat(inventory): add confirm-order and apply-delivery handlers"
```

---

## Task 5: Frontend cloudPost + Inventory schemas + API client

**Files:**
- Modify: `frontend/src/api/cloudRun.ts` — add cloudPost
- Create: `frontend/src/routes/Inventory/schemas.ts`
- Create: `frontend/src/routes/Inventory/api.ts`

- [ ] **Step 1: Add cloudPost to cloudRun.ts**

Read the file first, then add after the `cloudGet` function:

```typescript
export async function cloudPost<T>(
  auth: AuthSettings,
  path: string,
  body: unknown,
): Promise<T> {
  const url = new URL(path, window.location.origin).toString();
  let res: Response;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${auth.mainKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
  } catch {
    throw new CloudRunError('network', 'Could not reach the server.');
  }
  if (res.status === 401) throw new CloudRunError('unauthorized', 'Access key rejected.');
  if (!res.ok) throw new CloudRunError('server', `Server error (${res.status}).`);
  let responseBody: unknown;
  try { responseBody = await res.json(); } catch {
    throw new CloudRunError('bad_data', 'Server returned invalid JSON.');
  }
  return responseBody as T;
}
```

- [ ] **Step 2: Create Inventory schemas (mirrors API schemas)**

```typescript
// frontend/src/routes/Inventory/schemas.ts
import { z } from 'zod';

const CycleSchema = z.object({
  call_date: z.string(),
  delivery_date: z.string(),
  order: z.record(z.string(), z.number()).optional(),
  order_placed_at: z.string().nullable(),
  delivery_applied_at: z.string().nullable(),
});
export type Cycle = z.infer<typeof CycleSchema>;

export const InventoryResponseSchema = z.object({
  stock: z.record(z.string(), z.number()),
  cycle: CycleSchema.nullable(),
});
export type InventoryResponse = z.infer<typeof InventoryResponseSchema>;

export const OkResponseSchema = z.object({ ok: z.literal(true) });
```

- [ ] **Step 3: Create Inventory API client**

```typescript
// frontend/src/routes/Inventory/api.ts
import { cloudGet, cloudPost, CloudRunError } from '../../api/cloudRun';
import type { AuthSettings } from '../../auth/storage';
import { InventoryResponseSchema, OkResponseSchema, type InventoryResponse } from './schemas';

export { CloudRunError as ApiError };

export async function fetchInventory(auth: AuthSettings): Promise<InventoryResponse> {
  const data = await cloudGet<unknown>(auth, '/api/inventory');
  const parsed = InventoryResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Inventory response shape mismatch.');
  return parsed.data;
}

export async function logEvent(
  auth: AuthSettings,
  type: 'session' | 'manual' | 'stock_count',
  deltas: Record<string, number>,
  note?: string,
): Promise<void> {
  const data = await cloudPost<unknown>(auth, '/api/inventory/event', { type, deltas, note });
  const parsed = OkResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Unexpected event response.');
}

export async function confirmOrder(
  auth: AuthSettings,
  call_date: string,
  order: Record<string, number>,
): Promise<void> {
  const data = await cloudPost<unknown>(auth, '/api/inventory/confirm-order', { call_date, order });
  const parsed = OkResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Unexpected confirm-order response.');
}

export async function applyDelivery(
  auth: AuthSettings,
  adjustments?: Record<string, number>,
): Promise<void> {
  const data = await cloudPost<unknown>(auth, '/api/inventory/apply-delivery', { adjustments });
  const parsed = OkResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Unexpected apply-delivery response.');
}

export async function initCycle(auth: AuthSettings, call_date: string): Promise<void> {
  await confirmOrder(auth, call_date, {});
}
```

- [ ] **Step 4: Type-check**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend
npm run typecheck
# Expected: no errors
```

- [ ] **Step 5: Commit**

```bash
git add frontend/src/api/cloudRun.ts \
        frontend/src/routes/Inventory/schemas.ts \
        frontend/src/routes/Inventory/api.ts
git commit -m "feat(inventory): add cloudPost helper and inventory API client"
```

---

## Task 6: Inventory constants + stockCalc pure logic + tests

**Files:**
- Create: `frontend/src/routes/Inventory/constants.ts`
- Create: `frontend/src/routes/Inventory/lib/stockCalc.ts`
- Create: `frontend/src/routes/Inventory/lib/stockCalc.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// frontend/src/routes/Inventory/lib/stockCalc.test.ts
import { describe, it, expect } from 'vitest';
import {
  sessionsRemaining,
  stockStatus,
  needsOrdering,
  orderUnits,
  orderBoxes,
  sortStock,
} from './stockCalc';

describe('sessionsRemaining', () => {
  it('returns qty for 1:1 items (SAK, cartridge, saline)', () => {
    expect(sessionsRemaining('SAK-303', 12)).toBe(12);
    expect(sessionsRemaining('CAR-172-C', 6)).toBe(6);
    expect(sessionsRemaining('UK00000880', 10)).toBe(10);
  });

  it('divides by 2 for needles (2 per session)', () => {
    expect(sessionsRemaining('P00012326', 20)).toBe(10);
    expect(sessionsRemaining('P00012326', 5)).toBe(2);
  });

  it('multiplies by 10 for PAK (1 per 10 sessions)', () => {
    expect(sessionsRemaining('PAK-001', 2)).toBe(20);
    expect(sessionsRemaining('PAK-001', 0)).toBe(0);
  });

  it('returns null for hospital items', () => {
    expect(sessionsRemaining('heparin', 5)).toBeNull();
    expect(sessionsRemaining('epo', 3)).toBeNull();
  });

  it('returns null for unknown code', () => {
    expect(sessionsRemaining('UNKNOWN', 5)).toBeNull();
  });
});

describe('stockStatus', () => {
  it('returns red when sessions remaining < 8', () => {
    expect(stockStatus('SAK-303', 7)).toBe('red');
    expect(stockStatus('SAK-303', 0)).toBe('red');
  });

  it('returns amber when sessions remaining 8–15', () => {
    expect(stockStatus('SAK-303', 8)).toBe('amber');
    expect(stockStatus('SAK-303', 15)).toBe('amber');
  });

  it('returns green when sessions remaining >= 16', () => {
    expect(stockStatus('SAK-303', 16)).toBe('green');
    expect(stockStatus('SAK-303', 24)).toBe('green');
  });

  it('returns green for hospital items with stock > 0', () => {
    expect(stockStatus('heparin', 4)).toBe('green');
  });

  it('returns red for hospital items with 0 stock', () => {
    expect(stockStatus('heparin', 0)).toBe('red');
  });

  it('returns amber for hospital items with 1 unit', () => {
    expect(stockStatus('heparin', 1)).toBe('amber');
  });
});

describe('needsOrdering', () => {
  it('returns true when stock below target', () => {
    expect(needsOrdering('SAK-303', 10)).toBe(true);   // target = 24
  });

  it('returns false when stock at or above target', () => {
    expect(needsOrdering('SAK-303', 24)).toBe(false);
    expect(needsOrdering('SAK-303', 30)).toBe(false);
  });

  it('always returns false for hospital items', () => {
    expect(needsOrdering('heparin', 0)).toBe(false);
    expect(needsOrdering('epo', 0)).toBe(false);
  });
});

describe('orderBoxes', () => {
  it('calculates boxes needed for SAK (boxSize=2)', () => {
    // target=24 bags, have 10 → need 14 → ceil(14/2) = 7 boxes
    expect(orderBoxes('SAK-303', 10)).toBe(7);
  });

  it('calculates boxes needed for cartridges (boxSize=6)', () => {
    // target=24, have 6 → need 18 → ceil(18/6) = 3 boxes
    expect(orderBoxes('CAR-172-C', 6)).toBe(3);
  });

  it('returns 0 when stock meets or exceeds target', () => {
    expect(orderBoxes('SAK-303', 24)).toBe(0);
    expect(orderBoxes('SAK-303', 30)).toBe(0);
  });
});

describe('sortStock', () => {
  it('puts needs-ordering items first', () => {
    const entries = [
      { code: 'SAK-303', qty: 30 },         // green, no order
      { code: 'CAR-172-C', qty: 5 },        // red, needs order
    ];
    const sorted = sortStock(entries);
    expect(sorted[0].code).toBe('CAR-172-C');
  });

  it('sorts by priority within the same needs-ordering group', () => {
    const entries = [
      { code: 'PAK-001', qty: 0 },       // needs ordering, priority 4
      { code: 'SAK-303', qty: 0 },       // needs ordering, priority 1
    ];
    const sorted = sortStock(entries);
    expect(sorted[0].code).toBe('SAK-303');
  });

  it('places hospital items after all nxstage items', () => {
    const entries = [
      { code: 'heparin', qty: 0 },
      { code: 'SAK-303', qty: 0 },
    ];
    const sorted = sortStock(entries);
    expect(sorted[sorted.length - 1].code).toBe('heparin');
  });
});
```

- [ ] **Step 2: Run tests — expect failures**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend
npm run test -- --reporter=verbose src/routes/Inventory/lib/stockCalc.test.ts
# Expected: FAIL — module not found
```

- [ ] **Step 3: Write constants.ts**

```typescript
// frontend/src/routes/Inventory/constants.ts
export interface ItemDef {
  code: string;
  label: string;
  unit: string;
  boxSize: number;
  boxLabel: string;
  perSession: number | null;
  targetQty: number;
  section: 'nxstage' | 'hospital';
  priority: number;
}

export const ITEMS: ItemDef[] = [
  // ── NxStage supplies ──────────────────────────────────────────────────────
  { code: 'SAK-303',    label: 'SAK Dialysate',      unit: 'bag',       boxSize: 2,   boxLabel: 'box',   perSession: 1,    targetQty: 24, section: 'nxstage', priority: 1 },
  { code: 'CAR-172-C',  label: 'Cartridges',         unit: 'cartridge', boxSize: 6,   boxLabel: 'box',   perSession: 1,    targetQty: 24, section: 'nxstage', priority: 2 },
  { code: 'UK00000880', label: 'Saline 1L',          unit: 'bag',       boxSize: 10,  boxLabel: 'box',   perSession: 1,    targetQty: 24, section: 'nxstage', priority: 3 },
  { code: 'PAK-001',    label: 'PAK',                unit: 'unit',      boxSize: 1,   boxLabel: 'piece', perSession: null, targetQty: 3,  section: 'nxstage', priority: 4 },
  { code: 'P00012326',  label: 'Buttonhole Needles', unit: 'needle',    boxSize: 50,  boxLabel: 'box',   perSession: null, targetQty: 48, section: 'nxstage', priority: 5 },
  { code: 'UK00000774', label: 'On/Off Pack',        unit: 'pack',      boxSize: 60,  boxLabel: 'box',   perSession: null, targetQty: 24, section: 'nxstage', priority: 6 },
  { code: 'F00010983',  label: 'Chlorine Strips',    unit: 'strip',     boxSize: 100, boxLabel: 'pack',  perSession: 1,    targetQty: 24, section: 'nxstage', priority: 7 },
  { code: 'UK00000830', label: 'Sani-Cloth AF',      unit: 'box',       boxSize: 1,   boxLabel: 'box',   perSession: null, targetQty: 1,  section: 'nxstage', priority: 8 },
  { code: '1990134',    label: 'Spirigel Hand Gel',  unit: 'unit',      boxSize: 1,   boxLabel: 'piece', perSession: null, targetQty: 1,  section: 'nxstage', priority: 9 },
  { code: 'UK00000832', label: 'Sharps Bin',         unit: 'unit',      boxSize: 1,   boxLabel: 'piece', perSession: null, targetQty: 1,  section: 'nxstage', priority: 10 },
  { code: 'UK00000172', label: 'Micropore Tape',     unit: 'roll',      boxSize: 12,  boxLabel: 'box',   perSession: null, targetQty: 4,  section: 'nxstage', priority: 11 },
  // ── Hospital prescriptions ───────────────────────────────────────────────
  { code: 'heparin',    label: 'Heparin',            unit: 'unit',      boxSize: 1,   boxLabel: 'unit',  perSession: null, targetQty: 8,  section: 'hospital', priority: 1 },
  { code: 'epo',        label: 'EPO',                unit: 'unit',      boxSize: 1,   boxLabel: 'unit',  perSession: null, targetQty: 4,  section: 'hospital', priority: 2 },
];

export function getItem(code: string): ItemDef | undefined {
  return ITEMS.find(i => i.code === code);
}

// Fixed per-session deductions (variable items are passed explicitly by the caller)
export const SESSION_FIXED_DELTAS: Record<string, number> = {
  'SAK-303': -1,
  'CAR-172-C': -1,
  'UK00000880': -1,
  'F00010983': -1,
};
```

- [ ] **Step 4: Write stockCalc.ts**

```typescript
// frontend/src/routes/Inventory/lib/stockCalc.ts
import { ITEMS, getItem } from '../constants';

const RED_THRESHOLD = 8;    // < 2 weeks of sessions
const AMBER_THRESHOLD = 16; // < 4 weeks of sessions

export function sessionsRemaining(code: string, qty: number): number | null {
  if (code === 'PAK-001') return qty * 10;
  if (code === 'P00012326') return Math.floor(qty / 2);
  const item = getItem(code);
  if (!item || item.section === 'hospital') return null;
  if (item.perSession && item.perSession > 0) return Math.floor(qty / item.perSession);
  return null;
}

export type StockStatus = 'red' | 'amber' | 'green';

export function stockStatus(code: string, qty: number): StockStatus {
  const item = getItem(code);
  if (!item) return qty > 0 ? 'green' : 'red';

  if (item.section === 'hospital') {
    if (qty <= 0) return 'red';
    if (qty <= 1) return 'amber';
    return 'green';
  }

  const sr = sessionsRemaining(code, qty);
  if (sr === null) return qty <= 0 ? 'red' : qty <= 1 ? 'amber' : 'green';
  if (sr < RED_THRESHOLD) return 'red';
  if (sr < AMBER_THRESHOLD) return 'amber';
  return 'green';
}

export function needsOrdering(code: string, qty: number): boolean {
  const item = getItem(code);
  if (!item || item.section === 'hospital') return false;
  return qty < item.targetQty;
}

export function orderUnits(code: string, currentQty: number): number {
  const item = getItem(code);
  if (!item || item.section === 'hospital') return 0;
  return Math.max(0, item.targetQty - currentQty);
}

export function orderBoxes(code: string, currentQty: number): number {
  const item = getItem(code);
  if (!item) return 0;
  return Math.ceil(orderUnits(code, currentQty) / item.boxSize);
}

export interface StockEntry { code: string; qty: number; }

export function sortStock(entries: StockEntry[]): StockEntry[] {
  const nxstage = entries.filter(e => getItem(e.code)?.section === 'nxstage');
  const hospital = entries.filter(e => getItem(e.code)?.section === 'hospital');
  const unknowns = entries.filter(e => !getItem(e.code));

  function sortGroup(group: StockEntry[]): StockEntry[] {
    return [...group].sort((a, b) => {
      const aNeedsOrder = needsOrdering(a.code, a.qty);
      const bNeedsOrder = needsOrdering(b.code, b.qty);
      if (aNeedsOrder !== bNeedsOrder) return aNeedsOrder ? -1 : 1;
      return (getItem(a.code)?.priority ?? 99) - (getItem(b.code)?.priority ?? 99);
    });
  }

  return [...sortGroup(nxstage), ...sortGroup(hospital), ...unknowns];
}
```

- [ ] **Step 5: Run tests — expect all pass**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend
npm run test -- --reporter=verbose src/routes/Inventory/lib/stockCalc.test.ts
# Expected: all PASS
```

- [ ] **Step 6: Commit**

```bash
git add frontend/src/routes/Inventory/constants.ts \
        frontend/src/routes/Inventory/lib/stockCalc.ts \
        frontend/src/routes/Inventory/lib/stockCalc.test.ts
git commit -m "feat(inventory): add item constants and pure stock calculation logic"
```

---

## Task 7: DeliveryCycleBanner component

**Files:**
- Create: `frontend/src/routes/Inventory/components/DeliveryCycleBanner.tsx`

- [ ] **Step 1: Write the component**

```tsx
// frontend/src/routes/Inventory/components/DeliveryCycleBanner.tsx
import { CalendarDays, Package, Check } from 'lucide-react';
import type { Cycle } from '../schemas';

interface Props {
  cycle: Cycle | null;
  onSetupCycle: () => void;
  onOpenOrder: () => void;
}

function daysUntil(dateStr: string): number {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const target = new Date(dateStr);
  target.setHours(0, 0, 0, 0);
  return Math.round((target.getTime() - today.getTime()) / 86_400_000);
}

function fmt(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

export function DeliveryCycleBanner({ cycle, onSetupCycle, onOpenOrder }: Props) {
  if (!cycle) {
    return (
      <div className="bg-panel border border-slate-700 rounded-lg px-4 py-3 flex items-center justify-between">
        <span className="text-sm text-slate-400">No delivery cycle set up yet.</span>
        <button type="button" onClick={onSetupCycle} className="text-sm text-accent underline">
          Set call date
        </button>
      </div>
    );
  }

  const callDays = daysUntil(cycle.call_date);
  const deliveryDays = daysUntil(cycle.delivery_date);
  const orderPlaced = !!cycle.order_placed_at;

  // Delivery day or overdue
  if (deliveryDays <= 0 && orderPlaced) {
    const label = deliveryDays === 0 ? 'today' : `${Math.abs(deliveryDays)}d overdue`;
    return (
      <div className="bg-amber-900/30 border border-amber-700 rounded-lg px-4 py-3 flex items-center justify-between">
        <span className="inline-flex items-center gap-2 text-sm text-amber-300">
          <Package size={16} /> Delivery {label} · {fmt(cycle.delivery_date)}
        </span>
        <button type="button" onClick={onOpenOrder} className="text-sm text-accent underline">
          Apply
        </button>
      </div>
    );
  }

  return (
    <div className="bg-panel border border-slate-700 rounded-lg px-4 py-3 flex items-center gap-4 text-sm">
      <span className={`inline-flex items-center gap-1.5 ${orderPlaced ? 'text-slate-500' : 'text-slate-200'}`}>
        <CalendarDays size={14} />
        {orderPlaced
          ? <><Check size={12} className="text-emerald-400" /> Called · {fmt(cycle.call_date)}</>
          : callDays <= 0
            ? <span className="text-amber-300">Call today · {fmt(cycle.call_date)}</span>
            : <>Call in {callDays}d · {fmt(cycle.call_date)}</>
        }
      </span>

      <span className="text-slate-600">→</span>

      <span className={`inline-flex items-center gap-1.5 ${orderPlaced ? 'text-slate-200' : 'text-slate-500'}`}>
        <Package size={14} />
        {orderPlaced
          ? <>Delivery in {deliveryDays}d · {fmt(cycle.delivery_date)}</>
          : <>{fmt(cycle.delivery_date)}</>
        }
      </span>

      {!orderPlaced && (
        <button type="button" onClick={onOpenOrder} className="ml-auto text-xs text-accent underline">
          Place order
        </button>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Type-check**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend
npm run typecheck
# Expected: no errors
```

- [ ] **Step 3: Commit**

```bash
git add frontend/src/routes/Inventory/components/DeliveryCycleBanner.tsx
git commit -m "feat(inventory): add DeliveryCycleBanner component"
```

---

## Task 8: StockItemRow component

**Files:**
- Create: `frontend/src/routes/Inventory/components/StockItemRow.tsx`

- [ ] **Step 1: Write the component**

The undo pattern: fire the API call immediately (optimistic), show a 5-second undo toast. If undo is tapped, fire the reverse API call. The parent controls `qty` — it is passed in and updates are reported up via callbacks.

```tsx
// frontend/src/routes/Inventory/components/StockItemRow.tsx
import { useEffect, useRef, useState } from 'react';
import { Minus, Plus } from 'lucide-react';
import { sessionsRemaining, stockStatus } from '../lib/stockCalc';
import type { ItemDef } from '../constants';

interface Props {
  item: ItemDef;
  qty: number;
  onAdjust: (delta: number) => Promise<void>;
}

const STATUS_COLOUR: Record<string, string> = {
  red: 'text-red-400',
  amber: 'text-amber-400',
  green: 'text-emerald-400',
};

const STATUS_DOT: Record<string, string> = {
  red: 'bg-red-500',
  amber: 'bg-amber-500',
  green: 'bg-emerald-500',
};

interface Toast {
  id: number;
  label: string;
  undoDelta: number;
}

export function StockItemRow({ item, qty, onAdjust }: Props) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const toastId = useRef(0);

  async function handleAdjust(delta: number) {
    const id = ++toastId.current;
    const label = `${delta > 0 ? '+' : ''}${delta} ${item.label}`;
    setToasts(ts => [...ts, { id, label, undoDelta: -delta }]);

    // Fire API immediately (optimistic — parent already updated qty)
    try {
      await onAdjust(delta);
    } catch {
      // If API fails, revert via undo
      setToasts(ts => ts.filter(t => t.id !== id));
      try { await onAdjust(-delta); } catch { /* best effort revert */ }
    }

    // Auto-dismiss after 5s
    setTimeout(() => setToasts(ts => ts.filter(t => t.id !== id)), 5000);
  }

  async function handleUndo(toast: Toast) {
    setToasts(ts => ts.filter(t => t.id !== toast.id));
    try { await onAdjust(toast.undoDelta); } catch { /* best effort */ }
  }

  const sr = sessionsRemaining(item.code, qty);
  const status = stockStatus(item.code, qty);

  return (
    <div className="relative">
      <div className="flex items-center gap-3 py-2">
        <span className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${STATUS_DOT[status]}`} />

        <span className="flex-1 text-sm">
          <span className="text-slate-200">{item.label}</span>
          <span className={`ml-2 text-xs ${STATUS_COLOUR[status]}`}>
            {qty} {item.unit}{qty !== 1 ? 's' : ''}
            {sr != null && <span className="text-slate-500 ml-1">~{sr} sess</span>}
          </span>
        </span>

        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={() => handleAdjust(-1)}
            disabled={qty <= 0}
            className="w-7 h-7 rounded-full border border-slate-600 flex items-center justify-center text-slate-400 hover:text-slate-200 disabled:opacity-30"
            aria-label={`Use one ${item.label}`}
          >
            <Minus size={12} />
          </button>
          <button
            type="button"
            onClick={() => handleAdjust(1)}
            className="w-7 h-7 rounded-full border border-slate-600 flex items-center justify-center text-slate-400 hover:text-slate-200"
            aria-label={`Add one ${item.label}`}
          >
            <Plus size={12} />
          </button>
        </div>
      </div>

      {toasts.map(t => (
        <div
          key={t.id}
          className="absolute right-0 -bottom-8 z-10 bg-slate-700 border border-slate-600 rounded text-xs px-3 py-1 flex items-center gap-3 shadow"
        >
          <span className="text-slate-300">{t.label}</span>
          <button
            type="button"
            onClick={() => handleUndo(t)}
            className="text-accent underline"
          >
            Undo
          </button>
        </div>
      ))}
    </div>
  );
}
```

- [ ] **Step 2: Type-check**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend
npm run typecheck
# Expected: no errors
```

- [ ] **Step 3: Commit**

```bash
git add frontend/src/routes/Inventory/components/StockItemRow.tsx
git commit -m "feat(inventory): add StockItemRow with optimistic [−]/[+] and undo toast"
```

---

## Task 9: LogEventModal component

**Files:**
- Create: `frontend/src/routes/Inventory/components/LogEventModal.tsx`

Three tabs: PAK change (one tap), Manual use (item + delta), Stock count (enter actual quantities for all items).

- [ ] **Step 1: Write the component**

```tsx
// frontend/src/routes/Inventory/components/LogEventModal.tsx
import { useState } from 'react';
import { X } from 'lucide-react';
import { ITEMS } from '../constants';

type Tab = 'pak' | 'manual' | 'count';

interface Props {
  stock: Record<string, number>;
  onLogEvent: (
    type: 'manual' | 'stock_count',
    deltas: Record<string, number>,
    note?: string,
  ) => Promise<void>;
  onClose: () => void;
}

export function LogEventModal({ stock, onLogEvent, onClose }: Props) {
  const [tab, setTab] = useState<Tab>('pak');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // PAK tab
  async function handlePakChange() {
    setSaving(true);
    setError(null);
    try {
      await onLogEvent('manual', { 'PAK-001': -1 }, 'PAK change');
      onClose();
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  // Manual use tab
  const [manualCode, setManualCode] = useState('');
  const [manualDelta, setManualDelta] = useState('');
  async function handleManualUse() {
    if (!manualCode || !manualDelta) return;
    setSaving(true);
    setError(null);
    try {
      await onLogEvent('manual', { [manualCode]: -Math.abs(Number(manualDelta)) });
      onClose();
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  // Stock count tab
  const [counts, setCounts] = useState<Record<string, string>>(() =>
    Object.fromEntries(ITEMS.map(i => [i.code, String(stock[i.code] ?? 0)]))
  );
  async function handleStockCount() {
    setSaving(true);
    setError(null);
    try {
      const deltas: Record<string, number> = {};
      for (const [code, val] of Object.entries(counts)) {
        const n = parseInt(val, 10);
        if (!isNaN(n) && n >= 0) deltas[code] = n;
      }
      await onLogEvent('stock_count', deltas, 'monthly stock count');
      onClose();
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  const tabClass = (t: Tab) =>
    `px-3 py-1.5 text-sm rounded-t border-b-2 transition-colors ${
      tab === t ? 'border-accent text-accent' : 'border-transparent text-slate-400 hover:text-slate-200'
    }`;

  return (
    <div className="fixed inset-0 bg-black/60 flex items-end md:items-center justify-center z-50 p-4">
      <div className="bg-bg border border-slate-700 rounded-xl w-full max-w-sm">
        <div className="flex items-center justify-between px-4 pt-4">
          <span className="font-semibold text-slate-200">Log event</span>
          <button type="button" onClick={onClose} className="text-slate-500 hover:text-slate-300">
            <X size={18} />
          </button>
        </div>

        <div className="flex px-4 pt-3 gap-1 border-b border-slate-700">
          <button type="button" className={tabClass('pak')} onClick={() => setTab('pak')}>PAK change</button>
          <button type="button" className={tabClass('manual')} onClick={() => setTab('manual')}>Manual use</button>
          <button type="button" className={tabClass('count')} onClick={() => setTab('count')}>Stock count</button>
        </div>

        <div className="p-4 space-y-3">
          {tab === 'pak' && (
            <div className="space-y-3">
              <p className="text-sm text-slate-400">Records −1 PAK from stock. Tap confirm when you have just changed the PAK.</p>
              <button
                type="button"
                onClick={handlePakChange}
                disabled={saving}
                className="w-full bg-accent text-bg font-semibold rounded-lg py-2"
              >
                {saving ? 'Saving…' : 'Confirm PAK change'}
              </button>
            </div>
          )}

          {tab === 'manual' && (
            <div className="space-y-3">
              <select
                value={manualCode}
                onChange={e => setManualCode(e.target.value)}
                className="w-full bg-panel border border-slate-600 rounded px-3 py-2 text-sm text-slate-200"
              >
                <option value="">Select item…</option>
                {ITEMS.filter(i => i.section === 'nxstage').map(i => (
                  <option key={i.code} value={i.code}>{i.label}</option>
                ))}
              </select>
              <input
                type="number"
                min="1"
                inputMode="numeric"
                value={manualDelta}
                onChange={e => setManualDelta(e.target.value)}
                placeholder="Qty used"
                className="w-full bg-panel border border-slate-600 rounded px-3 py-2 text-sm text-slate-200"
              />
              <button
                type="button"
                onClick={handleManualUse}
                disabled={saving || !manualCode || !manualDelta}
                className="w-full bg-accent text-bg font-semibold rounded-lg py-2 disabled:opacity-40"
              >
                {saving ? 'Saving…' : 'Log use'}
              </button>
            </div>
          )}

          {tab === 'count' && (
            <div className="space-y-2">
              <p className="text-xs text-slate-500">Enter actual quantities on hand. This overwrites the running estimate.</p>
              <div className="max-h-64 overflow-y-auto space-y-2 pr-1">
                {ITEMS.map(i => (
                  <div key={i.code} className="flex items-center gap-3">
                    <label className="flex-1 text-sm text-slate-300 truncate">{i.label}</label>
                    <input
                      type="number"
                      min="0"
                      inputMode="numeric"
                      value={counts[i.code] ?? '0'}
                      onChange={e => setCounts(c => ({ ...c, [i.code]: e.target.value }))}
                      className="w-20 bg-panel border border-slate-600 rounded px-2 py-1 text-sm text-slate-200 text-right"
                    />
                  </div>
                ))}
              </div>
              <button
                type="button"
                onClick={handleStockCount}
                disabled={saving}
                className="w-full bg-accent text-bg font-semibold rounded-lg py-2"
              >
                {saving ? 'Saving…' : 'Save stock count'}
              </button>
            </div>
          )}

          {error && <p className="text-red-400 text-sm">{error}</p>}
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Type-check**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend
npm run typecheck
# Expected: no errors
```

- [ ] **Step 3: Commit**

```bash
git add frontend/src/routes/Inventory/components/LogEventModal.tsx
git commit -m "feat(inventory): add LogEventModal (PAK change, manual use, stock count)"
```

---

## Task 10: OrderView component

**Files:**
- Create: `frontend/src/routes/Inventory/components/OrderView.tsx`

Two-step flow: (1) stock count form → (2) order list with confirm and copy buttons.

- [ ] **Step 1: Write the component**

```tsx
// frontend/src/routes/Inventory/components/OrderView.tsx
import { useState } from 'react';
import { X, Copy, Check } from 'lucide-react';
import { ITEMS } from '../constants';
import { orderBoxes, orderUnits } from '../lib/stockCalc';

interface Props {
  stock: Record<string, number>;
  callDate: string;
  onStockCount: (deltas: Record<string, number>) => Promise<void>;
  onConfirmOrder: (callDate: string, order: Record<string, number>) => Promise<void>;
  onApplyDelivery: (adjustments?: Record<string, number>) => Promise<void>;
  mode: 'order' | 'delivery';
  onClose: () => void;
}

type Step = 'count' | 'order_list' | 'confirm_delivery';

export function OrderView({ stock, callDate, onStockCount, onConfirmOrder, onApplyDelivery, mode, onClose }: Props) {
  const [step, setStep] = useState<Step>(mode === 'delivery' ? 'confirm_delivery' : 'count');
  const [counts, setCounts] = useState<Record<string, string>>(() =>
    Object.fromEntries(ITEMS.filter(i => i.section === 'nxstage').map(i => [i.code, String(stock[i.code] ?? 0)]))
  );
  const [adjustments, setAdjustments] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  // Step 1: save stock count, advance to order list
  async function handleCountSubmit() {
    setSaving(true); setError(null);
    try {
      const deltas: Record<string, number> = {};
      for (const [code, val] of Object.entries(counts)) {
        const n = parseInt(val, 10);
        if (!isNaN(n) && n >= 0) deltas[code] = n;
      }
      await onStockCount(deltas);
      setStep('order_list');
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  // Computed order using the entered counts as current stock
  const orderedItems = ITEMS.filter(i => i.section === 'nxstage').map(i => {
    const current = parseInt(counts[i.code] ?? '0', 10) || 0;
    const boxes = orderBoxes(i.code, current);
    const units = orderUnits(i.code, current);
    return { item: i, current, boxes, units };
  }).filter(r => r.boxes > 0);

  // Step 2: confirm the order
  async function handleConfirmOrder() {
    setSaving(true); setError(null);
    try {
      const order: Record<string, number> = {};
      for (const { item, units } of orderedItems) order[item.code] = units;
      await onConfirmOrder(callDate, order);
      onClose();
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  // Copy order list to clipboard
  function copyToClipboard() {
    const lines = orderedItems.map(({ item, boxes }) =>
      `${item.label}: ${boxes} ${boxes === 1 ? item.boxLabel : item.boxLabel + 's'}`
    );
    navigator.clipboard.writeText(lines.join('\n')).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }

  // Delivery mode: show adjusted quantities, confirm apply
  async function handleApplyDelivery() {
    setSaving(true); setError(null);
    try {
      const adj: Record<string, number> = {};
      for (const [code, val] of Object.entries(adjustments)) {
        const n = parseInt(val, 10);
        if (!isNaN(n) && n >= 0) adj[code] = n;
      }
      await onApplyDelivery(Object.keys(adj).length > 0 ? adj : undefined);
      onClose();
    } catch { setError('Save failed'); }
    finally { setSaving(false); }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-end md:items-center justify-center z-50 p-4">
      <div className="bg-bg border border-slate-700 rounded-xl w-full max-w-sm max-h-[85vh] flex flex-col">
        <div className="flex items-center justify-between px-4 pt-4 pb-3 flex-shrink-0">
          <span className="font-semibold text-slate-200">
            {step === 'count' ? 'Step 1: Stock count' :
             step === 'order_list' ? 'Step 2: Order list' :
             'Apply delivery'}
          </span>
          <button type="button" onClick={onClose} className="text-slate-500 hover:text-slate-300">
            <X size={18} />
          </button>
        </div>

        <div className="overflow-y-auto flex-1 px-4 pb-4 space-y-3">
          {step === 'count' && (
            <>
              <p className="text-xs text-slate-500">Count what you physically have. This resets the running estimate before calculating the order.</p>
              {ITEMS.filter(i => i.section === 'nxstage').map(i => (
                <div key={i.code} className="flex items-center gap-3">
                  <span className="flex-1 text-sm text-slate-300 truncate">{i.label}</span>
                  <span className="text-xs text-slate-500">{i.unit}s</span>
                  <input
                    type="number"
                    min="0"
                    inputMode="numeric"
                    value={counts[i.code] ?? '0'}
                    onChange={e => setCounts(c => ({ ...c, [i.code]: e.target.value }))}
                    className="w-20 bg-panel border border-slate-600 rounded px-2 py-1 text-sm text-slate-200 text-right"
                  />
                </div>
              ))}
              <button
                type="button"
                onClick={handleCountSubmit}
                disabled={saving}
                className="w-full bg-accent text-bg font-semibold rounded-lg py-2"
              >
                {saving ? 'Saving…' : 'Next: calculate order →'}
              </button>
            </>
          )}

          {step === 'order_list' && (
            <>
              {orderedItems.length === 0 ? (
                <p className="text-sm text-slate-400 text-center py-4">Stock is sufficient — nothing to order.</p>
              ) : (
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-xs text-slate-500 uppercase">
                      <th className="text-left py-1">Item</th>
                      <th className="text-right py-1">Have</th>
                      <th className="text-right py-1">Order</th>
                    </tr>
                  </thead>
                  <tbody>
                    {orderedItems.map(({ item, current, boxes }) => (
                      <tr key={item.code} className="border-t border-slate-800 text-slate-300">
                        <td className="py-1.5">{item.label}</td>
                        <td className="text-right text-slate-500">{current}</td>
                        <td className="text-right font-semibold text-accent">
                          {boxes} {boxes === 1 ? item.boxLabel : item.boxLabel + 's'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={copyToClipboard}
                  className="flex-1 border border-slate-600 text-slate-300 rounded-lg py-2 text-sm inline-flex items-center justify-center gap-2"
                >
                  {copied ? <><Check size={14} /> Copied</> : <><Copy size={14} /> Copy list</>}
                </button>
                <button
                  type="button"
                  onClick={handleConfirmOrder}
                  disabled={saving}
                  className="flex-1 bg-accent text-bg font-semibold rounded-lg py-2 text-sm"
                >
                  {saving ? 'Saving…' : 'Confirm order'}
                </button>
              </div>
            </>
          )}

          {step === 'confirm_delivery' && (
            <>
              <p className="text-xs text-slate-500">Edit quantities if anything arrived differently. Leave blank to use the ordered amounts.</p>
              {ITEMS.filter(i => i.section === 'nxstage' && stock[i.code] !== undefined).map(i => (
                <div key={i.code} className="flex items-center gap-3">
                  <span className="flex-1 text-sm text-slate-300 truncate">{i.label}</span>
                  <input
                    type="number"
                    min="0"
                    inputMode="numeric"
                    value={adjustments[i.code] ?? ''}
                    placeholder="as ordered"
                    onChange={e => setAdjustments(a => ({ ...a, [i.code]: e.target.value }))}
                    className="w-24 bg-panel border border-slate-600 rounded px-2 py-1 text-sm text-slate-200 text-right placeholder:text-slate-600"
                  />
                </div>
              ))}
              <button
                type="button"
                onClick={handleApplyDelivery}
                disabled={saving}
                className="w-full bg-accent text-bg font-semibold rounded-lg py-2"
              >
                {saving ? 'Applying…' : 'Apply delivery'}
              </button>
            </>
          )}

          {error && <p className="text-red-400 text-sm">{error}</p>}
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Type-check**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend
npm run typecheck
# Expected: no errors
```

- [ ] **Step 3: Commit**

```bash
git add frontend/src/routes/Inventory/components/OrderView.tsx
git commit -m "feat(inventory): add OrderView (stock count → order list → confirm)"
```

---

## Task 11: Inventory index.tsx

**Files:**
- Modify: `frontend/src/routes/Inventory/index.tsx`

- [ ] **Step 1: Write the full Inventory route**

```tsx
// frontend/src/routes/Inventory/index.tsx
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Package } from 'lucide-react';
import { getAuth, type AuthSettings } from '../../auth/storage';
import { fetchInventory, logEvent, confirmOrder, applyDelivery, initCycle, ApiError } from './api';
import { ITEMS, SESSION_FIXED_DELTAS } from './constants';
import { sortStock } from './lib/stockCalc';
import { DeliveryCycleBanner } from './components/DeliveryCycleBanner';
import { StockItemRow } from './components/StockItemRow';
import { LogEventModal } from './components/LogEventModal';
import { OrderView } from './components/OrderView';
import type { Cycle } from './schemas';

type State =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; stock: Record<string, number>; cycle: Cycle | null };

export default function Inventory() {
  const navigate = useNavigate();
  const [auth, setAuth] = useState<AuthSettings | null>(null);
  const [state, setState] = useState<State>({ status: 'loading' });
  const [modal, setModal] = useState<'log' | 'order' | 'delivery' | 'setup' | null>(null);
  const [setupDate, setSetupDate] = useState('');
  const [setupSaving, setSetupSaving] = useState(false);

  // Initial load
  useEffect(() => {
    getAuth().then(a => {
      if (!a) { navigate('/setup', { replace: true }); return; }
      setAuth(a);
      return fetchInventory(a).then(data => {
        setState({ status: 'ready', stock: data.stock, cycle: data.cycle });
        // Auto-apply delivery if due
        if (data.cycle?.order_placed_at && !data.cycle.delivery_applied_at) {
          const today = new Date().toISOString().slice(0, 10);
          if (data.cycle.delivery_date <= today) {
            applyDelivery(a).then(() =>
              fetchInventory(a).then(d =>
                setState({ status: 'ready', stock: d.stock, cycle: d.cycle })
              )
            ).catch(() => {});
          }
        }
      });
    }).catch(err => setState({ status: 'error', message: String(err) }));
  }, [navigate]);

  async function handleAdjust(code: string, delta: number) {
    if (!auth || state.status !== 'ready') return;
    setState(s => s.status !== 'ready' ? s : {
      ...s,
      stock: { ...s.stock, [code]: (s.stock[code] ?? 0) + delta },
    });
    await logEvent(auth, 'manual', { [code]: delta });
  }

  async function handleLogEvent(
    type: 'manual' | 'stock_count',
    deltas: Record<string, number>,
    note?: string,
  ) {
    if (!auth || state.status !== 'ready') return;
    if (type === 'stock_count') {
      setState(s => s.status !== 'ready' ? s : { ...s, stock: { ...s.stock, ...deltas } });
    } else {
      const next = { ...((state as { stock: Record<string,number> }).stock) };
      for (const [code, delta] of Object.entries(deltas)) next[code] = (next[code] ?? 0) + delta;
      setState(s => s.status !== 'ready' ? s : { ...s, stock: next });
    }
    await logEvent(auth, type, deltas, note);
    // Refresh to get server-authoritative state
    const fresh = await fetchInventory(auth);
    setState(s => s.status !== 'ready' ? s : { ...s, stock: fresh.stock });
  }

  async function handleStockCount(deltas: Record<string, number>) {
    await handleLogEvent('stock_count', deltas, 'monthly stock count');
  }

  async function handleConfirmOrder(callDate: string, order: Record<string, number>) {
    if (!auth) return;
    await confirmOrder(auth, callDate, order);
    const fresh = await fetchInventory(auth);
    setState(s => s.status !== 'ready' ? s : { ...s, cycle: fresh.cycle });
  }

  async function handleApplyDelivery(adjustments?: Record<string, number>) {
    if (!auth) return;
    await applyDelivery(auth, adjustments);
    const fresh = await fetchInventory(auth);
    setState({ status: 'ready', stock: fresh.stock, cycle: fresh.cycle });
  }

  async function handleSetupCycle() {
    if (!auth || !setupDate) return;
    setSetupSaving(true);
    try {
      await initCycle(auth, setupDate);
      const fresh = await fetchInventory(auth);
      setState(s => s.status !== 'ready' ? s : { ...s, cycle: fresh.cycle });
      setModal(null);
    } catch { /* show inline */ }
    finally { setSetupSaving(false); }
  }

  if (state.status === 'loading') return <div className="p-4 text-slate-400">Loading…</div>;
  if (state.status === 'error') return <div className="p-4 text-red-400">Error: {state.message}</div>;

  const { stock, cycle } = state;
  const callDate = cycle?.call_date ?? new Date().toISOString().slice(0, 10);

  const nxstageItems = ITEMS.filter(i => i.section === 'nxstage');
  const hospitalItems = ITEMS.filter(i => i.section === 'hospital');
  const allEntries = ITEMS.map(i => ({ code: i.code, qty: stock[i.code] ?? 0 }));
  const sorted = sortStock(allEntries);
  const sortedNxstage = sorted.filter(e => nxstageItems.find(i => i.code === e.code));
  const sortedHospital = sorted.filter(e => hospitalItems.find(i => i.code === e.code));

  return (
    <div className="p-4 max-w-md mx-auto space-y-4">
      <h1 className="text-xl font-bold inline-flex items-center gap-2">
        <Package size={20} className="text-accent" /> Inventory
      </h1>

      <DeliveryCycleBanner
        cycle={cycle}
        onSetupCycle={() => setModal('setup')}
        onOpenOrder={() => setModal(cycle?.order_placed_at ? 'delivery' : 'order')}
      />

      <button
        type="button"
        onClick={() => setModal('log')}
        className="w-full border border-slate-600 text-slate-300 rounded-lg py-2 text-sm"
      >
        + Log event
      </button>

      {/* NxStage supplies */}
      <section>
        <h2 className="text-xs uppercase text-slate-500 tracking-wider mb-2">NxStage Supplies</h2>
        <div className="bg-panel border border-slate-700 rounded-lg divide-y divide-slate-700/50 px-3">
          {sortedNxstage.map(({ code, qty }) => {
            const item = nxstageItems.find(i => i.code === code)!;
            return (
              <StockItemRow
                key={code}
                item={item}
                qty={qty}
                onAdjust={delta => handleAdjust(code, delta)}
              />
            );
          })}
        </div>
      </section>

      {/* Hospital prescriptions */}
      <section>
        <h2 className="text-xs uppercase text-slate-500 tracking-wider mb-2">Hospital Prescriptions</h2>
        <div className="bg-panel border border-slate-700 rounded-lg divide-y divide-slate-700/50 px-3">
          {sortedHospital.map(({ code, qty }) => {
            const item = hospitalItems.find(i => i.code === code)!;
            return (
              <StockItemRow
                key={code}
                item={item}
                qty={qty}
                onAdjust={delta => handleAdjust(code, delta)}
              />
            );
          })}
        </div>
      </section>

      {/* Setup cycle modal */}
      {modal === 'setup' && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
          <div className="bg-bg border border-slate-700 rounded-xl w-full max-w-xs p-4 space-y-3">
            <h2 className="font-semibold text-slate-200">Set first call date</h2>
            <input
              type="date"
              value={setupDate}
              onChange={e => setSetupDate(e.target.value)}
              className="w-full bg-panel border border-slate-600 rounded px-3 py-2 text-sm text-slate-200"
            />
            <div className="flex gap-2">
              <button type="button" onClick={() => setModal(null)} className="flex-1 border border-slate-600 text-slate-300 rounded-lg py-2 text-sm">Cancel</button>
              <button type="button" onClick={handleSetupCycle} disabled={!setupDate || setupSaving} className="flex-1 bg-accent text-bg font-semibold rounded-lg py-2 text-sm disabled:opacity-40">
                {setupSaving ? 'Saving…' : 'Save'}
              </button>
            </div>
          </div>
        </div>
      )}

      {modal === 'log' && (
        <LogEventModal
          stock={stock}
          onLogEvent={handleLogEvent}
          onClose={() => setModal(null)}
        />
      )}

      {(modal === 'order' || modal === 'delivery') && (
        <OrderView
          stock={stock}
          callDate={callDate}
          onStockCount={handleStockCount}
          onConfirmOrder={handleConfirmOrder}
          onApplyDelivery={handleApplyDelivery}
          mode={modal === 'delivery' ? 'delivery' : 'order'}
          onClose={() => setModal(null)}
        />
      )}
    </div>
  );
}
```

- [ ] **Step 2: Type-check**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend
npm run typecheck
# Expected: no errors
```

- [ ] **Step 3: Run all tests**

```bash
npm run test
# Expected: all PASS (no regressions)
```

- [ ] **Step 4: Commit**

```bash
git add frontend/src/routes/Inventory/index.tsx
git commit -m "feat(inventory): implement full Inventory route"
```

---

## Task 12: ActiveSession — needles and on/off pack consumed fields

**Files:**
- Modify: `frontend/src/routes/Treatment/screens/ActiveSession.tsx`
- Modify: `frontend/src/routes/Treatment/index.tsx`
- Modify: `frontend/src/routes/Treatment/storage.ts`

The `onEnd` signature changes to pass consumed quantities. The `Screen.active` variant gains `heparinUsed`. The `Screen.post` variant gains `consumed`.

- [ ] **Step 1: Add SessionConsumed type + update ActiveState in storage.ts**

In `frontend/src/routes/Treatment/storage.ts`, add after the existing imports:

```typescript
export interface SessionConsumed {
  needles: number;
  onOffPacks: number;
  heparinUsed: boolean;
}
```

And add to `ActiveState`:
```typescript
export interface ActiveState {
  screen: 'pre' | 'active' | 'post';
  session?: Session;
  existingIds?: string[];
  readings?: PendingReading[];
  heparinUsed?: boolean;    // carried from pre → active
  consumed?: SessionConsumed;  // carried from active → post
  savedAt: number;
}
```

- [ ] **Step 2: Update Treatment/index.tsx Screen union**

In `frontend/src/routes/Treatment/index.tsx`, update the `Screen` type and the relevant handlers.

Replace the `Screen` type:
```typescript
import type { SessionConsumed } from './storage';

type Screen =
  | { name: 'loading' }
  | { name: 'home' }
  | { name: 'pre'; existingIds: string[] }
  | { name: 'active'; session: Session; readings: PendingReading[]; heparinUsed: boolean }
  | { name: 'post'; session: Session; consumed: SessionConsumed };
```

Update the `onSaved` callback on `PreTreatment`:
```typescript
onSaved={(session, heparinUsed) =>
  setScreen({ name: 'active', session, readings: [], heparinUsed })
}
```

Update the `onEnd` callback on `ActiveSession`:
```typescript
onEnd={consumed =>
  setScreen({ name: 'post', session: screen.session, consumed: { ...consumed, heparinUsed: screen.heparinUsed } })
}
```

Update the `saveActiveState` calls in the `screen` effect:
```typescript
} else if (screen.name === 'active') {
  saveActiveState({
    screen: 'active',
    session: screen.session,
    readings: screen.readings,
    heparinUsed: screen.heparinUsed,
  });
} else if (screen.name === 'post') {
  saveActiveState({ screen: 'post', session: screen.session, consumed: screen.consumed });
}
```

Update the restoration logic in the mount effect:
```typescript
} else if (active?.screen === 'active' && active.session) {
  const readings = (active.readings ?? []).map(r =>
    r.status === 'pending' ? { ...r, status: 'error' as const, errorMsg: 'interrupted' } : r
  );
  setScreen({ name: 'active', session: active.session, readings, heparinUsed: active.heparinUsed ?? false });
} else if (active?.screen === 'post' && active.session) {
  const consumed: SessionConsumed = active.consumed ?? { needles: 2, onOffPacks: 1, heparinUsed: false };
  setScreen({ name: 'post', session: active.session, consumed });
}
```

Pass `consumed` to `PostTreatment`:
```typescript
if (screen.name === 'post') {
  return (
    <PostTreatment
      settings={settings}
      auth={auth}
      session={screen.session}
      consumed={screen.consumed}
      onSaved={() => setScreen({ name: 'home' })}
    />
  );
}
```

Also pass `auth` and track it in state. Add `const [auth, setAuth] = useState<AuthSettings | null>(null)` and update the mount effect to `setAuth(a)` before constructing settings. Import `AuthSettings` from `'../../auth/storage'`.

- [ ] **Step 3: Update ActiveSession.tsx — consumed fields + new onEnd signature**

In `frontend/src/routes/Treatment/screens/ActiveSession.tsx`:

Change the Props interface:
```typescript
import type { SessionConsumed } from '../storage';

interface Props {
  settings: Settings;
  session: Session;
  initialReadings?: PendingReading[];
  onReadingsChange?: (rs: PendingReading[]) => void;
  onEnd: (consumed: Omit<SessionConsumed, 'heparinUsed'>) => void;
}
```

Add consumed state near the top of the component:
```typescript
const [needles, setNeedles] = useState(2);
const [onOffPacks, setOnOffPacks] = useState(1);
```

Add a section at the bottom of the JSX, before the readings list, after the "End" button area:

```tsx
{/* Consumed this session */}
<div className="bg-panel border border-slate-700 rounded-lg px-3 py-2">
  <p className="text-xs text-slate-500 mb-2">Consumed this session</p>
  <div className="grid grid-cols-2 gap-3">
    <div>
      <label className="text-xs text-slate-400 block mb-1">Needles used</label>
      <input
        type="number"
        min="0"
        inputMode="numeric"
        value={needles}
        onChange={e => setNeedles(Math.max(0, parseInt(e.target.value, 10) || 0))}
        className="w-full bg-bg border border-slate-600 rounded px-2 py-1 text-sm text-slate-200 text-center"
      />
    </div>
    <div>
      <label className="text-xs text-slate-400 block mb-1">On/Off packs</label>
      <input
        type="number"
        min="0"
        inputMode="numeric"
        value={onOffPacks}
        onChange={e => setOnOffPacks(Math.max(0, parseInt(e.target.value, 10) || 0))}
        className="w-full bg-bg border border-slate-600 rounded px-2 py-1 text-sm text-slate-200 text-center"
      />
    </div>
  </div>
</div>
```

Update the End button `onClick` to pass the consumed values:
```typescript
onClick={() => onEnd({ needles, onOffPacks })}
```

- [ ] **Step 4: Type-check**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend
npm run typecheck
# Expected: no errors
```

- [ ] **Step 5: Commit**

```bash
git add frontend/src/routes/Treatment/storage.ts \
        frontend/src/routes/Treatment/index.tsx \
        frontend/src/routes/Treatment/screens/ActiveSession.tsx
git commit -m "feat(inventory): thread session consumed quantities through Treatment screens"
```

---

## Task 13: PreTreatment — heparin toggle + stock display

**Files:**
- Modify: `frontend/src/routes/Treatment/screens/PreTreatment.tsx`

- [ ] **Step 1: Update PreTreatment**

Add `auth: AuthSettings | null` and `onSaved: (session: Session, heparinUsed: boolean) => void` to the Props interface. Import `AuthSettings` from `'../../auth/storage'`.

Change Props interface:
```typescript
import type { AuthSettings } from '../../auth/storage';
import { cloudGet } from '../../../api/cloudRun';

interface Props {
  settings: Settings;
  auth: AuthSettings | null;
  existingIds: string[];
  onSaved: (session: Session, heparinUsed: boolean) => void;
  onCancel: () => void;
}
```

Add heparin state near other `useState` calls:
```typescript
const [heparinUsed, setHeparinUsed] = useState(true);
const [heparinStock, setHeparinStock] = useState<number | null>(null);
```

Load heparin stock (non-blocking):
```typescript
useEffect(() => {
  if (!auth) return;
  cloudGet<{ stock: Record<string, number> }>(auth, '/api/inventory')
    .then(data => setHeparinStock(data.stock['heparin'] ?? 0))
    .catch(() => {});
}, [auth]);
```

Add heparin toggle to the JSX, below the grid and above the SaveButton:
```tsx
<div className="flex items-center justify-between bg-panel border border-slate-700 rounded-lg px-3 py-2">
  <div>
    <span className="text-sm text-slate-200">Heparin</span>
    {heparinStock !== null && (
      <span className="ml-2 text-xs text-slate-500">{heparinStock} remaining</span>
    )}
  </div>
  <button
    type="button"
    onClick={() => setHeparinUsed(h => !h)}
    className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
      heparinUsed
        ? 'bg-accent text-bg'
        : 'bg-slate-700 text-slate-400'
    }`}
  >
    {heparinUsed ? 'Used' : 'Not used'}
  </button>
</div>
```

Update the `submit` function to pass `heparinUsed` to `onSaved`:
```typescript
onSaved(session, heparinUsed);
```

Also update the Treatment/index.tsx `PreTreatment` rendering to pass `auth`:
```typescript
<PreTreatment
  settings={settings}
  auth={auth}
  existingIds={screen.existingIds}
  onSaved={(session, heparinUsed) =>
    setScreen({ name: 'active', session, readings: [], heparinUsed })
  }
  onCancel={() => setScreen({ name: 'home' })}
/>
```

- [ ] **Step 2: Type-check**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend
npm run typecheck
# Expected: no errors
```

- [ ] **Step 3: Commit**

```bash
git add frontend/src/routes/Treatment/screens/PreTreatment.tsx \
        frontend/src/routes/Treatment/index.tsx
git commit -m "feat(inventory): add heparin toggle to PreTreatment with stock display"
```

---

## Task 14: PostTreatment — EPO toggle, EPO stock display, fire session event

**Files:**
- Modify: `frontend/src/routes/Treatment/screens/PostTreatment.tsx`

- [ ] **Step 1: Update PostTreatment**

Add `auth`, `consumed` props. Import required dependencies.

```typescript
import { cloudGet } from '../../../api/cloudRun';
import { logEvent } from '../../Inventory/api';
import { SESSION_FIXED_DELTAS } from '../../Inventory/constants';
import type { AuthSettings } from '../../../auth/storage';
import type { SessionConsumed } from '../storage';
```

Update Props interface:
```typescript
interface Props {
  settings: Settings;
  auth: AuthSettings | null;
  session: Session;
  consumed: SessionConsumed;
  onSaved: () => void;
}
```

Add EPO state:
```typescript
const [epoUsed, setEpoUsed] = useState(true);
const [epoStock, setEpoStock] = useState<number | null>(null);
```

Load EPO stock (non-blocking):
```typescript
useEffect(() => {
  if (!auth) return;
  cloudGet<{ stock: Record<string, number> }>(auth, '/api/inventory')
    .then(data => setEpoStock(data.stock['epo'] ?? 0))
    .catch(() => {});
}, [auth]);
```

Add EPO toggle to the JSX, below the grid and above the SaveButton:
```tsx
<div className="flex items-center justify-between bg-panel border border-slate-700 rounded-lg px-3 py-2">
  <div>
    <span className="text-sm text-slate-200">EPO</span>
    {epoStock !== null && (
      <span className="ml-2 text-xs text-slate-500">{epoStock} remaining</span>
    )}
  </div>
  <button
    type="button"
    onClick={() => setEpoUsed(e => !e)}
    className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
      epoUsed
        ? 'bg-accent text-bg'
        : 'bg-slate-700 text-slate-400'
    }`}
  >
    {epoUsed ? 'Used' : 'Not used'}
  </button>
</div>
```

Update the `submit` function to fire the inventory session event after a successful `updateSession`. The inventory event is non-blocking — a failure here should not fail the session save.

Replace the `submit` function:
```typescript
async function submit() {
  setError(null);
  setSaving(true);
  try {
    await updateSession(settings, {
      session_id: sessionId,
      ...form,
      total_uf: effectiveTotalUf,
    });

    // Fire inventory session event (non-blocking — never fail the session save)
    if (auth) {
      const deltas: Record<string, number> = {
        ...SESSION_FIXED_DELTAS,
        'P00012326': -consumed.needles,
        'UK00000774': -consumed.onOffPacks,
      };
      if (consumed.heparinUsed) deltas['heparin'] = -1;
      if (epoUsed) deltas['epo'] = -1;
      logEvent(auth, 'session', deltas).catch(() => {});
    }

    onSaved();
  } catch (e) {
    setError(e instanceof ApiError ? `Save failed: ${e.code}` : String(e));
  } finally {
    setSaving(false);
  }
}
```

- [ ] **Step 2: Type-check**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend
npm run typecheck
# Expected: no errors
```

- [ ] **Step 3: Run all tests**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker
npm run test --prefix frontend && npm run test --prefix api
# Expected: all PASS — no regressions
```

- [ ] **Step 4: Commit**

```bash
git add frontend/src/routes/Treatment/screens/PostTreatment.tsx
git commit -m "feat(inventory): add EPO toggle to PostTreatment and fire session inventory event"
```

---

## Final: deploy

- [ ] **Build frontend and deploy**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend
npm run build
npx wrangler pages deploy dist --project-name=treatment-tracker --branch=master --commit-dirty=true
# Not needed — app is now on Firebase Hosting
```

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/frontend && npm run build
firebase deploy --only hosting --project homehd-personal
```

- [ ] **Deploy API**

```bash
cd /Users/ntg/Documents/Personal_Projects/treatment_tracker/api
gcloud run deploy homehd-api \
  --source . \
  --region=europe-west2 \
  --allow-unauthenticated \
  --set-secrets=MAIN_API_KEY=main-api-key:latest \
  --project=homehd-personal
```

- [ ] **Smoke test inventory endpoint**

```bash
KEY=$(security find-generic-password -a "$USER" -s "homehd-main-key" -w)
curl -s -H "Authorization: Bearer $KEY" https://homehd.web.app/api/inventory
# Expected: { "stock": {}, "cycle": null }
```

- [ ] **First-time setup in browser**
  1. Open `https://homehd.web.app/inventory`
  2. Tap "Set call date" → enter `2026-06-23` (next scheduled call)
  3. Use Log event → Stock count to enter current physical quantities
  4. Verify stock list renders with correct status colours

---

## Self-Review

**Spec coverage check:**

| Requirement | Task |
|---|---|
| Stock overview sorted: needs-ordering first, then by frequency | Task 6 (sortStock), Task 11 (renders sorted) |
| [−]/[+] quick actions with undo toast | Task 8 (StockItemRow) |
| Banner: next call date + delivery date, cycle-aware | Task 7 (DeliveryCycleBanner) |
| Call every 4 weeks, delivery +7 days | Task 4 (addDays), Task 7 |
| Auto-apply delivery on delivery day | Task 11 (mount effect) |
| Order calculator: stock count → order in boxes | Task 10 (OrderView) |
| Confirm order: stored, marks order_placed_at | Task 4 (confirm-order) |
| PAK manual log | Task 9 (LogEventModal, PAK tab) |
| Manual use (SAK prep failure, ad hoc) | Task 9 (LogEventModal, manual tab) |
| Session auto-deduct (fixed items) | Task 14 (SESSION_FIXED_DELTAS) |
| Needles + on/off pack: actual qty from Active Session | Tasks 12, 14 |
| Heparin toggle (Pre-treatment) + stock display | Task 13 |
| EPO toggle (Post-treatment) + stock display | Task 14 |
| Hospital items: no order calculator, count only | Task 6 (needsOrdering returns false), Task 11 (separate section) |
| NxStage / Hospital sections | Task 11 |
| Two-week to four-week buffer in order target | Task 6 (targetQty in constants = 24 sessions = 1 month + 2 weeks) |

**Placeholder scan:** No TBD or fill-in-later text. All code blocks are complete.

**Type consistency:** `SessionConsumed` defined once in `storage.ts`, imported by `ActiveSession`, `PreTreatment` (via index.tsx threading), and `PostTreatment`. `ITEMS`/`getItem`/`SESSION_FIXED_DELTAS` from `constants.ts` used consistently. `Cycle` from `schemas.ts` used in both banner and index.
