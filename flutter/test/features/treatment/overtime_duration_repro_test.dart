import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:home_hd/api/inventory_api.dart';
import 'package:home_hd/api/rest_client.dart';
import 'package:home_hd/app/providers.dart';
import 'package:home_hd/app/theme.dart';
import 'package:home_hd/features/inventory/inventory_models.dart';
import 'package:home_hd/features/treatment/models.dart';
import 'package:home_hd/features/treatment/providers.dart';
import 'package:home_hd/features/treatment/screens/active.dart';
import 'package:home_hd/features/treatment/treatment_repo.dart';

/// Repro for the reported "overtime reduces the recorded duration" bug.
///
/// Drives the REAL ActiveSession end-path: a countdown that started in the
/// past (already past target), then taps End and reads the durationMin the
/// Post screen receives. Confirms whether overtime is ADDED (elapsed) or
/// SUBTRACTED (target + negative remaining).

class _FakeRepo extends TreatmentRepo {
  @override
  Future<({List<Session> sessions, List<Reading> readings})> getAll() async =>
      (sessions: const <Session>[], readings: const <Reading>[]);
  @override
  Future<List<Reading>> getReadings(String sessionId) async =>
      const <Reading>[];
}

class _FakeInventoryApi extends InventoryApi {
  _FakeInventoryApi() : super(RestClient(mainKey: () => ''));
  @override
  Future<InventoryResponse> fetchInventory() async => const InventoryResponse(
        stock: {'heparin': 2, 'epo': 1},
        cycle: null,
        pakInstalledAt: null,
        pakSessions: 0,
      );
  @override
  Future<Map<String, num>> fetchStock() async => {'heparin': 2, 'epo': 1};
}

Widget _app(Widget child) => MaterialApp(theme: hdLightTheme(), home: child);

Future<int?> _endDurationFor(
  WidgetTester tester, {
  required int targetMin,
  required int elapsedMin,
}) async {
  int? captured;
  final startedAt =
      DateTime.now().millisecondsSinceEpoch - elapsedMin * 60000;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      treatmentRepoProvider.overrideWithValue(_FakeRepo()),
      inventoryApiProvider.overrideWithValue(_FakeInventoryApi()),
    ],
    child: _app(ActiveSession(
      session: const Session(
          sessionId: '2026-06-02', date: '2026-06-02', preWeight: 60),
      initialReadings: const [],
      heparinUsed: true,
      epoUsed: true,
      initialCountdownStartedAt: startedAt,
      initialTargetMin: targetMin,
      onReadingsChanged: (_) {},
      onCountdownChanged: (_, _) {},
      onHeparinChanged: (_) {},
      onEpoChanged: (_) {},
      onCommentChanged: (_) {},
      onEnd: (c) => captured = c.durationMin,
    )),
  ));
  await tester.tap(find.widgetWithText(TextButton, 'End'));
  await tester.pump();
  // Unmount so ActiveSession disposes and cancels its 1s ticker
  // (avoids a "Timer is still pending" failure at test teardown).
  await tester.pumpWidget(const SizedBox());
  return captured;
}

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('hd_test').path);
    await Hive.openBox(treatmentBoxName);
    await Hive.openBox(cacheBoxName);
  });

  testWidgets('OVERTIME: target 255 (4h15m), ran 265 min (10 min over)',
      (tester) async {
    final d = await _endDurationFor(tester, targetMin: 255, elapsedMin: 265);
    // ignore: avoid_print
    print('>>> OVERTIME  target=255  ran=265  ->  Post durationMin = $d  '
        '(correct=265 / bug-would-be=245)');
    expect(d, 265,
        reason: 'overtime must be ADDED: duration = elapsed = target + over');
  });

  testWidgets('NORMAL: target 255, ran 240 min (under target)',
      (tester) async {
    final d = await _endDurationFor(tester, targetMin: 255, elapsedMin: 240);
    // ignore: avoid_print
    print('>>> NORMAL    target=255  ran=240  ->  Post durationMin = $d  '
        '(correct=240)');
    expect(d, 240);
  });
}
