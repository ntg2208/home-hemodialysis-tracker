import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:home_hd/app/theme.dart';
import 'package:home_hd/features/settings/timer_settings_section.dart';
import 'package:home_hd/features/treatment/providers.dart';

Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: hdLightTheme(),
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('hd_timer_settings').path);
    await Hive.openBox(treatmentBoxName);
  });

  // Seed a NON-default value so the test proves the section READS the pref
  // rather than showing a hardcoded string. Written here in the normal async
  // zone — an awaited Hive write inside `testWidgets` never completes because
  // the test binding doesn't pump real file-I/O.
  setUp(() async {
    await Hive.box(treatmentBoxName)
        .put('timer_prefs', {'defaultTargetMin': 200}); // 3h 20m
  });

  testWidgets('displays the configured default treatment duration (3h 20m)',
      (tester) async {
    await tester.pumpWidget(_host(const TimerSettingsSection()));
    expect(find.textContaining('3h 20m'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 20)));
}
