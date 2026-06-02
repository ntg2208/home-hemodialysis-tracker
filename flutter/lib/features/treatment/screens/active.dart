import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell.dart';
import '../../../app/theme.dart';
import '../alerts.dart';
import '../models.dart';
import '../providers.dart';
import '../treatment_repo.dart';
import '../widgets/add_reading_sheet.dart';

const _defaultTargetMin = 255; // 4h 15m
const _notifyAtMins = [120, 60, 5];

class ActiveSession extends ConsumerStatefulWidget {
  const ActiveSession({
    super.key,
    required this.session,
    required this.initialReadings,
    required this.heparinUsed,
    this.initialCountdownStartedAt,
    this.initialTargetMin,
    required this.onReadingsChanged,
    required this.onCountdownChanged,
    required this.onHeparinChanged,
    required this.onEnd,
  });

  final Session session;
  final List<PendingReading> initialReadings;
  final bool heparinUsed;
  final int? initialCountdownStartedAt;
  final int? initialTargetMin;
  final void Function(List<PendingReading>) onReadingsChanged;
  final void Function(int? startedAt, int targetMin) onCountdownChanged;
  final void Function(bool) onHeparinChanged;
  final void Function(SessionConsumed) onEnd;

  @override
  ConsumerState<ActiveSession> createState() => _ActiveSessionState();
}

class _ActiveSessionState extends ConsumerState<ActiveSession> {
  late final List<PendingReading> _readings = [...widget.initialReadings];
  late int _targetMin = widget.initialTargetMin ?? _defaultTargetMin;
  late int? _countdownStartedAt = widget.initialCountdownStartedAt;
  late bool _heparinUsed = widget.heparinUsed;
  int _needles = 2;
  int _onOffPacks = 1;
  String? _inAppAlert;
  Timer? _ticker;
  final _notified = <int>{};

  @override
  void initState() {
    super.initState();
    final start = _countdownStartedAt;
    if (start != null) {
      final remaining =
          _targetMin * 60000 - (DateTime.now().millisecondsSinceEpoch - start);
      for (final m in _notifyAtMins) {
        if (remaining <= m * 60000) _notified.add(m);
      }
      _startTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = _countdownStartedAt;
      if (start == null) return;
      final remaining =
          _targetMin * 60000 - (DateTime.now().millisecondsSinceEpoch - start);
      for (final m in _notifyAtMins) {
        if (remaining <= m * 60000 && !_notified.contains(m)) {
          _notified.add(m);
          final label =
              m == 120 ? '2 hours' : (m == 60 ? '1 hour' : '5 minutes');
          _triggerAlert('$label remaining');
        }
      }
      setState(() {});
    });
  }

  void _triggerAlert(String message) {
    setState(() => _inAppAlert = message);
    TimerAlerts.fire(message); // mobile only; no-op on web
  }

  int get _nextSeq => _readings.isEmpty
      ? 1
      : _readings.map((r) => r.reading.seq).reduce((a, b) => a > b ? a : b) + 1;

  int? get _lastBloodFlow {
    for (final r in _readings) {
      if (r.reading.bloodFlow != null) return r.reading.bloodFlow;
    }
    return null;
  }

  Future<void> _persist(Reading reading) async {
    final idx =
        _readings.indexWhere((r) => r.reading.readingId == reading.readingId);
    setState(() {
      final pending = PendingReading(reading, status: SaveStatus.pending);
      if (idx >= 0) {
        _readings[idx] = pending;
      } else {
        _readings.insert(0, pending);
      }
      if (_countdownStartedAt == null) {
        _countdownStartedAt = DateTime.now().millisecondsSinceEpoch;
        TimerAlerts.requestPermission();
        _startTicker();
        widget.onCountdownChanged(_countdownStartedAt, _targetMin);
      }
    });
    _emitReadings();
    try {
      await ref.read(treatmentRepoProvider).saveReading(reading);
      _setStatus(reading.readingId, SaveStatus.saved);
    } catch (e) {
      _setStatus(reading.readingId, SaveStatus.error,
          msg: treatmentErrorCode(e));
      rethrow;
    }
  }

  Future<void> _retry(PendingReading r) async {
    _setStatus(r.reading.readingId, SaveStatus.pending);
    try {
      await ref.read(treatmentRepoProvider).saveReading(r.reading);
      _setStatus(r.reading.readingId, SaveStatus.saved);
    } catch (e) {
      _setStatus(r.reading.readingId, SaveStatus.error,
          msg: treatmentErrorCode(e));
    }
  }

  void _setStatus(String id, SaveStatus status, {String? msg}) {
    if (!mounted) return;
    setState(() {
      final i = _readings.indexWhere((r) => r.reading.readingId == id);
      if (i >= 0) {
        _readings[i].status = status;
        _readings[i].errorMsg = msg;
      }
    });
    _emitReadings();
  }

  void _emitReadings() => widget.onReadingsChanged([..._readings]);

  Future<void> _editTarget() async {
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => _TargetDialog(targetMin: _targetMin),
    );
    if (result != null && result > 0) {
      setState(() => _targetMin = result);
      widget.onCountdownChanged(_countdownStartedAt, _targetMin);
    }
  }

  void _end() {
    final duration = _countdownStartedAt == null
        ? null
        : ((DateTime.now().millisecondsSinceEpoch - _countdownStartedAt!) /
                60000)
            .round();
    widget.onEnd(SessionConsumed(
      needles: _needles,
      onOffPacks: _onOffPacks,
      heparinUsed: _heparinUsed,
      durationMin: duration,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final sorted = [..._readings]
      ..sort((a, b) => b.reading.seq.compareTo(a.reading.seq));

    final started = _countdownStartedAt != null;
    final targetMs = _targetMin * 60000;
    final remainingMs = started
        ? targetMs -
            (DateTime.now().millisecondsSinceEpoch - _countdownStartedAt!)
        : targetMs;
    final overtime = remainingMs < 0;
    final timerColor = !started
        ? t.textMuted
        : (overtime || remainingMs <= 5 * 60000)
            ? t.danger
            : remainingMs <= 10 * 60000
                ? t.warning
                : t.good;

    return HdScaffold(
      title: 'Session',
      showDrawer: false,
      titleWidget: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('Session  '),
        Text(widget.session.sessionId,
            style: hdMono.copyWith(fontSize: 15, color: t.textSecondary)),
      ]),
      actions: [
        TextButton.icon(
          onPressed: _end,
          icon: const Icon(Icons.stop, size: 16),
          label: const Text('End'),
        ),
      ],
      body: Column(
        children: [
          if (_inAppAlert != null) _alertBanner(t),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _preValuesCard(t),
                const SizedBox(height: 12),
                _countdownCard(t, started, remainingMs, timerColor),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => showAddReadingSheet(
                    context,
                    sessionId: widget.session.sessionId,
                    seq: _nextSeq,
                    defaultBloodFlow: _lastBloodFlow,
                    onSave: _persist,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add reading'),
                ),
                const SizedBox(height: 12),
                _consumedCard(t),
                const SizedBox(height: 12),
                _heparinToggle(t),
                const SizedBox(height: 16),
                if (sorted.isEmpty)
                  Text('No readings yet.',
                      style: TextStyle(color: t.textMuted))
                else
                  ...sorted.map((r) => _readingRow(t, r)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertBanner(HdTokens t) => Material(
        color: t.warning.withValues(alpha: 0.95),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Expanded(
                child: Text(_inAppAlert!,
                    style:
                        TextStyle(color: t.bg, fontWeight: FontWeight.w700))),
            IconButton(
                onPressed: () => setState(() => _inAppAlert = null),
                icon: Icon(Icons.close, color: t.bg, size: 18)),
          ]),
        ),
      );

  Widget _preValuesCard(HdTokens t) {
    Widget cell(IconData ic, Color c, String label, String value) => Row(
          children: [
            Icon(ic, size: 14, color: c),
            const SizedBox(width: 6),
            Text('$label ',
                style: TextStyle(color: t.textSecondary, fontSize: 13)),
            Flexible(
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textPrimary, fontSize: 13)),
            ),
          ],
        );
    final s = widget.session;
    return _card(t,
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 5,
          children: [
            cell(Icons.scale, t.textMuted, 'Weight',
                '${s.preWeight ?? '–'} kg'),
            cell(Icons.water_drop_outlined, t.accent, 'UF goal',
                '${s.ufGoal ?? '–'} L'),
            cell(Icons.favorite_border, t.vital, 'BP',
                '${s.preBpSys ?? '–'}/${s.preBpDia ?? '–'}'),
            cell(Icons.monitor_heart_outlined, t.good, 'Pulse',
                '${s.prePulse ?? '–'}'),
          ],
        ));
  }

  Widget _countdownCard(
      HdTokens t, bool started, int remainingMs, Color timerColor) {
    return _card(t,
        child: Row(
          children: [
            Icon(Icons.timer_outlined, size: 18, color: timerColor),
            const SizedBox(width: 8),
            if (started)
              Text(_formatRemaining(remainingMs),
                  style: hdMono.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: timerColor))
            else
              Flexible(
                child: Text('Waiting for first reading',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textMuted, fontSize: 13)),
              ),
            const Spacer(),
            InkWell(
              onTap: _editTarget,
              child: Row(children: [
                Text(_formatTarget(_targetMin),
                    style:
                        hdMono.copyWith(color: t.textSecondary, fontSize: 13)),
                const SizedBox(width: 4),
                Icon(Icons.edit_outlined, size: 12, color: t.textMuted),
              ]),
            ),
          ],
        ));
  }

  Widget _consumedCard(HdTokens t) {
    Widget stepper(String label, int value, ValueChanged<int> onChange) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: t.textSecondary)),
              const SizedBox(height: 4),
              Row(children: [
                _StepperButton(
                    icon: Icons.remove,
                    onTap: () => onChange(value > 0 ? value - 1 : 0)),
                Expanded(
                    child: Text('$value',
                        textAlign: TextAlign.center,
                        style: hdMono.copyWith(
                            fontSize: 16, color: t.textPrimary))),
                _StepperButton(
                    icon: Icons.add, onTap: () => onChange(value + 1)),
              ]),
            ],
          ),
        );
    return _card(t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Consumed this session',
                style: TextStyle(fontSize: 12, color: t.textMuted)),
            const SizedBox(height: 8),
            Row(children: [
              stepper('Needles used', _needles,
                  (v) => setState(() => _needles = v)),
              const SizedBox(width: 16),
              stepper('On/Off packs', _onOffPacks,
                  (v) => setState(() => _onOffPacks = v)),
            ]),
          ],
        ));
  }

  Widget _heparinToggle(HdTokens t) => _card(t,
      child: Row(children: [
        Text('Heparin', style: TextStyle(color: t.textPrimary)),
        const Spacer(),
        GestureDetector(
          onTap: () {
            setState(() => _heparinUsed = !_heparinUsed);
            widget.onHeparinChanged(_heparinUsed);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _heparinUsed ? t.accent : t.border,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(_heparinUsed ? 'Used' : 'Not used',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _heparinUsed ? t.accentOn : t.textSecondary)),
          ),
        ),
      ]));

  Widget _readingRow(HdTokens t, PendingReading p) {
    final r = p.reading;
    final Widget statusWidget = switch (p.status) {
      SaveStatus.pending => Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: t.textMuted)),
          const SizedBox(width: 4),
          Text('saving…', style: TextStyle(fontSize: 12, color: t.textMuted)),
        ]),
      SaveStatus.error => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 14, color: t.danger),
          const SizedBox(width: 4),
          Text('error', style: TextStyle(fontSize: 12, color: t.danger)),
        ]),
      SaveStatus.saved => Icon(Icons.check, size: 14, color: t.good),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(r.time, style: hdMono.copyWith(color: t.textSecondary)),
            const Spacer(),
            statusWidget,
          ]),
          const SizedBox(height: 2),
          Text(
            'BP ${r.bpSys ?? '–'}/${r.bpDia ?? '–'} · pulse ${r.pulse ?? '–'} · '
            'BF ${r.bloodFlow ?? '–'} · VP ${r.venousPressure ?? '–'} · '
            'AP ${r.arterialPressure ?? '–'}',
            style: TextStyle(color: t.textSecondary, fontSize: 13),
          ),
          if (r.note != null && r.note!.isNotEmpty)
            Text(r.note!,
                style: TextStyle(
                    color: t.textMuted,
                    fontSize: 13,
                    fontStyle: FontStyle.italic)),
          if (p.status == SaveStatus.error)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Text(p.errorMsg ?? 'error',
                    style: TextStyle(color: t.danger, fontSize: 12)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _retry(p),
                  child: Text('Retry',
                      style: TextStyle(
                          color: t.danger,
                          fontSize: 12,
                          decoration: TextDecoration.underline)),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _card(HdTokens t, {required Widget child}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.panel,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            shape: BoxShape.circle, border: Border.all(color: t.border)),
        child: Icon(icon, size: 16, color: t.textSecondary),
      ),
    );
  }
}

class _TargetDialog extends StatefulWidget {
  const _TargetDialog({required this.targetMin});
  final int targetMin;
  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  late int _h = widget.targetMin ~/ 60;
  late int _m = widget.targetMin % 60;
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Target time'),
      content: Row(mainAxisSize: MainAxisSize.min, children: [
        _numBox(_h, 0, 23, (v) => _h = v),
        const Padding(padding: EdgeInsets.all(8), child: Text('h')),
        _numBox(_m, 0, 59, (v) => _m = v),
        const Padding(padding: EdgeInsets.all(8), child: Text('m')),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => Navigator.pop(context, _h * 60 + _m),
            child: const Text('Set')),
      ],
    );
  }

  Widget _numBox(int value, int min, int max, ValueChanged<int> onChange) =>
      SizedBox(
        width: 56,
        child: TextFormField(
          initialValue: '$value',
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          onChanged: (raw) {
            final n = int.tryParse(raw);
            if (n != null) onChange(n.clamp(min, max));
          },
        ),
      );
}

String _formatRemaining(int ms) {
  final overtime = ms < 0;
  final abs = ms.abs();
  final h = abs ~/ 3600000;
  final m = (abs % 3600000) ~/ 60000;
  final s = (abs % 60000) ~/ 1000;
  return '${overtime ? '+' : ''}$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _formatTarget(int min) {
  final h = min ~/ 60;
  final m = min % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
