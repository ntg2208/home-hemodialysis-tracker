import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:home_hd/features/treatment/timer_prefs.dart';

void main() {
  group('TimerPrefs model', () {
    test('defaults: defaultTargetMin is 255 (4h 15m)', () {
      expect(TimerPrefs.defaults.defaultTargetMin, 255);
    });

    test('toJson / fromJson round-trips defaultTargetMin', () {
      const original = TimerPrefs(defaultTargetMin: 210);
      final restored = TimerPrefs.fromJson(original.toJson());
      expect(restored.defaultTargetMin, 210);
    });

    test('fromJson with missing field falls back to default', () {
      final p = TimerPrefs.fromJson({});
      expect(p.defaultTargetMin, 255);
    });

    test('copyWith changes defaultTargetMin', () {
      final p = TimerPrefs.defaults.copyWith(defaultTargetMin: 180);
      expect(p.defaultTargetMin, 180);
    });
  });

  group('TimerPrefsStore', () {
    setUpAll(() async {
      Hive.init(Directory.systemTemp.createTempSync('hd_timer_test').path);
      await Hive.openBox('treatment');
    });

    test('read on empty box returns defaults', () {
      final store = TimerPrefsStore(Hive.box('treatment'));
      expect(store.read().defaultTargetMin, 255);
    });

    test('write then read persists the value', () async {
      final store = TimerPrefsStore(Hive.box('treatment'));
      await store.write(const TimerPrefs(defaultTargetMin: 200));
      expect(store.read().defaultTargetMin, 200);
    });
  });
}
