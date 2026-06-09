import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/blood_tests/chart_data.dart';
import 'package:home_hd/features/blood_tests/logic.dart';
import 'package:home_hd/features/blood_tests/models.dart';

BloodTestRow row({
  String marker = 'haemoglobin',
  required String datetime,
  required double value,
  double? lo,
  double? hi,
  String timing = '',
  String phase = 'home-hd',
  String labId = '',
}) =>
    BloodTestRow(
      marker: marker,
      datetime: datetime,
      value: value,
      unit: 'g/L',
      refLow: lo,
      refHigh: hi,
      timing: timing,
      note: '',
      source: 'test',
      labId: labId.isEmpty ? datetime : labId,
      phase: phase,
      createdAt: '',
      qualitative: false,
    );

void main() {
  test('summarize: delta matches timing for dialysis-cleared markers', () {
    // pre and post draws in Jan and Feb — latest=post/Feb, previous must be post/Jan
    final s = summarize('urea', [
      row(datetime: '2026-01-15T08:00:00', value: 18.0, timing: 'pre'),
      row(datetime: '2026-01-15T20:00:00', value: 2.5, timing: 'post'),
      row(datetime: '2026-02-15T08:00:00', value: 16.0, timing: 'pre'),
      row(datetime: '2026-02-15T20:00:00', value: 2.1, timing: 'post'),
    ]);
    expect(s.latest!.timing, 'post');
    expect(s.latest!.value, 2.1);
    expect(s.previous!.timing, 'post');
    expect(s.previous!.value, 2.5);
    expect(s.delta, closeTo(-0.4, 0.0001));
  });

  test('summarize: delta is null when only one row has matching timing', () {
    // Only one pre draw, no previous pre → no delta
    final s = summarize('creatinine', [
      row(datetime: '2026-01-15T12:00:00', value: 900.0, timing: 'post'),
      row(datetime: '2026-02-15T08:00:00', value: 1073.0, timing: 'pre'),
    ]);
    expect(s.latest!.timing, 'pre');
    expect(s.previous, isNull);
    expect(s.delta, isNull);
  });

  test('summarize picks latest/previous, delta, in/out status', () {
    final s = summarize('haemoglobin', [
      row(datetime: '2026-01-01T08:00:00', value: 100, lo: 130, hi: 170),
      row(datetime: '2026-02-01T08:00:00', value: 120, lo: 130, hi: 170),
    ]);
    expect(s.latest!.value, 120);
    expect(s.previous!.value, 100);
    expect(s.delta, 20);
    expect(s.status, MarkerStatus.outOfRange); // 120 < 130
  });

  test('filterRows respects phase and from/to at bound granularity', () {
    final rows = [
      row(datetime: '2026-01-15T08:00:00', value: 1, phase: 'home-hd'),
      row(datetime: '2026-03-15T08:00:00', value: 2, phase: 'in-center-hd'),
      row(datetime: '2026-04-15T08:00:00', value: 3, phase: 'home-hd'),
    ];
    expect(filterRows(rows, phase: ['home-hd']).length, 2);
    expect(filterRows(rows, from: '2026-03').length, 2); // Mar + Apr
    expect(filterRows(rows, from: '2026-02', to: '2026-03').length, 1);
  });

  test('mergeRows: incoming wins on lab_id+marker key', () {
    final a = [row(datetime: '2026-01-01T00:00:00', value: 1, labId: 'L1')];
    final b = [row(datetime: '2026-01-01T00:00:00', value: 9, labId: 'L1')];
    final merged = mergeRows(a, b);
    expect(merged.length, 1);
    expect(merged.first.value, 9);
  });

  test('computeFetchRange backfills only the older uncovered slice', () {
    expect(computeFetchRange(null, '2025-01'), (from: '2025-01', to: null));
    expect(computeFetchRange('2026-01', '2026-03'), isNull); // inside coverage
    expect(computeFetchRange('2026-01', '2025-06'),
        (from: '2025-06', to: '2026-01'));
  });

  test('toSeries dedups per date with pre>post>plain priority', () {
    final series = toSeries([
      row(datetime: '2026-01-01T08:00:00', value: 50, timing: 'post'),
      row(datetime: '2026-01-01T07:00:00', value: 40, timing: 'pre'),
      row(datetime: '2026-01-02T08:00:00', value: 60, timing: ''),
    ]);
    expect(series.length, 2);
    expect(series.first.value, 40); // pre beat post on day 1
    expect(series.first.timing, 'pre');
  });
}
