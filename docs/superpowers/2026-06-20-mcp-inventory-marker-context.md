# Cloud MCP — Inventory & Marker Domain Context (+ get_orders)

<!-- combined spec + implementation plan -->

Date: 2026-06-20
Branch: `feat/mcp-inventory-marker-context`
Related: `2026-06-19-mcp-cloud-read-tools.md` (the read-tools foundation this extends)

## Summary

The cloud MCP read tools (`/api/mcp` on `homehd-api`) currently return **raw codes with no
meaning**. `get_inventory` returns `{ stock: { "P00012326": 52, ... } }` and `get_blood_markers`
returns rows keyed by opaque marker IDs (`phosphate`, `haemoglobin`). An external MCP client
(Claude Code, Gemini CLI) cannot tell:

- what `P00012326` is (Buttonhole Needles), its unit, or box size,
- how many sessions of supply a quantity represents (the per-session burn rate),
- what blood-marker IDs are valid or what they measure.

All of this domain knowledge lives **only in the Flutter client** (`constants.dart`,
`stock_calc.dart`). This work makes the cloud MCP surface **self-describing**: clients can
interpret codes, read units/box sizes, and get reliable "sessions of supply remaining" without
hallucinating the math. It also adds a fifth tool, `get_orders`, for the recent order/delivery list.

## Goals

1. `get_inventory` output is self-describing — each item carries label, unit, box size,
   per-session rate, target, **server-computed `sessions_remaining` and `status`**.
2. Supply math is **reliable** (computed server-side, matching the app), not left to the LLM.
3. Blood-marker queries are discoverable — the client knows every valid marker ID and its panel.
4. New `get_orders` tool returns the recent order/delivery history (default: last 3 months) plus
   the current open order.
5. The MCP server `instructions` field gives the narrative consumption model.

## Non-goals

- Syncing on-device rate-overrides to the server (see Constraints). Out of scope.
- Any write/mutation tools — this stays a read-only surface.
- Marker math. Each row already carries `unit`/`ref_low`/`ref_high`; markers need a glossary,
  not computation.
- `health://` Resources, the Skills layer — still deferred (per the prior read-tools spec).

## Constraints discovered

- **Rate-overrides are client-only.** `consumptionRatesProvider` persists `supply_rates` to
  on-device Hive (`cacheBoxName`), never Firestore. The Cloud Run server therefore cannot see a
  patient's custom rates and computes from **static catalogue defaults**. The `instructions`
  field states this explicitly. (Override-sync is a possible future enhancement, not this work.)
- **Authoritative math = `stock_calc.dart`, not `sessionFixedDeltas`.** `sessionFixedDeltas`
  (SAK, cartridge, saline, chlorine strip — 1 each) is only the write-path auto-deduction and
  omits needles (2/session), the on/off pack, and PAK lifespan. The numbers the **app actually
  displays** come from `sessionsRemaining()` / `stockStatus()`. We port those verbatim so the
  MCP agrees with the inventory screen. `sessionFixedDeltas` is intentionally NOT documented to
  the client — surfacing it would cause wrong/double-counted rates.
- **One active cycle.** Orders live on the single `inventory_config/cycle` doc (overwritten each
  cycle). Past orders are recorded as `inventory_events` with `type == 'delivery'`.

## Current state (code references)

| Concern | Location |
|---|---|
| MCP tool registry | `api/src/mcp/server.ts` (4 tools, no metadata) |
| Inventory reader | `api/src/lib/reads/inventoryReads.ts` (`getInventory`, `averagePakLifespan`) |
| REST deliveries (inline query to extract) | `api/src/handlers/inventory.ts` `.get('/deliveries')` |
| Item catalogue (source to port) | `flutter/lib/features/inventory/constants.dart` |
| Supply math (source to port) | `flutter/lib/features/inventory/stock_calc.dart` |
| Marker IDs / schema | `api/src/data/blood_tests.json`, `api/src/schemas/bloodTests.ts` |

## Design

### 1. New module: `api/src/lib/inventoryCatalogue.ts`

A TypeScript port of the Flutter catalogue + supply math — the API's own source of truth,
consistent with the existing "port of frontend TS" lineage in the Dart files.

**Catalogue** (mirror of `constants.dart` `items`), each entry:
`{ code, label, unit, boxSize, boxLabel, perSession, targetQty, section, priority }`.

```
SAK-303      SAK Dialysate      bag        box  size 2   perSession 1  target 24  nxstage
CAR-172-C    Cartridges         cartridge  box  size 6   perSession 1  target 24  nxstage
UK00000880   Saline 1L          bag        box  size 10  perSession 1  target 24  nxstage
PAK-001      PAK                unit       piece size 1  perSession -  target 3   nxstage
P00012326    Buttonhole Needles needle     box  size 50  perSession -  target 48  nxstage
UK00000774   On/Off Pack        pack       box  size 60  perSession 1  target 24  nxstage
F00010983    Chlorine Strips    strip      pack size 100 perSession 1  target 24  nxstage
UK00000830   Sani-Cloth AF      box        box  size 1   perSession -  target 1   nxstage
1990134      Spirigel Hand Gel  unit       piece size 1  perSession -  target 1   nxstage
UK00000832   Sharps Bin         unit       piece size 1  perSession -  target 1   nxstage
UK00000172   Micropore Tape     roll       box  size 12  perSession -  target 4   nxstage
heparin      Heparin            unit       unit size 1   perSession -  target 8   hospital
epo          EPO                unit       unit size 1   perSession -  target 4   hospital
```

**Math** (port `stock_calc.dart` verbatim, defaults only — no `rates` param):

- `sessionsRemaining(code, qty)`:
  - `PAK-001` → `qty * 10`
  - `P00012326` (needles) → `floor(qty / 2)`
  - hospital section or `perSession == null` → `null`
  - else → `floor(qty / perSession)`
- `stockStatus(code, qty)` → `'red' | 'amber' | 'green'`:
  - hospital: `qty <= 0` red, `qty <= 1` amber, else green
  - nxstage with sessions-remaining `sr`: `sr < 8` red, `sr < 16` amber, else green
    (8 = ~2 weeks, 16 = ~4 weeks, at ~4 sessions/week)
  - nxstage with `sr == null`: `qty <= 0` red, `qty <= 1` amber, else green
- `consumedUnits(code, sessions)` (for box math reuse): PAK `ceil(sessions/10)`,
  needles `sessions * 2`, else `sessions * perSession` (0 if none).
- helpers: `getItem(code)`, `boxesFor(code, qty)` → `ceil(qty / boxSize)`.

### 2. Enrich `get_inventory` output

`getInventory()` in `inventoryReads.ts` keeps reading the same Firestore data but maps the raw
`stock: { code: qty }` into an enriched array. Existing `cycle`, `pak_installed_at`,
`pak_sessions`, `pak_avg_sessions` are unchanged.

```jsonc
{
  "items": [
    {
      "code": "P00012326", "label": "Buttonhole Needles", "qty": 52,
      "unit": "needle", "box_size": 50, "box_label": "box",
      "per_session": 2, "target_qty": 48, "section": "nxstage",
      "sessions_remaining": 26, "status": "green"
    }
    // ...one per stock doc; codes not in the catalogue passed through with nulls + status from qty
  ],
  "cycle": { /* unchanged */ },
  "pak_installed_at": "...", "pak_sessions": 7, "pak_avg_sessions": 34.5
}
```

Note `per_session` is reported as the **effective** rate the math uses (needles → 2,
PAK → null but lifespan ~10 noted in instructions), so the client can reconcile
`sessions_remaining`. Facts live in structured output (reliable) because `instructions` is
best-effort across clients.

### 3. New tool: `get_orders`

Recent order/delivery list. Extract the inline `/deliveries` query into a shared reader.

- **New reader** `getDeliveries({ from?, to? })` in `inventoryReads.ts`: reads
  `inventory_events` where `type == 'delivery'`, sorted newest-first, filtered by timestamp.
  REST `.get('/deliveries')` is refactored to call it (one code path).
- **New reader** `getOrders({ from?, to? })`: returns `{ current_order, history }`.
  - `current_order`: from `inventory_config/cycle` — `null` unless `order_placed_at` set;
    else `{ call_date, delivery_date, placed_at, applied, items[] }` where `applied` =
    `delivery_applied_at != null`.
  - `history`: delivered orders from `getDeliveries`, newest-first.
  - All item maps enriched to `{ code, label, qty, boxes }` via the catalogue.

```jsonc
{
  "current_order": {
    "call_date": "2026-06-15", "delivery_date": "2026-06-22",
    "placed_at": "2026-06-15T09:00:00Z", "applied": false,
    "items": [ { "code": "SAK-303", "label": "SAK Dialysate", "qty": 24, "boxes": 12 } ]
  },
  "history": [
    { "date": "2026-05-25T...", "note": "delivery applied",
      "items": [ { "code": "CAR-172-C", "label": "Cartridges", "qty": 24, "boxes": 4 } ] }
  ]
}
```

**Tool registration** in `server.ts`:
- name `get_orders`, description: "Recent supply orders/deliveries. `history` = fulfilled
  deliveries (newest first); `current_order` = the one open order for this cycle (null if none
  placed). Defaults to the last 3 months."
- input: `from` (YYYY-MM-DD, default = today − 3 months), `to` (YYYY-MM-DD, optional),
  `limit` (positive int, optional — cap history to newest N, overrides date window).

### 4. Marker glossary (descriptions only)

Enrich the `marker` arg description in `bloodArgs` with the **full canonical ID list grouped by
panel**, keeping the existing symptom map. No output-shape change — rows already carry
`unit`/`ref_low`/`ref_high`.

| Panel | Marker IDs |
|---|---|
| FBC (full blood count) | `haemoglobin`, `haematocrit`, `rbc`, `wbc`, `platelets`, `mcv`, `mch`, `mchc`, `rdw`, `mpv`, `neutrophils`, `lymphocytes`, `monocytes`, `eosinophils`, `basophils`, `nucleated_rbc`, `reticulocyte_count_lnw`, `reticulocytes_abs_lnw` |
| U&E / renal | `sodium`, `potassium`, `chloride`, `bicarbonate`, `urea`, `creatinine`, `egfr`, `aki_alert` |
| Bone / mineral | `calcium`, `adjusted_calcium`, `phosphate`, `parathyroid_hormone`, `vitamin_d`, `alkaline_phosphatase` |
| Liver (LFT) | `albumin`, `globulin`, `total_protein`, `bilirubin`, `alt` |
| Haematinics / iron | `iron`, `ferritin`, `transferrin`, `transferrin_saturation`, `holotranscobalamin` (active B12), `folic_acid` |
| Inflammation / glycaemic | `crp`, `hba1c` |
| Virology / screening | `hbv_surface_ab`, `hbv_surface_ag`, `hcv_ab`, `hiv_1_2_ab_ag`, `mrsa_screen`, `histo_nwlp` |

Symptom map (kept): itching → `phosphate`,`calcium`; fatigue → `haemoglobin`,`ferritin`;
cramps → `potassium`,`calcium`; swelling → `albumin`,`sodium`.

Because the description string would get long, the panel list may be factored into a
`MARKER_GLOSSARY` constant in `server.ts` (or a small `markers.ts`) and interpolated.

### 5. Server `instructions` field

Set on the `McpServer` constructor (`server.ts`). Narrative layer only — load-bearing facts are
in the tool outputs. Content:

- Per-session consumption model: each session ≈ 1 SAK dialysate, 1 cartridge, 1 saline,
  1 on/off pack, 1 chlorine strip, **2 needles**; a PAK lasts ~10 sessions.
- `sessions_remaining` = full sessions the current stock covers; `status` thresholds
  (red < 8 ≈ 2 weeks, amber < 16 ≈ 4 weeks, green otherwise, at ~4 sessions/week).
- Rates are standard defaults; if the patient customised rates in the app those live on-device
  and are not reflected here.
- Hospital-section items (heparin, EPO) have no per-session rate; status is qty-based.
- Pointer to the marker glossary in `get_blood_markers`.

## Testing

- **Catalogue parity** (`inventoryCatalogue.test.ts`): every code in the Flutter `constants.dart`
  is present with matching fields; spot-check box sizes / perSession / targetQty.
- **Supply-math golden** (`inventoryCatalogue.test.ts`): for a fixed stock map, asserted
  `sessions_remaining` + `status` per item — values mirror `stock_calc.dart` (needles 2/session,
  PAK ×10, thresholds 8/16, hospital qty-based, unknown-code passthrough).
- **`getOrders` reader** (`inventoryReads.test.ts`): given fake cycle + delivery events →
  correct `current_order` (null when no `order_placed_at`; `applied` reflects
  `delivery_applied_at`) and date-windowed, newest-first, enriched `history`; `limit` caps.
- **`getInventory` enrichment** (`inventoryReads.test.ts`): raw stock → enriched items shape.
- **MCP route** (`mcp/route.test.ts` / `server.test.ts`): `tools/list` returns 5 tools;
  `get_orders` callable; 401 without auth still holds.
- Run `npm test` in `api/` — all existing (138+) tests stay green.

## Implementation plan (TDD, ordered)

1. **Catalogue module + math** — write `inventoryCatalogue.test.ts` (parity + golden) →
   implement `inventoryCatalogue.ts` (port `constants.dart` items + `stock_calc.dart` math).
2. **Enrich `get_inventory`** — test the enriched shape → map raw stock through the catalogue in
   `inventoryReads.ts`; keep `cycle`/PAK fields. Update `get_inventory` tool description.
3. **`getDeliveries` + `getOrders` readers** — test → implement in `inventoryReads.ts`; refactor
   REST `.get('/deliveries')` to call `getDeliveries`.
4. **Register `get_orders` tool** — `server.ts` registration + input schema (`from` default
   −3 months, `to`, `limit`); route test for 5 tools.
5. **Marker glossary** — add `MARKER_GLOSSARY` panel list; interpolate into `bloodArgs.marker`
   description.
6. **Server `instructions`** — add the narrative string to the `McpServer` constructor.
7. **Verify + deploy** — `npm test` green; deploy `homehd-api`; live-check against
   `https://homehd.web.app/api/mcp` (401 unauth, 5 tools listed, `get_inventory` enriched,
   `get_orders` returns history). Update the [[Home HD - AI Command Control]] vault note with a
   dated breadcrumb.

## Verification

- `npm test` in `api/` — all green, new tests included.
- Live: `claude mcp add --transport http homehd https://homehd.web.app/api/mcp --header
  "Authorization: Bearer <MAIN_API_KEY>"`; confirm 5 tools, enriched inventory, `get_orders`.
