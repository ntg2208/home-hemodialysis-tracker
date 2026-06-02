import '../features/inventory/inventory_models.dart';
import 'rest_client.dart';

/// Per-session consumable deltas applied automatically at session end.
/// Port of SESSION_FIXED_DELTAS in frontend/src/routes/Inventory/constants.ts.
const sessionFixedDeltas = <String, int>{
  'SAK-303': -1,
  'CAR-172-C': -1,
  'UK00000880': -1,
  'F00010983': -1,
};

/// Client for the inventory endpoints. Port of BloodTests/Inventory api.ts.
class InventoryApi {
  InventoryApi(this._rest);
  final RestClient _rest;

  Future<InventoryResponse> fetchInventory() async {
    final data = await _rest.get('/api/inventory');
    return InventoryResponse.fromJson(data);
  }

  /// Current stock map only (best-effort) — used by the Treatment med toggles.
  Future<Map<String, num>> fetchStock() async {
    try {
      final data = await _rest.get('/api/inventory');
      final stock = data['stock'];
      if (stock is Map) {
        return stock.map((k, v) => MapEntry(k as String, v as num));
      }
    } catch (_) {/* best-effort */}
    return {};
  }

  Future<void> logEvent(String type, Map<String, num> deltas, {String? note}) =>
      _rest.send('POST', '/api/inventory/event', body: {
        'type': type,
        'deltas': deltas,
        if (note != null) 'note': note,
      });

  Future<void> confirmOrder(String callDate, Map<String, int> order,
          {String? deliveryDate}) =>
      _rest.send('POST', '/api/inventory/confirm-order', body: {
        'call_date': callDate,
        'order': order,
        if (deliveryDate != null) 'delivery_date': deliveryDate,
      });

  Future<void> initCycle(String callDate, {String? deliveryDate}) =>
      confirmOrder(callDate, const {}, deliveryDate: deliveryDate);

  Future<void> updateCycleDates(String callDate, String deliveryDate) =>
      _rest.send('POST', '/api/inventory/update-cycle-dates',
          body: {'call_date': callDate, 'delivery_date': deliveryDate});

  Future<void> applyDelivery({Map<String, int>? adjustments}) =>
      _rest.send('POST', '/api/inventory/apply-delivery',
          body: {'adjustments': adjustments});

  Future<void> setPakInstall(String installedAt) => _rest
      .send('POST', '/api/inventory/set-pak-install', body: {'installed_at': installedAt});

  Future<List<DeliveryEvent>> fetchDeliveries() async {
    final data = await _rest.get('/api/inventory/deliveries');
    final list = data['deliveries'];
    if (list is! List) return [];
    return list
        .map((e) => DeliveryEvent.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
