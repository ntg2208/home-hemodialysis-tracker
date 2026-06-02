import 'rest_client.dart';

/// Per-session consumable deltas applied automatically at session end.
/// Port of SESSION_FIXED_DELTAS in frontend/src/routes/Inventory/constants.ts.
const sessionFixedDeltas = <String, int>{
  'SAK-303': -1,
  'CAR-172-C': -1,
  'UK00000880': -1,
  'F00010983': -1,
};

/// Thin client for the inventory endpoints used by the Treatment flow.
/// The full Inventory feature (Phase 3) builds on the same REST client.
class InventoryApi {
  InventoryApi(this._rest);
  final RestClient _rest;

  /// Current stock map (item code → quantity). Empty on any failure.
  Future<Map<String, num>> fetchStock() async {
    try {
      final data = await _rest.get('/api/inventory');
      final stock = data['stock'];
      if (stock is Map) {
        return stock.map((k, v) => MapEntry(k as String, v as num));
      }
    } catch (_) {/* stock display is best-effort */}
    return {};
  }

  Future<void> logEvent(
    String type,
    Map<String, num> deltas, {
    String? note,
  }) async {
    await _rest.send('POST', '/api/inventory/event', body: {
      'type': type,
      'deltas': deltas,
      if (note != null) 'note': note,
    });
  }
}
