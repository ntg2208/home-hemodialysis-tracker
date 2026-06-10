import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/blood_tests/models.dart';
import 'package:home_hd/features/chat/retriever_tools.dart';
import 'package:home_hd/features/treatment/models.dart';

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

    test('skips rows with empty or malformed datetime without crashing', () {
      final badRow = _btRow(marker: 'phosphate', datetime: '', value: 1.5, refLow: 0.8, refHigh: 1.5);
      final retriever = RetrieverTools(sessions: [], readings: [], bloodTestRows: [badRow], now: fixedNow);
      final result = retriever.getBloodMarkers(['phosphate'], 2);
      final rowList = ((result['results'] as List)[0] as Map)['rows'] as List;
      expect(rowList.isEmpty, true);
    });

    test('row at exact cutoff boundary is included', () {
      // cutoff for monthsBack=1 from 2026-06-10 is 2026-05-01
      final boundaryRow = _btRow(marker: 'phosphate', datetime: '2026-05-01T00:00:00', value: 1.2, refLow: 0.8, refHigh: 1.5);
      final retriever = RetrieverTools(sessions: [], readings: [], bloodTestRows: [boundaryRow], now: fixedNow);
      final result = retriever.getBloodMarkers(['phosphate'], 1);
      final rowList = ((result['results'] as List)[0] as Map)['rows'] as List;
      expect(rowList.length, 1);
    });

    test('row map contains all expected fields', () {
      final row = _btRow(marker: 'potassium', datetime: '2026-05-18T14:00:00', value: 4.2, refLow: 3.5, refHigh: 5.0, timing: 'pre');
      final retriever = RetrieverTools(sessions: [], readings: [], bloodTestRows: [row], now: fixedNow);
      final result = retriever.getBloodMarkers(['potassium'], 12);
      final rowMap = (((result['results'] as List)[0] as Map)['rows'] as List)[0] as Map;
      expect(rowMap['date'], '2026-05-18');
      expect(rowMap['value'], 4.2);
      expect(rowMap['unit'], 'mmol/L');
      expect(rowMap['ref_low'], 3.5);
      expect(rowMap['ref_high'], 5.0);
      expect(rowMap['in_range'], true);
      expect(rowMap['timing'], 'pre');
    });
  });

  group('getSessions', () {
    Session session(String date, {double? preW, double? postW,
        int? preSys, int? preDia, int? postSys, int? postDia,
        double? ufGoal, double? totalUf, int? durationMin}) =>
        Session(
          sessionId: date,
          date: date,
          preWeight: preW,
          postWeight: postW,
          preBpSys: preSys,
          preBpDia: preDia,
          postBpSys: postSys,
          postBpDia: postDia,
          ufGoal: ufGoal,
          totalUf: totalUf,
          durationMin: durationMin,
        );

    final sessions = [
      session('2026-06-09', preW: 61.0, postW: 59.4, preSys: 117, preDia: 89,
          postSys: 112, postDia: 78, ufGoal: 2.0, totalUf: 1.6, durationMin: 255),
      session('2026-06-07', preW: 60.5, postW: 59.0, preSys: 120, preDia: 80,
          postSys: 115, postDia: 75, ufGoal: 1.5, totalUf: 1.5, durationMin: 255),
      session('2026-06-05'),
      session('2026-06-03'),
      session('2026-06-01'),
      session('2026-05-30'),
      session('2026-05-28'),
      session('2026-05-26'),
    ];

    RetrieverTools makeRetriever() =>
        RetrieverTools(sessions: sessions, readings: [], bloodTestRows: [], now: fixedNow);

    test('last_n returns N most recent sessions, newest first', () {
      final result = makeRetriever().getSessions(lastN: 3);
      final list = result['sessions'] as List;
      expect(list.length, 3);
      expect((list[0] as Map)['date'], '2026-06-09');
      expect((list[1] as Map)['date'], '2026-06-07');
      expect(result['count'], 3);
    });

    test('default last_n is 7', () {
      final result = makeRetriever().getSessions();
      expect((result['sessions'] as List).length, 7);
    });

    test('last_n is clamped to 30', () {
      final result = makeRetriever().getSessions(lastN: 999);
      expect((result['sessions'] as List).length, sessions.length); // only 8 exist
    });

    test('from/to date range filters correctly', () {
      final result = makeRetriever().getSessions(from: '2026-06-01', to: '2026-06-07');
      final dates = (result['sessions'] as List).map((s) => (s as Map)['date']).toList();
      expect(dates, containsAll(['2026-06-01', '2026-06-05', '2026-06-07']));
      expect(dates, isNot(contains('2026-05-30')));
      expect(dates, isNot(contains('2026-06-09')));
    });

    test('from/to wins when both from/to and lastN provided', () {
      final result = makeRetriever().getSessions(lastN: 2, from: '2026-05-26', to: '2026-05-30');
      final list = result['sessions'] as List;
      expect(list.length, 3); // May sessions: 2026-05-26, 2026-05-28, 2026-05-30
    });

    test('weight_removed is computed correctly', () {
      final result = makeRetriever().getSessions(lastN: 1);
      final session = (result['sessions'] as List)[0] as Map;
      expect(session['weight_removed'], closeTo(1.6, 0.01));
    });

    test('uf_achievement_pct is computed correctly', () {
      final result = makeRetriever().getSessions(lastN: 1);
      final session = (result['sessions'] as List)[0] as Map;
      expect(session['uf_achievement_pct'], 80); // 1.6/2.0 = 80%
    });

    test('pre_bp formatted as sys/dia string', () {
      final result = makeRetriever().getSessions(lastN: 1);
      final session = (result['sessions'] as List)[0] as Map;
      expect(session['pre_bp'], '117/89');
      expect(session['post_bp'], '112/78');
    });

    test('null bp/weight fields are null in output', () {
      final result = makeRetriever().getSessions(from: '2026-06-05', to: '2026-06-05');
      final session = (result['sessions'] as List)[0] as Map;
      expect(session['pre_bp'], isNull);
      expect(session['pre_weight'], isNull);
    });

    test('include_readings: false gives empty readings array', () {
      final result = makeRetriever().getSessions(lastN: 1);
      final session = (result['sessions'] as List)[0] as Map;
      expect((session['readings'] as List).isEmpty, true);
    });
  });

  group('getOutOfRangeMarkers', () {
    test('returns empty result when no rows', () {
      final retriever = RetrieverTools(sessions: [], readings: [], bloodTestRows: [], now: fixedNow);
      final result = retriever.getOutOfRangeMarkers();
      expect(result['draw_date'], isNull);
      expect((result['out_of_range'] as List).isEmpty, true);
      expect(result['total_markers_checked'], 0);
    });

    test('identifies the most recent draw date', () {
      final rows = [
        _btRow(marker: 'phosphate', datetime: '2026-05-18T14:00:00', value: 1.9, refLow: 0.8, refHigh: 1.5),
        _btRow(marker: 'potassium', datetime: '2026-04-15T14:00:00', value: 4.2, refLow: 3.5, refHigh: 5.0),
      ];
      final result = RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow)
          .getOutOfRangeMarkers();
      expect(result['draw_date'], '2026-05-18');
    });

    test('flags marker with value above refHigh as high', () {
      final rows = [
        _btRow(marker: 'phosphate', datetime: '2026-05-18T14:00:00', value: 1.9, refLow: 0.8, refHigh: 1.5),
      ];
      final result = RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow)
          .getOutOfRangeMarkers();
      final flagged = (result['out_of_range'] as List)[0] as Map;
      expect(flagged['marker'], 'phosphate');
      expect(flagged['direction'], 'high');
    });

    test('flags marker with value below refLow as low', () {
      final rows = [
        _btRow(marker: 'potassium', datetime: '2026-05-18T14:00:00', value: 2.0, refLow: 3.5, refHigh: 5.0),
      ];
      final result = RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow)
          .getOutOfRangeMarkers();
      final flagged = (result['out_of_range'] as List)[0] as Map;
      expect(flagged['direction'], 'low');
    });

    test('skips markers with both bounds null (e.g. intact_pth)', () {
      final rows = [
        _btRow(marker: 'intact_pth', datetime: '2026-05-18T14:00:00', value: 99.0),
        _btRow(marker: 'phosphate',  datetime: '2026-05-18T14:00:00', value: 1.9, refLow: 0.8, refHigh: 1.5),
      ];
      final result = RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow)
          .getOutOfRangeMarkers();
      expect(result['total_markers_checked'], 1); // intact_pth excluded
    });

    test('prefers pre row over post when both exist on same date', () {
      final rows = [
        _btRow(marker: 'potassium', datetime: '2026-05-18T14:00:00', value: 4.2,
            refLow: 3.5, refHigh: 5.0, timing: 'post'), // in range
        _btRow(marker: 'potassium', datetime: '2026-05-18T12:00:00', value: 6.5,
            refLow: 3.5, refHigh: 5.0, timing: 'pre'),  // out of range (high)
      ];
      final result = RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow)
          .getOutOfRangeMarkers();
      // pre row used: 6.5 > 5.0 → flagged high
      final flagged = result['out_of_range'] as List;
      expect(flagged.length, 1);
      expect((flagged[0] as Map)['direction'], 'high');
    });

    test('in-range markers are not included in out_of_range', () {
      final rows = [
        _btRow(marker: 'potassium', datetime: '2026-05-18T14:00:00', value: 4.2, refLow: 3.5, refHigh: 5.0),
      ];
      final result = RetrieverTools(sessions: [], readings: [], bloodTestRows: rows, now: fixedNow)
          .getOutOfRangeMarkers();
      expect((result['out_of_range'] as List).isEmpty, true);
      expect(result['total_markers_checked'], 1);
    });
  });
}
