import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../models.dart';

/// Trend-tab results table: Date, Value, Range, Flag, Timing, Note (newest first).
class ResultsTable extends StatelessWidget {
  const ResultsTable({super.key, required this.rows});
  final List<BloodTestRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    if (rows.isEmpty) return const SizedBox.shrink();
    final sorted = [...rows]..sort((a, b) => b.datetime.compareTo(a.datetime));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      child: DataTable(
        headingRowHeight: 32,
        dataRowMinHeight: 30,
        dataRowMaxHeight: 44,
        columnSpacing: 20,
        headingTextStyle: TextStyle(
            fontSize: 11, color: t.textMuted, fontWeight: FontWeight.w600),
        dataTextStyle: TextStyle(fontSize: 13, color: t.textSecondary),
        columns: const [
          DataColumn(label: Text('DATE')),
          DataColumn(label: Text('VALUE')),
          DataColumn(label: Text('RANGE')),
          DataColumn(label: Text('FLAG')),
          DataColumn(label: Text('TIMING')),
          DataColumn(label: Text('NOTE')),
        ],
        rows: sorted.map((r) {
          final hasRange = r.refLow != null && r.refHigh != null;
          final String? flag = (r.qualitative || !hasRange)
              ? null
              : (r.value >= r.refLow! && r.value <= r.refHigh!) ? 'in' : 'out';
          final flagColor = flag == 'out'
              ? t.danger
              : flag == 'in'
                  ? t.good
                  : t.textMuted;
          return DataRow(cells: [
            DataCell(Text(r.datetime
                .substring(0, r.datetime.length.clamp(0, 16))
                .replaceFirst('T', ' '))),
            DataCell(Text(r.qualitative ? r.unit : '${_n(r.value)} ${r.unit}')),
            DataCell(Text(hasRange ? '${_n(r.refLow!)}–${_n(r.refHigh!)}' : '—')),
            DataCell(Text(flag ?? '—', style: TextStyle(color: flagColor))),
            DataCell(Text(r.timing.isEmpty ? '—' : r.timing)),
            DataCell(Text(r.note.isEmpty ? '—' : r.note)),
          ]);
        }).toList(),
      ),
    );
  }
}

String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
