import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../app/providers.dart'
    show aiSettingsControllerProvider, themeModeProvider, cacheBoxName;
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../treatment/providers.dart' show treatmentStoreProvider;
import '../treatment/store.dart';
import '../blood_tests/csv_import.dart' show csvImportTemplate;

// Stored in the cache box under a simple key.
const _patientNameKey = 'community_patient_name';

class CommunitySettingsScreen extends ConsumerStatefulWidget {
  const CommunitySettingsScreen({super.key});
  @override
  ConsumerState<CommunitySettingsScreen> createState() =>
      _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState
    extends ConsumerState<CommunitySettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _dryCtrl = TextEditingController();
  final _aiKeyCtrl = TextEditingController();
  bool _nameSaved = false;
  bool _drySaved = false;

  @override
  void initState() {
    super.initState();
    final box = Hive.box(cacheBoxName);
    _nameCtrl.text = box.get(_patientNameKey) as String? ?? '';
    final store = ref.read(treatmentStoreProvider);
    final dw = store.getDriedWeight();
    if (dw > 0) _dryCtrl.text = dw.toString();
    final ai = ref.read(aiSettingsControllerProvider);
    if (ai.apiKey != null) _aiKeyCtrl.text = ai.apiKey!;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dryCtrl.dispose();
    _aiKeyCtrl.dispose();
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

  Future<void> _saveAiKey() async {
    final key = _aiKeyCtrl.text.trim();
    if (key.isEmpty) {
      await ref.read(aiSettingsControllerProvider.notifier).clearKey();
    } else {
      await ref.read(aiSettingsControllerProvider.notifier).setKey(key);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('AI key saved')));
    }
  }

  Future<void> _downloadTemplate() async {
    await Clipboard.setData(const ClipboardData(text: csvImportTemplate));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV template copied to clipboard')));
    }
  }

  Future<void> _confirmClearAll() async {
    final t = context.hd;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all data'),
        content: const Text(
            'This will permanently delete all sessions, readings, blood tests, inventory, and chat history from this device. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: t.danger, foregroundColor: t.accentOn),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Clear all community boxes
    for (final boxName in [
      'community_sessions',
      'community_readings',
      'community_bt',
      'community_inventory',
      'community_events',
      'community_kb',
      'community_chat',
    ]) {
      Hive.box(boxName).clear();
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('All data cleared')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final mode = ref.watch(themeModeProvider);

    return HdScaffold(
      title: 'Settings',
      showDrawer: false,
      showChatFab: false,
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
          const SizedBox(height: 20),
          _section(t, 'AI ASSISTANT (OPTIONAL)'),
          Text(
            'Enter an AI Studio key to enable the chat assistant. Leave blank to hide the chat button.',
            style: TextStyle(fontSize: 12, color: t.textMuted),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _aiKeyCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'AI Studio API key'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: _saveAiKey, child: const Text('Save key')),
          const SizedBox(height: 20),
          _section(t, 'BLOOD TESTS'),
          OutlinedButton.icon(
            onPressed: _downloadTemplate,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Copy CSV template to clipboard'),
          ),
          const SizedBox(height: 20),
          _section(t, 'APPEARANCE'),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 28),
          _section(t, 'DATA'),
          OutlinedButton.icon(
            onPressed: _confirmClearAll,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Clear all data'),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.danger,
              side: BorderSide(color: t.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(HdTokens t, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, letterSpacing: 1, color: t.textMuted)),
      );
}
