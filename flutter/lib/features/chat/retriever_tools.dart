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
      final markerRows = bloodTestRows
          .where((r) {
            if (r.marker != marker) return false;
            final dt = DateTime.tryParse(r.datetime);
            return dt != null && !dt.isBefore(cutoff);
          })
          .toList()
        ..sort((a, b) {
          final dtA = DateTime.tryParse(a.datetime)!;
          final dtB = DateTime.tryParse(b.datetime)!;
          return dtB.compareTo(dtA);
        });

      return {
        'marker': marker,
        'rows': markerRows
            .map((r) => {
                  'date': r.datetime.substring(0, 10),
                  'value': r.value,
                  'unit': r.unit,
                  'ref_low': r.refLow,
                  'ref_high': r.refHigh,
                  'in_range': _inRange(r.value, r.refLow, r.refHigh),
                  'timing': r.timing,
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
