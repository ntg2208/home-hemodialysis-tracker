import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/fitness/fitness_api.dart';
import 'package:home_hd/features/fitness/metric_tiles.dart';

void main() {
  test('fitnessTiles is the first-version set in order', () {
    expect(fitnessTiles.map((t) => t.key).toList(), [
      'sleep',
      'daily-heart-rate-variability',
      'daily-resting-heart-rate',
      'respiratory-rate-sleep-summary',
    ]);
    expect(fitnessTiles.where((t) => t.isSleep).length, 1);
  });

  group('tileHeadline', () {
    final summary = FitnessSummary.fromJson({
      'generated_at': '',
      'types': [
        {
          'type': 'daily-heart-rate-variability',
          'latest': {'label': 'HRV', 'value': '48', 'unit': 'ms', 'at': '2026-06-03'},
        },
        {'type': 'daily-resting-heart-rate'}, // no latest
      ],
      'totals': {},
    });

    test('returns latest value + unit for a metric with data', () {
      final h = tileHeadline(summary, fitnessTiles[1]); // HRV
      expect(h.value, '48');
      expect(h.unit, 'ms');
    });

    test('returns an em dash when the metric has no latest reading', () {
      final h = tileHeadline(summary, fitnessTiles[2]); // RHR, no latest
      expect(h.value, '—');
    });
  });
}
