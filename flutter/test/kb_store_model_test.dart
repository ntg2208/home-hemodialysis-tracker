import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/kb/kb_store.dart';

void main() {
  group('KbEntry', () {
    test('toMap / fromMap round-trips', () {
      final now = DateTime(2026, 6, 3, 12, 0);
      final entry = KbEntry(
        id: 'test-id',
        title: 'Dry Weight',
        content: '59 kg',
        source: 'user',
        createdAt: now,
        updatedAt: now,
      );

      final map = entry.toMap();
      expect(map['id'], 'test-id');
      expect(map['title'], 'Dry Weight');
      expect(map['content'], '59 kg');
      expect(map['source'], 'user');
      expect(map['created_at'], isA<Timestamp>());

      final restored = KbEntry.fromMap(map);
      expect(restored.id, entry.id);
      expect(restored.title, entry.title);
      expect(restored.content, entry.content);
      expect(restored.source, entry.source);
      expect(restored.createdAt, entry.createdAt);
    });
  });
}
