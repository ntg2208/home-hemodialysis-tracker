// Compiled only when --dart-define=DEMO_SEED=true.
// Writes realistic-looking data to all community Hive boxes so the app
// looks lived-in for a screen recording.

import 'package:hive/hive.dart';
import '../../app/providers.dart' show cacheBoxName;
import '../../flavor.dart';
import '../treatment/models.dart';
import '../treatment/providers.dart' show treatmentBoxName;
import '../treatment/store.dart';
import 'demo_reload_stub.dart'
    if (dart.library.html) 'demo_reload_web.dart';

const bool kDemoSeedEnabled = bool.fromEnvironment('DEMO_SEED');

Future<void> runDemoSeed() async {
  await _clearAll();
  await _seedPatient();
  await _seedSessions();
  await _seedBloodTests();
  await _seedInventory();
  // Reload so TreatmentFlow re-runs _bootstrap() and picks up the active state.
  reloadPage();
}

// ── Clear ─────────────────────────────────────────────────────────────────────

Future<void> _clearAll() async {
  for (final n in [
    communitySessionsBox,
    communityReadingsBox,
    communityBtBox,
    communityInventoryBox,
    communityEventsBox,
    communityKbBox,
    communityChatBox,
  ]) {
    await Hive.box(n).clear();
  }
  // Dry weight and active state live in the shared treatment box — delete
  // just those keys so notification prefs etc. are untouched.
  final tx = Hive.box(treatmentBoxName);
  await tx.delete('dried_weight');
  await tx.delete('active_state');
  await tx.delete('sessions_cache');
  await tx.delete('last_session');
  await Hive.box(cacheBoxName).delete('community_patient_name');
}

// ── Patient ───────────────────────────────────────────────────────────────────

Future<void> _seedPatient() async {
  await Hive.box(cacheBoxName).put('community_patient_name', 'Alex');
  // Dry weight lives in the treatment box (read by TreatmentStore).
  await Hive.box(treatmentBoxName).put('dried_weight', 72.5);
}

// ── Sessions ──────────────────────────────────────────────────────────────────

Future<void> _seedSessions() async {
  final box = Hive.box(communitySessionsBox);
  final now = DateTime.now();

  // 6 completed sessions stored individually by sessionId (HiveTreatmentRepo pattern).
  final offsets = [21, 18, 14, 11, 7, 4];
  final sessions = offsets.map((d) => _session(now.subtract(Duration(days: d)))).toList();
  for (final s in sessions) {
    await box.put(s.sessionId, s.toMap());
  }

  // Active session started 3h24m ago with 4 readings already logged.
  // Active state lives in the shared treatment box (read by TreatmentStore).
  const activeId = 'demo-active';
  final startedAt = now.subtract(const Duration(hours: 3, minutes: 24));
  final activeSession = Session(
    sessionId: activeId,
    date: _date(now),
    preWeight: 73.2,
    ufGoal: 0.7,
    preBpSys: 148,
    preBpDia: 88,
    prePulse: 76,
  );
  final activeState = ActiveState(
    screen: 'active',
    session: activeSession,
    readings: _activeReadings(activeId, startedAt),
    countdownStartedAt: startedAt.millisecondsSinceEpoch,
    targetMin: 240,
    heparinUsed: true,
    epoUsed: false,
    savedAt: now.millisecondsSinceEpoch,
  );
  await Hive.box(treatmentBoxName).put('active_state', activeState.toMap());
}

Session _session(DateTime date) {
  final v = date.day; // cheap variation without dart:math
  return Session(
    sessionId: 'demo-${_date(date)}',
    date: _date(date),
    preWeight: 73.0 + (v % 5) * 0.1,
    ufGoal: 0.5 + (v % 3) * 0.1,
    preBpSys: 140 + v % 15,
    preBpDia: 82 + v % 8,
    prePulse: 72 + v % 6,
    postWeight: 72.4 + (v % 4) * 0.1,
    postBpSys: 128 + v % 12,
    postBpDia: 76 + v % 6,
    postPulse: 70 + v % 5,
    durationMin: 220 + v % 30,
    dialysateVolume: 24.0,
    totalUf: 0.5 + (v % 3) * 0.1,
    bloodProcessed: 48.0 + (v % 5) * 0.5,
  );
}

List<PendingReading> _activeReadings(String sessionId, DateTime startedAt) => [
      _reading(sessionId, 1, startedAt,
          bpSys: 148, bpDia: 88, pulse: 76, flow: 380, vp: 122, ap: -122),
      _reading(sessionId, 2, startedAt.add(const Duration(hours: 1)),
          bpSys: 134, bpDia: 82, pulse: 74, flow: 390, vp: 124, ap: -124),
      _reading(sessionId, 3, startedAt.add(const Duration(hours: 2)),
          bpSys: 126, bpDia: 78, pulse: 72, flow: 385, vp: 126, ap: -126),
      _reading(sessionId, 4, startedAt.add(const Duration(hours: 3)),
          bpSys: 122, bpDia: 76, pulse: 70, flow: 390, vp: 124, ap: -124),
    ];

PendingReading _reading(String sessionId, int seq, DateTime time,
        {required int bpSys,
        required int bpDia,
        required int pulse,
        required int flow,
        required int vp,
        required int ap}) =>
    PendingReading(
      Reading(
        readingId: 'demo-r-$seq',
        sessionId: sessionId,
        seq: seq,
        time: time.toIso8601String(),
        bpSys: bpSys,
        bpDia: bpDia,
        pulse: pulse,
        bloodFlow: flow,
        venousPressure: vp,
        arterialPressure: ap,
      ),
      status: SaveStatus.saved,
    );

// ── Blood Tests ───────────────────────────────────────────────────────────────

Future<void> _seedBloodTests() async {
  final box = Hive.box(communityBtBox);
  final now = DateTime.now();

  // 3 monthly result sets
  final rows = <Map<String, dynamic>>[];
  for (var monthsAgo = 2; monthsAgo >= 0; monthsAgo--) {
    final date = DateTime(now.year, now.month - monthsAgo, 15);
    rows.addAll(_btMonth(date));
  }

  await box.put('bt_rows', rows);
  await box.put(
      'bt_covered_from',
      DateTime(now.year, now.month - 2, 1)
          .toIso8601String()
          .substring(0, 10));
}

List<Map<String, dynamic>> _btMonth(DateTime date) {
  final dt = date.toIso8601String();
  final v = date.day;
  return [
    // Out of range intentionally — anaemia and raised phosphate are realistic for HD
    _bt(dt, 'haemoglobin', 105.0 + v % 10, 'g/L', lo: 130, hi: 170),
    _bt(dt, 'ferritin', 280.0 + v % 40, 'μg/L', lo: 200, hi: 500),
    _bt(dt, 'potassium', 4.8 + (v % 4) * 0.1, 'mmol/L', lo: 3.5, hi: 5.5),
    _bt(dt, 'sodium', 138.0 + v % 4, 'mmol/L', lo: 135, hi: 145),
    _bt(dt, 'bicarbonate', 22.0 + v % 4, 'mmol/L', lo: 22, hi: 29),
    _bt(dt, 'phosphate', 1.8 + (v % 4) * 0.1, 'mmol/L', lo: 0.8, hi: 1.5),
    _bt(dt, 'adjusted_calcium', 2.35 + (v % 4) * 0.05, 'mmol/L', lo: 2.2, hi: 2.6),
    _bt(dt, 'albumin', 38.0 + v % 5, 'g/L', lo: 35, hi: 50),
    _bt(dt, 'creatinine', 820.0 + v % 80, 'μmol/L', lo: null, hi: 110),
    _bt(dt, 'urea', 18.0 + v % 8, 'mmol/L', lo: null, hi: 7.1),
    _bt(dt, 'egfr', 8.0 + v % 3, 'mL/min/1.73m²', lo: null, hi: null),
    _bt(dt, 'intact_pth', 45.0 + v % 20, 'pg/mL', lo: 15, hi: 65),
  ];
}

Map<String, dynamic> _bt(String datetime, String marker, double value,
        String unit, {double? lo, double? hi}) =>
    {
      'marker': marker,
      'datetime': datetime,
      'value': value,
      'unit': unit,
      'ref_low': lo,
      'ref_high': hi,
      'timing': 'pre',
      'note': '',
      'source': 'Demo Lab',
      'lab_id': 'demo-$marker-${datetime.substring(0, 10)}',
      'phase': 'routine',
      'created_at': datetime,
      'qualitative': false,
    };

// ── Inventory ─────────────────────────────────────────────────────────────────

Future<void> _seedInventory() async {
  final box = Hive.box(communityInventoryBox);
  final deliveryDate = DateTime.now().add(const Duration(days: 21));

  // SAK and CAR are low — will show red dots and generate an order
  await box.put('stock', {
    'SAK-303': 8,       // target 24 — needs ordering
    'CAR-172-C': 10,    // target 24 — needs ordering
    'UK00000880': 20,   // saline — ok
    'PAK-001': 3,       // at target
    'P00012326': 52,    // needles — above target 48
    'UK00000774': 28,   // on/off packs — ok
    'F00010983': 22,    // chlorine strips — ok
    'UK00000830': 2,    // sani-cloth
    '1990134': 2,       // hand gel
    'UK00000832': 1,    // sharps bin
    'UK00000172': 6,    // micropore tape
  });

  await box.put('cycle', {
    'delivery_date': _date(deliveryDate),
    'call_date': _date(DateTime.now().subtract(const Duration(days: 7))),
  });

  // PAK installed 21 days / ~9 sessions ago
  await box.put('pak_installed_at',
      DateTime.now().subtract(const Duration(days: 21)).toIso8601String());
  await box.put('pak_sessions', 9);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _date(DateTime d) => d.toIso8601String().substring(0, 10);
