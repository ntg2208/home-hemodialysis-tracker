// Treatment domain models. Mirrors frontend/src/routes/Treatment/schemas.ts.
// Firestore stores all numerics as real numbers.

double? _d(Object? v) => v == null ? null : (v as num).toDouble();
int? _i(Object? v) => v == null ? null : (v as num).round();

class Session {
  const Session({
    required this.sessionId,
    required this.date,
    this.preWeight,
    this.ufGoal,
    this.ufRate,
    this.preBpSys,
    this.preBpDia,
    this.prePulse,
    this.postWeight,
    this.postBpSys,
    this.postBpDia,
    this.postPulse,
    this.durationMin,
    this.dialysateVolume,
    this.totalUf,
    this.bloodProcessed,
    this.createdAt,
  });

  final String sessionId;
  final String date;
  final double? preWeight;
  final double? ufGoal;
  final double? ufRate;
  final int? preBpSys;
  final int? preBpDia;
  final int? prePulse;
  final double? postWeight;
  final int? postBpSys;
  final int? postBpDia;
  final int? postPulse;
  final int? durationMin;
  final double? dialysateVolume;
  final double? totalUf;
  final double? bloodProcessed;
  final String? createdAt;

  /// Firestore document map. Drops nulls so we never overwrite a field with null.
  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{'session_id': sessionId, 'date': date};
    void put(String k, Object? v) {
      if (v != null) m[k] = v;
    }

    put('pre_weight', preWeight);
    put('uf_goal', ufGoal);
    put('uf_rate', ufRate);
    put('pre_bp_sys', preBpSys);
    put('pre_bp_dia', preBpDia);
    put('pre_pulse', prePulse);
    put('post_weight', postWeight);
    put('post_bp_sys', postBpSys);
    put('post_bp_dia', postBpDia);
    put('post_pulse', postPulse);
    put('duration_min', durationMin);
    put('dialysate_volume', dialysateVolume);
    put('total_uf', totalUf);
    put('blood_processed', bloodProcessed);
    put('created_at', createdAt);
    return m;
  }

  factory Session.fromMap(Map<String, dynamic> m) => Session(
        sessionId: m['session_id'] as String,
        date: m['date'] as String,
        preWeight: _d(m['pre_weight']),
        ufGoal: _d(m['uf_goal']),
        ufRate: _d(m['uf_rate']),
        preBpSys: _i(m['pre_bp_sys']),
        preBpDia: _i(m['pre_bp_dia']),
        prePulse: _i(m['pre_pulse']),
        postWeight: _d(m['post_weight']),
        postBpSys: _i(m['post_bp_sys']),
        postBpDia: _i(m['post_bp_dia']),
        postPulse: _i(m['post_pulse']),
        durationMin: _i(m['duration_min']),
        dialysateVolume: _d(m['dialysate_volume']),
        totalUf: _d(m['total_uf']),
        bloodProcessed: _d(m['blood_processed']),
        createdAt: m['created_at'] as String?,
      );
}

class Reading {
  const Reading({
    required this.readingId,
    required this.sessionId,
    required this.seq,
    required this.time,
    this.bpSys,
    this.bpDia,
    this.pulse,
    this.bloodFlow,
    this.venousPressure,
    this.arterialPressure,
    this.note,
    this.createdAt,
  });

  final String readingId;
  final String sessionId;
  final int seq;
  final String time;
  final int? bpSys;
  final int? bpDia;
  final int? pulse;
  final int? bloodFlow;
  final int? venousPressure;
  final int? arterialPressure;
  final String? note;
  final String? createdAt;

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'reading_id': readingId,
      'session_id': sessionId,
      'seq': seq,
      'time': time,
    };
    void put(String k, Object? v) {
      if (v != null) m[k] = v;
    }

    put('bp_sys', bpSys);
    put('bp_dia', bpDia);
    put('pulse', pulse);
    put('blood_flow', bloodFlow);
    put('venous_pressure', venousPressure);
    put('arterial_pressure', arterialPressure);
    put('note', note);
    put('created_at', createdAt);
    return m;
  }

  factory Reading.fromMap(Map<String, dynamic> m) => Reading(
        readingId: m['reading_id'] as String,
        sessionId: m['session_id'] as String,
        seq: _i(m['seq']) ?? 0,
        time: (m['time'] ?? '') as String,
        bpSys: _i(m['bp_sys']),
        bpDia: _i(m['bp_dia']),
        pulse: _i(m['pulse']),
        bloodFlow: _i(m['blood_flow']),
        venousPressure: _i(m['venous_pressure']),
        arterialPressure: _i(m['arterial_pressure']),
        note: m['note'] as String?,
        createdAt: m['created_at'] as String?,
      );
}

enum SaveStatus { pending, saved, error }

/// A reading plus its optimistic-save status (UI-only; never written to Firestore).
class PendingReading {
  PendingReading(this.reading, {this.status = SaveStatus.pending, this.errorMsg});
  final Reading reading;
  SaveStatus status;
  String? errorMsg;
}

/// Per-session consumables carried Active → Post, fed to the inventory deduction.
class SessionConsumed {
  const SessionConsumed({
    this.needles = 2,
    this.onOffPacks = 1,
    this.heparinUsed = false,
    this.durationMin,
  });
  final int needles;
  final int onOffPacks;
  final bool heparinUsed;
  final int? durationMin;
}
