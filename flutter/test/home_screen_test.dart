import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:home_hd/app/theme.dart';
import 'package:home_hd/features/treatment/models.dart';
import 'package:home_hd/features/treatment/providers.dart';
import 'package:home_hd/features/treatment/screens/home.dart';
import 'package:home_hd/features/treatment/store.dart';
import 'package:home_hd/features/treatment/treatment_repo.dart';

class _FakeRepo extends TreatmentRepo {
  @override
  Future<({List<Session> sessions, List<Reading> readings})> getAll() async => (
        sessions: const <Session>[
          Session(
              sessionId: '2026-06-01',
              date: '2026-06-01',
              preBpSys: 130,
              preBpDia: 80,
              postBpSys: 120,
              postBpDia: 75,
              totalUf: 1.6),
          Session(sessionId: '2026-05-30', date: '2026-05-30'),
        ],
        readings: const <Reading>[],
      );
}

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('hd_test').path);
    await Hive.openBox(treatmentBoxName);
    // Pre-populate the session cache so TreatmentHome renders without a network call.
    await TreatmentStore(Hive.box(treatmentBoxName)).saveCachedSessions(const [
      Session(
          sessionId: '2026-06-01',
          date: '2026-06-01',
          preBpSys: 130,
          preBpDia: 80,
          postBpSys: 120,
          postBpDia: 75,
          totalUf: 1.6),
      Session(sessionId: '2026-05-30', date: '2026-05-30'),
    ]);
  });

  testWidgets('Home renders sessions from the repo, newest first',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [treatmentRepoProvider.overrideWithValue(_FakeRepo())],
      child: MaterialApp(
        theme: hdLightTheme(),
        home: TreatmentHome(onStartSession: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2026-06-01'), findsOneWidget);
    expect(find.text('2026-05-30'), findsOneWidget);
    expect(find.text('Start session'), findsOneWidget);
    expect(find.text('Dried weight'), findsOneWidget);
  });
}
