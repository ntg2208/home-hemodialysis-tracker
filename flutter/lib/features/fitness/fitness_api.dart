import '../../api/rest_client.dart';

/// Models + client for GET /api/fitness/summary and POST /api/fitness/sync.
/// Mirrors the shapes in frontend/src/routes/Fitness/index.tsx.

class FitnessLatest {
  const FitnessLatest(this.label, this.value, this.unit, this.at);
  final String label;
  final String value;
  final String unit;
  final String at;

  factory FitnessLatest.fromJson(Map<String, dynamic> j) => FitnessLatest(
        (j['label'] ?? '') as String,
        '${j['value'] ?? ''}',
        (j['unit'] ?? '') as String,
        (j['at'] ?? '') as String,
      );
}

class FitnessType {
  const FitnessType({
    required this.type,
    this.lastSynced,
    this.count,
    this.lastDate,
    this.stale = false,
    this.latest,
    this.bytes,
    this.error,
  });

  final String type;
  final String? lastSynced;
  final int? count;
  final String? lastDate;
  final bool stale;
  final FitnessLatest? latest;
  final int? bytes;
  final String? error;

  factory FitnessType.fromJson(Map<String, dynamic> j) => FitnessType(
        type: j['type'] as String,
        lastSynced: j['last_synced'] as String?,
        count: (j['count'] as num?)?.toInt(),
        lastDate: j['last_date'] as String?,
        stale: j['stale'] as bool? ?? false,
        latest: j['latest'] == null
            ? null
            : FitnessLatest.fromJson(
                Map<String, dynamic>.from(j['latest'] as Map)),
        bytes: (j['bytes'] as num?)?.toInt(),
        error: j['error'] as String?,
      );
}

class FitnessTotals {
  const FitnessTotals(this.types, this.healthy, this.stale, this.bytes);
  final int types;
  final int healthy;
  final int stale;
  final int bytes;

  factory FitnessTotals.fromJson(Map<String, dynamic> j) => FitnessTotals(
        (j['types'] as num?)?.toInt() ?? 0,
        (j['healthy'] as num?)?.toInt() ?? 0,
        (j['stale'] as num?)?.toInt() ?? 0,
        (j['bytes'] as num?)?.toInt() ?? 0,
      );
}

class FitnessSummary {
  const FitnessSummary(this.generatedAt, this.types, this.totals);
  final String generatedAt;
  final List<FitnessType> types;
  final FitnessTotals totals;

  factory FitnessSummary.fromJson(Map<String, dynamic> j) => FitnessSummary(
        (j['generated_at'] ?? '') as String,
        ((j['types'] as List?) ?? [])
            .map((e) => FitnessType.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        FitnessTotals.fromJson(
            Map<String, dynamic>.from((j['totals'] as Map?) ?? {})),
      );

  /// Most recent last_synced across all types (or null).
  String? get lastSynced => types.fold<String?>(null, (max, t) {
        final d = t.lastSynced;
        return (d != null && (max == null || d.compareTo(max) > 0)) ? d : max;
      });

  bool get allHealthy => totals.stale == 0 && !types.any((t) => t.error != null);
  bool get hasData => types.any((t) => (t.count ?? 0) > 0);
}

class FitnessApi {
  FitnessApi(this._rest);
  final RestClient _rest;

  Future<FitnessSummary> fetchSummary() async {
    final data = await _rest.get('/api/fitness/summary');
    return FitnessSummary.fromJson(data);
  }

  /// Returns the per-type sync result map; caller surfaces any errors.
  Future<Map<String, dynamic>> sync() async {
    final data = await _rest.send('POST', '/api/fitness/sync', body: {});
    final synced = data['synced'];
    return synced is Map ? Map<String, dynamic>.from(synced) : {};
  }
}
