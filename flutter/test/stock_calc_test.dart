import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/inventory/stock_calc.dart';

void main() {
  group('sessionsRemaining', () {
    test('1:1 items return qty', () {
      expect(sessionsRemaining('SAK-303', 12), 12);
      expect(sessionsRemaining('CAR-172-C', 6), 6);
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

  test('orderBoxes ceils units/boxSize to reach target', () {
    expect(orderBoxes('SAK-303', 10), 7); // (24-10)/2 = 7
    expect(orderBoxes('CAR-172-C', 6), 3); // (24-6)/6 = 3
    expect(orderBoxes('SAK-303', 24), 0);
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
