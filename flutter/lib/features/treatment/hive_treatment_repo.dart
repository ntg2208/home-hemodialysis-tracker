import 'package:hive/hive.dart';

import '../../flavor.dart';
import 'models.dart';
import 'treatment_repo.dart';

class HiveTreatmentRepo extends TreatmentRepo {
  Box get _sessions => Hive.box(communitySessionsBox);
  Box get _readings => Hive.box(communityReadingsBox);

  @override
  Future<void> saveSession(Session s) async =>
      _sessions.put(s.sessionId, s.toMap());

  @override
  Future<void> saveReading(Reading r) async =>
      _readings.put(r.readingId, r.toMap());

  @override
  Future<void> updateSession(String sessionId, Map<String, dynamic> patch) async {
    final existing = _sessions.get(sessionId);
    if (existing == null) return;
    final merged = Map<String, dynamic>.from(existing as Map)..addAll(patch);
    await _sessions.put(sessionId, merged);
  }

  @override
  Future<List<Reading>> getReadings(String sessionId) async {
    // Eagerly collect all values first — lazy Hive iteration on web can be flaky.
    final all = _readings.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    return all
        .where((m) => m['session_id'] == sessionId)
        .map(Reading.fromMap)
        .toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    final toDelete = _readings.keys
        .where((k) {
          final v = _readings.get(k);
          if (v == null) return false;
          return (v as Map)['session_id'] == sessionId;
        })
        .toList();
    for (final k in toDelete) {
      await _readings.delete(k);
    }
    await _sessions.delete(sessionId);
  }

  @override
  Future<({List<Session> sessions, List<Reading> readings})> getAll() async {
    final sessions = _sessions.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .where((m) => (m['session_id'] as String?)?.isNotEmpty ?? false)
        .map(Session.fromMap)
        .toList();
    final readings = _readings.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .where((m) => (m['reading_id'] as String?)?.isNotEmpty ?? false)
        .map(Reading.fromMap)
        .toList();
    return (
      sessions: List<Session>.unmodifiable(sessions),
      readings: List<Reading>.unmodifiable(readings),
    );
  }
}
