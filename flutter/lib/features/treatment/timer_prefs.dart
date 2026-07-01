import 'package:hive/hive.dart';

/// Persisted treatment-timer preferences.
///
/// [defaultTargetMin] is the countdown target used for a new session when no
/// per-session target has been set. Community patients set this once to their
/// own prescribed session length; it can still be overridden per session via
/// the timer's edit control.
class TimerPrefs {
  const TimerPrefs({required this.defaultTargetMin});

  final int defaultTargetMin;

  static const defaults = TimerPrefs(defaultTargetMin: 255); // 4h 15m

  TimerPrefs copyWith({int? defaultTargetMin}) =>
      TimerPrefs(defaultTargetMin: defaultTargetMin ?? this.defaultTargetMin);

  factory TimerPrefs.fromJson(Map<dynamic, dynamic> j) => TimerPrefs(
        defaultTargetMin:
            (j['defaultTargetMin'] as num?)?.toInt() ?? defaults.defaultTargetMin,
      );

  Map<String, dynamic> toJson() => {'defaultTargetMin': defaultTargetMin};
}

/// Hive-backed store for [TimerPrefs].
class TimerPrefsStore {
  TimerPrefsStore(this._box);
  final Box _box;

  static const _key = 'timer_prefs';

  TimerPrefs read() {
    final raw = _box.get(_key);
    if (raw is Map) return TimerPrefs.fromJson(raw);
    return TimerPrefs.defaults;
  }

  Future<void> write(TimerPrefs p) => _box.put(_key, p.toJson());
}
