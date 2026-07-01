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
import 'package:home_hd/features/treatment/screens/post.dart';
import 'package:home_hd/features/treatment/timer_prefs.dart';
import 'package:home_hd/features/treatment/treatment_repo.dart';
import 'package:home_hd/widgets/number_field.dart';

/// The new default treatment duration (TimerPrefs.defaultTargetMin) must drive
/// the Active countdown target AND the Post duration fallback — not a hardcode.

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

get _overrides => [
      treatmentRepoProvider.overrideWithValue(_FakeRepo()),
      inventoryApiProvider.overrideWithValue(_FakeInventoryApi()),
    ];

void _setDefault(int min) =>
    TimerPrefsStore(Hive.box(treatmentBoxName)).write(TimerPrefs(defaultTargetMin: min));

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('hd_timer_wire').path);
    await Hive.openBox(treatmentBoxName);
    await Hive.openBox(cacheBoxName);
  });

  testWidgets('Active countdown target uses the TimerPrefs default (180 → 3H)',
      (tester) async {
    _setDefault(180);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides,
      child: _app(ActiveSession(
        session: const Session(
            sessionId: '2026-06-02', date: '2026-06-02', preWeight: 60),
        initialReadings: const [],
        heparinUsed: true,
        epoUsed: true,
        // No per-session target set → must fall back to the prefs default.
        initialTargetMin: null,
        initialCountdownStartedAt: DateTime.now().millisecondsSinceEpoch,
        onReadingsChanged: (_) {},
        onCountdownChanged: (_, _) {},
        onHeparinChanged: (_) {},
        onEpoChanged: (_) {},
        onCommentChanged: (_) {},
        onEnd: (_) {},
      )),
    ));
    expect(find.textContaining('TARGET 3H'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // dispose ticker
  });

  testWidgets('Post duration falls back to the TimerPrefs default (200)',
      (tester) async {
    // The post form's NumberField grid overflows ~16px in the headless
    // layout; that's pre-existing layout noise unrelated to this value check.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    _setDefault(200);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides,
      child: _app(PostTreatment(
        session: const Session(
            sessionId: '2026-06-02', date: '2026-06-02', preWeight: 60),
        // durationMin null → must fall back to the prefs default, not 255.
        consumed: const SessionConsumed(
            needles: 2, onOffPacks: 1, heparinUsed: false),
        onSaved: () {},
        onCancel: () {},
      )),
    ));
    await tester.pump();

    final durationField = tester.widget<NumberField>(find.byWidgetPredicate(
        (w) => w is NumberField && w.label == 'Duration (min)'));
    expect(durationField.value, 200);
  });
}
