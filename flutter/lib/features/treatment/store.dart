import 'package:hive/hive.dart';

import '../../flavor.dart';
import 'models.dart';

/// Local persistence for Treatment. Mirrors frontend/src/routes/Treatment/storage.ts:
/// dry weight, sessions cache, last session, and the active-session restore state
/// (24h TTL). Backed by a single Hive box (IndexedDB on web, file on mobile).
const _activeTtlMs = 24 * 60 * 60 * 1000;
const driedWeightDefault = 59.0;

Map<String, dynamic> _asStringMap(Object? v) =>
    Map<String, dynamic>.from(v as Map);

class ActiveState {
  ActiveState({
    required this.screen,
    this.session,
    this.existingIds,
    this.readings,
    this.heparinUsed,
    this.epoUsed,
    this.consumed,
    this.countdownStartedAt,
    this.targetMin,
    this.comment,
    required this.savedAt,
  });

  final String screen; // 'pre' | 'active' | 'post'
  final Session? session;
  final List<String>? existingIds;
  final List<PendingReading>? readings;
  final bool? heparinUsed;
  final bool? epoUsed;
  final SessionConsumed? consumed;
  final int? countdownStartedAt;
  final int? targetMin;
  final String? comment;
  final int savedAt;

  Map<String, dynamic> toMap() => {
        'screen': screen,
        if (session != null) 'session': session!.toMap(),
        if (existingIds != null) 'existingIds': existingIds,
        if (readings != null)
          'readings': readings!
              .map((p) => {
                    ...p.reading.toMap(),
                    'status': p.status.name,
                    if (p.errorMsg != null) 'errorMsg': p.errorMsg,
                  })
              .toList(),
        if (heparinUsed != null) 'heparinUsed': heparinUsed,
        if (epoUsed != null) 'epoUsed': epoUsed,
        if (consumed != null)
          'consumed': {
            'needles': consumed!.needles,
            'onOffPacks': consumed!.onOffPacks,
            'heparinUsed': consumed!.heparinUsed,
            'epoUsed': consumed!.epoUsed,
            if (consumed!.durationMin != null)
              'durationMin': consumed!.durationMin,
          },
        if (countdownStartedAt != null) 'countdownStartedAt': countdownStartedAt,
        if (targetMin != null) 'targetMin': targetMin,
        if (comment != null) 'comment': comment,
        'savedAt': savedAt,
      };

  static ActiveState fromMap(Map<String, dynamic> m) {
    SaveStatus parseStatus(String? s) =>
        SaveStatus.values.firstWhere((e) => e.name == s,
            orElse: () => SaveStatus.saved);
    return ActiveState(
      screen: m['screen'] as String,
      session: m['session'] == null
          ? null
          : Session.fromMap(_asStringMap(m['session'])),
      existingIds: (m['existingIds'] as List?)?.cast<String>(),
      readings: (m['readings'] as List?)?.map((r) {
        final rm = _asStringMap(r);
        return PendingReading(
          Reading.fromMap(rm),
          status: parseStatus(rm['status'] as String?),
          errorMsg: rm['errorMsg'] as String?,
        );
      }).toList(),
      heparinUsed: m['heparinUsed'] as bool?,
      epoUsed: m['epoUsed'] as bool?,
      consumed: m['consumed'] == null
          ? null
          : () {
              final c = _asStringMap(m['consumed']);
              return SessionConsumed(
                needles: (c['needles'] as num?)?.toInt() ?? 2,
                onOffPacks: (c['onOffPacks'] as num?)?.toInt() ?? 1,
                heparinUsed: c['heparinUsed'] as bool? ?? true,
                epoUsed: c['epoUsed'] as bool? ?? true,
                durationMin: (c['durationMin'] as num?)?.toInt(),
              );
            }(),
      countdownStartedAt: (m['countdownStartedAt'] as num?)?.toInt(),
      targetMin: (m['targetMin'] as num?)?.toInt(),
      comment: m['comment'] as String?,
      savedAt: (m['savedAt'] as num).toInt(),
    );
  }
}

class TreatmentStore {
  TreatmentStore(this._box);
  final Box _box;

  static const _driedKey = 'dried_weight';
  static const _sessionsKey = 'sessions_cache';
  static const _lastKey = 'last_session';
  static const _activeKey = 'active_state';

  double getDriedWeight() {
    final v = _box.get(_driedKey);
    if (v is num && v.isFinite) return v.toDouble();
    return kCommunity ? 0.0 : driedWeightDefault;
  }

  Future<void> saveDriedWeight(double kg) => _box.put(_driedKey, kg);

  Future<void> setDriedWeight(double kg) => _box.put(_driedKey, kg);

  List<Session>? getCachedSessions() {
    final raw = _box.get(_sessionsKey);
    if (raw is! List) return null;
    return raw.map((e) => Session.fromMap(_asStringMap(e))).toList();
  }

  Future<void> saveCachedSessions(List<Session> sessions) =>
      _box.put(_sessionsKey, sessions.map((s) => s.toMap()).toList());

  Session? getLastSession() {
    final raw = _box.get(_lastKey);
    return raw is Map ? Session.fromMap(_asStringMap(raw)) : null;
  }

  Future<void> saveLastSession(Session s) => _box.put(_lastKey, s.toMap());

  ActiveState? getActiveState() {
    final raw = _box.get(_activeKey);
    if (raw is! Map) return null;
    final s = ActiveState.fromMap(_asStringMap(raw));
    if (DateTime.now().millisecondsSinceEpoch - s.savedAt > _activeTtlMs) {
      _box.delete(_activeKey);
      return null;
    }
    return s;
  }

  Future<void> saveActiveState(ActiveState s) =>
      _box.put(_activeKey, s.toMap());

  Future<void> clearActiveState() => _box.delete(_activeKey);
}
