import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/blood_tests/csv_import.dart';

void main() {
  const validCsv = '''date,marker,value,unit,ref_low,ref_high,timing,note
2026-06-01,creatinine,980,umol/L,64,104,pre,
2026-06-01,potassium,5.1,mmol/L,3.5,5.1,,fasting''';

  test('parses valid rows', () {
    final result = parseCsvImport(validCsv);
    expect(result.valid.length, 2);
    expect(result.errors, isEmpty);
    expect(result.valid.first.marker, 'creatinine');
    expect(result.valid.first.value, 980.0);
    expect(result.valid.first.timing, 'pre');
  });

  test('rejects row with non-numeric value', () {
    final csv = 'date,marker,value,unit,ref_low,ref_high,timing,note\n2026-06-01,creatinine,abc,umol/L,,,, ';
    final result = parseCsvImport(csv);
    expect(result.valid, isEmpty);
    expect(result.errors.first.reason, contains('numeric'));
  });

  test('rejects row with invalid date', () {
    final csv = 'date,marker,value,unit,ref_low,ref_high,timing,note\nnot-a-date,creatinine,980,umol/L,,,,';
    final result = parseCsvImport(csv);
    expect(result.errors.first.reason, contains('date'));
  });

  test('rejects row with empty marker', () {
    final csv = 'date,marker,value,unit,ref_low,ref_high,timing,note\n2026-06-01,,980,umol/L,,,,';
    final result = parseCsvImport(csv);
    expect(result.errors.first.reason, contains('marker'));
  });

  test('rejects row when ref_low >= ref_high', () {
    final csv = 'date,marker,value,unit,ref_low,ref_high,timing,note\n2026-06-01,creatinine,980,umol/L,104,64,,';
    final result = parseCsvImport(csv);
    expect(result.errors.first.reason, contains('ref_low'));
  });

  test('accepts row with missing optional fields', () {
    final csv = 'date,marker,value,unit,ref_low,ref_high,timing,note\n2026-06-01,myMarker,1.5,,,,,';
    final result = parseCsvImport(csv);
    expect(result.valid.length, 1);
  });
}
