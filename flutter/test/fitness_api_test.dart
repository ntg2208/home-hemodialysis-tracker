import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/fitness/fitness_api.dart';

void main() {
  test('FitnessSummary.fromJson parses types, totals, latest', () {
    final s = FitnessSummary.fromJson({
      'generated_at': '2026-06-01T10:00:00.000Z',
      'types': [
        {
          'type': 'daily-resting-heart-rate',
          'last_synced': '2026-05-31',
          'count': 35,
          'last_date': '2026-05-31',
          'stale': false,
          'latest': {'label': 'Resting HR', 'value': '83', 'unit': 'bpm', 'at': '2026-05-31'},
          'bytes': 1128,
        },
        {'type': 'heart-rate', 'last_synced': '2026-05-30', 'count': 1000, 'stale': false},
      ],
      'totals': {'types': 9, 'healthy': 9, 'stale': 0, 'bytes': 44415331},
    });

    expect(s.types.length, 2);
    expect(s.types.first.latest?.value, '83');
    expect(s.types[1].latest, isNull);
    expect(s.totals.bytes, 44415331);
    expect(s.lastSynced, '2026-05-31'); // most recent across types
    expect(s.allHealthy, isTrue);
    expect(s.hasData, isTrue);
  });

  test('allHealthy false when a type has an error or is stale', () {
    final s = FitnessSummary.fromJson({
      'generated_at': '',
      'types': [
        {'type': 'heart-rate', 'error': 'fetch failed', 'stale': false},
      ],
      'totals': {'types': 1, 'healthy': 0, 'stale': 0, 'bytes': 0},
    });
    expect(s.allHealthy, isFalse);
    expect(s.hasData, isFalse);
  });
}
