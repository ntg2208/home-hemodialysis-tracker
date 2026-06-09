import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/blood_tests/marker_definitions.dart';

void main() {
  test('marker list has at least 40 entries', () {
    expect(markerDefinitions.length, greaterThanOrEqualTo(40));
  });

  test('all markers have non-empty name and displayName', () {
    for (final m in markerDefinitions) {
      expect(m.name.isNotEmpty, isTrue, reason: 'name empty');
      expect(m.displayName.isNotEmpty, isTrue, reason: 'displayName empty for ${m.name}');
    }
  });

  test('creatinine entry has expected defaults', () {
    final cr = markerDefinitions.firstWhere((m) => m.name == 'creatinine');
    expect(cr.defaultUnit, 'umol/L');
    expect(cr.refLow, isNotNull);
    expect(cr.refHigh, isNotNull);
  });

  test('list is sorted A-Z by displayName', () {
    final names = markerDefinitions.map((m) => m.displayName.toLowerCase()).toList();
    final sorted = [...names]..sort();
    expect(names, sorted);
  });
}
