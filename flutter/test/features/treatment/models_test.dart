import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/treatment/models.dart';

void main() {
  group('Session.comment', () {
    test('toMap includes comment when set', () {
      const s = Session(
        sessionId: 'test-01',
        date: '2026-06-08',
        comment: 'good session',
      );
      expect(s.toMap()['comment'], 'good session');
    });

    test('toMap omits comment key when null', () {
      const s = Session(sessionId: 'test-01', date: '2026-06-08');
      expect(s.toMap().containsKey('comment'), isFalse);
    });

    test('fromMap reads comment back', () {
      final s = Session.fromMap({
        'session_id': 'test-01',
        'date': '2026-06-08',
        'comment': 'restored note',
      });
      expect(s.comment, 'restored note');
    });

    test('fromMap returns null comment when key absent', () {
      final s = Session.fromMap({
        'session_id': 'test-01',
        'date': '2026-06-08',
      });
      expect(s.comment, isNull);
    });

    test('toMap/fromMap roundtrip preserves comment', () {
      const original = Session(
        sessionId: 'test-01',
        date: '2026-06-08',
        totalUf: 1.5,
        comment: 'test note',
      );
      final copy = Session.fromMap(original.toMap());
      expect(copy.comment, 'test note');
      expect(copy.totalUf, 1.5);
    });

    test('spread-override pattern preserves other fields', () {
      const s = Session(
        sessionId: 'test-01',
        date: '2026-06-08',
        totalUf: 1.5,
        preBpSys: 130,
      );
      final updated =
          Session.fromMap({...s.toMap(), 'comment': 'added later'});
      expect(updated.comment, 'added later');
      expect(updated.totalUf, 1.5);
      expect(updated.preBpSys, 130);
    });

    test('spread-override with null clears comment', () {
      const s = Session(
          sessionId: 'test-01', date: '2026-06-08', comment: 'old note');
      final updated =
          Session.fromMap({...s.toMap(), 'comment': null});
      expect(updated.comment, isNull);
    });
  });
}
