import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/kb/kb_store.dart';

void main() {
  test('KbEntry toJson/fromJson roundtrip', () {
    final entry = KbEntry(
      id: 'kb-1',
      title: 'Dry Weight',
      content: '59 kg',
      source: 'user',
      createdAt: DateTime.utc(2026, 6, 1, 10),
      updatedAt: DateTime.utc(2026, 6, 2, 12),
    );
    final json = entry.toJson();
    expect(json['created_at'], isA<String>());
    final restored = KbEntry.fromJson(json);
    expect(restored.id, entry.id);
    expect(restored.title, entry.title);
    expect(restored.createdAt.millisecondsSinceEpoch,
        entry.createdAt.millisecondsSinceEpoch);
  });
}
