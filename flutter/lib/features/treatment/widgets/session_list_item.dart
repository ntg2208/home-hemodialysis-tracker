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
        : '—';
    final totalUf = session.totalUf != null ? _fmt(session.totalUf!) : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined, size: 18, color: t.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.sessionId,
                    style: hdMono.copyWith(
                        fontSize: 14, color: t.textPrimary)),
                const SizedBox(height: 2),
                Text('BP $preBp → $postBp',
                    style: TextStyle(fontSize: 12, color: t.textMuted)),
              ],
            ),
          ),
          Icon(Icons.water_drop_outlined, size: 14, color: t.accent),
          const SizedBox(width: 4),
          Text(totalUf, style: TextStyle(fontSize: 14, color: t.textSecondary)),
        ],
      ),
    );
  }
}

String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
