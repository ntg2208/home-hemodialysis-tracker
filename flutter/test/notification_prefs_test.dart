import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/treatment/notification_prefs.dart';

void main() {
  test('defaults: enabled true, alertMins [120, 60, 5]', () {
    const p = NotificationPrefs.defaults;
    expect(p.enabled, isTrue);
    expect(p.alertMins, [120, 60, 5]);
  });

  test('toJson / fromJson round-trips enabled and alertMins', () {
    const original = NotificationPrefs(enabled: false, alertMins: [30, 5]);
    final restored = NotificationPrefs.fromJson(original.toJson());
    expect(restored.enabled, isFalse);
    expect(restored.alertMins, [30, 5]);
  });

  test('fromJson with missing fields falls back to defaults', () {
    final p = NotificationPrefs.fromJson({});
    expect(p.enabled, isTrue);
    expect(p.alertMins, [120, 60, 5]);
  });

  test('copyWith changes only the specified field', () {
    const p = NotificationPrefs.defaults;
    final disabled = p.copyWith(enabled: false);
    expect(disabled.enabled, isFalse);
    expect(disabled.alertMins, [120, 60, 5]);

    final newMins = p.copyWith(alertMins: [10, 5]);
    expect(newMins.enabled, isTrue);
    expect(newMins.alertMins, [10, 5]);
  });

  test('activeAlertMins returns empty list when notifications disabled', () {
    const p = NotificationPrefs(enabled: false, alertMins: [120, 60, 5]);
    expect(p.activeAlertMins, isEmpty);
  });

  test('activeAlertMins returns sorted alertMins when enabled', () {
    const p = NotificationPrefs(enabled: true, alertMins: [5, 120, 30]);
    expect(p.activeAlertMins, [120, 30, 5]);
  });
}
