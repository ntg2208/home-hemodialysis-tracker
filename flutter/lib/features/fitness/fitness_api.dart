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

/// One point of a daily metric series (GET /api/fitness/series).
class SeriesPoint {
  const SeriesPoint(this.date, this.value);
  final String date;
  final double value;

  factory SeriesPoint.fromJson(Map<String, dynamic> j) =>
      SeriesPoint((j['date'] ?? '') as String, ((j['value'] as num?) ?? 0).toDouble());
}

class FitnessSeries {
  const FitnessSeries(this.type, this.points);
  final String type;
  final List<SeriesPoint> points;

  factory FitnessSeries.fromJson(Map<String, dynamic> j) => FitnessSeries(
        (j['type'] ?? '') as String,
        ((j['points'] as List?) ?? [])
            .map((e) => SeriesPoint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// A stage total (e.g. DEEP 70m) within a night.
class SleepStage {
  const SleepStage(this.type, this.minutes);
  final String type;
  final int minutes;

  factory SleepStage.fromJson(Map<String, dynamic> j) =>
      SleepStage((j['type'] ?? '') as String, (j['minutes'] as num?)?.toInt() ?? 0);
}

/// One hypnogram segment (a contiguous run of a single stage).
class HypnogramSegment {
  const HypnogramSegment(this.type, this.start, this.end);
  final String type;
  final String start;
  final String end;

  factory HypnogramSegment.fromJson(Map<String, dynamic> j) => HypnogramSegment(
        (j['type'] ?? '') as String,
        (j['start'] ?? '') as String,
        (j['end'] ?? '') as String,
      );
}

class SleepNight {
  const SleepNight({
    required this.date,
    required this.minutesAsleep,
    required this.minutesAwake,
    required this.hasStages,
    required this.stages,
    required this.hypnogram,
  });

  final String date;
  final int? minutesAsleep;
  final int? minutesAwake;
  final bool hasStages;
  final List<SleepStage> stages;
  final List<HypnogramSegment> hypnogram;

  factory SleepNight.fromJson(Map<String, dynamic> j) => SleepNight(
        date: (j['date'] ?? '') as String,
        minutesAsleep: (j['minutesAsleep'] as num?)?.toInt(),
        minutesAwake: (j['minutesAwake'] as num?)?.toInt(),
        hasStages: j['hasStages'] as bool? ?? false,
        stages: ((j['stages'] as List?) ?? [])
            .map((e) => SleepStage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        hypnogram: ((j['hypnogram'] as List?) ?? [])
            .map((e) => HypnogramSegment.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class FitnessSleep {
  const FitnessSleep(this.nights);
  final List<SleepNight> nights;

  factory FitnessSleep.fromJson(Map<String, dynamic> j) => FitnessSleep(
        ((j['nights'] as List?) ?? [])
            .map((e) => SleepNight.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class FitnessApi {
  FitnessApi(this._rest);
  final RestClient _rest;

  Future<FitnessSummary> fetchSummary() async {
    final data = await _rest.get('/api/fitness/summary');
    return FitnessSummary.fromJson(data);
  }

  /// Daily series for one metric type (defaults to the last 30 days server-side).
  Future<FitnessSeries> fetchSeries(String type) async {
    final data = await _rest.get('/api/fitness/series', query: {'type': type});
    return FitnessSeries.fromJson(data);
  }

  /// Per-night sleep detail (defaults to the last 30 nights server-side).
  Future<FitnessSleep> fetchSleep() async {
    final data = await _rest.get('/api/fitness/sleep');
    return FitnessSleep.fromJson(data);
  }

  /// Returns the per-type sync result map; caller surfaces any errors.
  Future<Map<String, dynamic>> sync() async {
    final data = await _rest.send('POST', '/api/fitness/sync', body: {});
    final synced = data['synced'];
    return synced is Map ? Map<String, dynamic>.from(synced) : {};
  }
}
