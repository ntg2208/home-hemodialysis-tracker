// flutter/lib/features/kb/kb_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import 'kb_entry_sheet.dart';
import 'kb_providers.dart';
import 'kb_store.dart';

class KbScreen extends ConsumerStatefulWidget {
  const KbScreen({super.key});
  @override
  ConsumerState<KbScreen> createState() => _KbScreenState();
}

class _KbScreenState extends ConsumerState<KbScreen> {
  List<KbEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await ref.read(kbStoreProvider).getAll();
      if (mounted) setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = 'Could not load Knowledge Base. Pull to retry.';
        _loading = false;
      });
    }
  }

  Future<void> _addOrEdit([KbEntry? existing]) async {
    final result = await showKbEntrySheet(context, existing: existing);
    if (result == null) return;
    try {
      await ref.read(kbStoreProvider).save(result);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save entry.')));
      }
    }
  }

  Future<void> _delete(KbEntry entry) async {
    final t = context.hd;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry'),
        content: Text('Delete "${entry.title}"?'),
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
    try {
      await ref.read(kbStoreProvider).delete(entry.id);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not delete entry.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
          child: Text(_error!, style: TextStyle(color: t.textMuted)));
    } else if (_entries.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 48, color: t.textMuted),
            const SizedBox(height: 12),
            Text('No entries yet.',
                style: TextStyle(color: t.textMuted)),
            const SizedBox(height: 8),
            Text('Add patient context used by the AI assistant.',
                style: TextStyle(color: t.textMuted, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _EntryCard(
            entry: _entries[i],
            onEdit: () => _addOrEdit(_entries[i]),
            onDelete: () => _delete(_entries[i]),
          ),
        ),
      );
    }

    return HdScaffold(
      title: 'Knowledge Base',
      body: body,
      actions: [
        IconButton(
          onPressed: () => _addOrEdit(),
          tooltip: 'Add entry',
          icon: const Icon(Icons.add_outlined),
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });
  final KbEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.panel,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: t.textPrimary)),
                  const SizedBox(height: 4),
                  Text(entry.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: t.textSecondary)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: t.textMuted),
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}
