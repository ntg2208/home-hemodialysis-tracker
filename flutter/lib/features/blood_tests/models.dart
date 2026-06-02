// Blood test domain models. Mirrors frontend/src/routes/BloodTests/schemas.ts.

class BloodTestRow {
  const BloodTestRow({
    required this.marker,
    required this.datetime,
    required this.value,
    required this.unit,
    required this.refLow,
    required this.refHigh,
    required this.timing, // '', 'pre', 'post'
    required this.note,
    required this.source,
    required this.labId,
    required this.phase,
    required this.createdAt,
    required this.qualitative,
  });

  final String marker;
  final String datetime;
  final double value;
  final String unit;
  final double? refLow;
  final double? refHigh;
  final String timing;
  final String note;
  final String source;
  final String labId;
  final String phase;
  final String createdAt;
  final bool qualitative;

  factory BloodTestRow.fromJson(Map<String, dynamic> j) => BloodTestRow(
        marker: j['marker'] as String,
        datetime: j['datetime'] as String,
        value: (j['value'] as num?)?.toDouble() ?? 0,
        unit: (j['unit'] ?? '') as String,
        refLow: (j['ref_low'] as num?)?.toDouble(),
        refHigh: (j['ref_high'] as num?)?.toDouble(),
        timing: (j['timing'] ?? '') as String,
        note: (j['note'] ?? '') as String,
        source: (j['source'] ?? '') as String,
        labId: (j['lab_id'] ?? '') as String,
        phase: (j['phase'] ?? '') as String,
        createdAt: (j['created_at'] ?? '') as String,
        qualitative: j['qualitative'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'marker': marker,
        'datetime': datetime,
        'value': value,
        'unit': unit,
        'ref_low': refLow,
        'ref_high': refHigh,
        'timing': timing,
        'note': note,
        'source': source,
        'lab_id': labId,
        'phase': phase,
        'created_at': createdAt,
        'qualitative': qualitative,
      };
}

enum MarkerStatus { inRange, outOfRange, unknown }

class MarkerSummary {
  const MarkerSummary({
    required this.marker,
    required this.latest,
    required this.previous,
    required this.delta,
    required this.status,
  });
  final String marker;
  final BloodTestRow? latest;
  final BloodTestRow? previous;
  final double? delta;
  final MarkerStatus status;
}

/// One plotted point (post per-date dedup).
class ChartDatum {
  const ChartDatum({
    required this.dateMs,
    required this.value,
    required this.timing,
    required this.inRange,
    required this.unit,
    required this.datetime,
    required this.refLow,
    required this.refHigh,
  });
  final double dateMs;
  final double value;
  final String timing;
  final bool? inRange;
  final String unit;
  final String datetime;
  final double? refLow;
  final double? refHigh;
}

class RefRange {
  const RefRange(this.low, this.high, this.unit);
  final double low;
  final double high;
  final String unit;
}
