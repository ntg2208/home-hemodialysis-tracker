# Community Supply Rates — Design Spec

**Date:** 2026-06-18
**Scope:** Community flavor only (`kCommunity = true`). Personal flavor unchanged.

## Problem

`constants.dart` hard-codes per-session consumption rates and buffer targets for all NxStage supply items. Other home HD patients using the community app may have different prescriptions (e.g. 2 SAK bags per session for longer treatment, different needle counts). There is no way to customise these without recompiling.

## Goal

A settings UI where community users enter their own consumption rates and buffer targets. The inventory order calculation and stock status indicators use these values instead of the catalogue defaults.

---

## 1. Data Model

### `RateOverride`

```dart
class RateOverride {
  final int? perSession;  // null = keep catalogue default
  final int? targetQty;   // null = keep catalogue default
}
```

Stored in the existing `cacheBoxName` Hive box under key `'supply_rates'` as a `Map<String, dynamic>` (code → `{perSession, targetQty}`). Same box as patient name, dry weight, AI key.

- `RateOverride.perSession: int?` — integer units per session. PAK's 1/10 rate can't be represented as an integer without changing `ItemDef`, so PAK rate is **not overridable in v1** — the hardcoded special-case stays and the field is shown read-only in the UI.
- Needles default = 2/session and are overridable.
- All 1:1 items are overridable.
- Items with no session rate (Sani-Cloth, Sharps, etc.) show only the target field.

### Storage schema

```json
{
  "SAK-303":    { "perSession": 1, "targetQty": 24 },
  "P00012326":  { "perSession": 2, "targetQty": 48 },
  "UK00000830": { "targetQty": 1 }
}
```

Only items the user has changed are stored. Missing = use catalogue default.

---

## 2. Provider

**File:** `lib/features/inventory/consumption_rates_provider.dart`

```dart
// State: Map<String, RateOverride>
// Provider: consumptionRatesProvider (Notifier)
//   - load(): reads cacheBoxName Hive box, key 'supply_rates'
//   - save(Map<String, RateOverride>): writes to Hive, updates state
```

Loaded at widget build time (same pattern as `aiSettingsControllerProvider`). No async delay — Hive box is already open.

---

## 3. Constants layer

**`constants.dart`** — new function:

```dart
ItemDef? resolveItem(String code, Map<String, RateOverride> rates) {
  final base = getItem(code);
  if (base == null) return null;
  final o = rates[code];
  if (o == null) return base;
  return ItemDef(
    code: base.code,
    label: base.label,
    unit: base.unit,
    boxSize: base.boxSize,
    boxLabel: base.boxLabel,
    section: base.section,
    priority: base.priority,
    perSession: o.perSession ?? base.perSession,
    targetQty: o.targetQty ?? base.targetQty,
  );
}
```

`getItem` is unchanged. Existing tests and call sites unaffected.

---

## 4. Stock calc layer

**`stock_calc.dart`** — all six public functions gain an optional parameter:

```dart
Map<String, RateOverride> rates = const {}
```

Each function calls `resolveItem(code, rates)` instead of `getItem(code)`.

PAK (`PAK-001`) and needle (`P00012326`) special-case branches in `consumedUnits` and `sessionsRemaining` are guarded: if `rates[code]?.perSession != null`, skip the special-case and use `perSession` directly. This allows override while keeping the default behaviour for unoverridden items.

**Affected functions:** `sessionsRemaining`, `stockStatus`, `consumedUnits`, `orderUnits`, `orderBoxes`, `needsOrdering`, `sortStock`.

All existing call sites compile unchanged (rates defaults to `{}`). All 17 existing tests pass unchanged.

---

## 5. Inventory widgets

**`inventory_screen.dart`** — watches `consumptionRatesProvider`, passes rates to `stockStatus`, `sessionsRemaining`, `needsOrdering`, `sortStock`.

**`inventory_sheets.dart`** — watches `consumptionRatesProvider`, passes rates to `orderBoxes`.

Both are already `ConsumerWidget` / `ConsumerStatefulWidget`.

---

## 6. Settings UI

**New file:** `lib/features/settings/supply_rates_section.dart`

`SupplyRatesSection` is a `ConsumerStatefulWidget`. Added to `CommunitySettingsScreen` under a new `SUPPLY RATES` section header, between `DRY WEIGHT` and `AI ASSISTANT`.

### Layout per item (NxStage items only, hospital excluded)

```
SAK Dialysate
  Per session: [  1  ]  bags     Target qty: [  24  ]  bags
Buttonhole Needles
  Per session: [  2  ]  needles  Target qty: [  48  ]  needles
PAK
  Per session: 0.1 (fixed)       Target qty: [   3  ]  units
Sani-Cloth AF
  (no rate)                      Target qty: [   1  ]  box
```

- Numeric keyboard for all inputs.
- Pre-filled from effective defaults (catalogue values).
- PAK rate shown as read-only text (not editable in v1).
- Items with `perSession == null` in catalogue show only the target field.

### Save behaviour

Single **Save rates** button at the bottom of the section. On tap:
- Parse all fields. Non-numeric or ≤ 0 values fall back silently to catalogue default (field is not saved in the override map).
- Write to Hive via `consumptionRatesProvider.notifier.save(overrides)`.
- Show snackbar: "Supply rates saved".
- No per-row save or live preview.

### Reset

A small **Reset to defaults** text button clears the Hive entry and reloads fields from catalogue defaults.

---

## 7. Error handling

- Hive read failure on load → fall back to empty overrides (catalogue defaults used).
- All parse errors on save → silently drop that field (use catalogue default), still save the rest.
- No network involved — no retry logic needed.

---

## 8. Testing

New test file: `test/consumption_rates_test.dart`

| Test | What it checks |
|------|----------------|
| `resolveItem` returns base when no override | catalogue default unchanged |
| `resolveItem` overrides `perSession` | override takes effect |
| `resolveItem` overrides `targetQty` | override takes effect |
| `resolveItem` partial override | only the set field changes |
| `consumedUnits` with rate override for SAK | uses override perSession |
| `consumedUnits` with rate override for needles | override replaces hardcoded ×2 |
| `orderBoxes` with target override | uses override targetQty as target |
| `sessionsRemaining` with rate override | override replaces hardcoded logic for needles |

Existing 17 tests in `stock_calc_test.dart` must continue to pass unmodified.

---

## 9. Out of scope (v1)

- Personal flavor — rates stay hardcoded.
- PAK rate override — rate is fixed at 1/10 by NxStage machine design.
- Adding/removing items from the catalogue — item list is still hardcoded.
- Per-item enable/disable toggle.
- Export/import of rate profiles.
