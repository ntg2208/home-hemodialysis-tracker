# Community Supply Rates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let community-flavor users customise per-session consumption rates and buffer targets for NxStage supply items, stored in Hive and applied throughout the inventory calculation layer.

**Architecture:** A pure-Dart `RateOverride` model is stored in the existing `cacheBoxName` Hive box. A Riverpod `ConsumptionRatesNotifier` loads/saves overrides. A new `resolveItem()` in `constants.dart` merges catalogue defaults with overrides. All `stock_calc.dart` functions accept an optional `rates` map and call `resolveItem` instead of `getItem`. A `SupplyRatesSection` widget in `CommunitySettingsScreen` lets users fill in their values.

**Tech Stack:** Flutter 3.44, Riverpod 2.x (`NotifierProvider`), Hive 2.x, `flutter_test`

## Global Constraints

- Community flavor only — no changes to personal-flavor code paths.
- All `stock_calc.dart` functions must remain backwards-compatible: existing call sites with no `rates` argument must compile and behave identically.
- PAK-001 per-session rate is not overridable (hardcoded 1/10). PAK target quantity IS overridable.
- All 17 existing tests in `test/stock_calc_test.dart` must still pass.
- Follow existing Hive/Riverpod patterns from `lib/app/providers.dart` (`NotifierProvider`, `Hive.box(cacheBoxName).get/put`).
- Run tests with: `uv run flutter test` (or `flutter test` directly if uv not applicable — this is a Flutter project, not Python).
  - Actually: `cd flutter && flutter test`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| **Create** | `lib/features/inventory/rate_overrides.dart` | `RateOverride` model (pure Dart, no Flutter deps) |
| **Create** | `lib/features/inventory/consumption_rates_provider.dart` | `ConsumptionRatesNotifier` + `consumptionRatesProvider` |
| **Modify** | `lib/features/inventory/constants.dart` | Add `resolveItem()` |
| **Modify** | `lib/features/inventory/stock_calc.dart` | Add `rates` param to all 7 functions |
| **Modify** | `lib/features/inventory/inventory_screen.dart` | Pass rates to `_StockRow` + `sortStock` |
| **Modify** | `lib/features/inventory/inventory_sheets.dart` | Pass rates to `orderBoxes` |
| **Create** | `lib/features/settings/supply_rates_section.dart` | `SupplyRatesSection` widget |
| **Modify** | `lib/features/settings/community_settings_screen.dart` | Add `SupplyRatesSection` |
| **Create** | `test/consumption_rates_test.dart` | Unit tests for `resolveItem` + overridden stock_calc |

All paths are relative to `flutter/`.

---

## Task 1: `RateOverride` model + `resolveItem` + stock_calc `rates` param

**Files:**
- Create: `lib/features/inventory/rate_overrides.dart`
- Modify: `lib/features/inventory/constants.dart`
- Modify: `lib/features/inventory/stock_calc.dart`
- Test: `test/consumption_rates_test.dart`

**Interfaces:**
- Produces: `RateOverride` class with `perSession: int?` and `targetQty: int?`
- Produces: `resolveItem(String code, Map<String, RateOverride> rates) → ItemDef?` in `constants.dart`
- Produces: all `stock_calc.dart` functions with optional named `rates` param

---

- [ ] **Step 1: Write the failing tests**

Create `flutter/test/consumption_rates_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/inventory/constants.dart';
import 'package:home_hd/features/inventory/rate_overrides.dart';
import 'package:home_hd/features/inventory/stock_calc.dart';

void main() {
  group('resolveItem', () {
    test('returns base item when no overrides map', () {
      final item = resolveItem('SAK-303', {});
      expect(item?.perSession, 1);
      expect(item?.targetQty, 24);
    });

    test('returns null for unknown code', () {
      expect(resolveItem('UNKNOWN', {}), isNull);
    });

    test('overrides perSession', () {
      final item = resolveItem('SAK-303', {
        'SAK-303': const RateOverride(perSession: 2),
      });
      expect(item?.perSession, 2);
      expect(item?.targetQty, 24); // unchanged
    });

    test('overrides targetQty', () {
      final item = resolveItem('SAK-303', {
        'SAK-303': const RateOverride(targetQty: 32),
      });
      expect(item?.perSession, 1); // unchanged
      expect(item?.targetQty, 32);
    });

    test('partial override: only the set field changes', () {
      final item = resolveItem('CAR-172-C', {
        'CAR-172-C': const RateOverride(targetQty: 30),
      });
      expect(item?.perSession, 1);
      expect(item?.targetQty, 30);
    });

    test('null override fields keep catalogue defaults', () {
      final item = resolveItem('SAK-303', {
        'SAK-303': const RateOverride(),
      });
      expect(item?.perSession, 1);
      expect(item?.targetQty, 24);
    });
  });

  group('stock_calc with rates', () {
    test('consumedUnits uses overridden perSession for SAK', () {
      final rates = {'SAK-303': const RateOverride(perSession: 2)};
      expect(consumedUnits('SAK-303', 20, rates: rates), 40);
    });

    test('consumedUnits override replaces hardcoded needle rate', () {
      final rates = {'P00012326': const RateOverride(perSession: 1)};
      expect(consumedUnits('P00012326', 20, rates: rates), 20); // override: 1/session
    });

    test('consumedUnits still uses hardcoded needle rate when no override', () {
      expect(consumedUnits('P00012326', 20), 40); // default: 2/session
    });

    test('orderBoxes uses overridden targetQty as fallback', () {
      // Sani-Cloth: no session rate, falls back to targetQty. Override targetQty to 2.
      final rates = {'UK00000830': const RateOverride(targetQty: 2)};
      expect(orderBoxes('UK00000830', 0, rates: rates), 2);
      expect(orderBoxes('UK00000830', 1, rates: rates), 1);
    });

    test('orderBoxes uses overridden perSession for delivery-session target', () {
      // SAK with 2/session, deliverySessions=20 → target=40, have=10 → order=30 → 15 boxes
      final rates = {'SAK-303': const RateOverride(perSession: 2)};
      expect(orderBoxes('SAK-303', 10, deliverySessions: 20, rates: rates), 15);
    });

    test('sessionsRemaining uses overridden perSession for needles', () {
      // Override needles to 1/session: 20 needles → 20 sessions
      final rates = {'P00012326': const RateOverride(perSession: 1)};
      expect(sessionsRemaining('P00012326', 20, rates: rates), 20);
    });

    test('needsOrdering uses overridden targetQty', () {
      // SAK override targetQty=30: having 25 should need ordering
      final rates = {'SAK-303': const RateOverride(targetQty: 30)};
      expect(needsOrdering('SAK-303', 25, rates: rates), isTrue);
      expect(needsOrdering('SAK-303', 25), isFalse); // default target=24
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd flutter && flutter test test/consumption_rates_test.dart
```

Expected: errors like `Target of URI doesn't exist 'rate_overrides.dart'` and `resolveItem not defined`.

- [ ] **Step 3: Create `rate_overrides.dart`**

Create `flutter/lib/features/inventory/rate_overrides.dart`:

```dart
class RateOverride {
  const RateOverride({this.perSession, this.targetQty});
  final int? perSession;
  final int? targetQty;

  Map<String, dynamic> toJson() => {
    if (perSession != null) 'perSession': perSession,
    if (targetQty != null) 'targetQty': targetQty,
  };

  factory RateOverride.fromJson(Map<dynamic, dynamic> m) => RateOverride(
    perSession: (m['perSession'] as num?)?.toInt(),
    targetQty: (m['targetQty'] as num?)?.toInt(),
  );
}
```

- [ ] **Step 4: Add `resolveItem` to `constants.dart`**

Add at the top of `flutter/lib/features/inventory/constants.dart`:

```dart
import 'rate_overrides.dart';
```

Add at the bottom (after `getItem`):

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

- [ ] **Step 5: Update `stock_calc.dart` — add `rates` param to all functions**

Replace the entire contents of `flutter/lib/features/inventory/stock_calc.dart` with:

```dart
import 'constants.dart';
import 'rate_overrides.dart';

const _redThreshold = 8;
const _amberThreshold = 16;

enum StockStatus { red, amber, green }

int? sessionsRemaining(String code, int qty,
    {Map<String, RateOverride> rates = const {}}) {
  // PAK: 1 per 10 sessions — overridable
  if (code == 'PAK-001') {
    final o = rates['PAK-001']?.perSession;
    if (o != null && o > 0) return qty ~/ o;
    return qty * 10;
  }
  // Needles: 2 per session — overridable
  if (code == 'P00012326') {
    final o = rates['P00012326']?.perSession;
    if (o != null && o > 0) return qty ~/ o;
    return qty ~/ 2;
  }
  final item = resolveItem(code, rates);
  if (item == null || item.section == 'hospital') return null;
  if (item.perSession != null && item.perSession! > 0) {
    return qty ~/ item.perSession!;
  }
  return null;
}

StockStatus stockStatus(String code, int qty,
    {Map<String, RateOverride> rates = const {}}) {
  final item = resolveItem(code, rates) ?? getItem(code);
  if (item == null) return qty > 0 ? StockStatus.green : StockStatus.red;

  if (item.section == 'hospital') {
    if (qty <= 0) return StockStatus.red;
    if (qty <= 1) return StockStatus.amber;
    return StockStatus.green;
  }

  final sr = sessionsRemaining(code, qty, rates: rates);
  if (sr == null) {
    return qty <= 0
        ? StockStatus.red
        : qty <= 1
            ? StockStatus.amber
            : StockStatus.green;
  }
  if (sr < _redThreshold) return StockStatus.red;
  if (sr < _amberThreshold) return StockStatus.amber;
  return StockStatus.green;
}

bool needsOrdering(String code, int qty,
    {Map<String, RateOverride> rates = const {}}) {
  final item = resolveItem(code, rates);
  if (item == null || item.section == 'hospital') return false;
  return qty < item.targetQty;
}

int consumedUnits(String code, int sessionsTotal,
    {Map<String, RateOverride> rates = const {}}) {
  // PAK: 1 per 10 sessions — overridable
  if (code == 'PAK-001') {
    final o = rates['PAK-001']?.perSession;
    if (o != null && o > 0) return (sessionsTotal * o);
    return (sessionsTotal / 10).ceil();
  }
  // Needles: 2 per session — overridable
  if (code == 'P00012326') {
    final o = rates['P00012326']?.perSession;
    if (o != null && o > 0) return sessionsTotal * o;
    return sessionsTotal * 2;
  }
  final item = resolveItem(code, rates);
  if (item == null || item.perSession == null || item.perSession! <= 0) return 0;
  return sessionsTotal * item.perSession!;
}

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

class StockEntry {
  const StockEntry(this.code, this.qty);
  final String code;
  final int qty;
}

List<StockEntry> sortStock(List<StockEntry> entries,
    {Map<String, RateOverride> rates = const {}}) {
  List<StockEntry> sortGroup(List<StockEntry> group) {
    final g = [...group];
    g.sort((a, b) {
      final aNeeds = needsOrdering(a.code, a.qty, rates: rates);
      final bNeeds = needsOrdering(b.code, b.qty, rates: rates);
      if (aNeeds != bNeeds) return aNeeds ? -1 : 1;
      return (getItem(a.code)?.priority ?? 99)
          .compareTo(getItem(b.code)?.priority ?? 99);
    });
    return g;
  }

  final nxstage =
      entries.where((e) => getItem(e.code)?.section == 'nxstage').toList();
  final hospital =
      entries.where((e) => getItem(e.code)?.section == 'hospital').toList();
  final unknown = entries.where((e) => getItem(e.code) == null).toList();
  return [...sortGroup(nxstage), ...sortGroup(hospital), ...unknown];
}
```

Note: `orderUnits` now also has the `working` clamp fix from the code review (`clamp(0, currentQty)`).

- [ ] **Step 6: Run all tests**

```bash
cd flutter && flutter test
```

Expected: all tests pass including the original 17 in `test/stock_calc_test.dart` and the new tests in `test/consumption_rates_test.dart`.

- [ ] **Step 7: Commit**

```bash
cd flutter && git add lib/features/inventory/rate_overrides.dart lib/features/inventory/constants.dart lib/features/inventory/stock_calc.dart test/consumption_rates_test.dart
git commit -m "feat(inventory): RateOverride model + resolveItem + rates param in stock_calc"
```

---

## Task 2: `ConsumptionRatesNotifier` provider

**Files:**
- Create: `lib/features/inventory/consumption_rates_provider.dart`

**Interfaces:**
- Consumes: `RateOverride` from `rate_overrides.dart`; `cacheBoxName` from `app/providers.dart`; `Hive` from `package:hive/hive.dart`
- Produces: `consumptionRatesProvider` — `NotifierProvider<ConsumptionRatesNotifier, Map<String, RateOverride>>`
- Produces: `ConsumptionRatesNotifier.save(Map<String, RateOverride>)` — persists to Hive, updates state
- Produces: `ConsumptionRatesNotifier.reset()` — clears override, reverts to catalogue defaults

---

- [ ] **Step 1: Create `consumption_rates_provider.dart`**

Create `flutter/lib/features/inventory/consumption_rates_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../app/providers.dart' show cacheBoxName;
import 'rate_overrides.dart';

const _supplyRatesKey = 'supply_rates';

final consumptionRatesProvider =
    NotifierProvider<ConsumptionRatesNotifier, Map<String, RateOverride>>(
        ConsumptionRatesNotifier.new);

class ConsumptionRatesNotifier extends Notifier<Map<String, RateOverride>> {
  @override
  Map<String, RateOverride> build() {
    final raw = Hive.box(cacheBoxName).get(_supplyRatesKey) as Map? ?? {};
    return {
      for (final e in raw.entries)
        e.key as String: RateOverride.fromJson(e.value as Map),
    };
  }

  Future<void> save(Map<String, RateOverride> overrides) async {
    await Hive.box(cacheBoxName).put(
      _supplyRatesKey,
      {for (final e in overrides.entries) e.key: e.value.toJson()},
    );
    state = Map.unmodifiable(overrides);
  }

  Future<void> reset() async {
    await Hive.box(cacheBoxName).delete(_supplyRatesKey);
    state = const {};
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd flutter && flutter analyze lib/features/inventory/consumption_rates_provider.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
cd flutter && git add lib/features/inventory/consumption_rates_provider.dart
git commit -m "feat(inventory): ConsumptionRatesNotifier — Hive-backed rates provider"
```

---

## Task 3: `SupplyRatesSection` widget + wire into `CommunitySettingsScreen`

**Files:**
- Create: `lib/features/settings/supply_rates_section.dart`
- Modify: `lib/features/settings/community_settings_screen.dart`

**Interfaces:**
- Consumes: `consumptionRatesProvider` from `consumption_rates_provider.dart`
- Consumes: `items` list + `RateOverride` + `getItem` from `constants.dart` / `rate_overrides.dart`
- No new exports — widget is internal to settings.

---

- [ ] **Step 1: Create `supply_rates_section.dart`**

Create `flutter/lib/features/settings/supply_rates_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inventory/constants.dart';
import '../inventory/consumption_rates_provider.dart';
import '../inventory/rate_overrides.dart';

class SupplyRatesSection extends ConsumerStatefulWidget {
  const SupplyRatesSection({super.key});
  @override
  ConsumerState<SupplyRatesSection> createState() => _SupplyRatesSectionState();
}

class _SupplyRatesSectionState extends ConsumerState<SupplyRatesSection> {
  // NxStage items only — hospital excluded.
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

  // Returns the effective default per-session rate for display.
  // PAK returns null (rate shown as read-only text). Needles returns 2.
  // Items with no session rate return null (no rate field shown).
  int? _effectiveDefaultRate(ItemDef item) {
    if (item.code == 'PAK-001') return null;
    if (item.code == 'P00012326') return 2;
    return item.perSession;
  }

  @override
  void dispose() {
    for (final c in _rateCtrl.values) c.dispose();
    for (final c in _targetCtrl.values) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final overrides = <String, RateOverride>{};
    for (final item in _nxstage) {
      final rateText = _rateCtrl[item.code]?.text.trim() ?? '';
      final targetText = _targetCtrl[item.code]?.text.trim() ?? '';
      final rate = int.tryParse(rateText);
      final target = int.tryParse(targetText);
      // Only store fields that are valid positive values.
      final validRate = (rate != null && rate > 0) ? rate : null;
      final validTarget = (target != null && target > 0) ? target : null;
      if (validRate != null || validTarget != null) {
        overrides[item.code] = RateOverride(
          perSession: item.code != 'PAK-001' ? validRate : null,
          targetQty: validTarget,
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Rates reset to defaults')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in _nxstage) _itemRow(item),
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
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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

- [ ] **Step 2: Add `SupplyRatesSection` to `CommunitySettingsScreen`**

In `flutter/lib/features/settings/community_settings_screen.dart`:

Add the import near the top (with the other local imports):

```dart
import '../inventory/consumption_rates_provider.dart' show consumptionRatesProvider;
import 'supply_rates_section.dart';
```

In the `build` method's `ListView` children, add after the `DRY WEIGHT` block and before `AI ASSISTANT`. The dry weight block ends with:

```dart
          const SizedBox(height: 20),
          _section(t, 'AI ASSISTANT (OPTIONAL)'),
```

Insert before that `AI ASSISTANT` line:

```dart
          _section(t, 'SUPPLY RATES'),
          Text(
            'How many of each supply you use per session and how much to keep on hand. Defaults are for a standard NxStage treatment.',
            style: TextStyle(fontSize: 12, color: t.textMuted),
          ),
          const SizedBox(height: 8),
          const SupplyRatesSection(),
          const SizedBox(height: 20),
```

- [ ] **Step 3: Verify it compiles**

```bash
cd flutter && flutter analyze lib/features/settings/supply_rates_section.dart lib/features/settings/community_settings_screen.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
cd flutter && git add lib/features/settings/supply_rates_section.dart lib/features/settings/community_settings_screen.dart
git commit -m "feat(settings): SupplyRatesSection — community supply rate editor"
```

---

## Task 4: Wire inventory screen and sheets to pass rates

**Files:**
- Modify: `lib/features/inventory/inventory_screen.dart`
- Modify: `lib/features/inventory/inventory_sheets.dart`

**Interfaces:**
- Consumes: `consumptionRatesProvider` from `consumption_rates_provider.dart`
- `_StockRow` gains a `rates` named parameter

---

- [ ] **Step 1: Update `inventory_screen.dart`**

Add import at top:

```dart
import 'consumption_rates_provider.dart';
import 'rate_overrides.dart';
```

In `_InventoryScreenState.build()`, after `final data = _data;` (near line 220), watch the rates provider:

```dart
final rates = kCommunity ? ref.watch(consumptionRatesProvider) : const <String, RateOverride>{};
```

This requires adding `import '../../flavor.dart';` if not already present.

Pass `rates` into `_section` by updating its signature and the `sortStock` call:

The existing `sortStock` call on line ~223:
```dart
final sorted = sortStock(entries);
```
Change to:
```dart
final sorted = sortStock(entries, rates: rates);
```

The existing `_section` helper:
```dart
Widget _section(HdTokens t, String title, List<StockEntry> entries, InventoryResponse data) {
```
Change to:
```dart
Widget _section(HdTokens t, String title, List<StockEntry> entries, InventoryResponse data,
    {Map<String, RateOverride> rates = const {}}) {
```

Inside `_section`, the `_StockRow` constructor (line ~300):
```dart
_StockRow(
  item: getItem(e.code)!,
  qty: e.qty,
  onAdjust: (d) => _adjust(e.code, d),
  onSetExact: () => _setExact(e.code, e.qty),
  pakInstalledAt: e.code == 'PAK-001' ? data.pakInstalledAt : null,
  pakSessions: e.code == 'PAK-001' ? data.pakSessions : null,
  pakAvgSessions: e.code == 'PAK-001' ? data.pakAvgSessions : null,
),
```
Change to:
```dart
_StockRow(
  item: resolveItem(e.code, rates) ?? getItem(e.code)!,
  qty: e.qty,
  rates: rates,
  onAdjust: (d) => _adjust(e.code, d),
  onSetExact: () => _setExact(e.code, e.qty),
  pakInstalledAt: e.code == 'PAK-001' ? data.pakInstalledAt : null,
  pakSessions: e.code == 'PAK-001' ? data.pakSessions : null,
  pakAvgSessions: e.code == 'PAK-001' ? data.pakAvgSessions : null,
),
```

Pass `rates` at the two `_section` call sites in `build()` (nxstage and hospital sections). Example:
```dart
_section(t, 'NxStage', nxstage, data, rates: rates),
// ...
_section(t, 'Hospital', hospital, data, rates: rates),
```

Add `rates` field to `_StockRow` widget:

```dart
class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.item,
    required this.qty,
    required this.onAdjust,
    required this.onSetExact,
    this.pakInstalledAt,
    this.pakSessions,
    this.pakAvgSessions,
    this.rates = const {},  // new
  });
  final ItemDef item;
  final int qty;
  final ValueChanged<int> onAdjust;
  final VoidCallback onSetExact;
  final String? pakInstalledAt;
  final int? pakSessions;
  final double? pakAvgSessions;
  final Map<String, RateOverride> rates;  // new
```

In `_StockRow.build()`, update the two calls:
```dart
final sr = sessionsRemaining(item.code, qty, rates: rates);
final status = stockStatus(item.code, qty, rates: rates);
```

- [ ] **Step 2: Update `inventory_sheets.dart`**

Add import at top:

```dart
import 'consumption_rates_provider.dart';
import 'rate_overrides.dart';
import '../../flavor.dart';
```

In `_OrderSheetState._submitCount()`, read the rates before the loop. The state class is already `ConsumerState`, so `ref` is available:

```dart
Future<void> _submitCount() async {
  setState(() => _saving = true);
  try {
    await ref
        .read(inventoryApiProvider)
        .logEvent('stock_count', _counts, note: 'order stock count');
    _boxes.clear();
    final ds = _deliverySessions(widget.data.cycle?.deliveryDate);
    final rates = kCommunity
        ? ref.read(consumptionRatesProvider)
        : const <String, RateOverride>{};
    for (final i in _nxstage) {
      final b = orderBoxes(i.code, _counts[i.code] ?? 0,
          backupQty: _backup[i.code] ?? 0,
          deliverySessions: ds,
          rates: rates);
      if (b > 0) _boxes[i.code] = b;
    }
    setState(() {
      _step = _OrderStep.list;
      _saving = false;
    });
  } catch (_) {
    if (mounted) setState(() => _saving = false);
  }
}
```

- [ ] **Step 3: Run all tests**

```bash
cd flutter && flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Also fix the backup stepper bug from code review**

While in `inventory_sheets.dart`, fix the backup `+` button cap (code review finding #2). Find the backup `+` button (line ~369). It currently reads:

```dart
_roundBtn(t, Icons.add,
    () => setState(() => _backup[i.code] = backup + 1)),
```

Change to:

```dart
_roundBtn(t, Icons.add,
    backup >= (_counts[i.code] ?? 0)
        ? null
        : () => setState(() => _backup[i.code] = backup + 1)),
```

- [ ] **Step 5: Commit**

```bash
cd flutter && git add lib/features/inventory/inventory_screen.dart lib/features/inventory/inventory_sheets.dart
git commit -m "feat(inventory): wire consumptionRatesProvider into stock display and order calculation

Also fixes backup stepper upper bound (code review #2)."
```

---

## Done

All 4 tasks complete. Verify the full test suite one last time:

```bash
cd flutter && flutter test
```

Then manually smoke-test in the community flavor:
1. Open Settings → Supply Rates. Confirm all NxStage items appear with defaults pre-filled.
2. Change SAK to 2/session, target to 32. Tap Save rates. Restart app — values persist.
3. Open Inventory. SAK sessions-remaining halves (uses 2/session). Order calculation doubles the SAK quantity.
4. Tap Reset to defaults — SAK reverts to 1/session, target 24.
5. PAK rate field shows "0.1 (fixed)" and is not editable; target field is editable.
