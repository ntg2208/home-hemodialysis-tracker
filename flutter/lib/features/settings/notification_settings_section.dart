import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../treatment/notification_prefs.dart';
import '../treatment/providers.dart';

class NotificationSettingsSection extends ConsumerStatefulWidget {
  const NotificationSettingsSection({super.key});

  @override
  ConsumerState<NotificationSettingsSection> createState() =>
      _NotificationSettingsSectionState();
}

class _NotificationSettingsSectionState
    extends ConsumerState<NotificationSettingsSection> {
  final _addCtrl = TextEditingController();
  String? _addError;

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  void _add(NotificationPrefs prefs) {
    final v = int.tryParse(_addCtrl.text.trim());
    if (v == null || v <= 0 || v > 480) {
      setState(() => _addError = 'Enter a number between 1 and 480');
      return;
    }
    if (prefs.alertMins.contains(v)) {
      setState(() => _addError = '$v min is already in the list');
      return;
    }
    final updated = [...prefs.alertMins, v];
    ref.read(notificationPrefsProvider.notifier).update(
          prefs.copyWith(alertMins: updated),
        );
    _addCtrl.clear();
    setState(() => _addError = null);
  }

  void _remove(NotificationPrefs prefs, int m) {
    final updated = prefs.alertMins.where((x) => x != m).toList();
    ref.read(notificationPrefsProvider.notifier).update(
          prefs.copyWith(alertMins: updated),
        );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final prefs = ref.watch(notificationPrefsProvider);
    final notifier = ref.read(notificationPrefsProvider.notifier);
    final sorted = [...prefs.alertMins]..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle row
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Session timer alerts',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary)),
                const SizedBox(height: 2),
                Text('Notify when this much time remains',
                    style: TextStyle(fontSize: 12, color: t.textMuted)),
              ],
            ),
          ),
          Switch(
            value: prefs.enabled,
            onChanged: (v) => notifier.update(prefs.copyWith(enabled: v)),
          ),
        ]),

        if (prefs.enabled) ...[
          const SizedBox(height: 10),

          // Threshold list
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('No alerts set — add one below.',
                  style: TextStyle(fontSize: 12, color: t.textMuted)),
            )
          else
            ...sorted.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(Icons.notifications_outlined,
                        size: 15, color: t.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_minsLabel(m),
                          style: TextStyle(
                              fontSize: 13, color: t.textSecondary)),
                    ),
                    GestureDetector(
                      onTap: () => _remove(prefs, m),
                      child: Icon(Icons.close, size: 16, color: t.textMuted),
                    ),
                  ]),
                )),

          const SizedBox(height: 10),

          // Add row
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                controller: _addCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Minutes remaining',
                  hintText: 'e.g. 45',
                  errorText: _addError,
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _addError = null),
                onSubmitted: (_) => _add(prefs),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton(
                onPressed: () => _add(prefs),
                child: const Text('Add'),
              ),
            ),
          ]),
        ],
      ],
    );
  }

  String _minsLabel(int m) {
    if (m >= 60 && m % 60 == 0) {
      final h = m ~/ 60;
      return h == 1 ? '1 hour left' : '$h hours left';
    }
    return '$m minutes left';
  }
}
