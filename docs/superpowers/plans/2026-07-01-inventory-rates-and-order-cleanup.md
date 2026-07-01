# Inventory Supply Rates Move + Order Backup Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the per-item supply-rate config (per-session usage, target qty) from Settings onto the Inventory page as a bottom sheet triggered by an icon on the NxStage Supplies section, with expanded in-context instructions; and remove the backup/reserve stock field from the shared "Place order" flow entirely (UI + calculation + tests), affecting both personal and community flavors.

**Architecture:** Two independent, additive-then-subtractive changes to the existing Flutter (Riverpod) app. Part A relocates a self-contained `ConsumerStatefulWidget` from `lib/features/settings/` to a new file in `lib/features/inventory/`, rebuilt as a modal bottom sheet matching the existing sheet pattern in that folder, then wires a trigger and deletes the old Settings entry point. Part B deletes a parameter (`backupQty`) threaded through `stock_calc.dart` and the `OrderSheet` bottom sheet, plus its dedicated tests.

**Tech Stack:** Flutter, flutter_riverpod, Hive (local persistence for rate overrides), flutter_test.

**Reference design doc:** `docs/superpowers/2026-07-01-inventory-rates-and-order-cleanup-design.md`

## Global Constraints

- Repo root (git): `/Users/ntg/Documents/Personal_Projects/treatment_tracker`. The Flutter package lives in the `flutter/` subdirectory — `cd flutter` before running any `flutter`/`dart` command. All file paths below are relative to `flutter/`.
- Package name is `home_hd` (see `flutter/pubspec.yaml`); import Dart packages as `package:home_hd/...`.
- Two build flavors share this codebase, gated by the compile-time constant `kCommunity` in `lib/flavor.dart` (`String.fromEnvironment('FLAVOR') == 'community'`). Plain `flutter test` always runs with `kCommunity == false` (confirmed by `test/flavor_test.dart`) — there is no test-time override, so any behavior gated on `kCommunity` can only be exercised via static analysis / manual verification, not automated tests, in this plan.
- UI conventions to follow: theme tokens via `context.hd` (`lib/app/theme.dart`); Inventory bottom sheets follow the pattern in `lib/features/inventory/inventory_sheets.dart` — `Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [grab handle, title, ..., ConstrainedBox(maxHeight: ...) > ListView(shrinkWrap: true) for long lists, action row])`, opened via the private `_sheet()` helper on `_InventoryScreenState` which wraps content in `_SheetShell`.
- No backend/API changes anywhere in this plan.
- After each task: `flutter analyze` must report `No issues found!` for touched files, and relevant tests must pass, before committing.

---

### Task 1: Remove backup/reserve field from the Place order flow

**Files:**
- Modify: `lib/features/inventory/stock_calc.dart:74-104` (`orderUnits`, `orderBoxes`)
- Modify: `lib/features/inventory/inventory_sheets.dart` (`OrderSheet`/`_OrderSheetState`, lines ~227-464)
- Test: `test/stock_calc_test.dart:52-85` (`orderBoxes` group)

**Interfaces:**
- Produces: `orderUnits(String code, int currentQty, {int? deliverySessions, Map<String, RateOverride> rates})` and `orderBoxes(String code, int currentQty, {int? deliverySessions, Map<String, RateOverride> rates})` — same names/return types as before, `backupQty` parameter removed. The only caller is `_submitCount()` inside `OrderSheet`.

- [ ] **Step 1: Run the existing test suite to confirm a clean baseline**

Run: `cd flutter && flutter test test/stock_calc_test.dart`
Expected: All tests PASS, including the `orderBoxes` group (6 tests).

- [ ] **Step 2: Update `test/stock_calc_test.dart` to drop backup-specific assertions**

Replace:
```dart
    test('excludes backup qty from working stock', () {
      // working = 10-8 = 2, target = 24, order = ceil((24-2)/2) = 11
      expect(orderBoxes('SAK-303', 10, backupQty: 8), 11);
      expect(orderBoxes('SAK-303', 10, backupQty: 0), 7);
    });

    test('delivery sessions: normal order (7-day lead = 4 sessions + 16 buffer = 20)', () {
      // Need 20 bags, have 10 working → order 10 → ceil(10/2) = 5 boxes
      expect(orderBoxes('SAK-303', 10, deliverySessions: 20), 5);
    });

    test('delivery sessions: early order (3-week lead = 12 sessions + 16 buffer = 28)', () {
      // Need 28 bags, have 10 working → order 18 → ceil(18/2) = 9 boxes
      expect(orderBoxes('SAK-303', 10, deliverySessions: 28), 9);
    });

    test('delivery sessions with backup: excludes backup from working stock', () {
      // 20 total, 8 backup → working = 12; need 28; order 16 → ceil(16/2) = 8 boxes
      expect(orderBoxes('SAK-303', 20, backupQty: 8, deliverySessions: 28), 8);
    });
```

With:
```dart
    test('delivery sessions: normal order (7-day lead = 4 sessions + 16 buffer = 20)', () {
      // Need 20 bags, have 10 working → order 10 → ceil(10/2) = 5 boxes
      expect(orderBoxes('SAK-303', 10, deliverySessions: 20), 5);
    });

    test('delivery sessions: early order (3-week lead = 12 sessions + 16 buffer = 28)', () {
      // Need 28 bags, have 10 working → order 18 → ceil(18/2) = 9 boxes
      expect(orderBoxes('SAK-303', 10, deliverySessions: 28), 9);
    });
```

This removes the two backup-only tests and drops the now-obsolete `backupQty:` argument from the two delivery-session tests (which test unrelated behavior).

- [ ] **Step 3: Run tests again to confirm the trimmed suite is still green**

Run: `cd flutter && flutter test test/stock_calc_test.dart`
Expected: PASS; the `orderBoxes` group now has 4 tests instead of 6.

- [ ] **Step 4: Remove `backupQty` from `orderUnits` and `orderBoxes` in `stock_calc.dart`**

Replace:
```dart
int orderUnits(String code, int currentQty,
    {int backupQty = 0,
    int? deliverySessions,
    Map<String, RateOverride> rates = const {}}) {
  final item = resolveItem(code, rates);
  if (item == null || item.section == 'hospital') return 0;
  final working = (currentQty - backupQty).clamp(0, currentQty);
  int target;
  if (deliverySessions != null) {
    final consumed = consumedUnits(code, deliverySessions, rates: rates);
    target = consumed > 0 ? consumed : item.targetQty;
  } else {
    target = item.targetQty;
  }
  final n = target - working;
  return n < 0 ? 0 : n;
}

int orderBoxes(String code, int currentQty,
    {int backupQty = 0,
    int? deliverySessions,
    Map<String, RateOverride> rates = const {}}) {
  final item = resolveItem(code, rates) ?? getItem(code);
  if (item == null) return 0;
  return (orderUnits(code, currentQty,
              backupQty: backupQty,
              deliverySessions: deliverySessions,
              rates: rates) /
          item.boxSize)
      .ceil();
}
```

With:
```dart
int orderUnits(String code, int currentQty,
    {int? deliverySessions, Map<String, RateOverride> rates = const {}}) {
  final item = resolveItem(code, rates);
  if (item == null || item.section == 'hospital') return 0;
  int target;
  if (deliverySessions != null) {
    final consumed = consumedUnits(code, deliverySessions, rates: rates);
    target = consumed > 0 ? consumed : item.targetQty;
  } else {
    target = item.targetQty;
  }
  final n = target - currentQty;
  return n < 0 ? 0 : n;
}

int orderBoxes(String code, int currentQty,
    {int? deliverySessions, Map<String, RateOverride> rates = const {}}) {
  final item = resolveItem(code, rates) ?? getItem(code);
  if (item == null) return 0;
  return (orderUnits(code, currentQty,
              deliverySessions: deliverySessions, rates: rates) /
          item.boxSize)
      .ceil();
}
```

- [ ] **Step 5: Confirm the expected compile break at the one remaining call site**

Run: `cd flutter && flutter analyze lib/features/inventory/inventory_sheets.dart`
Expected: An error on the `orderBoxes(...)` call inside `_submitCount()` — `The named parameter 'backupQty' isn't defined`. This confirms the next step is necessary; it's fixed in Step 6.

- [ ] **Step 6a: Remove the `_backup` field from `_OrderSheetState`**

Replace:
```dart
class _OrderSheetState extends ConsumerState<OrderSheet> {
  _OrderStep _step = _OrderStep.count;
  late final Map<String, int> _counts; // physical stock count per nxstage item
  final Map<String, int> _backup = {}; // backup/reserve qty per item (excluded from order)
  final Map<String, int> _boxes = {}; // boxes to order per item
```

With:
```dart
class _OrderSheetState extends ConsumerState<OrderSheet> {
  _OrderStep _step = _OrderStep.count;
  late final Map<String, int> _counts; // physical stock count per nxstage item
  final Map<String, int> _boxes = {}; // boxes to order per item
```

- [ ] **Step 6b: Remove the `backupQty:` argument in `_submitCount()`**

Replace:
```dart
      for (final i in _nxstage) {
        final b = orderBoxes(i.code, _counts[i.code] ?? 0,
            backupQty: _backup[i.code] ?? 0, deliverySessions: ds, rates: rates);
        if (b > 0) _boxes[i.code] = b;
      }
```

With:
```dart
      for (final i in _nxstage) {
        final b = orderBoxes(i.code, _counts[i.code] ?? 0,
            deliverySessions: ds, rates: rates);
        if (b > 0) _boxes[i.code] = b;
      }
```

- [ ] **Step 6c: Simplify `_countStep` — drop the backup instructions sentence and the backup control row**

Replace:
```dart
  Widget _countStep(HdTokens t) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Count what you physically have. If ordering early, enter backup/reserve stock separately — it is excluded from the order calculation.',
            style: TextStyle(fontSize: 12, color: t.textMuted),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: ListView(
              shrinkWrap: true,
              children: _nxstage.map((i) {
                final backup = _backup[i.code] ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(i.label,
                                style: TextStyle(color: t.textPrimary, fontSize: 14))),
                        Text('${i.unit}s ',
                            style: TextStyle(color: t.textMuted, fontSize: 11)),
                        SizedBox(
                          width: 64,
                          child: TextFormField(
                            initialValue: '${_counts[i.code] ?? 0}',
                            textAlign: TextAlign.right,
                            keyboardType: TextInputType.number,
                            onChanged: (raw) {
                              final n = int.tryParse(raw);
                              if (n != null && n >= 0) _counts[i.code] = n;
                            },
                          ),
                        ),
                      ]),
                      Row(children: [
                        const SizedBox(width: 12),
                        Text('backup: ',
                            style: TextStyle(color: t.textMuted, fontSize: 11)),
                        _roundBtn(t, Icons.remove,
                            backup <= 0
                                ? null
                                : () => setState(() => _backup[i.code] = backup - 1)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('$backup',
                              style: TextStyle(color: t.textMuted, fontSize: 12)),
                        ),
                        _roundBtn(t, Icons.add,
                            backup >= (_counts[i.code] ?? 0)
                                ? null
                                : () => setState(
                                    () => _backup[i.code] = backup + 1)),
                      ]),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
              onPressed: _saving ? null : _submitCount,
              child: Text(_saving ? 'Saving…' : 'Next: calculate order →')),
        ],
      );
```

With:
```dart
  Widget _countStep(HdTokens t) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Count what you physically have.',
            style: TextStyle(fontSize: 12, color: t.textMuted),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: ListView(
              shrinkWrap: true,
              children: _nxstage.map((i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                        child: Text(i.label,
                            style: TextStyle(color: t.textPrimary, fontSize: 14))),
                    Text('${i.unit}s ',
                        style: TextStyle(color: t.textMuted, fontSize: 11)),
                    SizedBox(
                      width: 64,
                      child: TextFormField(
                        initialValue: '${_counts[i.code] ?? 0}',
                        textAlign: TextAlign.right,
                        keyboardType: TextInputType.number,
                        onChanged: (raw) {
                          final n = int.tryParse(raw);
                          if (n != null && n >= 0) _counts[i.code] = n;
                        },
                      ),
                    ),
                  ]),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
              onPressed: _saving ? null : _submitCount,
              child: Text(_saving ? 'Saving…' : 'Next: calculate order →')),
        ],
      );
```

- [ ] **Step 6d: Simplify the "have X (Y backup)" text in `_listStep`**

Replace:
```dart
                          Text(
                            (_backup[i.code] ?? 0) > 0
                                ? 'have ${_counts[i.code] ?? 0} (${_backup[i.code]} backup)'
                                : 'have ${_counts[i.code] ?? 0}',
                            style: TextStyle(color: t.textMuted, fontSize: 11),
                          ),
```

With:
```dart
                          Text(
                            'have ${_counts[i.code] ?? 0}',
                            style: TextStyle(color: t.textMuted, fontSize: 11),
                          ),
```

- [ ] **Step 7: Verify static analysis is clean**

Run: `cd flutter && flutter analyze lib/features/inventory/inventory_sheets.dart lib/features/inventory/stock_calc.dart`
Expected: `No issues found!`

- [ ] **Step 8: Run the affected test files**

Run: `cd flutter && flutter test test/stock_calc_test.dart test/render_smoke_test.dart test/consumption_rates_test.dart`
Expected: All PASS (the `OrderSheet (count step)` smoke test in `render_smoke_test.dart` only checks for `'Step 1: Stock count'` and no exceptions, so it's unaffected by the backup removal).

- [ ] **Step 9: Commit**

```bash
cd flutter && git add lib/features/inventory/stock_calc.dart lib/features/inventory/inventory_sheets.dart test/stock_calc_test.dart
git commit -m "$(cat <<'EOF'
Remove backup/reserve stock field from Place order flow

Simplifies the order-count step (shared by personal and community
flavors) and drops the now-unused backupQty parameter from the
underlying order-quantity calculation, plus its dedicated tests.
EOF
)"
```

---

### Task 2: Create `SupplyRatesSheet` in the Inventory feature

**Files:**
- Create: `lib/features/inventory/supply_rates_sheet.dart`
- Test: `test/render_smoke_test.dart` (add to existing `group('inventory sheets render', ...)`)

**Interfaces:**
- Produces: `SupplyRatesSheet` — a `ConsumerStatefulWidget` with only a `key` constructor param, buildable standalone (e.g. inside `_app(sheet)` or via `_sheet()`), returning a `Column` (not a `Scaffold`) matching the shape of `OrderSheet`/`DeliverySheet`/etc. in `inventory_sheets.dart`. Consumed by Task 3.
- Consumes: `consumptionRatesProvider` (`lib/features/inventory/consumption_rates_provider.dart`), `items`/`ItemDef` (`lib/features/inventory/constants.dart`), `RateOverride` (`lib/features/inventory/rate_overrides.dart`), `HdTokens`/`context.hd` (`lib/app/theme.dart`).

- [ ] **Step 1: Create `lib/features/inventory/supply_rates_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'constants.dart';
import 'consumption_rates_provider.dart';
import 'rate_overrides.dart';

Widget _grab(HdTokens t) => Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: t.textMuted, borderRadius: BorderRadius.circular(2)),
      ),
    );

class SupplyRatesSheet extends ConsumerStatefulWidget {
  const SupplyRatesSheet({super.key});
  @override
  ConsumerState<SupplyRatesSheet> createState() => _SupplyRatesSheetState();
}

class _SupplyRatesSheetState extends ConsumerState<SupplyRatesSheet> {
  static final _nxstage = items.where((i) => i.section == 'nxstage').toList();

  final Map<String, TextEditingController> _rateCtrl = {};
  final Map<String, TextEditingController> _targetCtrl = {};
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final overrides = ref.read(consumptionRatesProvider);
    for (final item in _nxstage) {
      final o = overrides[item.code];
      final effectiveRate = _effectiveDefaultRate(item);
      _rateCtrl[item.code] = TextEditingController(
        text: o?.perSession != null
            ? '${o!.perSession}'
            : (effectiveRate != null ? '$effectiveRate' : ''),
      );
      final effectiveTarget = o?.targetQty ?? item.targetQty;
      _targetCtrl[item.code] =
          TextEditingController(text: '$effectiveTarget');
    }
  }

  // Returns the display default per-session rate.
  // PAK returns null (shown as read-only "0.1"). Needles returns 2.
  // Items with no session rate return null (no rate field shown).
  int? _effectiveDefaultRate(ItemDef item) {
    if (item.code == 'PAK-001') return null;
    if (item.code == 'P00012326') return 2;
    return item.perSession;
  }

  @override
  void dispose() {
    for (final c in _rateCtrl.values) {
      c.dispose();
    }
    for (final c in _targetCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final overrides = <String, RateOverride>{};
    for (final item in _nxstage) {
      final rateText = _rateCtrl[item.code]?.text.trim() ?? '';
      final targetText = _targetCtrl[item.code]?.text.trim() ?? '';
      final rate = int.tryParse(rateText);
      final target = int.tryParse(targetText);
      final validRate = (rate != null && rate > 0) ? rate : null;
      final validTarget = (target != null && target > 0) ? target : null;
      // Only store fields that differ from catalogue defaults — so future
      // catalogue corrections still reach users who haven't customised them.
      final defaultRate = _effectiveDefaultRate(item);
      final rateChanged = item.code != 'PAK-001' &&
          validRate != null &&
          validRate != defaultRate;
      final targetChanged = validTarget != null && validTarget != item.targetQty;
      if (rateChanged || targetChanged) {
        overrides[item.code] = RateOverride(
          perSession: rateChanged ? validRate : null,
          targetQty: targetChanged ? validTarget : null,
        );
      }
    }
    await ref.read(consumptionRatesProvider.notifier).save(overrides);
    setState(() => _saved = true);
  }

  Future<void> _reset() async {
    await ref.read(consumptionRatesProvider.notifier).reset();
    for (final item in _nxstage) {
      final effectiveRate = _effectiveDefaultRate(item);
      _rateCtrl[item.code]?.text =
          effectiveRate != null ? '$effectiveRate' : '';
      _targetCtrl[item.code]?.text = '${item.targetQty}';
    }
    setState(() => _saved = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rates reset to defaults')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grab(t),
        Text(
          'Supply rates',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          'Per session is how many units you use each treatment. Target qty is '
          'how many to keep on hand as a buffer. Together they drive the "~N '
          'sess" estimate and the status dot (red/amber/green) shown next to '
          'each item on the Inventory page.',
          style: TextStyle(fontSize: 12, color: t.textMuted),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: ListView(
            shrinkWrap: true,
            children: [for (final item in _nxstage) _itemRow(item)],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _save,
                child: Text(_saved ? 'Saved ✓' : 'Save rates'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _reset,
              child: const Text('Reset to defaults'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _itemRow(ItemDef item) {
    final isPak = item.code == 'PAK-001';
    final hasRate = isPak || _effectiveDefaultRate(item) != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Row(
            children: [
              if (hasRate) ...[
                Expanded(
                  child: isPak
                      ? InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Per session',
                            isDense: true,
                          ),
                          child: const Text('0.1 (fixed)',
                              style: TextStyle(fontSize: 14)),
                        )
                      : TextField(
                          controller: _rateCtrl[item.code],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Per session',
                            hintText: '${_effectiveDefaultRate(item)}',
                            isDense: true,
                            suffixText: item.unit,
                          ),
                          onChanged: (_) => setState(() => _saved = false),
                        ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: _targetCtrl[item.code],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Target qty',
                    hintText: '${item.targetQty}',
                    isDense: true,
                    suffixText: item.unit,
                  ),
                  onChanged: (_) => setState(() => _saved = false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run static analysis on the new file**

Run: `cd flutter && flutter analyze lib/features/inventory/supply_rates_sheet.dart`
Expected: `No issues found!`

- [ ] **Step 3: Add a render-smoke test alongside the other inventory sheets**

In `test/render_smoke_test.dart`, add the import (alphabetically after the existing `inventory_sheets.dart` import):
```dart
import 'package:home_hd/features/inventory/inventory_sheets.dart';
import 'package:home_hd/features/inventory/supply_rates_sheet.dart';
```

Then add a test inside `group('inventory sheets render', ...)`, immediately after the `ViewOrderSheet` test:
```dart
    testWidgets('ViewOrderSheet', (tester) async {
      await pumpSheet(tester,
          ViewOrderSheet(cycle: cycle, onEdit: () {}, onEarlyDelivery: () {}));
      expect(find.text('Placed order'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SupplyRatesSheet', (tester) async {
      await pumpSheet(tester, const SupplyRatesSheet());
      expect(find.text('Supply rates'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
```
(This uses the file's existing `pumpSheet` helper and `setUpAll` Hive box setup — `consumptionRatesProvider` reads `Hive.box(cacheBoxName)`, already opened in `setUpAll`.)

- [ ] **Step 4: Run the smoke test**

Run: `cd flutter && flutter test test/render_smoke_test.dart`
Expected: All PASS, including the new `SupplyRatesSheet` test.

- [ ] **Step 5: Commit**

```bash
cd flutter && git add lib/features/inventory/supply_rates_sheet.dart test/render_smoke_test.dart
git commit -m "$(cat <<'EOF'
Add SupplyRatesSheet: inventory-owned bottom sheet for supply-rate config

New home for the per-session/target-qty editor, following the existing
inventory bottom-sheet pattern, with expanded instructions on what the
fields do. Not yet wired to any trigger — that lands in the next commit.
EOF
)"
```

---

### Task 3: Wire the trigger on Inventory, remove the old Settings section

**Files:**
- Modify: `lib/features/inventory/inventory_screen.dart` (imports, `_section`, call sites, new `_openSupplyRates`)
- Modify: `lib/features/settings/community_settings_screen.dart` (remove SUPPLY RATES section + import)
- Delete: `lib/features/settings/supply_rates_section.dart`

**Interfaces:**
- Consumes: `SupplyRatesSheet` (from Task 2), the existing private `_sheet()` method on `_InventoryScreenState`, `kCommunity` (`lib/flavor.dart`).

- [ ] **Step 1: Add the import to `inventory_screen.dart`**

Replace:
```dart
import 'inventory_sheets.dart';
import 'rate_overrides.dart';
import 'stock_calc.dart';
```

With:
```dart
import 'inventory_sheets.dart';
import 'rate_overrides.dart';
import 'stock_calc.dart';
import 'supply_rates_sheet.dart';
```

- [ ] **Step 2: Add an optional `onConfigureRates` callback to `_section()` and render the icon when present**

Replace:
```dart
  Widget _section(
    HdTokens t,
    String title,
    List<StockEntry> entries,
    InventoryResponse data, {
    Map<String, RateOverride> rates = const {},
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(fontSize: 12, letterSpacing: 1, color: t.textMuted),
        ),
        const SizedBox(height: 8),
```

With:
```dart
  Widget _section(
    HdTokens t,
    String title,
    List<StockEntry> entries,
    InventoryResponse data, {
    Map<String, RateOverride> rates = const {},
    VoidCallback? onConfigureRates,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(fontSize: 12, letterSpacing: 1, color: t.textMuted),
            ),
            if (onConfigureRates != null) ...[
              const Spacer(),
              GestureDetector(
                onTap: onConfigureRates,
                child: Icon(Icons.tune, size: 16, color: t.textMuted),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
```

- [ ] **Step 3: Pass the callback at the NxStage Supplies call site only**

Replace:
```dart
            _section(t, 'NxStage Supplies', nxstage, data, rates: rates),
            const SizedBox(height: 16),
            _section(t, 'Hospital Prescriptions', hospital, data, rates: rates),
```

With:
```dart
            _section(
              t,
              'NxStage Supplies',
              nxstage,
              data,
              rates: rates,
              onConfigureRates: kCommunity ? _openSupplyRates : null,
            ),
            const SizedBox(height: 16),
            _section(t, 'Hospital Prescriptions', hospital, data, rates: rates),
```

- [ ] **Step 4: Add the `_openSupplyRates` method next to the other `_open*` sheet-opening methods**

Replace:
```dart
  void _openDelivery(Cycle cycle) =>
      _sheet(DeliverySheet(cycle: cycle, onDone: _load));
}
```

With:
```dart
  void _openDelivery(Cycle cycle) =>
      _sheet(DeliverySheet(cycle: cycle, onDone: _load));

  void _openSupplyRates() => _sheet(const SupplyRatesSheet());
}
```

- [ ] **Step 5: Run static analysis**

Run: `cd flutter && flutter analyze lib/features/inventory/inventory_screen.dart`
Expected: `No issues found!`

- [ ] **Step 6: Run the inventory render-smoke test**

Run: `cd flutter && flutter test test/render_smoke_test.dart`
Expected: PASS — `InventoryScreen renders from a fake api` still finds `'NXSTAGE SUPPLIES'` with no exception. The tune icon does not render in this test (`kCommunity` is `false` without `--dart-define=FLAVOR=community`), so this only confirms the non-community path is unaffected.

- [ ] **Step 7: Remove the SUPPLY RATES section from `community_settings_screen.dart`**

Replace:
```dart
          const SizedBox(height: 20),
          _section(t, 'SUPPLY RATES'),
          Text(
            'How many of each supply you use per session and how much to keep on hand. Defaults are for a standard NxStage treatment.',
            style: TextStyle(fontSize: 12, color: t.textMuted),
          ),
          const SizedBox(height: 8),
          const SupplyRatesSection(),
          const SizedBox(height: 20),
          _section(t, 'AI ASSISTANT (OPTIONAL)'),
```

With:
```dart
          const SizedBox(height: 20),
          _section(t, 'AI ASSISTANT (OPTIONAL)'),
```

- [ ] **Step 8: Remove the now-unused import from `community_settings_screen.dart`**

Delete the line:
```dart
import 'supply_rates_section.dart';
```

- [ ] **Step 9: Delete the old widget file**

Run: `cd flutter && git rm lib/features/settings/supply_rates_section.dart`

- [ ] **Step 10: Run static analysis across the whole project**

Run: `cd flutter && flutter analyze`
Expected: `No issues found!` (confirms nothing else references the deleted file or `SupplyRatesSection`).

- [ ] **Step 11: Run the full test suite**

Run: `cd flutter && flutter test`
Expected: All PASS.

- [ ] **Step 12: Manual verification in community flavor**

Run: `cd flutter && flutter devices` to find an attached device/emulator id, then:
`flutter run --dart-define=FLAVOR=community -d <the device id from the previous command>`

With the app running:
- Open the Inventory tab; confirm a small tune (⚙) icon appears next to "NXSTAGE SUPPLIES" and *not* next to "HOSPITAL PRESCRIPTIONS".
- Tap it; confirm the sheet opens showing the expanded instructions, per-item fields prefilled with current values, and Save/Reset behave as before (Save shows "Saved ✓", Reset restores defaults and shows the snackbar).
- Open Settings; confirm the "SUPPLY RATES" section is gone and the rest of the screen (dry weight, AI assistant, etc.) is unaffected.
- Open "Place order" from Inventory; confirm Step 1 no longer shows backup controls and the order quantities calculated in Step 2 look correct.

- [ ] **Step 13: Commit**

```bash
cd flutter && git add lib/features/inventory/inventory_screen.dart lib/features/settings/community_settings_screen.dart lib/features/settings/supply_rates_section.dart
git commit -m "$(cat <<'EOF'
Move supply-rate config from Settings to a tune icon on Inventory

NxStage Supplies section on the Inventory page now opens
SupplyRatesSheet directly, with in-context instructions on how the
two fields affect stock status. Removed the old Settings entry point
and its now-unused widget file.
EOF
)"
```
