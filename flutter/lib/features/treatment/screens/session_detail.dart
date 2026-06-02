import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../models.dart';
import '../providers.dart';

/// Opens the session detail as a bottom-sheet popup. Resolves to `true` if the
/// session was deleted (so Home can refresh), otherwise null.
Future<bool?> showSessionDetailSheet(BuildContext context, Session session) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SessionDetailSheet(session: session),
  );
}

/// Read-only detail of a past session: pre values, intra-session readings, post
/// values, plus Delete.
class SessionDetailSheet extends ConsumerStatefulWidget {
  const SessionDetailSheet({super.key, required this.session});
  final Session session;

  @override
  ConsumerState<SessionDetailSheet> createState() => _SessionDetailSheetState();
}

class _SessionDetailSheetState extends ConsumerState<SessionDetailSheet> {
  List<Reading>? _readings;
  bool _error = false;
  bool _deleting = false;

  Session get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _loadReadings();
  }

  Future<void> _loadReadings() async {
    setState(() => _error = false);
    try {
      final r = await ref.read(treatmentRepoProvider).getReadings(_s.sessionId);
      if (mounted) setState(() => _readings = r);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _delete() async {
    final t = context.hd;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session'),
        content: Text(
            'Delete session ${_s.sessionId} and all its readings? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: t.danger, foregroundColor: t.accentOn),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _deleting = true);
    try {
      await ref.read(treatmentRepoProvider).deleteSession(_s.sessionId);
      if (mounted) Navigator.pop(context, true); // signal Home to refresh
    } catch (_) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Delete failed — try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Container(
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: t.textMuted, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(children: [
                Text('Session  ',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary)),
                Text(_s.sessionId,
                    style: hdMono.copyWith(fontSize: 15, color: t.textSecondary)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: t.textSecondary),
                ),
              ]),
            ),
            Divider(height: 1, color: t.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _card(t, 'PRE-TREATMENT', [
                    _kv(t, 'Weight', _u(_s.preWeight, 'kg')),
                    _kv(t, 'UF goal', _u(_s.ufGoal, 'L')),
                    _kv(t, 'UF rate', _u(_s.ufRate, 'mL/h')),
                    _kv(t, 'BP', _bp(_s.preBpSys, _s.preBpDia)),
                    _kv(t, 'Pulse', _u(_s.prePulse, 'bpm')),
                  ]),
                  const SizedBox(height: 12),
                  _readingsSection(t),
                  const SizedBox(height: 12),
                  _card(t, 'POST-TREATMENT', [
                    _kv(t, 'Weight', _u(_s.postWeight, 'kg')),
                    _kv(t, 'BP', _bp(_s.postBpSys, _s.postBpDia)),
                    _kv(t, 'Pulse', _u(_s.postPulse, 'bpm')),
                    _kv(t, 'Duration',
                        _s.durationMin == null ? '—' : '${_s.durationMin} min'),
                    _kv(t, 'Dialysate', _u(_s.dialysateVolume, 'L')),
                    _kv(t, 'Total UF', _u(_s.totalUf, 'L')),
                    _kv(t, 'Blood processed', _u(_s.bloodProcessed, 'L')),
                  ]),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _deleting ? null : _delete,
                    icon: _deleting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: t.danger))
                        : const Icon(Icons.delete_outline),
                    label: Text(_deleting ? 'Deleting…' : 'Delete session'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: t.danger,
                        side: BorderSide(color: t.danger)),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readingsSection(HdTokens t) {
    final readings = _readings;
    return _card(t, 'READINGS', [
      if (_error)
        Row(children: [
          Expanded(
              child: Text('Could not load readings.',
                  style: TextStyle(color: t.danger, fontSize: 13))),
          TextButton(onPressed: _loadReadings, child: const Text('Retry')),
        ])
      else if (readings == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Loading…', style: TextStyle(color: t.textMuted)),
        )
      else if (readings.isEmpty)
        Text('No readings.', style: TextStyle(color: t.textMuted))
      else
        ...readings.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.time, style: hdMono.copyWith(color: t.textSecondary)),
                  Text(
                    'BP ${r.bpSys ?? '–'}/${r.bpDia ?? '–'} · pulse ${r.pulse ?? '–'} · '
                    'BF ${r.bloodFlow ?? '–'} · VP ${r.venousPressure ?? '–'} · '
                    'AP ${r.arterialPressure ?? '–'}',
                    style: TextStyle(color: t.textSecondary, fontSize: 13),
                  ),
                  if (r.note != null && r.note!.isNotEmpty)
                    Text(r.note!,
                        style: TextStyle(
                            color: t.textMuted,
                            fontSize: 13,
                            fontStyle: FontStyle.italic)),
                ],
              ),
            )),
    ]);
  }

  Widget _card(HdTokens t, String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.panel,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 11, letterSpacing: 1, color: t.textMuted)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );

  Widget _kv(HdTokens t, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
                child: Text(k,
                    style: TextStyle(color: t.textSecondary, fontSize: 13))),
            Text(v, style: TextStyle(color: t.textPrimary, fontSize: 13)),
          ],
        ),
      );

  String _u(num? v, String unit) =>
      v == null ? '—' : '${v == v.roundToDouble() ? v.toInt() : v} $unit';
  String _bp(int? s, int? d) =>
      (s == null && d == null) ? '—' : '${s ?? '–'}/${d ?? '–'}';
}
