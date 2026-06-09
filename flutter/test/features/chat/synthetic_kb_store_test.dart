import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/test_mode/synthetic_repos.dart';

void main() {
  group('SyntheticKbStore', () {
    test('getAll returns non-empty list without hitting Firestore', () async {
      final store = SyntheticKbStore();
      final entries = await store.getAll();
      expect(entries, isNotEmpty);
    });

    test('entries have non-empty title and content', () async {
      final store = SyntheticKbStore();
      final entries = await store.getAll();
      for (final e in entries) {
        expect(e.title, isNotEmpty);
        expect(e.content, isNotEmpty);
      }
    });

    test('save is a no-op that does not throw', () async {
      final store = SyntheticKbStore();
      final entries = await store.getAll();
      await expectLater(store.save(entries.first), completes);
      // getAll still returns the same entries (write was ignored)
      expect(await store.getAll(), hasLength(entries.length));
    });

    test('delete is a no-op that does not throw', () async {
      final store = SyntheticKbStore();
      final entries = await store.getAll();
      await expectLater(store.delete(entries.first.id), completes);
      expect(await store.getAll(), hasLength(entries.length));
    });
  });
}
