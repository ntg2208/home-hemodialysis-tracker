import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'hive_bt_store.dart';
import 'marker_definitions.dart';
import 'models.dart';
import 'providers.dart';

Future<void> showEntrySheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const ProviderScope(
      child: _EntrySheet(),
    ),
  );
}

class _EntrySheet extends ConsumerStatefulWidget {
  const _EntrySheet();
  @override
  ConsumerState<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends ConsumerState<_EntrySheet> {
  DateTime _date = DateTime.now();
  MarkerDefinition? _marker;
  final _searchCtrl  = TextEditingController();
  final _valueCtrl   = TextEditingController();
  final _unitCtrl    = TextEditingController();
  final _refLowCtrl  = TextEditingController();
  final _refHighCtrl = TextEditingController();
  final _noteCtrl    = TextEditingController();
  String _timing = '';
  bool _saving = false;
  String? _error;

  List<MarkerDefinition> get _filtered {
    final q = _searchCtrl.text.toLowerCase();
    if (q.isEmpty) return markerDefinitions;
    return markerDefinitions
        .where((m) => m.displayName.toLowerCase().contains(q) ||
                      m.name.toLowerCase().contains(q))
        .toList();
  }

  void _selectFirstMatch() {
    final matches = _filtered;
    if (matches.isNotEmpty) _selectMarker(matches.first);
  }

  void _selectMarker(MarkerDefinition m) {
    setState(() {
      _marker = m;
      _searchCtrl.text = m.displayName;
      if (_unitCtrl.text.isEmpty) _unitCtrl.text = m.defaultUnit;
      if (_refLowCtrl.text.isEmpty && m.refLow != null)
        _refLowCtrl.text = m.refLow!.toString();
      if (_refHighCtrl.text.isEmpty && m.refHigh != null)
        _refHighCtrl.text = m.refHigh!.toString();
    });
  }

  Future<void> _save({bool addAnother = false}) async {
    final markerName = _searchCtrl.text.trim();
    if (markerName.isEmpty) {
      setState(() => _error = 'Marker is required');
      return;
    }
    final value = double.tryParse(_valueCtrl.text.trim());
    if (value == null) {
      setState(() => _error = 'Value must be a number');
      return;
    }
    setState(() { _saving = true; _error = null; });

    final row = BloodTestRow(
      marker: markerName.toLowerCase().replaceAll(' ', '_'),
      datetime: '${_date.toIso8601String().substring(0, 10)}T09:00:00.000Z',
      value: value,
      unit: _unitCtrl.text.trim(),
      refLow: double.tryParse(_refLowCtrl.text),
      refHigh: double.tryParse(_refHighCtrl.text),
      timing: _timing,
      note: _noteCtrl.text.trim(),
      source: 'manual',
      labId: '',
      phase: '',
      createdAt: DateTime.now().toIso8601String().substring(0, 10),
      qualitative: false,
    );

    final store = ref.read(btStoreProvider) as HiveBtStore;
    await store.upsertRow(row);

    if (!mounted) return;
    if (addAnother) {
      setState(() {
        _saving = false;
        _marker = null;
        _searchCtrl.clear();
        _valueCtrl.clear();
        _unitCtrl.clear();
        _refLowCtrl.clear();
        _refHighCtrl.clear();
        _noteCtrl.clear();
        _timing = '';
      });
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _valueCtrl.dispose();
    _unitCtrl.dispose();
    _refLowCtrl.dispose();
    _refHighCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(child: Text('Add result',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 12),
            // Date
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(_date.toIso8601String().substring(0, 10)),
            ),
            const SizedBox(height: 12),
            // Marker search
            TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Marker',
                hintText: 'Search or type custom marker',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (_) => setState(() { _marker = null; }),
              onSubmitted: (_) => _selectFirstMatch(),
            ),
            if (_searchCtrl.text.isNotEmpty && _marker == null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView(
                  shrinkWrap: true,
                  children: _filtered.map((m) => ListTile(
                    dense: true,
                    title: Text(m.displayName, style: const TextStyle(fontSize: 13)),
                    onTap: () => _selectMarker(m),
                  )).toList(),
                ),
              ),
            const SizedBox(height: 8),
            // Value + Unit row
            Row(children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _valueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Value'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _unitCtrl,
                  decoration: const InputDecoration(labelText: 'Unit'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            // Ref range row
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _refLowCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Ref low'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _refHighCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Ref high'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // Timing
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pre',  label: Text('Pre')),
                ButtonSegment(value: 'post', label: Text('Post')),
                ButtonSegment(value: '',     label: Text('None')),
              ],
              selected: {_timing},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _timing = s.first),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: t.danger, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(addAnother: true),
                  child: const Text('Add another'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(),
                  child: const Text('Save'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
