import 'dart:ui';

import 'models.dart';

/// Port of lib/chartData.ts.

// pre = cyan, post = amber, plain = indigo (mode-agnostic accent hues).
const _preColor = Color(0xFF22D3EE);
const _postColor = Color(0xFFF59E0B);
const _plainColor = Color(0xFF818CF8);

Color pointColor(String timing) => switch (timing) {
      'pre' => _preColor,
      'post' => _postColor,
      _ => _plainColor,
    };

const lineColor = _plainColor;

/// Latest row that has a reference range (drives the shaded band).
RefRange? getReferenceRange(List<BloodTestRow> rows) {
  final withRange = rows
      .where((r) => r.refLow != null && r.refHigh != null)
      .toList()
    ..sort((a, b) => b.datetime.compareTo(a.datetime));
  if (withRange.isEmpty) return null;
  final r = withRange.first;
  return RefRange(r.refLow!, r.refHigh!, r.unit);
}

// Same-day dedup priority: pre beats post beats plain.
const _timingRank = <String, int>{'pre': 0, 'post': 1, '': 2};

/// One representative datum per calendar date, sorted ascending by datetime.
List<ChartDatum> toSeries(List<BloodTestRow> rows) {
  final byDate = <String, BloodTestRow>{};
  for (final r in rows.where((r) => !r.qualitative)) {
    final dateKey = r.datetime.substring(0, 10);
    final existing = byDate[dateKey];
    final rank = _timingRank[r.timing] ?? 2;
    if (existing == null || rank < (_timingRank[existing.timing] ?? 2)) {
      byDate[dateKey] = r;
    }
  }

  final sorted = byDate.values.toList()
    ..sort((a, b) => a.datetime.compareTo(b.datetime));

  return sorted.map((r) {
    final inRange = (r.refLow != null && r.refHigh != null)
        ? (r.value >= r.refLow! && r.value <= r.refHigh!)
        : null;
    return ChartDatum(
      dateMs: (DateTime.tryParse(r.datetime) ?? DateTime(2000))
          .millisecondsSinceEpoch
          .toDouble(),
      value: r.value,
      timing: r.timing,
      inRange: inRange,
      unit: r.unit,
      datetime: r.datetime,
      refLow: r.refLow,
      refHigh: r.refHigh,
    );
  }).toList();
}
