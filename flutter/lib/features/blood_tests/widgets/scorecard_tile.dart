import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../markers.dart';
import '../models.dart';

class ScorecardTile extends StatelessWidget {
  const ScorecardTile({
    super.key,
    required this.summary,
    required this.starred,
    required this.onSelect,
    required this.onToggleStar,
  });

  final MarkerSummary summary;
  final bool starred;
  final VoidCallback onSelect;
  final VoidCallback onToggleStar;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final latest = summary.latest;
    final borderColor = switch (summary.status) {
      MarkerStatus.inRange => t.good,
      MarkerStatus.outOfRange => t.danger,
      MarkerStatus.unknown => t.border,
    };
    final valueColor = switch (summary.status) {
      MarkerStatus.outOfRange => t.danger,
      _ => t.textPrimary,
    };
    final refRange = (latest?.refLow != null && latest?.refHigh != null)
        ? '${_n(latest!.refLow!)}–${_n(latest.refHigh!)} ${latest.unit}'
        : null;

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: borderColor, width: 4)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName(summary.marker),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: t.textPrimary)),
                  if (latest != null)
                    Text(_fmtDate(latest.datetime),
                        style: TextStyle(fontSize: 11, color: t.textMuted)),
                  if (refRange != null)
                    Text(refRange,
                        style: TextStyle(fontSize: 11, color: t.textMuted)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(latest != null ? '${_n(latest.value)} ${latest.unit}' : '—',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: valueColor)),
                if (summary.delta != null && summary.previous != null)
                  Text(_fmtDelta(summary.delta!, summary.previous!.value),
                      style: TextStyle(fontSize: 11, color: t.textMuted)),
              ],
            ),
            IconButton(
              onPressed: onToggleStar,
              visualDensity: VisualDensity.compact,
              icon: Icon(starred ? Icons.star : Icons.star_border,
                  size: 16,
                  color: starred ? t.warning : t.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String _fmtDelta(double delta, double prev) {
  final sign = delta >= 0 ? '+' : '−';
  return '$sign${_n(delta.abs())} from ${_n(prev)}';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _fmtDate(String datetime) {
  final d = DateTime.tryParse(datetime);
  if (d == null) return datetime;
  return '${d.day} ${_months[d.month - 1]} ${d.year % 100}';
}
