import 'constants.dart';

/// Port of frontend/src/routes/Inventory/lib/stockCalc.ts.

const _redThreshold = 8; // < 2 weeks of sessions
const _amberThreshold = 16; // < 4 weeks of sessions

enum StockStatus { red, amber, green }

/// Sessions of supply remaining, or null for hospital/unknown items.
int? sessionsRemaining(String code, int qty) {
  if (code == 'PAK-001') return qty * 10;
  if (code == 'P00012326') return qty ~/ 2;
  final item = getItem(code);
  if (item == null || item.section == 'hospital') return null;
  if (item.perSession != null && item.perSession! > 0) {
    return qty ~/ item.perSession!;
  }
  return null;
}

StockStatus stockStatus(String code, int qty) {
  final item = getItem(code);
  if (item == null) return qty > 0 ? StockStatus.green : StockStatus.red;

  if (item.section == 'hospital') {
    if (qty <= 0) return StockStatus.red;
    if (qty <= 1) return StockStatus.amber;
    return StockStatus.green;
  }

  final sr = sessionsRemaining(code, qty);
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

bool needsOrdering(String code, int qty) {
  final item = getItem(code);
  if (item == null || item.section == 'hospital') return false;
  return qty < item.targetQty;
}

int orderUnits(String code, int currentQty) {
  final item = getItem(code);
  if (item == null || item.section == 'hospital') return 0;
  final n = item.targetQty - currentQty;
  return n < 0 ? 0 : n;
}

int orderBoxes(String code, int currentQty) {
  final item = getItem(code);
  if (item == null) return 0;
  return (orderUnits(code, currentQty) / item.boxSize).ceil();
}

class StockEntry {
  const StockEntry(this.code, this.qty);
  final String code;
  final int qty;
}

List<StockEntry> sortStock(List<StockEntry> entries) {
  List<StockEntry> sortGroup(List<StockEntry> group) {
    final g = [...group];
    g.sort((a, b) {
      final aNeeds = needsOrdering(a.code, a.qty);
      final bNeeds = needsOrdering(b.code, b.qty);
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
