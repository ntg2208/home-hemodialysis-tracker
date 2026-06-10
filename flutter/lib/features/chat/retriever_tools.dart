import '../blood_tests/models.dart';
import '../treatment/models.dart';

class RetrieverTools {
  RetrieverTools({
    required this.sessions,
    required this.readings,
    required this.bloodTestRows,
    DateTime? now,
  }) : _now = now ?? DateTime.now();

  final List<Session> sessions;
  final List<Reading> readings;
  final List<BloodTestRow> bloodTestRows;
  final DateTime _now;

  Map<String, dynamic> getBloodMarkers(List<String> markers, int monthsBack) {
    final cutoff = DateTime(_now.year, _now.month - monthsBack, 1);

    final results = markers.map((marker) {
      final parsed = bloodTestRows
          .where((r) => r.marker == marker)
          .map((r) => (r, DateTime.tryParse(r.datetime)))
          .where((pair) => pair.$2 != null && !pair.$2!.isBefore(cutoff))
          .toList()
        ..sort((a, b) => b.$2!.compareTo(a.$2!));

      return {
        'marker': marker,
        'rows': parsed
            .map((pair) {
              final r = pair.$1;
              final dt = pair.$2!;
              return {
                'date':
                    '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}',
                'value': r.value,
                'unit': r.unit,
                'ref_low': r.refLow,
                'ref_high': r.refHigh,
                'in_range': _inRange(r.value, r.refLow, r.refHigh),
                'timing': r.timing,
              };
            })
            .toList(),
      };
    }).toList();

    return {'results': results};
  }

  Map<String, dynamic> getSessions({
    int? lastN,
    String? from,
    String? to,
    bool includeReadings = false,
  }) {
    var sorted = [...sessions]..sort((a, b) => b.date.compareTo(a.date));

    List<Session> filtered;
    if (from != null || to != null) {
      filtered = sorted.where((s) {
        if (from != null && s.date.compareTo(from) < 0) return false;
        if (to != null && s.date.compareTo(to) > 0) return false;
        return true;
      }).toList();
    } else {
      final n = (lastN ?? 7).clamp(1, 30);
      filtered = sorted.take(n).toList();
    }

    final sessionMaps = filtered.map((s) {
      final weightRemoved = (s.preWeight != null && s.postWeight != null)
          ? double.parse((s.preWeight! - s.postWeight!).toStringAsFixed(1))
          : null;
      final ufAchievementPct =
          (s.ufGoal != null && s.ufGoal! > 0 && s.totalUf != null)
              ? ((s.totalUf! / s.ufGoal!) * 100).round()
              : null;

      final Map<String, dynamic> m = {
        'date': s.date,
        'session_id': s.sessionId,
        'pre_weight': s.preWeight,
        'post_weight': s.postWeight,
        'weight_removed': weightRemoved,
        'pre_bp': s.preBpSys != null && s.preBpDia != null ? '${s.preBpSys}/${s.preBpDia}' : null,
        'post_bp': s.postBpSys != null && s.postBpDia != null ? '${s.postBpSys}/${s.postBpDia}' : null,
        'pre_pulse': s.prePulse,
        'post_pulse': s.postPulse,
        'uf_goal': s.ufGoal,
        'total_uf': s.totalUf,
        'uf_achievement_pct': ufAchievementPct,
        'duration_min': s.durationMin,
        'comment': s.comment ?? '',
      };

      if (includeReadings) {
        final sessionReadings = readings
            .where((r) => r.sessionId == s.sessionId)
            .toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));
        m['readings'] = sessionReadings
            .map((r) => {
                  'time': r.time,
                  'bp': r.bpSys != null && r.bpDia != null ? '${r.bpSys}/${r.bpDia}' : null,
                  'pulse': r.pulse,
                  'blood_flow': r.bloodFlow,
                })
            .toList();
      } else {
        m['readings'] = <dynamic>[];
      }

      return m;
    }).toList();

    return {'sessions': sessionMaps, 'count': sessionMaps.length};
  }

  Map<String, dynamic> getOutOfRangeMarkers() =>
      {'draw_date': null, 'out_of_range': <dynamic>[], 'total_markers_checked': 0};

  bool _inRange(double value, double? refLow, double? refHigh) {
    if (refLow != null && value < refLow) return false;
    if (refHigh != null && value > refHigh) return false;
    return true;
  }
}
