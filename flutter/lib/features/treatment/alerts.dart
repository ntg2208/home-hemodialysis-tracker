import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

/// Active-session timer alerts. On mobile: a local notification + vibration that
/// reach the user even when the app is backgrounded. On web: a no-op here — the
/// caller still shows the in-app banner, which is the documented web limitation
/// (a browser tab can't notify when closed). See the plan's per-platform section.
class TimerAlerts {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static Future<void> _ensureInit() async {
    if (_inited || kIsWeb) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    _inited = true;
  }

  /// Request notification permission (Android 13+, iOS) when the countdown starts.
  static Future<void> requestPermission() async {
    if (kIsWeb) return;
    try {
      await _ensureInit();
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {/* best-effort */}
  }

  static Future<void> fire(String message) async {
    if (kIsWeb) return; // web: in-app banner only (handled by the caller)
    try {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(pattern: const [0, 200, 100, 200]);
      }
    } catch (_) {}
    try {
      await _ensureInit();
      await _plugin.show(
        id: 0,
        title: 'HD Session',
        body: message,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'hd_timer',
            'Session timer',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }
}
