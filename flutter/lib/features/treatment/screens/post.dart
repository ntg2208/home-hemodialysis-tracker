import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/inventory_api.dart';
import '../../../app/shell.dart';
import '../../../app/theme.dart';
import '../../../widgets/number_field.dart';
import '../../../widgets/save_button.dart';
import '../models.dart';
import '../providers.dart';
import '../treatment_repo.dart';

num _round2(num n) => (n * 100).round() / 100;

const _defaultDurationMin = 255;
const _defaultDialysateVolume = 49;

class PostTreatment extends ConsumerStatefulWidget {
  const PostTreatment({
    super.key,
    required this.session,
    required this.consumed,
    required this.onSaved,
  });

  final Session session;
  final SessionConsumed consumed;
  final VoidCallback onSaved;

  @override
  ConsumerState<PostTreatment> createState() => _PostTreatmentState();
}

class _PostTreatmentState extends ConsumerState<PostTreatment> {
  double? _postWeight, _dialysateVolume, _totalUf, _bloodProcessed;
  int? _bpSys, _bpDia, _pulse, _durationMin;
  bool _totalUfTouched = false;
  bool _saving = false;
  String? _error;
  late bool _heparinUsed = widget.consumed.heparinUsed;
  late bool _epoUsed = widget.consumed.epoUsed;
  num? _heparinStock;
  num? _epoStock;

  @override
  void initState() {
    super.initState();
    _durationMin = widget.consumed.durationMin ?? _defaultDurationMin;
    _dialysateVolume = _defaultDialysateVolume.toDouble();
    ref.read(inventoryApiProvider).fetchStock().then((stock) {
      if (mounted) {
        setState(() {
          _heparinStock = stock['heparin'];
          _epoStock = stock['epo'];
        });
      }
    });
  }

  double? get _derivedTotalUf =>
      (widget.session.preWeight != null && _postWeight != null)
          ? _round2(widget.session.preWeight! - _postWeight!).toDouble()
          : null;
  double? get _effectiveTotalUf => _totalUfTouched ? _totalUf : _derivedTotalUf;

  bool get _ready => _postWeight != null && _bpSys != null && _bpDia != null;

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _saving = true;
    });
    bool saved = false;
    try {
      await ref
          .read(treatmentRepoProvider)
          .updateSession(
            widget.session.sessionId,
            {
              if (_postWeight != null) 'post_weight': _postWeight,
              if (_bpSys != null) 'post_bp_sys': _bpSys,
              if (_bpDia != null) 'post_bp_dia': _bpDia,
              if (_pulse != null) 'post_pulse': _pulse,
              if (_durationMin != null) 'duration_min': _durationMin,
              if (_dialysateVolume != null) 'dialysate_volume': _dialysateVolume,
              if (_effectiveTotalUf != null) 'total_uf': _effectiveTotalUf,
              if (_bloodProcessed != null) 'blood_processed': _bloodProcessed,
            },
          )
          .timeout(const Duration(seconds: 6));
      saved = true;
    } on TimeoutException {
      // Offline: Firestore wrote to local cache and will sync when online.
      saved = true;
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Save failed: ${treatmentErrorCode(e)}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (saved) {
      // Fire inventory deduction best-effort — don't block Finish.
      final deltas = <String, num>{
        ...sessionFixedDeltas,
        'P00012326': -widget.consumed.needles,
        'UK00000774': -widget.consumed.onOffPacks,
        if (_heparinUsed) 'heparin': -1,
        if (_epoUsed) 'epo': -1,
      };
      ref.read(inventoryApiProvider)
          .logEvent('session', deltas, note: widget.session.sessionId)
          .catchError((_) {});
      widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return HdScaffold(
      title: 'Post-treatment',
      showDrawer: false,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.session.sessionId,
              style: hdMono.copyWith(color: t.textMuted)),
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
                  label: 'Blood processed (L)',
                  value: _bloodProcessed,
                  onChanged: (v) => _bloodProcessed = v?.toDouble()),
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
                  onChanged: (v) => _pulse = v?.toInt()),
              NumberField(
                  label: 'Weight (kg)',
                  value: _postWeight,
                  required: true,
                  onChanged: (v) => setState(() => _postWeight = v?.toDouble())),
              NumberField(
                  label: 'Duration (min)',
                  value: _durationMin,
                  integer: true,
                  onChanged: (v) => _durationMin = v?.toInt()),
              NumberField(
                  label: 'Dialysate vol (L)',
                  value: _dialysateVolume,
                  onChanged: (v) => _dialysateVolume = v?.toDouble()),
              NumberField(
                  label: 'Total UF (L)',
                  value: _effectiveTotalUf,
                  onChanged: (v) => setState(() {
                        _totalUfTouched = v != null;
                        _totalUf = v?.toDouble();
                      })),
            ],
            ),
          ),
          const SizedBox(height: 16),
          _MedToggle(
            label: 'Heparin',
            subtitle: 'Used during session',
            stock: _heparinStock,
            used: _heparinUsed,
            onChanged: (v) => setState(() => _heparinUsed = v),
          ),
          const SizedBox(height: 8),
          _MedToggle(
            label: 'EPO',
            subtitle: 'Erythropoietin',
            stock: _epoStock,
            used: _epoUsed,
            onChanged: (v) => setState(() => _epoUsed = v),
          ),
          const SizedBox(height: 20),
          SaveButton(
            saving: _saving,
            enabled: _ready,
            error: _error,
            icon: Icons.check_circle_outline,
            label: 'Finish session',
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
