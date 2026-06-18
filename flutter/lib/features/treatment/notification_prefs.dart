import 'package:hive/hive.dart';

/// Persisted notification preferences for the active session countdown timer.
class NotificationPrefs {
  const NotificationPrefs({required this.enabled, required this.alertMins});

  final bool enabled;

  /// Minutes-remaining thresholds that trigger an alert, e.g. [120, 60, 5].
  final List<int> alertMins;

  static const defaults = NotificationPrefs(
    enabled: true,
    alertMins: [120, 60, 5],
  );

  /// All supported threshold options shown in the settings UI.
  static const allOptions = [120, 90, 60, 30, 15, 10, 5];

  /// Returns [alertMins] sorted descending, or empty list when disabled.
  List<int> get activeAlertMins {
    if (!enabled) return const [];
    return [...alertMins]..sort((a, b) => b.compareTo(a));
  }

  NotificationPrefs copyWith({bool? enabled, List<int>? alertMins}) =>
      NotificationPrefs(
        enabled: enabled ?? this.enabled,
        alertMins: alertMins ?? this.alertMins,
      );

  factory NotificationPrefs.fromJson(Map<dynamic, dynamic> j) =>
      NotificationPrefs(
        enabled: j['enabled'] as bool? ?? defaults.enabled,
        alertMins: j['alertMins'] is List
            ? (j['alertMins'] as List).cast<int>()
            : [...defaults.alertMins],
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'alertMins': alertMins,
      };
}

/// Hive-backed store for [NotificationPrefs].
class NotificationPrefsStore {
  NotificationPrefsStore(this._box);
  final Box _box;

  static const _key = 'notification_prefs';

  NotificationPrefs read() {
    final raw = _box.get(_key);
    if (raw is Map) return NotificationPrefs.fromJson(raw);
    return NotificationPrefs.defaults;
  }

  Future<void> write(NotificationPrefs p) =>
      _box.put(_key, p.toJson());
}
