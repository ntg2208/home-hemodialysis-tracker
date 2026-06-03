import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../models.dart';

class SessionListItem extends StatelessWidget {
  const SessionListItem({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final preBp = (session.preBpSys != null && session.preBpDia != null)
        ? '${session.preBpSys}/${session.preBpDia}'
        : '—';
    final postBp = (session.postBpSys != null && session.postBpDia != null)
        ? '${session.postBpSys}/${session.postBpDia}'
        : null;
    final bpLabel = postBp != null ? '$preBp → $postBp' : 'BP $preBp';
    final totalUf = session.totalUf != null ? _fmt(session.totalUf!) : null;
    final duration = session.durationMin != null
        ? _formatDur(session.durationMin!)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date + BP
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatDate(session.date),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary)),
                const SizedBox(height: 3),
                Text(bpLabel,
                    style: TextStyle(fontSize: 12, color: t.textMuted)),
              ],
            ),
          ),
          // UF + Duration
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (totalUf != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('UF ', style: TextStyle(fontSize: 12, color: t.textMuted)),
                  Text(totalUf,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.accent)),
                  Text(' L', style: TextStyle(fontSize: 12, color: t.textMuted)),
                ]),
              if (duration != null) ...[
                const SizedBox(height: 2),
                Text('Dur $duration',
                    style: TextStyle(fontSize: 12, color: t.textMuted)),
              ],
              const SizedBox(height: 2),
              Text(session.sessionId,
                  style: hdMono.copyWith(fontSize: 11, color: t.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

String _fmt(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String _formatDur(int min) {
  final h = min ~/ 60;
  final m = min % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

final _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
final _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _formatDate(String iso) {
  try {
    final d = DateTime.parse(iso);
    final day = _weekdays[d.weekday - 1];
    final month = _months[d.month - 1];
    return '$day ${d.day} $month';
  } catch (_) {
    return iso;
  }
}
