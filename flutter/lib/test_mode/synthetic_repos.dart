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
import '../features/kb/kb_store.dart';
import '../features/treatment/models.dart';
import '../features/treatment/treatment_repo.dart';
import '../storage/cache_store.dart';
import 'synthetic_data.dart';

// ── TreatmentRepo ─────────────────────────────────────────────────────────────

class SyntheticTreatmentRepo extends TreatmentRepo {
  // In-memory copies so new sessions/readings created during a demo are visible.
  final List<Session> _sessions = [...syntheticSessions];
  final List<Reading> _readings = [...syntheticReadings];

  @override
  Future<void> saveSession(Session s) async {
    final idx = _sessions.indexWhere((x) => x.sessionId == s.sessionId);
    if (idx >= 0) {
      _sessions[idx] = s;
    } else {
      _sessions.add(s);
    }
  }

  @override
  Future<void> saveReading(Reading r) async {
    final idx = _readings.indexWhere((x) => x.readingId == r.readingId);
    if (idx >= 0) {
      _readings[idx] = r;
    } else {
      _readings.add(r);
    }
  }

  @override
  Future<void> updateSession(String sessionId, Map<String, dynamic> patch) async {
    final idx = _sessions.indexWhere((s) => s.sessionId == sessionId);
    if (idx >= 0) {
      _sessions[idx] = Session.fromMap({..._sessions[idx].toMap(), ...patch});
    }
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    _sessions.removeWhere((s) => s.sessionId == sessionId);
    _readings.removeWhere((r) => r.sessionId == sessionId);
  }

  @override
  Future<List<Reading>> getReadings(String sessionId) async =>
      _readings.where((r) => r.sessionId == sessionId).toList();

  @override
  Future<List<Session>> getSessions({int limit = 30}) async {
    final sorted = [..._sessions]..sort((a, b) => b.date.compareTo(a.date));
    return sorted.take(limit).toList();
  }

  @override
  Future<({List<Session> sessions, List<Reading> readings})> getAll() async =>
      (sessions: List<Session>.unmodifiable(_sessions), readings: List<Reading>.unmodifiable(_readings));
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

  @override
  Future<FitnessSeries> fetchSeries(String type) async {
    final today = DateTime.now();
    final points = List.generate(14, (i) {
      final d = today.subtract(Duration(days: 13 - i));
      final date = d.toIso8601String().substring(0, 10);
      final base = type == 'daily-heart-rate-variability'
          ? 44.0
          : type == 'daily-resting-heart-rate'
              ? 58.0
              : 14.0;
      return SeriesPoint(date, base + (i % 5) - 2);
    });
    return FitnessSeries(type, points);
  }

  @override
  Future<FitnessSleep> fetchSleep() async {
    final today = DateTime.now();
    final nights = List.generate(7, (i) {
      final d = today.subtract(Duration(days: i));
      final date = d.toIso8601String().substring(0, 10);
      return SleepNight(
        date: date,
        minutesAsleep: 420 + (i % 4) * 15,
        minutesAwake: 18,
        hasStages: true,
        stages: const [
          SleepStage('AWAKE', 18),
          SleepStage('DEEP', 70),
          SleepStage('LIGHT', 300),
          SleepStage('REM', 92),
        ],
        hypnogram: [
          HypnogramSegment('AWAKE', '${date}T00:09:00Z', '${date}T00:18:00Z'),
          HypnogramSegment('LIGHT', '${date}T00:18:00Z', '${date}T02:00:00Z'),
          HypnogramSegment('DEEP', '${date}T02:00:00Z', '${date}T03:10:00Z'),
          HypnogramSegment('REM', '${date}T03:10:00Z', '${date}T04:42:00Z'),
          HypnogramSegment('LIGHT', '${date}T04:42:00Z', '${date}T08:09:00Z'),
        ],
      );
    });
    return FitnessSleep(nights);
  }
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

// ── KbStore ───────────────────────────────────────────────────────────────────

final _syntheticKbEntries = [
  KbEntry(
    id: 'kb-1',
    title: 'Dry Weight',
    content: '59 kg — target post-dialysis weight.',
    source: 'user',
    createdAt: DateTime(2026, 5, 1),
    updatedAt: DateTime(2026, 5, 1),
  ),
  KbEntry(
    id: 'kb-2',
    title: 'Session Duration',
    content: '4 hours 15 minutes standard session.',
    source: 'user',
    createdAt: DateTime(2026, 5, 1),
    updatedAt: DateTime(2026, 5, 1),
  ),
];

class SyntheticKbStore implements KbRepository {
  @override
  Future<List<KbEntry>> getAll() async => List.unmodifiable(_syntheticKbEntries);

  @override
  Future<void> save(KbEntry e) async {}

  @override
  Future<void> delete(String id) async {}
}
