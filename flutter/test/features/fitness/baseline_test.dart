import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/fitness/baseline.dart';

void main() {
  group('median', () {
    test('returns null for empty', () => expect(median([]), isNull));
    test('odd length → middle', () => expect(median([3, 1, 2]), 2));
    test('even length → mean of middle two', () => expect(median([1, 2, 3, 4]), 2.5));
  });

  group('arrow', () {
    test('up when above baseline beyond tolerance', () => expect(arrow(60, 50), Trend.up));
    test('down when below baseline beyond tolerance', () => expect(arrow(40, 50), Trend.down));
    test('steady within tolerance', () => expect(arrow(51, 50), Trend.steady));
    test('steady when baseline is zero', () => expect(arrow(5, 0), Trend.steady));
  });

  group('trailingBaseline', () {
    test('null when fewer than 2 points', () => expect(trailingBaseline([5]), isNull));
    test('median of priors (excludes the last value)', () {
      expect(trailingBaseline([40, 42, 44, 50]), 42); // priors [40,42,44]
    });
    test('uses only the trailing `window` priors', () {
      final values = <double>[999, 40, 40, 40, 40, 40, 40, 40, 41];
      expect(trailingBaseline(values, window: 7), 40); // old outlier excluded
    });
  });

  group('trendFromSeries', () {
    test('null when fewer than 2 points', () => expect(trendFromSeries([42]), isNull));
    test('compares last value to median of prior window', () {
      // prior = [40,42,44] median 42; today 50 → up
      expect(trendFromSeries([40, 42, 44, 50]), Trend.up);
    });
    test('uses only the trailing `window` priors', () {
      // window 7: priors are the 7 before the last; an old outlier is excluded
      final values = <double>[999, 40, 40, 40, 40, 40, 40, 40, 41];
      expect(trendFromSeries(values, window: 7), Trend.steady);
    });
  });
}
