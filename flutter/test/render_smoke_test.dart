import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/app/theme.dart';
import 'package:home_hd/api/rest_client.dart';
import 'package:home_hd/features/blood_tests/models.dart';
import 'package:home_hd/features/blood_tests/widgets/trend_chart.dart';
import 'package:home_hd/features/inventory/inventory_models.dart';
import 'package:home_hd/api/inventory_api.dart';
import 'package:home_hd/features/inventory/inventory_screen.dart';
import 'package:home_hd/features/treatment/models.dart';
import 'package:home_hd/features/treatment/providers.dart';
import 'package:home_hd/features/treatment/screens/active.dart';
import 'package:home_hd/features/treatment/treatment_repo.dart';

/// Headless "does it survive first paint" coverage for the riskiest screens.
/// Catches throws on render (null-bangs, layout asserts, degenerate chart axes) —
/// not visual correctness.

Widget _app(Widget child) =>
    MaterialApp(theme: hdLightTheme(), home: Scaffold(body: child));

BloodTestRow _row(String dt, double v) => BloodTestRow(
      marker: 'haemoglobin',
      datetime: dt,
      value: v,
      unit: 'g/L',
      refLow: 130,
      refHigh: 170,
      timing: 'pre',
      note: '',
      source: 't',
      labId: dt,
      phase: 'home-hd',
      createdAt: '',
      qualitative: false,
    );

class _FakeRepo extends TreatmentRepo {
  @override
  Future<({List<Session> sessions, List<Reading> readings})> getAll() async =>
      (sessions: const <Session>[], readings: const <Reading>[]);
}

class _FakeInventoryApi extends InventoryApi {
  _FakeInventoryApi() : super(RestClient(mainKey: () => ''));
  @override
  Future<InventoryResponse> fetchInventory() async => const InventoryResponse(
        stock: {'SAK-303': 10, 'CAR-172-C': 30, 'heparin': 2},
        cycle: null,
        pakInstalledAt: null,
        pakSessions: 0,
      );
}

void main() {
  testWidgets('TrendChart renders with multiple points', (tester) async {
    await tester.pumpWidget(_app(TrendChart(
      marker: 'haemoglobin',
      rows: [_row('2026-01-01T08:00:00', 100), _row('2026-02-01T08:00:00', 120)],
    )));
    expect(find.text('Haemoglobin'), findsOneWidget);
  });

  testWidgets('TrendChart renders a single-point series (flat-X guard)',
      (tester) async {
    // Regression: minX==maxX must not divide-by-zero in fl_chart.
    await tester.pumpWidget(_app(TrendChart(
      marker: 'haemoglobin',
      rows: [_row('2026-01-01T08:00:00', 118)],
    )));
    expect(tester.takeException(), isNull);
    expect(find.text('Haemoglobin'), findsOneWidget);
  });

  testWidgets('ActiveSession renders its first frame', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [treatmentRepoProvider.overrideWithValue(_FakeRepo())],
      child: _app(ActiveSession(
        session: const Session(sessionId: '2026-06-02', date: '2026-06-02', preWeight: 60),
        initialReadings: const [],
        heparinUsed: true,
        onReadingsChanged: (_) {},
        onCountdownChanged: (_, _) {},
        onHeparinChanged: (_) {},
        onEnd: (_) {},
      )),
    ));
    // No reading added → countdown not started → no periodic timer to settle.
    expect(find.text('Add reading'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('InventoryScreen renders from a fake api', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [inventoryApiProvider.overrideWithValue(_FakeInventoryApi())],
      child: _app(const InventoryScreen()),
    ));
    await tester.pump(); // resolve fetchInventory future
    expect(find.text('NXSTAGE SUPPLIES'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
