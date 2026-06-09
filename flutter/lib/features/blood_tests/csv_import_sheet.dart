import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'csv_import.dart';
import 'hive_bt_store.dart';
import 'models.dart';
import 'providers.dart';

Future<void> showCsvImportSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _CsvImportSheet(),
  );
}

class _CsvImportSheet extends ConsumerStatefulWidget {
  const _CsvImportSheet();
  @override
  ConsumerState<_CsvImportSheet> createState() => _CsvImportSheetState();
}

class _CsvImportSheetState extends ConsumerState<_CsvImportSheet> {
  CsvParseResult? _result;
  bool _importing = false;
  String? _importedCount;

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null) return;
    final text = String.fromCharCodes(bytes);
    setState(() => _result = parseCsvImport(text));
  }

  Future<void> _doImport() async {
    final result = _result;
    if (result == null || result.valid.isEmpty) return;
    setState(() => _importing = true);
    final store = ref.read(btStoreProvider) as HiveBtStore;
    for (final row in result.valid) {
      await store.upsertRow(row);
    }
    setState(() {
      _importing = false;
      _importedCount = '${result.valid.length}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;

    if (_importedCount != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: t.success),
            const SizedBox(height: 16),
            Text('Imported $_importedCount rows',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }

    final result = _result;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Import CSV',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 12),
            if (result == null) ...[
              Text(
                'Select a CSV file with columns: date, marker, value, unit, ref_low, ref_high, timing, note',
                style: TextStyle(fontSize: 13, color: t.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.upload_file),
                label: const Text('Choose file'),
              ),
            ] else ...[
              Text(
                '${result.valid.length} valid row(s), ${result.errors.length} error(s)',
                style: TextStyle(
                    color: result.errors.isEmpty ? t.success : t.warning,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [
                    for (final row in result.valid)
                      _RowTile(marker: row.marker, date: row.datetime.substring(0, 10), ok: true),
                    for (final err in result.errors)
                      _RowTile(
                          marker: err.rawRow.length > 1 ? err.rawRow[1] : '?',
                          date: err.rawRow.isNotEmpty ? err.rawRow[0] : '?',
                          ok: false,
                          reason: err.reason),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                TextButton(
                    onPressed: () => setState(() => _result = null),
                    child: const Text('Choose different file')),
                const Spacer(),
                if (result.valid.isNotEmpty)
                  FilledButton(
                    onPressed: _importing ? null : _doImport,
                    child: _importing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Import ${result.valid.length} rows'),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.marker, required this.date, required this.ok, this.reason});
  final String marker;
  final String date;
  final bool ok;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 16, color: ok ? t.success : t.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            ok ? '$date  $marker' : '$date  $marker  —  $reason',
            style: TextStyle(
                fontSize: 12,
                color: ok ? t.textPrimary : t.danger),
          ),
        ),
      ]),
    );
  }
}
