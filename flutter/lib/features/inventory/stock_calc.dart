import 'constants.dart';
import 'rate_overrides.dart';

/// Port of frontend/src/routes/Inventory/lib/stockCalc.ts.

const _redThreshold = 8; // < 2 weeks of sessions
const _amberThreshold = 16; // < 4 weeks of sessions

enum StockStatus { red, amber, green }

int? sessionsRemaining(String code, int qty,
    {Map<String, RateOverride> rates = const {}}) {
  if (code == 'PAK-001') return qty * 10;  // always hardcoded, no override
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
  if (code == 'PAK-001') return (sessionsTotal / 10).ceil();  // always hardcoded, no override
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
