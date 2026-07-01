# Inventory: move supply-rate config to Inventory page; remove order backup field

## Motivation

Two small UX cleanups to the Inventory feature (community flavor for Part A, both flavors for Part B):

1. Supply-rate configuration ("per session" / "target qty" per item) currently lives buried in Settings, disconnected from the Inventory screen where those numbers actually matter (they drive the "~N sess" estimate and the red/amber/green status dot on each item row). Move it to where it's used, and explain it better in context.
2. The "Place order" flow (`OrderSheet`) has a "backup/reserve" stock field per item that's confusing in practice and no longer wanted. Remove it, including the underlying calculation support, so no dead code remains.

## Part A — Move supply-rate config to Inventory page

### Current state

- `SupplyRatesSection` (`lib/features/settings/supply_rates_section.dart`) renders per-item "Per session" / "Target qty" fields for all `section == 'nxstage'` items, with Save/Reset buttons. It reads/writes `consumptionRatesProvider` (Hive-backed overrides).
- It's embedded directly in `community_settings_screen.dart` under a "SUPPLY RATES" header with a one-line description. It is **not** shown in the personal-flavor `settings_screen.dart` — this is a community-only feature, gated implicitly by which settings screen includes it.
- `InventoryScreen` already reads `consumptionRatesProvider` (only when `kCommunity`) to compute stock status/sessions-remaining, but has no way to edit rates from that screen.

### New state

- **Relocate the widget**: move the implementation from `lib/features/settings/supply_rates_section.dart` into a new `lib/features/inventory/supply_rates_sheet.dart`, rebuilt as `SupplyRatesSheet` — a modal bottom sheet following the existing pattern in `inventory_sheets.dart` (`_grab` handle, title, `ConstrainedBox(maxHeight: 380) > ListView(shrinkWrap: true)` for the item rows, action row with Save/Reset). The per-item field logic, controllers, and save/reset behavior against `consumptionRatesProvider` are unchanged.
- **Expanded instructions**: replace the current one-liner with text explaining:
  - **Per session** — how many units get used each treatment session
  - **Target qty** — how many units to keep on hand as a buffer
  - That these two values drive the "~N sess" remaining estimate and the status dot (red/amber/green) shown on each item row on the Inventory page
- **Entry point**: on `InventoryScreen`, add a small icon (`Icons.tune`, styled like the existing edit-pencil in `_Banner._headerRow`) next to the **"NxStage Supplies"** section title only (not "Hospital Prescriptions" — those items have no configurable rates, per `constants.dart`). Tapping it calls `_sheet(const SupplyRatesSheet())`, matching the existing `_openLogEvent`/`_openHistory` pattern. The icon is shown only when `kCommunity` is true, matching today's gating.
- **Settings screen cleanup**: remove the "SUPPLY RATES" header, description text, and `SupplyRatesSection` widget entirely from `community_settings_screen.dart`, along with the now-unused import.
- Delete `lib/features/settings/supply_rates_section.dart` after the move.
- No changes to `consumptionRatesProvider`, `rate_overrides.dart`, or `constants.dart`.

## Part B — Remove backup/reserve field from Place order screen

### Current state

`OrderSheet` (`lib/features/inventory/inventory_sheets.dart`) is a single shared screen used by both personal and community flavors (only the `rates` computation inside it is `kCommunity`-gated). In its "Step 1: Stock count" step, each item has:
- A stock-count field
- A "backup: [-] N [+]" control that marks part of the counted stock as reserve, excluded from the order calculation via `backupQty` passed into `orderBoxes()`

The "Step 2: Order list" step also shows `have X (Y backup)` when backup > 0.

`backupQty` is a parameter on `orderUnits()` and `orderBoxes()` in `stock_calc.dart`, with dedicated test cases in `test/stock_calc_test.dart`.

### New state

Remove the backup/reserve concept entirely — UI and underlying calculation support — since it's shared code, this removes it from both personal and community builds:

- `OrderSheet`: remove the `_backup` field, the backup row UI in the count step, the "(Y backup)" text in the list step, and simplify the instructional text to drop the backup/reserve sentence.
- `stock_calc.dart`: remove the `backupQty` parameter from `orderUnits()` and `orderBoxes()` (and the `working = currentQty - backupQty` clamp logic in `orderUnits`, using `currentQty` directly).
- `test/stock_calc_test.dart`: remove the backup-specific test cases (currently asserting `orderBoxes('SAK-303', 10, backupQty: 8)` etc.); keep the non-backup cases as-is.
- No other callers of `orderUnits`/`orderBoxes` pass `backupQty` (confirmed via repo-wide search), so this is a clean removal with no call-site fallout elsewhere.

## Testing

- Existing widget/unit tests don't cover `SupplyRatesSection`/`community_settings_screen.dart` supply-rate UI directly (confirmed via search), so no test migration needed for Part A beyond ensuring the app still compiles and analyzes cleanly.
- Part B requires updating `test/stock_calc_test.dart` to drop the backup-specific assertions.
- Manual verification: run the app in community flavor, confirm the "NxStage Supplies" tune icon opens the rates sheet, save/reset still works, and Settings no longer shows supply rates. Confirm "Place order" flow (both flavors) no longer shows backup controls and still calculates order quantities correctly.

## Out of scope

- No backend/API changes.
- No changes to `EditOrderSheet` or `ViewOrderSheet` (backup never appeared there).
- No changes to how rates are computed/gated by `kCommunity` — personal flavor still doesn't get the rates sheet, since it doesn't use rate overrides.
