import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../app/providers.dart'
    show authControllerProvider, aiSettingsControllerProvider, AiSettings, themeModeProvider, testModeProvider, cacheBoxName;
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../firebase/firebase_init.dart';
import '../treatment/providers.dart' show treatmentStoreProvider;

const _patientNameKey = 'patient_name';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameCtrl  = TextEditingController();
  final _dryCtrl   = TextEditingController();
  bool _nameSaved  = false;
  bool _drySaved   = false;

  @override
  void initState() {
    super.initState();
    final box = Hive.box(cacheBoxName);
    _nameCtrl.text = box.get(_patientNameKey) as String? ?? '';
    final store = ref.read(treatmentStoreProvider);
    final dw = store.getDriedWeight();
    if (dw > 0) _dryCtrl.text = dw.toString();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dryCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    await Hive.box(cacheBoxName).put(_patientNameKey, _nameCtrl.text.trim());
    setState(() => _nameSaved = true);
  }

  Future<void> _saveDryWeight() async {
    final v = double.tryParse(_dryCtrl.text.trim());
    if (v == null || v <= 0) return;
    await ref.read(treatmentStoreProvider).setDriedWeight(v);
    setState(() => _drySaved = true);
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
    await ref.read(authControllerProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final mode = ref.watch(themeModeProvider);

    return HdScaffold(
      title: 'Settings',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(t, 'PATIENT'),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Your name',
              hintText: 'Used in PDF export headers',
            ),
            onChanged: (_) => setState(() => _nameSaved = false),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: _saveName,
              child: Text(_nameSaved ? 'Saved ✓' : 'Save name')),
          const SizedBox(height: 20),
          _section(t, 'DRY WEIGHT'),
          TextField(
            controller: _dryCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Dry weight (kg)',
              hintText: 'e.g. 68.5',
            ),
            onChanged: (_) => setState(() => _drySaved = false),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: _saveDryWeight,
              child: Text(_drySaved ? 'Saved ✓' : 'Save dry weight')),
          const SizedBox(height: 28),
          _section(t, 'APPEARANCE'),
          const SizedBox(height: 8),
          _ThemeToggle(
            mode: mode,
            onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
          ),
          const SizedBox(height: 28),
          _section(t, 'CREDENTIALS'),
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
          _section(t, 'AI ASSISTANT'),
          const SizedBox(height: 8),
          const _AiSection(),
          const SizedBox(height: 28),
          _section(t, 'DEVELOPER'),
          const SizedBox(height: 8),
          const _TestModeSection(),
        ],
      ),
    );
  }

  Widget _section(HdTokens t, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(label,
            style: TextStyle(fontSize: 12, letterSpacing: 1, color: t.textMuted)),
      );
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

// ── AI Assistant ──────────────────────────────────────────────────────────────

class _AiSection extends ConsumerStatefulWidget {
  const _AiSection();
  @override
  ConsumerState<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends ConsumerState<_AiSection> {
  final _keyCtrl = TextEditingController();
  final bool _obscure = true;
  bool _keySaved = false;

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
            suffixIcon: IconButton(
              icon: const Icon(Icons.content_paste, size: 18),
              tooltip: 'Paste from clipboard',
              onPressed: ai.enabled ? _pasteKey : null,
            ),
          ),
          onChanged: (_) => setState(() => _keySaved = false),
          onSubmitted: (v) => _saveKey(v),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: ai.enabled ? () => _saveKey(_keyCtrl.text) : null,
          child: Text(_keySaved ? 'Saved ✓' : 'Save key'),
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
            style: TextButton.styleFrom(foregroundColor: t.danger, padding: EdgeInsets.zero),
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
    setState(() => _keyCtrl.text = text);
    await _saveKey(text);
  }

  Future<void> _saveKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await ref.read(aiSettingsControllerProvider.notifier).clearKey();
    } else {
      await ref.read(aiSettingsControllerProvider.notifier).setKey(trimmed);
    }
    setState(() => _keySaved = true);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('AI key saved')));
    }
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
    setState(() => _keySaved = false);
    await ref.read(aiSettingsControllerProvider.notifier).clearKey();
  }
}

// ── Test Mode ──────────────────────────────────────────────────────────────────

class _TestModeSection extends ConsumerWidget {
  const _TestModeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.hd;
    final testMode = ref.watch(testModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: testMode ? t.warning.withValues(alpha: 0.12) : t.panel,
            border: Border.all(
                color: testMode ? t.warning : t.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.science_outlined,
                        size: 16,
                        color: testMode ? t.warning : t.textSecondary),
                    const SizedBox(width: 6),
                    Text('Test mode',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color:
                                testMode ? t.warning : t.textPrimary)),
                    if (testMode) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: t.warning,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('ON',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: t.bg)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    testMode
                        ? 'Using synthetic data — your real data is unchanged.'
                        : 'Replaces all data with 20 sessions, synthetic blood tests, fitness and inventory for AI testing.',
                    style: TextStyle(
                        fontSize: 12,
                        color: testMode ? t.warning : t.textMuted),
                  ),
                ],
              ),
            ),
            Switch(
              value: testMode,
              onChanged: (_) =>
                  ref.read(testModeProvider.notifier).toggle(),
              activeThumbColor: t.warning,
            ),
          ]),
        ),
      ],
    );
  }
}
