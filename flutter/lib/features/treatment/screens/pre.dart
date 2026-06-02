import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell.dart';
import '../../../app/theme.dart';
import '../../../widgets/number_field.dart';
import '../../../widgets/save_button.dart';
import '../models.dart';
import '../providers.dart';
import '../session_id.dart';
import '../treatment_repo.dart';

num _round2(num n) => (n * 100).round() / 100;

class PreTreatment extends ConsumerStatefulWidget {
  const PreTreatment({
    super.key,
    required this.existingIds,
    required this.onSaved,
    required this.onCancel,
  });

  final List<String> existingIds;
  final void Function(Session session, bool heparinUsed) onSaved;
  final VoidCallback onCancel;

  @override
  ConsumerState<PreTreatment> createState() => _PreTreatmentState();
}

class _PreTreatmentState extends ConsumerState<PreTreatment> {
  num? _preWeight, _ufGoal, _ufRate;
  int? _bpSys, _bpDia, _pulse;
  bool _goalTouched = false, _rateTouched = false;
  bool _saving = false;
  String? _error;
  late double _driedWeight;
  bool _heparinUsed = true;
  num? _heparinStock;

  @override
  void initState() {
    super.initState();
    _driedWeight = ref.read(treatmentStoreProvider).getDriedWeight();
    ref.read(inventoryApiProvider).fetchStock().then((stock) {
      if (mounted) setState(() => _heparinStock = stock['heparin']);
    });
  }

  num? get _derivedGoal =>
      _preWeight != null ? _round2(_preWeight! - _driedWeight) : null;
  num? get _effectiveGoal => _goalTouched ? _ufGoal : _derivedGoal;
  num? get _derivedRate =>
      _effectiveGoal != null ? _round2(_effectiveGoal! / 0.004) : null;
  num? get _effectiveRate => _rateTouched ? _ufRate : _derivedRate;

  bool get _ready =>
      _preWeight != null &&
      _effectiveGoal != null &&
      _bpSys != null &&
      _bpDia != null;

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _saving = true;
    });
    final date = todayIso();
    final session = Session(
      sessionId: nextSessionId(date, widget.existingIds),
      date: date,
      preWeight: _preWeight?.toDouble(),
      ufGoal: _effectiveGoal?.toDouble(),
      ufRate: _effectiveRate?.toDouble(),
      preBpSys: _bpSys,
      preBpDia: _bpDia,
      prePulse: _pulse,
    );
    try {
      await ref.read(treatmentRepoProvider).saveSession(session);
      ref.read(treatmentStoreProvider).saveLastSession(session);
      widget.onSaved(session, _heparinUsed);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Save failed: ${treatmentErrorCode(e)}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HdScaffold(
      title: 'Pre-treatment',
      showDrawer: false,
      leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onCancel,
          tooltip: 'Cancel'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.4,
            children: [
              NumberField(
                  label: 'Weight (kg)',
                  value: _preWeight,
                  required: true,
                  onChanged: (v) => setState(() => _preWeight = v)),
              NumberField(
                  label: 'UF goal (L)',
                  value: _effectiveGoal,
                  required: true,
                  onChanged: (v) => setState(() {
                        _goalTouched = v != null;
                        _ufGoal = v;
                      })),
              NumberField(
                  label: 'UF rate',
                  value: _effectiveRate,
                  onChanged: (v) => setState(() {
                        _rateTouched = v != null;
                        _ufRate = v;
                      })),
              NumberField(
                  label: 'BP sys',
                  value: _bpSys,
                  integer: true,
                  required: true,
                  onChanged: (v) => setState(() => _bpSys = v?.toInt())),
              NumberField(
                  label: 'BP dia',
                  value: _bpDia,
                  integer: true,
                  required: true,
                  onChanged: (v) => setState(() => _bpDia = v?.toInt())),
              NumberField(
                  label: 'Pulse',
                  value: _pulse,
                  integer: true,
                  onChanged: (v) => setState(() => _pulse = v?.toInt())),
            ],
          ),
          const SizedBox(height: 16),
          _MedToggle(
            label: 'Heparin',
            stock: _heparinStock,
            used: _heparinUsed,
            onToggle: () => setState(() => _heparinUsed = !_heparinUsed),
          ),
          const SizedBox(height: 20),
          SaveButton(
            saving: _saving,
            enabled: _ready,
            error: _error,
            icon: Icons.play_arrow,
            label: 'Start session',
            onPressed: _submit,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Used/Not-used pill toggle for a medication, with optional remaining-stock hint.
class _MedToggle extends StatelessWidget {
  const _MedToggle({
    required this.label,
    required this.stock,
    required this.used,
    required this.onToggle,
  });
  final String label;
  final num? stock;
  final bool used;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: t.textPrimary)),
          if (stock != null) ...[
            const SizedBox(width: 8),
            Text('$stock remaining',
                style: TextStyle(fontSize: 12, color: t.textMuted)),
          ],
          const Spacer(),
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: used ? t.accent : t.border,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(used ? 'Used' : 'Not used',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: used ? t.accentOn : t.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}
