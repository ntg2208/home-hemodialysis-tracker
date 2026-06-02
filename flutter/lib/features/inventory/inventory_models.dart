// Port of frontend/src/routes/Inventory/schemas.ts.

class Cycle {
  const Cycle({
    required this.callDate,
    required this.deliveryDate,
    this.order,
    this.orderPlacedAt,
    this.deliveryAppliedAt,
  });
  final String callDate;
  final String deliveryDate;
  final Map<String, int>? order;
  final String? orderPlacedAt;
  final String? deliveryAppliedAt;

  bool get orderPlaced => orderPlacedAt != null;

  factory Cycle.fromJson(Map<String, dynamic> j) => Cycle(
        callDate: j['call_date'] as String,
        deliveryDate: j['delivery_date'] as String,
        order: (j['order'] as Map?)
            ?.map((k, v) => MapEntry(k as String, (v as num).toInt())),
        orderPlacedAt: j['order_placed_at'] as String?,
        deliveryAppliedAt: j['delivery_applied_at'] as String?,
      );
}

class DeliveryEvent {
  const DeliveryEvent(this.timestamp, this.deltas, this.note);
  final String timestamp;
  final Map<String, int> deltas;
  final String? note;

  factory DeliveryEvent.fromJson(Map<String, dynamic> j) => DeliveryEvent(
        j['timestamp'] as String,
        (j['deltas'] as Map?)
                ?.map((k, v) => MapEntry(k as String, (v as num).toInt())) ??
            {},
        j['note'] as String?,
      );
}

class InventoryResponse {
  const InventoryResponse({
    required this.stock,
    required this.cycle,
    required this.pakInstalledAt,
    required this.pakSessions,
  });
  final Map<String, int> stock;
  final Cycle? cycle;
  final String? pakInstalledAt;
  final int pakSessions;

  factory InventoryResponse.fromJson(Map<String, dynamic> j) => InventoryResponse(
        stock: (j['stock'] as Map?)
                ?.map((k, v) => MapEntry(k as String, (v as num).toInt())) ??
            {},
        cycle: j['cycle'] == null
            ? null
            : Cycle.fromJson(Map<String, dynamic>.from(j['cycle'] as Map)),
        pakInstalledAt: j['pak_installed_at'] as String?,
        pakSessions: (j['pak_sessions'] as num?)?.toInt() ?? 0,
      );
}
