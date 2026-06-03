import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../widgets/number_field.dart';
import '../models.dart';
import '../session_id.dart';

/// Opens the Add-reading bottom sheet. [onSave] does the optimistic persist and may
/// throw; the sheet shows the error and stays open so the user can retry.
Future<void> showAddReadingSheet(
  BuildContext context, {
  required String sessionId,
  required int seq,
  int? defaultBloodFlow,
  required Future<void> Function(Reading) onSave,
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
    ),
  );
}

class _AddReadingSheet extends StatefulWidget {
  const _AddReadingSheet({
    required this.sessionId,
    required this.seq,
    required this.defaultBloodFlow,
    required this.onSave,
  });
  final String sessionId;
  final int seq;
  final int? defaultBloodFlow;
  final Future<void> Function(Reading) onSave;

  @override
  State<_AddReadingSheet> createState() => _AddReadingSheetState();
}

class _AddReadingSheetState extends State<_AddReadingSheet> {
  late String _time = nowHHMM();
  int? _bpSys, _bpDia, _pulse, _vp, _ap;
  late int? _bloodFlow = widget.defaultBloodFlow;
  String? _note;
  bool _saving = false;
  String? _error;

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
      note: (_note?.isEmpty ?? true) ? null : _note,
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
                      onChanged: (v) => _bpSys = v?.toInt()),
                  NumberField(
                      label: 'BP dia',
                      value: _bpDia,
                      integer: true,
                      onChanged: (v) => _bpDia = v?.toInt()),
                  NumberField(
                      label: 'Pulse',
                      value: _pulse,
                      integer: true,
                      onChanged: (v) => _pulse = v?.toInt()),
                  NumberField(
                      label: 'Blood flow',
                      value: _bloodFlow,
                      integer: true,
                      onChanged: (v) => _bloodFlow = v?.toInt()),
                  NumberField(
                      label: 'VP',
                      value: _vp,
                      integer: true,
                      onChanged: (v) => _vp = v?.toInt()),
                  NumberField(
                      label: 'AP',
                      value: _ap,
                      integer: true,
                      onChanged: (v) => _ap = v?.toInt()),
                ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g. felt lightheaded, slowed UF',
                ),
                onChanged: (v) => _note = v,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(color: t.danger, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: _SheetButton(
                    label: 'Cancel',
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    accent: false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SheetButton(
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

/// Pill-shaped sheet action button. [accent] = cyan fill; otherwise dark fill.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onPressed,
    required this.accent,
    this.icon,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool accent;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final bg = accent ? t.accent : t.panel;
    final fg = accent ? t.accentOn : t.textPrimary;
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedOpacity(
        opacity: onPressed == null ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: accent ? null : Border.all(color: t.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: fg))
              else if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
