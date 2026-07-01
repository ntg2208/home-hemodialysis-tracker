import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../treatment/providers.dart';
import '../treatment/timer_prefs.dart';

/// Settings control for the default treatment (countdown) duration used when a
/// new session has no per-session target. Patients set their own prescribed
/// session length here once; it can still be overridden per session.
class TimerSettingsSection extends ConsumerWidget {
  const TimerSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.hd;
    final prefs = ref.watch(timerPrefsProvider);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Default treatment duration',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary)),
              const SizedBox(height: 2),
              Text('Countdown target for a new session',
                  style: TextStyle(fontSize: 12, color: t.textMuted)),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: () => _edit(context, ref, prefs),
          child: Text(_format(prefs.defaultTargetMin)),
        ),
      ],
    );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, TimerPrefs prefs) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _DurationDialog(targetMin: prefs.defaultTargetMin),
    );
    if (result != null && result > 0) {
      await ref
          .read(timerPrefsProvider.notifier)
          .update(prefs.copyWith(defaultTargetMin: result));
    }
  }

  static String _format(int min) {
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

class _DurationDialog extends StatefulWidget {
  const _DurationDialog({required this.targetMin});
  final int targetMin;
  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  late int _h = widget.targetMin ~/ 60;
  late int _m = widget.targetMin % 60;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Default treatment duration'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _numBox(_h, 0, 23, (v) => _h = v),
          const Padding(padding: EdgeInsets.all(8), child: Text('h')),
          _numBox(_m, 0, 59, (v) => _m = v),
          const Padding(padding: EdgeInsets.all(8), child: Text('m')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _h * 60 + _m),
          child: const Text('Set'),
        ),
      ],
    );
  }

  Widget _numBox(int value, int min, int max, ValueChanged<int> onChange) =>
      SizedBox(
        width: 56,
        child: TextFormField(
          initialValue: '$value',
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          onChanged: (raw) {
            final n = int.tryParse(raw);
            if (n != null) onChange(n.clamp(min, max));
          },
        ),
      );
}
