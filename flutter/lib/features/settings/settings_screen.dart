import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart' show authControllerProvider, aiSettingsControllerProvider, AiSettings, themeModeProvider;
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
          const SizedBox(height: 28),
          Text('AI ASSISTANT',
              style: TextStyle(fontSize: 12, letterSpacing: 1, color: t.textMuted)),
          const SizedBox(height: 8),
          const _AiSection(),
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

class _AiSection extends ConsumerStatefulWidget {
  const _AiSection();
  @override
  ConsumerState<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends ConsumerState<_AiSection> {
  final _keyCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final ai = ref.read(aiSettingsControllerProvider);
    if (ai.apiKey != null) _keyCtrl.text = ai.apiKey!;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final ai = ref.watch(aiSettingsControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable AI chat'),
          value: ai.enabled,
          onChanged: (v) =>
              ref.read(aiSettingsControllerProvider.notifier).setEnabled(v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _keyCtrl,
          obscureText: _obscure,
          enabled: ai.enabled,
          decoration: InputDecoration(
            labelText: 'AI Studio API key',
            hintText: 'AIza…',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_keyCtrl.text.isNotEmpty)
                  IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_off
                        : Icons.visibility,
                        size: 18),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                IconButton(
                  icon: const Icon(Icons.content_paste, size: 18),
                  tooltip: 'Paste from clipboard',
                  onPressed: ai.enabled ? _pasteKey : null,
                ),
              ],
            ),
          ),
          onSubmitted: (v) => _saveKey(v),
          onEditingComplete: () => _saveKey(_keyCtrl.text),
        ),
        const SizedBox(height: 4),
        Text(
          'Get a free key at aistudio.google.com',
          style: TextStyle(fontSize: 11, color: t.textMuted),
        ),
        const SizedBox(height: 8),
        _statusLine(t, ai),
        if (ai.apiKey != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _confirmClearKey(context),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Clear API key'),
            style:
                TextButton.styleFrom(foregroundColor: t.danger, padding: EdgeInsets.zero),
          ),
        ],
      ],
    );
  }

  Widget _statusLine(HdTokens t, AiSettings ai) {
    if (!ai.enabled) return const SizedBox.shrink();
    if (!ai.ready) {
      return Row(children: [
        Icon(Icons.warning_amber_rounded, size: 14, color: t.warning),
        const SizedBox(width: 4),
        Expanded(
          child: Text('API key required — chat will show an error until one is entered',
              style: TextStyle(fontSize: 11, color: t.warning)),
        ),
      ]);
    }
    return Row(children: [
      Icon(Icons.check_circle_outline, size: 14, color: t.success),
      const SizedBox(width: 4),
      Text('AI assistant ready', style: TextStyle(fontSize: 11, color: t.success)),
    ]);
  }

  Future<void> _pasteKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _keyCtrl.text = text;
    await _saveKey(text);
  }

  Future<void> _saveKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return;
    await ref.read(aiSettingsControllerProvider.notifier).setKey(trimmed);
  }

  Future<void> _confirmClearKey(BuildContext context) async {
    final t = context.hd;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear AI Studio key'),
        content: const Text('Remove the stored API key from this device?'),
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
    _keyCtrl.clear();
    await ref.read(aiSettingsControllerProvider.notifier).clearKey();
  }
}
