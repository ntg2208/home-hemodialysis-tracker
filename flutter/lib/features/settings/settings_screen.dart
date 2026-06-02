import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../firebase/firebase_init.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.hd;
    final mode = ref.watch(themeModeProvider);

    return HdScaffold(
      title: 'Settings',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('APPEARANCE',
              style: TextStyle(
                  fontSize: 12, letterSpacing: 1, color: t.textMuted)),
          const SizedBox(height: 8),
          _ThemeToggle(
            mode: mode,
            onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
          ),
          const SizedBox(height: 28),
          Text('CREDENTIALS',
              style: TextStyle(
                  fontSize: 12, letterSpacing: 1, color: t.textMuted)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmClear(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Clear credentials'),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.danger,
              side: BorderSide(color: t.danger),
            ),
          ),
          const SizedBox(height: 28),
          Text('MORE',
              style: TextStyle(
                  fontSize: 12, letterSpacing: 1, color: t.textMuted)),
          const SizedBox(height: 8),
          Text('Dried-weight default and notification preferences — coming soon.',
              style: TextStyle(color: t.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final t = context.hd;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear credentials'),
        content: const Text('Clear all saved credentials on this device?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: t.danger, foregroundColor: t.accentOn),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await firebaseAuth.signOut();
    } catch (_) {/* ignore */}
    await ref.read(authControllerProvider).signOut(); // router redirects to Setup
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.mode, required this.onChanged});
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(value: ThemeMode.system, label: Text('System')),
        ButtonSegment(value: ThemeMode.light, label: Text('Light')),
        ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
      ],
      selected: {mode},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        shape: WidgetStateProperty.all(const StadiumBorder()),
        side: WidgetStateProperty.all(BorderSide(color: t.border)),
      ),
    );
  }
}
