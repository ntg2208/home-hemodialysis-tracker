import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../widgets/number_field.dart';
import '../../chat/command_dispatch.dart' show PrefillReading;
import '../models.dart';
import '../session_id.dart';
import 'sheet_button.dart';

/// Opens the Add-reading bottom sheet. [onSave] does the optimistic persist and may
/// throw; the sheet shows the error and stays open so the user can retry.
Future<void> showAddReadingSheet(
  BuildContext context, {
  required String sessionId,
  required int seq,
  int? defaultBloodFlow,
  required Future<void> Function(Reading) onSave,
  PrefillReading? prefill,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddReadingSheet(
      sessionId: sessionId,
      seq: seq,
      defaultBloodFlow: defaultBloodFlow,
      onSave: onSave,
      prefill: prefill,
    ),
  );
}

class _AddReadingSheet extends StatefulWidget {
  const _AddReadingSheet({
    required this.sessionId,
    required this.seq,
    required this.defaultBloodFlow,
    required this.onSave,
    this.prefill,
  });
  final String sessionId;
  final int seq;
  final int? defaultBloodFlow;
  final Future<void> Function(Reading) onSave;
  final PrefillReading? prefill;

  @override
  State<_AddReadingSheet> createState() => _AddReadingSheetState();
}

class _AddReadingSheetState extends State<_AddReadingSheet> {
  final Set<String> _aiFilledFields = {};
  late String _time = nowHHMM();
  int? _bpSys, _bpDia, _pulse, _vp, _ap;
  late int? _bloodFlow = widget.defaultBloodFlow;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    if (p != null) {
      if (p.bpSys != null) {
        _bpSys = p.bpSys;
        _aiFilledFields.add('bpSys');
      }
      if (p.bpDia != null) {
        _bpDia = p.bpDia;
        _aiFilledFields.add('bpDia');
      }
      if (p.pulse != null) {
        _pulse = p.pulse;
        _aiFilledFields.add('pulse');
      }
      if (p.bloodFlow != null) {
        _bloodFlow = p.bloodFlow;
        _aiFilledFields.add('bloodFlow');
      }
      if (p.vp != null) {
        _vp = p.vp;
        _aiFilledFields.add('vp');
      }
      if (p.ap != null) {
        _ap = p.ap;
        _aiFilledFields.add('ap');
      }
    }
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _saving = true;
    });
    final reading = Reading(
      readingId: '${widget.sessionId}-r${widget.seq}',
      sessionId: widget.sessionId,
      seq: widget.seq,
      time: _time,
      bpSys: _bpSys,
      bpDia: _bpDia,
      pulse: _pulse,
      bloodFlow: _bloodFlow,
      venousPressure: _vp,
      arterialPressure: _ap,
      createdAt: DateTime.now().toIso8601String(),
    );
    try {
      await widget.onSave(reading);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = 'Save failed');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime() async {
    final parts = _time.split(':');
    final initial = TimeOfDay(
        hour: int.tryParse(parts.first) ?? 0,
        minute: int.tryParse(parts.last) ?? 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() => _time =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: t.textMuted,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text('Reading #${widget.seq}',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary)),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickTime,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Time'),
                  child: Text(_time,
                      style: hdMono.copyWith(
                          fontSize: 18, color: t.textPrimary)),
                ),
              ),
              const SizedBox(height: 12),
              FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 12,
                childAspectRatio: 2.2,
                children: [
                  NumberField(
                      label: 'BP sys',
                      value: _bpSys,
                      integer: true,
                      suffix: _aiFilledFields.contains('bpSys')
                          ? const Icon(Icons.auto_awesome,
                              size: 14, color: Color(0xFFF59E0B))
                          : null,
                      onChanged: (v) {
                        _bpSys = v?.toInt();
                        _aiFilledFields.remove('bpSys');
                      }),
                  NumberField(
                      label: 'BP dia',
                      value: _bpDia,
                      integer: true,
                      suffix: _aiFilledFields.contains('bpDia')
                          ? const Icon(Icons.auto_awesome,
                              size: 14, color: Color(0xFFF59E0B))
                          : null,
                      onChanged: (v) {
                        _bpDia = v?.toInt();
                        _aiFilledFields.remove('bpDia');
                      }),
                  NumberField(
                      label: 'Pulse',
                      value: _pulse,
                      integer: true,
                      suffix: _aiFilledFields.contains('pulse')
                          ? const Icon(Icons.auto_awesome,
                              size: 14, color: Color(0xFFF59E0B))
                          : null,
                      onChanged: (v) {
                        _pulse = v?.toInt();
                        _aiFilledFields.remove('pulse');
                      }),
                  NumberField(
                      label: 'Blood flow',
                      value: _bloodFlow,
                      integer: true,
                      suffix: _aiFilledFields.contains('bloodFlow')
                          ? const Icon(Icons.auto_awesome,
                              size: 14, color: Color(0xFFF59E0B))
                          : null,
                      onChanged: (v) {
                        _bloodFlow = v?.toInt();
                        _aiFilledFields.remove('bloodFlow');
                      }),
                  NumberField(
                      label: 'VP',
                      value: _vp,
                      integer: true,
                      suffix: _aiFilledFields.contains('vp')
                          ? const Icon(Icons.auto_awesome,
                              size: 14, color: Color(0xFFF59E0B))
                          : null,
                      onChanged: (v) {
                        _vp = v?.toInt();
                        _aiFilledFields.remove('vp');
                      }),
                  NumberField(
                      label: 'AP',
                      value: _ap,
                      integer: true,
                      suffix: _aiFilledFields.contains('ap')
                          ? const Icon(Icons.auto_awesome,
                              size: 14, color: Color(0xFFF59E0B))
                          : null,
                      onChanged: (v) {
                        _ap = v?.toInt();
                        _aiFilledFields.remove('ap');
                      }),
                ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(color: t.danger, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: SheetButton(
                    label: 'Cancel',
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    accent: false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SheetButton(
                    label: 'Save reading',
                    icon: Icons.check,
                    onPressed: _saving ? null : _submit,
                    loading: _saving,
                    accent: true,
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
