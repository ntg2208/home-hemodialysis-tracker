// Synthetic drop-in replacements for all data repos/stores/APIs.
// Each class extends its real counterpart and overrides data-access methods.
// Write methods are no-ops so test mode is fully read-only.

import '../api/inventory_api.dart';
import '../api/rest_client.dart';
import '../features/blood_tests/blood_tests_api.dart';
import '../features/blood_tests/bt_store.dart';
import '../features/blood_tests/models.dart';
import '../features/fitness/fitness_api.dart';
import '../features/inventory/inventory_models.dart';
import '../features/treatment/models.dart';
import '../features/treatment/treatment_repo.dart';
import '../storage/cache_store.dart';
import 'synthetic_data.dart';

// ── TreatmentRepo ─────────────────────────────────────────────────────────────

class SyntheticTreatmentRepo extends TreatmentRepo {
  @override
  Future<void> saveSession(Session s) async {}

  @override
  Future<void> saveReading(Reading r) async {}

  @override
  Future<void> updateSession(String sessionId, Map<String, dynamic> patch) async {}

  @override
  Future<void> deleteSession(String sessionId) async {}

  @override
  Future<List<Reading>> getReadings(String sessionId) async =>
      syntheticReadings.where((r) => r.sessionId == sessionId).toList();

  @override
  Future<({List<Session> sessions, List<Reading> readings})> getAll() async =>
      (sessions: syntheticSessions, readings: syntheticReadings);
}

// ── InventoryApi ──────────────────────────────────────────────────────────────

class SyntheticInventoryApi extends InventoryApi {
  SyntheticInventoryApi() : super(RestClient(mainKey: () => ''));

  @override
  Future<InventoryResponse> fetchInventory() async => syntheticInventory;

  @override
  Future<Map<String, num>> fetchStock() async =>
      syntheticInventory.stock.map((k, v) => MapEntry(k, v));

  @override
  Future<void> logEvent(String type, Map<String, num> deltas,
      {String? note}) async {}

  @override
  Future<void> rollbackSession(String sessionId) async {}

  @override
  Future<void> confirmOrder(String callDate, Map<String, int> order,
      {String? deliveryDate}) async {}

  @override
  Future<void> initCycle(String callDate, {String? deliveryDate}) async {}

  @override
  Future<void> updateCycleDates(String callDate, String deliveryDate) async {}

  @override
  Future<void> applyDelivery({Map<String, int>? adjustments}) async {}

  @override
  Future<void> updateOrder(Map<String, int> order) async {}

  @override
  Future<void> setPakInstall(String installedAt) async {}

  @override
  Future<List<DeliveryEvent>> fetchDeliveries() async => [];
}

// ── BtStore ───────────────────────────────────────────────────────────────────

class SyntheticBtStore extends BtStore {
  SyntheticBtStore(super.box);

  @override
  BtCache readCache() => BtCache(
        syntheticBloodTestRows,
        '2026-04-01',
        DateTime(2026, 5, 20, 8).millisecondsSinceEpoch,
      );

  @override
  Future<void> writeCache(
      List<BloodTestRow> rows, String coveredFrom, int lastSynced) async {}
}

// ── BloodTestsApi ─────────────────────────────────────────────────────────────

class SyntheticBloodTestsApi extends BloodTestsApi {
  SyntheticBloodTestsApi() : super(RestClient(mainKey: () => ''));

  @override
  Future<List<BloodTestRow>> fetchRange({String? from, String? to}) async =>
      syntheticBloodTestRows;
}

// ── FitnessApi ────────────────────────────────────────────────────────────────

class SyntheticFitnessApi extends FitnessApi {
  SyntheticFitnessApi() : super(RestClient(mainKey: () => ''));

  @override
  Future<FitnessSummary> fetchSummary() async =>
      FitnessSummary.fromJson(syntheticFitnessSummaryJson);

  @override
  Future<Map<String, dynamic>> sync() async => {};
}

// ── CacheStore ────────────────────────────────────────────────────────────────
// Returns synthetic JSON for the two keys the chat and screens use.
// Other keys pass through to the real Hive box so unrelated features work.

class SyntheticCacheStore extends CacheStore {
  SyntheticCacheStore(super.box);

  static const _fitnessKey = 'fitness_summary';
  static const _inventoryKey = 'inventory';

  Map<String, dynamic>? _synthetic(String key) {
    if (key == _fitnessKey) return syntheticFitnessSummaryJson;
    if (key == _inventoryKey) return syntheticInventory.toJson();
    return null;
  }

  @override
  Map<String, dynamic>? read(String key, Duration ttl) =>
      _synthetic(key) ?? super.read(key, ttl);

  @override
  Map<String, dynamic>? readStale(String key) =>
      _synthetic(key) ?? super.readStale(key);

  @override
  Future<void> write(String key, Map<String, dynamic> data) async {
    // Block synthetic keys from being overwritten by live API calls.
    if (key == _fitnessKey || key == _inventoryKey) return;
    return super.write(key, data);
  }
}
