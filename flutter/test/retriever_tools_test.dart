import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/blood_tests/models.dart';
import 'package:home_hd/features/chat/retriever_tools.dart';

BloodTestRow _btRow({
  required String marker,
  required String datetime,
  required double value,
  double? refLow,
  double? refHigh,
  String timing = '',
}) =>
    BloodTestRow(
      marker: marker,
      datetime: datetime,
      value: value,
      unit: 'mmol/L',
      refLow: refLow,
      refHigh: refHigh,
      timing: timing,
      note: '',
      source: '',
      labId: 'lab1',
      phase: 'home-hd',
      createdAt: '',
      qualitative: false,
    );

void main() {
  final fixedNow = DateTime(2026, 6, 10);

  group('getBloodMarkers', () {
    final rows = [
      _btRow(marker: 'phosphate', datetime: '2026-05-18T14:00:00', value: 1.9, refLow: 0.8, refHigh: 1.5),
      _btRow(marker: 'phosphate', datetime: '2026-04-15T14:00:00', value: 1.6, refLow: 0.8, refHigh: 1.5),
      _btRow(marker: 'potassium', datetime: '2026-05-18T14:00:00', value: 4.2, refLow: 3.5, refHigh: 5.0),
      _btRow(marker: 'egfr',      datetime: '2026-05-18T14:00:00', value: 5.0),
    ];

    RetrieverTools makeRetriever() =>
        RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow);

    test('returns one result object per requested marker', () {
      final result = makeRetriever().getBloodMarkers(['phosphate', 'potassium'], 12);
      final results = result['results'] as List;
      expect(results.length, 2);
      expect((results[0] as Map)['marker'], 'phosphate');
      expect((results[1] as Map)['marker'], 'potassium');
    });

    test('rows are sorted newest-first', () {
      final result = makeRetriever().getBloodMarkers(['phosphate'], 12);
      final rows = ((result['results'] as List)[0] as Map)['rows'] as List;
      expect((rows[0] as Map)['date'], '2026-05-18');
      expect((rows[1] as Map)['date'], '2026-04-15');
    });

    test('months_back excludes rows older than cutoff', () {
      final result = makeRetriever().getBloodMarkers(['phosphate'], 1);
      final rowList = ((result['results'] as List)[0] as Map)['rows'] as List;
      expect(rowList.length, 1);
      expect((rowList[0] as Map)['date'], '2026-05-18');
    });

    test('unknown marker returns empty rows array', () {
      final result = makeRetriever().getBloodMarkers(['unknown'], 12);
      final rowList = ((result['results'] as List)[0] as Map)['rows'] as List;
      expect(rowList.isEmpty, true);
    });

    test('in_range is true when both ref bounds are null', () {
      final result = makeRetriever().getBloodMarkers(['egfr'], 12);
      final row = (((result['results'] as List)[0] as Map)['rows'] as List)[0] as Map;
      expect(row['in_range'], true);
    });

    test('in_range is false when value exceeds refHigh', () {
      final result = makeRetriever().getBloodMarkers(['phosphate'], 12);
      final row = (((result['results'] as List)[0] as Map)['rows'] as List)[0] as Map;
      expect(row['in_range'], false);
    });

    test('in_range is false when value is below refLow', () {
      final lowRow = _btRow(marker: 'potassium', datetime: '2026-05-01T00:00:00', value: 2.0, refLow: 3.5, refHigh: 5.0);
      final retriever = RetrieverTools(sessions: [], readings: [], bloodTestRows: [lowRow], now: fixedNow);
      final result = retriever.getBloodMarkers(['potassium'], 12);
      final row = (((result['results'] as List)[0] as Map)['rows'] as List)[0] as Map;
      expect(row['in_range'], false);
    });
  });
}
