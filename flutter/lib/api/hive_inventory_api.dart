import 'package:hive/hive.dart';

import '../api/inventory_api.dart';
import '../api/rest_client.dart';
import '../features/inventory/inventory_models.dart';
import '../flavor.dart';

class HiveInventoryApi extends InventoryApi {
  HiveInventoryApi() : super(RestClient(mainKey: () => ''));

  Box get _stock => Hive.box(communityInventoryBox);
  Box get _events => Hive.box(communityEventsBox);

  @override
  Future<InventoryResponse> fetchInventory() async {
    final stockRaw = _stock.get('stock') as Map? ?? {};
    final cycleRaw = _stock.get('cycle') as Map?;
    return InventoryResponse(
      stock: Map<String, int>.from(
          stockRaw.map((k, v) => MapEntry(k as String, (v as num).toInt()))),
      cycle: cycleRaw != null
          ? Cycle.fromJson(Map<String, dynamic>.from(cycleRaw))
          : null,
      pakInstalledAt: _stock.get('pak_installed_at') as String?,
      pakSessions: (_stock.get('pak_sessions') as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<Map<String, num>> fetchStock() async {
    final raw = _stock.get('stock') as Map? ?? {};
    return Map<String, num>.from(
        raw.map((k, v) => MapEntry(k as String, v as num)));
  }

  @override
  Future<void> logEvent(String type, Map<String, num> deltas,
      {String? note}) async {
    final stock = Map<String, num>.from(
        ((_stock.get('stock') as Map?) ?? {})
            .map((k, v) => MapEntry(k as String, v as num)));
    deltas.forEach((k, v) {
      stock[k] = (stock[k] ?? 0) + v;
    });
    await _stock.put('stock', stock);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await _events.put(id, {
      'id': id,
      'type': type,
      'deltas': deltas.map((k, v) => MapEntry(k, v)),
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> rollbackSession(String sessionId) async {}

  @override
  Future<void> confirmOrder(String callDate, Map<String, int> order,
      {String? deliveryDate}) async {
    final cycleRaw = _stock.get('cycle') as Map? ?? {};
    final merged = Map<String, dynamic>.from(cycleRaw)
      ..['call_date'] = callDate
      ..['order'] = order
      ..['order_placed_at'] = DateTime.now().toIso8601String();
    if (deliveryDate != null) merged['delivery_date'] = deliveryDate;
    await _stock.put('cycle', merged);
  }

  @override
  Future<void> initCycle(String callDate, {String? deliveryDate}) async {
    await _stock.put('cycle', {
      'call_date': callDate,
      if (deliveryDate != null) 'delivery_date': deliveryDate,
    });
  }

  @override
  Future<void> updateCycleDates(
      String callDate, String deliveryDate) async {
    final cycleRaw =
        Map<String, dynamic>.from((_stock.get('cycle') as Map?) ?? {});
    cycleRaw['call_date'] = callDate;
    cycleRaw['delivery_date'] = deliveryDate;
    await _stock.put('cycle', cycleRaw);
  }

  @override
  Future<void> applyDelivery({Map<String, int>? adjustments}) async {
    final cycleRaw =
        Map<String, dynamic>.from((_stock.get('cycle') as Map?) ?? {});
    cycleRaw['delivery_applied_at'] = DateTime.now().toIso8601String();
    await _stock.put('cycle', cycleRaw);
  }

  @override
  Future<void> updateOrder(Map<String, int> order) async {
    final cycleRaw =
        Map<String, dynamic>.from((_stock.get('cycle') as Map?) ?? {});
    cycleRaw['order'] = order;
    await _stock.put('cycle', cycleRaw);
  }

  @override
  Future<void> setPakInstall(String installedAt) async =>
      _stock.put('pak_installed_at', installedAt);

  @override
  Future<List<DeliveryEvent>> fetchDeliveries() async => [];
}
