import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/treatment/session_id.dart';

void main() {
  group('nextSessionId', () {
    test('no existing → bare date', () {
      expect(nextSessionId('2026-06-02', []), '2026-06-02');
      expect(nextSessionId('2026-06-02', ['2026-06-01']), '2026-06-02');
    });

    test('one same-day session → -2', () {
      expect(nextSessionId('2026-06-02', ['2026-06-02']), '2026-06-02-2');
    });

    test('uses max suffix + 1, not count', () {
      expect(
        nextSessionId('2026-06-02', ['2026-06-02', '2026-06-02-3']),
        '2026-06-02-4',
      );
    });

    test('ignores other dates', () {
      expect(
        nextSessionId('2026-06-02', ['2026-06-01-5', '2026-06-02']),
        '2026-06-02-2',
      );
    });
  });

  test('todayIso / nowHHMM zero-pad', () {
    final t = DateTime(2026, 3, 5, 9, 7);
    expect(todayIso(t), '2026-03-05');
    expect(nowHHMM(t), '09:07');
  });
}
