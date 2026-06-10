import '../blood_tests/models.dart';
import '../treatment/models.dart';

class RetrieverTools {
  RetrieverTools({
    required this.sessions,
    required this.readings,
    required this.bloodTestRows,
    DateTime? now,
  }) : _now = now ?? DateTime.now();

  final List<Session> sessions;
  final List<Reading> readings;
  final List<BloodTestRow> bloodTestRows;
  final DateTime _now;

  Map<String, dynamic> getBloodMarkers(List<String> markers, int monthsBack) {
    final cutoff = DateTime(_now.year, _now.month - monthsBack, 1);

    final results = markers.map((marker) {
      final parsed = bloodTestRows
          .where((r) => r.marker == marker)
          .map((r) => (r, DateTime.tryParse(r.datetime)))
          .where((pair) => pair.$2 != null && !pair.$2!.isBefore(cutoff))
          .toList()
        ..sort((a, b) => b.$2!.compareTo(a.$2!));

      return {
        'marker': marker,
        'rows': parsed
            .map((pair) {
              final r = pair.$1;
              final dt = pair.$2!;
              return {
                'date':
                    '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}',
                'value': r.value,
                'unit': r.unit,
                'ref_low': r.refLow,
                'ref_high': r.refHigh,
                'in_range': _inRange(r.value, r.refLow, r.refHigh),
                'timing': r.timing,
              };
            })
            .toList(),
      };
    }).toList();

    return {'results': results};
  }

  Map<String, dynamic> getSessions(
          {int? lastN, String? from, String? to, bool includeReadings = false}) =>
      {'sessions': <dynamic>[], 'count': 0};

  Map<String, dynamic> getOutOfRangeMarkers() =>
      {'draw_date': null, 'out_of_range': <dynamic>[], 'total_markers_checked': 0};

  bool _inRange(double value, double? refLow, double? refHigh) {
    if (refLow != null && value < refLow) return false;
    if (refHigh != null && value > refHigh) return false;
    return true;
  }
}
