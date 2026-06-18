import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/inventory/stock_calc.dart';

void main() {
  group('sessionsRemaining', () {
    test('1:1 items return qty', () {
      expect(sessionsRemaining('SAK-303', 12), 12);
      expect(sessionsRemaining('CAR-172-C', 6), 6);
      expect(sessionsRemaining('UK00000774', 24), 24); // On/Off Pack now 1/session
    });
    test('needles divide by 2, PAK multiplies by 10', () {
      expect(sessionsRemaining('P00012326', 20), 10);
      expect(sessionsRemaining('PAK-001', 2), 20);
    });
    test('hospital + unknown return null', () {
      expect(sessionsRemaining('heparin', 5), isNull);
      expect(sessionsRemaining('UNKNOWN', 5), isNull);
    });
  });

  group('stockStatus', () {
    test('nxstage thresholds (red <8, amber 8-15, green >=16)', () {
      expect(stockStatus('SAK-303', 7), StockStatus.red);
      expect(stockStatus('SAK-303', 8), StockStatus.amber);
      expect(stockStatus('SAK-303', 16), StockStatus.green);
    });
    test('hospital: 0 red, 1 amber, >1 green', () {
      expect(stockStatus('heparin', 0), StockStatus.red);
      expect(stockStatus('heparin', 1), StockStatus.amber);
      expect(stockStatus('heparin', 4), StockStatus.green);
    });
  });

  group('consumedUnits', () {
    test('1:1 session items scale linearly', () {
      expect(consumedUnits('SAK-303', 20), 20);
      expect(consumedUnits('CAR-172-C', 16), 16);
    });
    test('needles are 2/session', () {
      expect(consumedUnits('P00012326', 20), 40);
    });
    test('PAK is 1 per 10 sessions, ceil', () {
      expect(consumedUnits('PAK-001', 20), 2);
      expect(consumedUnits('PAK-001', 15), 2); // ceil(15/10)
    });
    test('monthly items return 0 (no per-session rate)', () {
      expect(consumedUnits('UK00000830', 20), 0); // Sani-Cloth
      expect(consumedUnits('UK00000832', 20), 0); // Sharps Bin
    });
  });

  group('orderBoxes', () {
    test('falls back to fixed targetQty when no delivery date given', () {
      expect(orderBoxes('SAK-303', 10), 7); // ceil((24-10)/2)
      expect(orderBoxes('CAR-172-C', 6), 3); // ceil((24-6)/6)
      expect(orderBoxes('SAK-303', 24), 0);
    });

    test('excludes backup qty from working stock', () {
      // working = 10-8 = 2, target = 24, order = ceil((24-2)/2) = 11
      expect(orderBoxes('SAK-303', 10, backupQty: 8), 11);
      expect(orderBoxes('SAK-303', 10, backupQty: 0), 7);
    });

    test('delivery sessions: normal order (7-day lead = 4 sessions + 16 buffer = 20)', () {
      // Need 20 bags, have 10 working → order 10 → ceil(10/2) = 5 boxes
      expect(orderBoxes('SAK-303', 10, deliverySessions: 20), 5);
    });

    test('delivery sessions: early order (3-week lead = 12 sessions + 16 buffer = 28)', () {
      // Need 28 bags, have 10 working → order 18 → ceil(18/2) = 9 boxes
      expect(orderBoxes('SAK-303', 10, deliverySessions: 28), 9);
    });

    test('delivery sessions with backup: excludes backup from working stock', () {
      // 20 total, 8 backup → working = 12; need 28; order 16 → ceil(16/2) = 8 boxes
      expect(orderBoxes('SAK-303', 20, backupQty: 8, deliverySessions: 28), 8);
    });

    test('monthly items fall back to targetQty even with delivery sessions', () {
      // Sani-Cloth has no per-session rate; consumedUnits returns 0 → use targetQty=1
      expect(orderBoxes('UK00000830', 0, deliverySessions: 28), 1);
      expect(orderBoxes('UK00000830', 1, deliverySessions: 28), 0);
    });
  });

  test('needsOrdering false for hospital, true below target', () {
    expect(needsOrdering('SAK-303', 10), isTrue);
    expect(needsOrdering('SAK-303', 24), isFalse);
    expect(needsOrdering('heparin', 0), isFalse);
  });

  test('sortStock: needs-ordering first, then priority, hospital after nxstage', () {
    final sorted = sortStock(const [
      StockEntry('heparin', 0),
      StockEntry('SAK-303', 30), // green, no order
      StockEntry('CAR-172-C', 5), // needs order
    ]);
    expect(sorted.first.code, 'CAR-172-C'); // needs ordering first
    expect(sorted.last.code, 'heparin'); // hospital after nxstage
  });
}
