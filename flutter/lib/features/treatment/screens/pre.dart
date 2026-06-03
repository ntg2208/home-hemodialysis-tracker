import 'dart:async';

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
  final void Function(Session session, bool heparinUsed, bool epoUsed) onSaved;
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
  bool _epoUsed = false;
  num? _heparinStock;
  num? _epoStock;

  @override
  void initState() {
    super.initState();
    _driedWeight = ref.read(treatmentStoreProvider).getDriedWeight();
    ref.read(inventoryApiProvider).fetchStock().then((stock) {
      if (mounted) {
        setState(() {
          _heparinStock = stock['heparin'];
          _epoStock = stock['epo'];
        });
      }
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
    bool saved = false;
    try {
      await ref
          .read(treatmentRepoProvider)
          .saveSession(session)
          .timeout(const Duration(seconds: 6));
      saved = true;
    } on TimeoutException {
      saved = true;
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Save failed: ${treatmentErrorCode(e)}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (saved) {
      ref.read(treatmentStoreProvider).saveLastSession(session);
      widget.onSaved(session, _heparinUsed, _epoUsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
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
          // Instructional tip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Enter pre-treatment vitals. UF goal and rate auto-calculate '
              'from your dried weight (${_driedWeight.toStringAsFixed(0)} kg) '
              '— edit any field to override.',
              style: TextStyle(fontSize: 13, color: t.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          // Weight + UF goal
          Row(children: [
            Expanded(
              child: NumberField(
                label: 'Weight (kg)',
                value: _preWeight,
                required: true,
                onChanged: (v) => setState(() => _preWeight = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NumberField(
                label: 'UF goal (L)',
                value: _effectiveGoal,
                required: true,
                suffix: !_goalTouched && _derivedGoal != null
                    ? const AutoBadge()
                    : null,
                onChanged: (v) => setState(() {
                  _goalTouched = v != null;
                  _ufGoal = v;
                }),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          // UF rate — full width
          NumberField(
            label: 'UF rate (mL/h)',
            value: _effectiveRate,
            integer: true,
            suffix: !_rateTouched && _derivedRate != null
                ? const AutoBadge()
                : null,
            onChanged: (v) => setState(() {
              _rateTouched = v != null;
              _ufRate = v;
            }),
          ),
          const SizedBox(height: 12),
          // BP sys + BP dia
          Row(children: [
            Expanded(
              child: NumberField(
                label: 'BP systolic',
                value: _bpSys,
                integer: true,
                required: true,
                onChanged: (v) => setState(() => _bpSys = v?.toInt()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NumberField(
                label: 'BP diastolic',
                value: _bpDia,
                integer: true,
                required: true,
                onChanged: (v) => setState(() => _bpDia = v?.toInt()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          // Pulse — full width, last numeric field → done action
          NumberField(
            label: 'Pulse (bpm)',
            value: _pulse,
            integer: true,
            textInputAction: TextInputAction.done,
            onChanged: (v) => setState(() => _pulse = v?.toInt()),
          ),
          const SizedBox(height: 20),
          // EPO toggle
          _MedToggle(
            label: 'EPO',
            subtitle: 'Erythropoietin — carried to Post',
            stock: _epoStock,
            used: _epoUsed,
            onChanged: (v) => setState(() => _epoUsed = v),
          ),
          const SizedBox(height: 8),
          // Heparin toggle
          _MedToggle(
            label: 'Heparin',
            subtitle: 'Carried into Active & Post',
            stock: _heparinStock,
            used: _heparinUsed,
            onChanged: (v) => setState(() => _heparinUsed = v),
          ),
          const SizedBox(height: 20),
          SaveButton(
            saving: _saving,
            enabled: _ready,
            error: _error,
            icon: Icons.play_arrow_outlined,
            label: 'Start session',
            onPressed: _submit,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _MedToggle extends StatelessWidget {
  const _MedToggle({
    required this.label,
    required this.subtitle,
    required this.used,
    required this.onChanged,
    this.stock,
  });
  final String label;
  final String subtitle;
  final bool used;
  final ValueChanged<bool> onChanged;
  final num? stock;

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
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary)),
                if (stock != null) ...[
                  const SizedBox(width: 8),
                  Text('$stock left',
                      style: TextStyle(fontSize: 12, color: t.textMuted)),
                ],
              ]),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(fontSize: 12, color: t.textMuted)),
            ],
          ),
        ),
        Switch(
          value: used,
          onChanged: onChanged,
          activeThumbColor: t.accent,
        ),
      ]),
    );
  }
}
