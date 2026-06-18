import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/inventory/constants.dart';
import 'package:home_hd/features/inventory/rate_overrides.dart';
import 'package:home_hd/features/inventory/stock_calc.dart';

void main() {
  group('resolveItem', () {
    test('returns base item when no overrides map', () {
      final item = resolveItem('SAK-303', {});
      expect(item?.perSession, 1);
      expect(item?.targetQty, 24);
    });

    test('returns null for unknown code', () {
      expect(resolveItem('UNKNOWN', {}), isNull);
    });

    test('overrides perSession', () {
      final item = resolveItem('SAK-303', {
        'SAK-303': const RateOverride(perSession: 2),
      });
      expect(item?.perSession, 2);
      expect(item?.targetQty, 24); // unchanged
    });

    test('overrides targetQty', () {
      final item = resolveItem('SAK-303', {
        'SAK-303': const RateOverride(targetQty: 32),
      });
      expect(item?.perSession, 1); // unchanged
      expect(item?.targetQty, 32);
    });

    test('partial override: only the set field changes', () {
      final item = resolveItem('CAR-172-C', {
        'CAR-172-C': const RateOverride(targetQty: 30),
      });
      expect(item?.perSession, 1);
      expect(item?.targetQty, 30);
    });

    test('null override fields keep catalogue defaults', () {
      final item = resolveItem('SAK-303', {
        'SAK-303': const RateOverride(),
      });
      expect(item?.perSession, 1);
      expect(item?.targetQty, 24);
    });
  });

  group('stock_calc with rates', () {
    test('consumedUnits uses overridden perSession for SAK', () {
      final rates = {'SAK-303': const RateOverride(perSession: 2)};
      expect(consumedUnits('SAK-303', 20, rates: rates), 40);
    });

    test('consumedUnits override replaces hardcoded needle rate', () {
      final rates = {'P00012326': const RateOverride(perSession: 1)};
      expect(consumedUnits('P00012326', 20, rates: rates), 20); // override: 1/session
    });

    test('consumedUnits still uses hardcoded needle rate when no override', () {
      expect(consumedUnits('P00012326', 20), 40); // default: 2/session
    });

    test('orderBoxes uses overridden targetQty as fallback', () {
      // Sani-Cloth: no session rate, falls back to targetQty. Override targetQty to 2.
      final rates = {'UK00000830': const RateOverride(targetQty: 2)};
      expect(orderBoxes('UK00000830', 0, rates: rates), 2);
      expect(orderBoxes('UK00000830', 1, rates: rates), 1);
    });

    test('orderBoxes uses overridden perSession for delivery-session target', () {
      // SAK with 2/session, deliverySessions=20 → target=40, have=10 → order=30 → 15 boxes
      final rates = {'SAK-303': const RateOverride(perSession: 2)};
      expect(orderBoxes('SAK-303', 10, deliverySessions: 20, rates: rates), 15);
    });

    test('sessionsRemaining uses overridden perSession for needles', () {
      // Override needles to 1/session: 20 needles → 20 sessions
      final rates = {'P00012326': const RateOverride(perSession: 1)};
      expect(sessionsRemaining('P00012326', 20, rates: rates), 20);
    });

    test('needsOrdering uses overridden targetQty', () {
      // SAK override targetQty=30: having 25 should need ordering
      final rates = {'SAK-303': const RateOverride(targetQty: 30)};
      expect(needsOrdering('SAK-303', 25, rates: rates), isTrue);
      expect(needsOrdering('SAK-303', 25), isFalse); // default target=24
    });

    test('PAK-001 perSession is not overridable — always uses 1/10 rate', () {
      final rates = {'PAK-001': const RateOverride(perSession: 5)};
      // Despite the override, rate stays 1/10: 20 sessions → 2 PAKs
      expect(consumedUnits('PAK-001', 20, rates: rates), 2);
      // sessionsRemaining: 2 PAKs → 20 sessions regardless of override
      expect(sessionsRemaining('PAK-001', 2, rates: rates), 20);
    });
  });

  group('On/Off Pack perSession fix', () {
    test('sessionsRemaining uses perSession=1 for On/Off Pack', () {
      expect(sessionsRemaining('UK00000774', 24), 24);
      expect(sessionsRemaining('UK00000774', 8), 8);
    });
    test('stockStatus On/Off Pack at 8 units is amber (not green)', () {
      expect(stockStatus('UK00000774', 8), StockStatus.amber);
      expect(stockStatus('UK00000774', 16), StockStatus.green);
      expect(stockStatus('UK00000774', 7), StockStatus.red);
    });
  });
}
