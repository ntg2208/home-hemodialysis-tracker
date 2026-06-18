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
import '../../../app/providers.dart' show testModeProvider;
import '../../../flavor.dart';
import '../../chat/command_dispatch.dart'
    show prefillPreCommandProvider, PrefillPreTreatment;

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
  bool _heparinUsed = false;
  bool _epoUsed = false;
  num? _heparinStock;
  num? _epoStock;
  final Set<String> _aiFilledFields = {};

  @override
  void initState() {
    super.initState();
    _driedWeight = ref.read(treatmentStoreProvider).getDriedWeight();

    if (ref.read(testModeProvider)) {
      _preWeight = 61.5;
      _bpSys = 138;
      _bpDia = 88;
      _pulse = 96;
    }

    ref.read(inventoryApiProvider).fetchStock().then((stock) {
      if (mounted) {
        setState(() {
          _heparinStock = stock['heparin'];
          _epoStock = stock['epo'];
        });
      }
    });

    // Read current value first (may have been set before this widget mounted)
    final pending = ref.read(prefillPreCommandProvider);
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyAiPrefill(pending);
        ref.read(prefillPreCommandProvider.notifier).set(null);
      });
    }

    // Listen for future AI prefill commands
    ref.listenManual(prefillPreCommandProvider, (_, cmd) {
      if (cmd == null || !mounted) return;
      _applyAiPrefill(cmd);
      ref.read(prefillPreCommandProvider.notifier).set(null); // consume
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

  void _applyAiPrefill(PrefillPreTreatment cmd) {
    setState(() {
      if (cmd.weight != null) {
        _preWeight = cmd.weight;
        _aiFilledFields.add('weight');
      }
      if (cmd.bpSys != null) {
        _bpSys = cmd.bpSys;
        _aiFilledFields.add('bpSys');
      }
      if (cmd.bpDia != null) {
        _bpDia = cmd.bpDia;
        _aiFilledFields.add('bpDia');
      }
      if (cmd.pulse != null) {
        _pulse = cmd.pulse;
        _aiFilledFields.add('pulse');
      }
      if (cmd.ufGoal != null) {
        _ufGoal = cmd.ufGoal;
        _goalTouched = true;
        _aiFilledFields.add('ufGoal');
      }
      if (cmd.ufRate != null) {
        _ufRate = cmd.ufRate;
        _rateTouched = true;
        _aiFilledFields.add('ufRate');
      }
    });
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
        tooltip: 'Cancel',
      ),
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
              'from your dry weight (${_driedWeight.toStringAsFixed(0)} kg) '
              '— edit any field to override.',
              style: TextStyle(fontSize: 13, color: t.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              children: [
                // Weight + UF goal
                Row(
                  children: [
                    Expanded(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: NumberField(
                          label: 'Weight (kg)',
                          value: _preWeight,
                          required: true,
                          suffix: _aiFilledFields.contains('weight')
                              ? const Icon(
                                  Icons.auto_awesome,
                                  size: 14,
                                  color: Color(0xFFF59E0B),
                                )
                              : null,
                          onChanged: (v) => setState(() {
                            _preWeight = v;
                            _aiFilledFields.remove('weight');
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: NumberField(
                          label: 'UF goal (L)',
                          value: _effectiveGoal,
                          required: true,
                          suffix: _aiFilledFields.contains('ufGoal')
                              ? const Icon(
                                  Icons.auto_awesome,
                                  size: 14,
                                  color: Color(0xFFF59E0B),
                                )
                              : !_goalTouched && _derivedGoal != null
                              ? const AutoBadge()
                              : null,
                          onChanged: (v) => setState(() {
                            _goalTouched = v != null;
                            _ufGoal = v;
                            _aiFilledFields.remove('ufGoal');
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // UF rate — full width
                FocusTraversalOrder(
                  order: const NumericFocusOrder(3),
                  child: NumberField(
                    label: 'UF rate (mL/h)',
                    value: _effectiveRate,
                    integer: true,
                    suffix: _aiFilledFields.contains('ufRate')
                        ? const Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: Color(0xFFF59E0B),
                          )
                        : !_rateTouched && _derivedRate != null
                        ? const AutoBadge()
                        : null,
                    onChanged: (v) => setState(() {
                      _rateTouched = v != null;
                      _ufRate = v;
                      _aiFilledFields.remove('ufRate');
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                // BP sys + BP dia
                Row(
                  children: [
                    Expanded(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(4),
                        child: NumberField(
                          label: 'BP systolic',
                          value: _bpSys,
                          integer: true,
                          required: true,
                          suffix: _aiFilledFields.contains('bpSys')
                              ? const Icon(
                                  Icons.auto_awesome,
                                  size: 14,
                                  color: Color(0xFFF59E0B),
                                )
                              : null,
                          onChanged: (v) => setState(() {
                            _bpSys = v?.toInt();
                            _aiFilledFields.remove('bpSys');
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(5),
                        child: NumberField(
                          label: 'BP diastolic',
                          value: _bpDia,
                          integer: true,
                          required: true,
                          suffix: _aiFilledFields.contains('bpDia')
                              ? const Icon(
                                  Icons.auto_awesome,
                                  size: 14,
                                  color: Color(0xFFF59E0B),
                                )
                              : null,
                          onChanged: (v) => setState(() {
                            _bpDia = v?.toInt();
                            _aiFilledFields.remove('bpDia');
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Pulse — full width, last numeric field → done action
                FocusTraversalOrder(
                  order: const NumericFocusOrder(6),
                  child: NumberField(
                    label: 'Pulse (bpm)',
                    value: _pulse,
                    integer: true,
                    textInputAction: TextInputAction.done,
                    suffix: _aiFilledFields.contains('pulse')
                        ? const Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: Color(0xFFF59E0B),
                          )
                        : null,
                    onChanged: (v) => setState(() {
                      _pulse = v?.toInt();
                      _aiFilledFields.remove('pulse');
                    }),
                  ),
                ),
              ],
            ),
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
          // Dry weight guard for community
          if (kCommunity && _driedWeight <= 0) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Set your dry weight in Settings before starting a session.',
                style: TextStyle(fontSize: 12, color: context.hd.warning),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          SaveButton(
            saving: _saving,
            enabled: _ready && !(kCommunity && _driedWeight <= 0),
            error: _error,
            icon: Icons.play_arrow_outlined,
            label: 'Start session',
            onPressed: () => _submit(),
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                    ),
                    if (stock != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '$stock left',
                        style: TextStyle(fontSize: 12, color: t.textMuted),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: t.textMuted),
                ),
              ],
            ),
          ),
          Switch(value: used, onChanged: onChanged, activeThumbColor: t.accent),
        ],
      ),
    );
  }
}
