import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/app/theme.dart';
import 'package:home_hd/features/fitness/fitness_detail.dart';
import 'package:home_hd/features/fitness/metric_tiles.dart';
import 'package:home_hd/features/fitness/providers.dart';
import 'package:home_hd/test_mode/synthetic_repos.dart';

Widget _wrap(Widget child) => ProviderScope(
      overrides: [fitnessApiProvider.overrideWithValue(SyntheticFitnessApi())],
      child: MaterialApp(theme: hdLightTheme(), home: child),
    );

void main() {
  testWidgets('trend detail shows latest value and baseline after load',
      (tester) async {
    await tester.pumpWidget(_wrap(TrendDetailScreen(def: fitnessTiles[1]))); // HRV
    await tester.pumpAndSettle();
    expect(find.text('HRV'), findsWidgets); // app bar title
    expect(find.textContaining('baseline'), findsWidgets);
  });

  testWidgets('sleep detail shows total asleep and stage breakdown',
      (tester) async {
    await tester.pumpWidget(_wrap(const SleepDetailScreen()));
    await tester.pumpAndSettle();
    expect(find.text('asleep'), findsOneWidget);
    expect(find.text('DEEP'), findsOneWidget);
  });
}
