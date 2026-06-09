import 'package:csv/csv.dart';

import 'models.dart';

class CsvParseResult {
  const CsvParseResult({required this.valid, required this.errors});
  final List<BloodTestRow> valid;
  final List<CsvRowError> errors;
}

class CsvRowError {
  const CsvRowError({required this.rowIndex, required this.rawRow, required this.reason});
  final int rowIndex;
  final List<String> rawRow;
  final String reason;
}

CsvParseResult parseCsvImport(String csvText) {
  final lines = const CsvToListConverter(eol: '\n').convert(csvText);
  if (lines.isEmpty) return const CsvParseResult(valid: [], errors: []);

  final header = lines.first.map((c) => c.toString().trim().toLowerCase()).toList();
  final idx = {for (var i = 0; i < header.length; i++) header[i]: i};

  int col(String name) => idx[name] ?? -1;
  String cell(List row, String name) {
    final i = col(name);
    return i >= 0 && i < row.length ? row[i].toString().trim() : '';
  }

  final valid = <BloodTestRow>[];
  final errors = <CsvRowError>[];

  for (var i = 1; i < lines.length; i++) {
    final row = lines[i];
    final raw = row.map((c) => c.toString()).toList();

    final dateStr = cell(row, 'date');
    final marker  = cell(row, 'marker');
    final valStr  = cell(row, 'value');
    final unit    = cell(row, 'unit');
    final refLowStr  = cell(row, 'ref_low');
    final refHighStr = cell(row, 'ref_high');
    final timing  = cell(row, 'timing');
    final note    = cell(row, 'note');

    if (marker.isEmpty) {
      errors.add(CsvRowError(rowIndex: i, rawRow: raw, reason: 'marker name is required'));
      continue;
    }

    DateTime date;
    try {
      date = DateTime.parse(dateStr);
    } catch (_) {
      errors.add(CsvRowError(rowIndex: i, rawRow: raw, reason: 'invalid date "$dateStr" — use YYYY-MM-DD'));
      continue;
    }

    final value = double.tryParse(valStr);
    if (value == null) {
      errors.add(CsvRowError(rowIndex: i, rawRow: raw, reason: 'value must be numeric, got "$valStr"'));
      continue;
    }

    final refLow  = refLowStr.isEmpty  ? null : double.tryParse(refLowStr);
    final refHigh = refHighStr.isEmpty ? null : double.tryParse(refHighStr);

    if (refLow != null && refHigh != null && refLow >= refHigh) {
      errors.add(CsvRowError(rowIndex: i, rawRow: raw, reason: 'ref_low ($refLow) must be less than ref_high ($refHigh)'));
      continue;
    }

    valid.add(BloodTestRow(
      marker: marker,
      datetime: '${date.toIso8601String().substring(0, 10)}T09:00:00.000Z',
      value: value,
      unit: unit,
      refLow: refLow,
      refHigh: refHigh,
      timing: timing,
      note: note,
      source: 'csv_import',
      labId: '',
      phase: '',
      createdAt: DateTime.now().toIso8601String().substring(0, 10),
      qualitative: false,
    ));
  }

  return CsvParseResult(valid: valid, errors: errors);
}

const csvImportTemplate =
    'date,marker,value,unit,ref_low,ref_high,timing,note\n'
    '2026-06-01,creatinine,980,umol/L,64,104,pre,\n'
    '2026-06-01,urea,18.2,mmol/L,2.5,7.8,pre,\n'
    '2026-06-01,potassium,5.1,mmol/L,3.5,5.1,,\n';
