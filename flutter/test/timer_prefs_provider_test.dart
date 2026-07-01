import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:home_hd/features/treatment/providers.dart';
import 'package:home_hd/features/treatment/timer_prefs.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('hd_timer_prov').path);
    await Hive.openBox(treatmentBoxName);
  });

  test('timerPrefsProvider exposes defaults, then reflects an update', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(timerPrefsProvider).defaultTargetMin, 255);

    await container
        .read(timerPrefsProvider.notifier)
        .update(const TimerPrefs(defaultTargetMin: 210));

    expect(container.read(timerPrefsProvider).defaultTargetMin, 210);
    // Persisted to the store, not just held in memory.
    expect(
      TimerPrefsStore(Hive.box(treatmentBoxName)).read().defaultTargetMin,
      210,
    );
  });
}
