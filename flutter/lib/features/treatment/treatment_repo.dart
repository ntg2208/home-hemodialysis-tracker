import 'package:cloud_firestore/cloud_firestore.dart';

import '../../firebase/firebase_init.dart';
import 'models.dart';

/// Client-side Firestore access for Treatment. Port of
/// frontend/src/routes/Treatment/api.ts. Writes/reads `treatment_sessions` and
/// `treatment_readings` directly (no Cloud Run) under the custom-token session.
class TreatmentRepo {
  CollectionReference<Map<String, dynamic>> get _sessions =>
      firestore.collection('treatment_sessions');
  CollectionReference<Map<String, dynamic>> get _readings =>
      firestore.collection('treatment_readings');

  Future<void> saveSession(Session s) =>
      _sessions.doc(s.sessionId).set(s.toMap());

  Future<void> saveReading(Reading r) =>
      _readings.doc(r.readingId).set(r.toMap());

  /// Merge-write so a partial patch (post-treatment fields) never clobbers the
  /// session created in Pre.
  Future<void> updateSession(String sessionId, Map<String, dynamic> patch) =>
      _sessions.doc(sessionId).set(patch, SetOptions(merge: true));

  Future<({List<Session> sessions, List<Reading> readings})> getAll() async {
    final results = await Future.wait([_sessions.get(), _readings.get()]);
    final sessions = <Session>[];
    for (final doc in results[0].docs) {
      final data = doc.data();
      // Empty-row guard (port of stripEmptyRows): skip docs missing the key.
      if ((data['session_id'] as String?)?.isNotEmpty ?? false) {
        sessions.add(Session.fromMap(data));
      }
    }
    final readings = <Reading>[];
    for (final doc in results[1].docs) {
      final data = doc.data();
      if ((data['reading_id'] as String?)?.isNotEmpty ?? false) {
        readings.add(Reading.fromMap(data));
      }
    }
    return (sessions: sessions, readings: readings);
  }
}

/// Maps a Firestore failure to a stable code, mirroring the React wrapError.
String treatmentErrorCode(Object e) {
  final msg = e.toString().toLowerCase();
  return msg.contains('permission') ? 'unauthorized' : 'network_error';
}
