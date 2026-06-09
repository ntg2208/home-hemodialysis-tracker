// Static synthetic data for test mode — treatment sessions, readings,
// blood tests, fitness, and inventory. All values are realistic HD patient data.

import '../features/blood_tests/models.dart';
import '../features/inventory/inventory_models.dart';
import '../features/treatment/models.dart';

// ── Sessions ─────────────────────────────────────────────────────────────────

final List<Session> syntheticSessions = [
  const Session(sessionId: '2026-04-01', date: '2026-04-01', preWeight: 61.2, ufGoal: 1.8, ufRate: 450, preBpSys: 138, preBpDia: 88, prePulse: 98, postWeight: 59.5, postBpSys: 118, postBpDia: 80, postPulse: 85, durationMin: 255, dialysateVolume: 49.0, totalUf: 1.5, bloodProcessed: 88.0),
  const Session(sessionId: '2026-04-03', date: '2026-04-03', preWeight: 61.5, ufGoal: 2.0, ufRate: 500, preBpSys: 142, preBpDia: 90, prePulse: 102, postWeight: 59.7, postBpSys: 122, postBpDia: 82, postPulse: 88, durationMin: 258, dialysateVolume: 49.0, totalUf: 1.7, bloodProcessed: 91.0),
  const Session(sessionId: '2026-04-06', date: '2026-04-06', preWeight: 61.0, ufGoal: 1.6, ufRate: 400, preBpSys: 135, preBpDia: 85, prePulse: 95, postWeight: 59.5, postBpSys: 115, postBpDia: 78, postPulse: 82, durationMin: 252, dialysateVolume: 49.0, totalUf: 1.4, bloodProcessed: 86.0),
  const Session(sessionId: '2026-04-08', date: '2026-04-08', preWeight: 62.0, ufGoal: 2.1, ufRate: 525, preBpSys: 145, preBpDia: 92, prePulse: 105, postWeight: 59.8, postBpSys: 125, postBpDia: 83, postPulse: 90, durationMin: 260, dialysateVolume: 49.0, totalUf: 1.9, bloodProcessed: 93.0),
  const Session(sessionId: '2026-04-11', date: '2026-04-11', preWeight: 61.3, ufGoal: 1.9, ufRate: 475, preBpSys: 140, preBpDia: 89, prePulse: 100, postWeight: 59.5, postBpSys: 119, postBpDia: 81, postPulse: 86, durationMin: 255, dialysateVolume: 49.0, totalUf: 1.6, bloodProcessed: 89.0),
  const Session(sessionId: '2026-04-13', date: '2026-04-13', preWeight: 60.8, ufGoal: 1.5, ufRate: 375, preBpSys: 132, preBpDia: 84, prePulse: 92, postWeight: 59.4, postBpSys: 112, postBpDia: 77, postPulse: 80, durationMin: 248, dialysateVolume: 49.0, totalUf: 1.3, bloodProcessed: 85.0),
  const Session(sessionId: '2026-04-16', date: '2026-04-16', preWeight: 61.8, ufGoal: 2.2, ufRate: 550, preBpSys: 148, preBpDia: 93, prePulse: 108, postWeight: 60.0, postBpSys: 128, postBpDia: 85, postPulse: 92, durationMin: 262, dialysateVolume: 49.0, totalUf: 2.0, bloodProcessed: 95.0),
  const Session(sessionId: '2026-04-18', date: '2026-04-18', preWeight: 61.1, ufGoal: 1.7, ufRate: 425, preBpSys: 136, preBpDia: 86, prePulse: 96, postWeight: 59.5, postBpSys: 116, postBpDia: 79, postPulse: 83, durationMin: 253, dialysateVolume: 49.0, totalUf: 1.5, bloodProcessed: 87.0),
  const Session(sessionId: '2026-04-21', date: '2026-04-21', preWeight: 61.6, ufGoal: 2.0, ufRate: 500, preBpSys: 141, preBpDia: 90, prePulse: 101, postWeight: 59.7, postBpSys: 121, postBpDia: 82, postPulse: 87, durationMin: 257, dialysateVolume: 49.0, totalUf: 1.8, bloodProcessed: 90.0),
  const Session(sessionId: '2026-04-23', date: '2026-04-23', preWeight: 60.7, ufGoal: 1.4, ufRate: 350, preBpSys: 130, preBpDia: 83, prePulse: 90, postWeight: 59.4, postBpSys: 110, postBpDia: 76, postPulse: 79, durationMin: 245, dialysateVolume: 49.0, totalUf: 1.2, bloodProcessed: 84.0),
  const Session(sessionId: '2026-04-26', date: '2026-04-26', preWeight: 61.9, ufGoal: 2.1, ufRate: 525, preBpSys: 144, preBpDia: 91, prePulse: 104, postWeight: 59.8, postBpSys: 124, postBpDia: 84, postPulse: 89, durationMin: 259, dialysateVolume: 49.0, totalUf: 1.9, bloodProcessed: 92.0),
  const Session(sessionId: '2026-04-28', date: '2026-04-28', preWeight: 61.4, ufGoal: 1.9, ufRate: 475, preBpSys: 139, preBpDia: 88, prePulse: 99, postWeight: 59.6, postBpSys: 120, postBpDia: 81, postPulse: 86, durationMin: 256, dialysateVolume: 49.0, totalUf: 1.7, bloodProcessed: 90.0),
  const Session(sessionId: '2026-05-01', date: '2026-05-01', preWeight: 61.2, ufGoal: 1.8, ufRate: 450, preBpSys: 137, preBpDia: 87, prePulse: 97, postWeight: 59.5, postBpSys: 117, postBpDia: 80, postPulse: 84, durationMin: 254, dialysateVolume: 49.0, totalUf: 1.6, bloodProcessed: 88.0),
  const Session(sessionId: '2026-05-03', date: '2026-05-03', preWeight: 62.1, ufGoal: 2.2, ufRate: 550, preBpSys: 147, preBpDia: 93, prePulse: 107, postWeight: 60.0, postBpSys: 127, postBpDia: 85, postPulse: 91, durationMin: 261, dialysateVolume: 49.0, totalUf: 2.0, bloodProcessed: 94.0),
  const Session(sessionId: '2026-05-06', date: '2026-05-06', preWeight: 61.0, ufGoal: 1.6, ufRate: 400, preBpSys: 134, preBpDia: 85, prePulse: 94, postWeight: 59.5, postBpSys: 114, postBpDia: 78, postPulse: 81, durationMin: 251, dialysateVolume: 49.0, totalUf: 1.4, bloodProcessed: 86.0),
  const Session(sessionId: '2026-05-08', date: '2026-05-08', preWeight: 61.7, ufGoal: 2.0, ufRate: 500, preBpSys: 143, preBpDia: 91, prePulse: 103, postWeight: 59.8, postBpSys: 123, postBpDia: 83, postPulse: 88, durationMin: 258, dialysateVolume: 49.0, totalUf: 1.8, bloodProcessed: 91.0),
  const Session(sessionId: '2026-05-11', date: '2026-05-11', preWeight: 61.3, ufGoal: 1.8, ufRate: 450, preBpSys: 138, preBpDia: 88, prePulse: 98, postWeight: 59.6, postBpSys: 118, postBpDia: 80, postPulse: 85, durationMin: 255, dialysateVolume: 49.0, totalUf: 1.6, bloodProcessed: 89.0),
  const Session(sessionId: '2026-05-14', date: '2026-05-14', preWeight: 60.9, ufGoal: 1.5, ufRate: 375, preBpSys: 133, preBpDia: 84, prePulse: 93, postWeight: 59.4, postBpSys: 113, postBpDia: 77, postPulse: 81, durationMin: 249, dialysateVolume: 49.0, totalUf: 1.3, bloodProcessed: 85.0),
  const Session(sessionId: '2026-05-17', date: '2026-05-17', preWeight: 61.5, ufGoal: 2.0, ufRate: 500, preBpSys: 140, preBpDia: 89, prePulse: 100, postWeight: 59.6, postBpSys: 120, postBpDia: 81, postPulse: 86, durationMin: 256, dialysateVolume: 49.0, totalUf: 1.7, bloodProcessed: 90.0),
  const Session(sessionId: '2026-05-20', date: '2026-05-20', preWeight: 61.8, ufGoal: 2.1, ufRate: 525, preBpSys: 146, preBpDia: 92, prePulse: 106, postWeight: 59.9, postBpSys: 126, postBpDia: 84, postPulse: 90, durationMin: 260, dialysateVolume: 49.0, totalUf: 1.9, bloodProcessed: 93.0),
];

// ── Readings ──────────────────────────────────────────────────────────────────
// 3 readings per session at 18:30, 19:30, 20:30.

Reading _r(String sid, int seq, String time, int sys, int dia, int pulse, int vp, int ap) =>
    Reading(
      readingId: '$sid-r$seq',
      sessionId: sid,
      seq: seq,
      time: time,
      bpSys: sys,
      bpDia: dia,
      pulse: pulse,
      bloodFlow: 350,
      venousPressure: vp,
      arterialPressure: ap,
    );

final List<Reading> syntheticReadings = [
  // 2026-04-01
  _r('2026-04-01', 1, '18:30', 136, 86, 96, 232, 174), _r('2026-04-01', 2, '19:30', 128, 83, 92, 215, 188), _r('2026-04-01', 3, '20:30', 131, 84, 89, 208, 193),
  // 2026-04-03
  _r('2026-04-03', 1, '18:30', 140, 88, 100, 238, 178), _r('2026-04-03', 2, '19:30', 132, 85, 95, 220, 192), _r('2026-04-03', 3, '20:30', 134, 86, 91, 212, 197),
  // 2026-04-06
  _r('2026-04-06', 1, '18:30', 133, 84, 93, 228, 170), _r('2026-04-06', 2, '19:30', 125, 81, 89, 210, 184), _r('2026-04-06', 3, '20:30', 128, 82, 86, 204, 190),
  // 2026-04-08
  _r('2026-04-08', 1, '18:30', 143, 90, 103, 245, 182), _r('2026-04-08', 2, '19:30', 135, 86, 98, 228, 196), _r('2026-04-08', 3, '20:30', 137, 87, 94, 218, 200),
  // 2026-04-11
  _r('2026-04-11', 1, '18:30', 138, 87, 98, 234, 176), _r('2026-04-11', 2, '19:30', 130, 84, 94, 218, 190), _r('2026-04-11', 3, '20:30', 132, 85, 90, 210, 195),
  // 2026-04-13
  _r('2026-04-13', 1, '18:30', 130, 83, 90, 225, 168), _r('2026-04-13', 2, '19:30', 122, 80, 86, 208, 182), _r('2026-04-13', 3, '20:30', 124, 81, 83, 202, 188),
  // 2026-04-16
  _r('2026-04-16', 1, '18:30', 146, 91, 106, 250, 186), _r('2026-04-16', 2, '19:30', 138, 87, 101, 232, 200), _r('2026-04-16', 3, '20:30', 140, 88, 97, 222, 204),
  // 2026-04-18
  _r('2026-04-18', 1, '18:30', 134, 85, 94, 230, 172), _r('2026-04-18', 2, '19:30', 126, 82, 90, 213, 186), _r('2026-04-18', 3, '20:30', 129, 83, 87, 206, 192),
  // 2026-04-21
  _r('2026-04-21', 1, '18:30', 139, 88, 99, 236, 177), _r('2026-04-21', 2, '19:30', 131, 85, 95, 219, 191), _r('2026-04-21', 3, '20:30', 133, 86, 91, 211, 196),
  // 2026-04-23
  _r('2026-04-23', 1, '18:30', 128, 82, 88, 222, 166), _r('2026-04-23', 2, '19:30', 120, 79, 84, 205, 180), _r('2026-04-23', 3, '20:30', 122, 80, 81, 200, 186),
  // 2026-04-26
  _r('2026-04-26', 1, '18:30', 142, 90, 102, 242, 180), _r('2026-04-26', 2, '19:30', 134, 86, 97, 225, 194), _r('2026-04-26', 3, '20:30', 136, 87, 93, 216, 198),
  // 2026-04-28
  _r('2026-04-28', 1, '18:30', 137, 87, 97, 233, 175), _r('2026-04-28', 2, '19:30', 129, 84, 93, 216, 189), _r('2026-04-28', 3, '20:30', 131, 85, 89, 208, 194),
  // 2026-05-01
  _r('2026-05-01', 1, '18:30', 135, 86, 95, 230, 173), _r('2026-05-01', 2, '19:30', 127, 83, 91, 213, 187), _r('2026-05-01', 3, '20:30', 130, 84, 88, 207, 192),
  // 2026-05-03
  _r('2026-05-03', 1, '18:30', 145, 91, 105, 248, 184), _r('2026-05-03', 2, '19:30', 137, 87, 100, 230, 198), _r('2026-05-03', 3, '20:30', 139, 88, 96, 220, 202),
  // 2026-05-06
  _r('2026-05-06', 1, '18:30', 132, 84, 92, 227, 170), _r('2026-05-06', 2, '19:30', 124, 81, 88, 210, 184), _r('2026-05-06', 3, '20:30', 126, 82, 85, 203, 189),
  // 2026-05-08
  _r('2026-05-08', 1, '18:30', 141, 89, 101, 240, 179), _r('2026-05-08', 2, '19:30', 133, 85, 96, 222, 193), _r('2026-05-08', 3, '20:30', 135, 86, 92, 213, 197),
  // 2026-05-11
  _r('2026-05-11', 1, '18:30', 136, 87, 96, 231, 174), _r('2026-05-11', 2, '19:30', 128, 84, 92, 214, 188), _r('2026-05-11', 3, '20:30', 130, 85, 88, 207, 193),
  // 2026-05-14
  _r('2026-05-14', 1, '18:30', 131, 83, 91, 226, 169), _r('2026-05-14', 2, '19:30', 123, 80, 87, 209, 183), _r('2026-05-14', 3, '20:30', 125, 81, 84, 203, 188),
  // 2026-05-17
  _r('2026-05-17', 1, '18:30', 138, 88, 98, 234, 176), _r('2026-05-17', 2, '19:30', 130, 85, 94, 217, 190), _r('2026-05-17', 3, '20:30', 132, 86, 90, 210, 195),
  // 2026-05-20
  _r('2026-05-20', 1, '18:30', 144, 90, 104, 246, 182), _r('2026-05-20', 2, '19:30', 136, 86, 99, 228, 196), _r('2026-05-20', 3, '20:30', 138, 87, 95, 219, 200),
];

// ── Blood Tests ───────────────────────────────────────────────────────────────
// Two test dates — some markers in range, some elevated (realistic for HD).

BloodTestRow _bt(String marker, String date, double value, String unit,
        double? low, double? high) =>
    BloodTestRow(
      marker: marker,
      datetime: '${date}T09:00:00',
      value: value,
      unit: unit,
      refLow: low,
      refHigh: high,
      timing: 'pre',
      note: '',
      source: 'lab',
      labId: 'TEST-${date.replaceAll('-', '')}',
      phase: 'home-hd',
      createdAt: '${date}T09:00:00',
      qualitative: false,
    );

final List<BloodTestRow> syntheticBloodTestRows = [
  // 2026-05-15 — latest test
  _bt('creatinine',       '2026-05-15', 842.0,  'umol/L', 59.0,  104.0),  // high (expected in HD)
  _bt('potassium',        '2026-05-15', 5.3,    'mmol/L', 3.5,   5.0),    // slightly elevated
  _bt('haemoglobin',      '2026-05-15', 108.0,  'g/L',    120.0, 160.0),  // low (anaemia)
  _bt('urea',             '2026-05-15', 19.8,   'mmol/L', 2.5,   7.8),    // high (pre-dialysis)
  _bt('phosphate',        '2026-05-15', 1.92,   'mmol/L', 0.8,   1.5),    // elevated
  _bt('albumin',          '2026-05-15', 37.0,   'g/L',    35.0,  50.0),   // in range
  _bt('adjusted_calcium', '2026-05-15', 2.35,   'mmol/L', 2.2,   2.6),    // in range
  _bt('bicarbonate',      '2026-05-15', 21.0,   'mmol/L', 22.0,  29.0),   // borderline low
  // 2026-04-10 — previous test
  _bt('creatinine',       '2026-04-10', 878.0,  'umol/L', 59.0,  104.0),
  _bt('potassium',        '2026-04-10', 5.6,    'mmol/L', 3.5,   5.0),
  _bt('haemoglobin',      '2026-04-10', 103.0,  'g/L',    120.0, 160.0),
  _bt('urea',             '2026-04-10', 22.1,   'mmol/L', 2.5,   7.8),
  _bt('phosphate',        '2026-04-10', 2.15,   'mmol/L', 0.8,   1.5),
  _bt('albumin',          '2026-04-10', 35.5,   'g/L',    35.0,  50.0),
  _bt('adjusted_calcium', '2026-04-10', 2.28,   'mmol/L', 2.2,   2.6),
  _bt('bicarbonate',      '2026-04-10', 19.5,   'mmol/L', 22.0,  29.0),
];

// ── Fitness Summary ───────────────────────────────────────────────────────────
// JSON shape matches FitnessSummary.fromJson and the keys read by ChatContextBuilder.

final Map<String, dynamic> syntheticFitnessSummaryJson = {
  'generated_at': '2026-05-20T08:00:00Z',
  'types': [
    {
      'type': 'daily-resting-heart-rate',
      'last_synced': '2026-05-20',
      'count': 90,
      'last_date': '2026-05-20',
      'stale': false,
      'latest': {'beatsPerMinute': 71},
    },
    {
      'type': 'daily-heart-rate-variability',
      'last_synced': '2026-05-20',
      'count': 90,
      'last_date': '2026-05-20',
      'stale': false,
      'latest': {'averageHeartRateVariabilityMilliseconds': 48},
    },
    {
      'type': 'sleep',
      'last_synced': '2026-05-20',
      'count': 90,
      'last_date': '2026-05-20',
      'stale': false,
      'latest': {
        'summary': {
          'minutesAsleep': '440',
          'stagesSummary': [
            {'type': 'DEEP', 'minutes': '88'},
            {'type': 'REM',  'minutes': '112'},
            {'type': 'LIGHT','minutes': '200'},
            {'type': 'WAKE', 'minutes': '18'},
          ],
        },
      },
    },
    {
      'type': 'steps',
      'last_synced': '2026-05-20',
      'count': 90,
      'last_date': '2026-05-20',
      'stale': false,
      'latest': {'steps': 6240},
    },
  ],
  'totals': {'types': 4, 'healthy': 4, 'stale': 0, 'bytes': 204800},
};

// ── Inventory ─────────────────────────────────────────────────────────────────
// Mix of low (below target) and high stock to exercise inventory UI.

final InventoryResponse syntheticInventory = InventoryResponse(
  stock: const {
    'SAK-303':      3,   // dialysate — CRITICAL LOW  (target 24)
    'CAR-172-C':    18,  // cartridges — ok           (target 24)
    'UK00000880':   2,   // saline 1L  — CRITICAL LOW (target 24)
    'PAK-001':      2,   // PAK        — ok           (target 3)
    'P00012326':    95,  // needles    — HIGH         (target 48)
    'UK00000774':   68,  // on/off     — HIGH         (target 24)
    'F00010983':    6,   // chlorine   — LOW          (target 24)
    'UK00000830':   4,   // sani-cloth — HIGH         (target 1)
    '1990134':      1,   // hand gel   — ok           (target 1)
    'UK00000832':   2,   // sharps bin — HIGH         (target 1)
    'UK00000172':   4,   // micropore  — ok           (target 4)
    'heparin':      1,   // heparin    — CRITICAL LOW (target 8)
    'epo':          5,   // EPO        — HIGH         (target 4)
  },
  cycle: Cycle(
    callDate: '2026-06-10',
    deliveryDate: '2026-06-17',
    // Units stored as boxes × boxSize so ViewOrderSheet displays non-zero box counts.
    // SAK-303 boxSize=2 → 11 boxes=22, UK00000880 boxSize=10 → 3 boxes=30,
    // CAR-172-C boxSize=6 → 1 box=6, F00010983 boxSize=100 → 1 box=100.
    order: const {
      'SAK-303': 22, 'CAR-172-C': 6, 'UK00000880': 30, 'F00010983': 100,
    },
    orderPlacedAt: '2026-06-04T10:00:00Z',
  ),
  pakInstalledAt: '2026-05-01T00:00:00Z',
  pakSessions: 19,
);
