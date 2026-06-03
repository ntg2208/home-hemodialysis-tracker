// flutter/lib/features/kb/kb_entry_sheet.dart
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'kb_store.dart';

/// Bottom sheet for adding or editing a KB entry.
/// Returns the saved [KbEntry] or null if cancelled.
Future<KbEntry?> showKbEntrySheet(
  BuildContext context, {
  KbEntry? existing,
}) {
  return showModalBottomSheet<KbEntry?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _KbEntrySheet(existing: existing),
  );
}

class _KbEntrySheet extends StatefulWidget {
  const _KbEntrySheet({this.existing});
  final KbEntry? existing;
  @override
  State<_KbEntrySheet> createState() => _KbEntrySheetState();
}

class _KbEntrySheetState extends State<_KbEntrySheet> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _content = TextEditingController(text: widget.existing?.content ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty && _content.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: t.textMuted,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.existing == null ? 'Add entry' : 'Edit entry',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              minLines: 3,
              maxLines: 6,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                  labelText: 'Content',
                  hintText: 'Free text — used as context for the AI assistant'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _valid && !_saving ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _save() {
    final now = DateTime.now();
    final entry = KbEntry(
      id: widget.existing?.id ?? KbEntry.newId(),
      title: _title.text.trim(),
      content: _content.text.trim(),
      source: 'user',
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );
    Navigator.of(context).pop(entry);
  }
}
